#!/usr/bin/env python3
"""Read-only occurrence tracing of one frozen native workflow replay."""
from collections import Counter
from contextlib import ExitStack
import copy
import hashlib
import json
from pathlib import Path
import socket
import sys
import traceback
from unittest.mock import patch

ROOT = Path('/tmp/checkpoint-native-workflow-qualification-20260910').resolve()
SERVICE = ROOT / 'backend/bedrock-question-service'
CAPTURE = Path('/tmp/checkpoint-native-workflow-live-20260910/capture.json')
RAW_MAPPING = Path('/tmp/checkpoint-native-workflow-raw-assessment-20260910-v2/private-mapping.json')
OUTPUT = ROOT / 'docs/evidence/native-workflow-20260910/stage-lineage.json'
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import complete_question_solution as solver  # noqa: E402
from evals import checkpoint_runtime_qualification as runtime  # noqa: E402
import generation_diagnostics as diagnostics  # noqa: E402
import question_generation as generation  # noqa: E402
import question_quality as quality  # noqa: E402
import question_verification as verification  # noqa: E402


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def clone(value):
    return copy.deepcopy(value)


capture_bytes = CAPTURE.read_bytes()
capture = quality._strict_json_object(capture_bytes.decode())
mapping_bytes = RAW_MAPPING.read_bytes()
mapping = quality._strict_json_object(mapping_bytes.decode())
require(mapping['capture_byte_sha256'] == sha(capture_bytes), 'Raw packet has different capture bytes.')
require(mapping['plan_sha256'] == capture['plan_sha256'], 'Raw packet has different plan.')
raw_ids = {(row['call_index'], row['question_index']): row for row in mapping['items']}
require(len(raw_ids) == len(mapping['items']), 'Raw occurrence mapping is ambiguous.')
occurrences, concealed, raw_objects, sanitized_objects, verified_objects = {}, {}, {}, {}, {}
call_census, quality_events, traced_calls = [], [], []
last_call_index = None


def oid(call_index, question_index):
    return f'author-call-{call_index:02d}-item-{question_index:02d}'


def remember(table, value, record):
    previous = table.get(id(value))
    require(previous is None or previous == (value, record), 'Runtime object identity was rebound.')
    # Retain the actual object to prevent CPython ID reuse during later passes.
    table[id(value)] = (value, record)


def lookup(table, value):
    stored, result = table[id(value)]
    require(stored is value, 'Runtime identity changed.')
    return result


def source_location(frame):
    return {'file': str(Path(frame.f_code.co_filename).relative_to(SERVICE)),
            'function': frame.f_code.co_name, 'line': frame.f_lineno}


def ancestor(frame, code):
    while frame is not None:
        if frame.f_code is code:
            return frame
        frame = frame.f_back
    return None


def subject(question):
    return {key: clone(question[key]) for key in ('prompt', 'choices')}


def private_fields(question):
    return {key: clone(question[key]) for key in
            ('expectedAnswer', 'answer', 'explanation', 'choiceExplanations') if key in question}


def user_data(call):
    text = call['request']['messages'][0]['content'][0]['text']
    tag = {'solver': 'question_solution_json', 'reviewer': 'question_review_json'}[call['role']]
    prefix, suffix = f'<{tag}>\n', f'\n</{tag}>'
    require(text.startswith(prefix) and text.endswith(suffix), 'Unexpected captured request envelope.')
    return quality._strict_json_object(text[len(prefix):-len(suffix)])


for call_index, call in enumerate(capture['calls']):
    require(runtime._hash(call['request']) == call['request_sha256'], 'Captured request hash changed.')
    text = call['observation']['response']['text']
    parsed = quality._strict_json_object(text)
    entry = {'call_index': call_index, 'operation_index': call['operation_index'],
             'operation_call_index': call['operation_call_index'], 'role': call['role'],
             'request_sha256': call['request_sha256'], 'response_text_sha256': sha(text.encode()),
             'response_envelope_property_order': list(parsed)}
    call_census.append(entry)
    if call['role'] not in {'author', 'author_json_repair'}:
        continue
    entry['raw_occurrence_count'] = len(parsed['questions'])
    for question_index, question in enumerate(parsed['questions']):
        key = oid(call_index, question_index)
        raw_map = raw_ids[(call_index, question_index)]
        require(question == raw_map['question'], 'Raw blind mapping changed authored content.')
        occurrences[key] = {
            'occurrence_id': key, 'raw_blind_packet_id': raw_map['id'],
            'operation_index': call['operation_index'],
            'case_id': capture['operations'][call['operation_index']]['case_id'],
            'author': {'call_index': call_index, 'operation_call_index': call['operation_call_index'],
                       'question_index': question_index, 'role': call['role'],
                       'request_sha256': call['request_sha256'], 'response_text_sha256': entry['response_text_sha256'],
                       'question_sha256': runtime._hash(question), 'response_property_order': list(question),
                       'subject': subject(question), 'authored_difficulty': question['difficulty']},
            'sanitize': None, 'solver': None, 'reviewer': None, 'returned': None,
        }
        concealed[key] = {'occurrence_id': key, 'raw_blind_packet_id': raw_map['id'],
                          'authored': private_fields(question)}


def on_call_boundary(frame, event, result):
    global last_call_index
    if event != 'return':
        return on_call_boundary
    current = frame.f_locals
    position = current['position']
    call = capture['calls'][position]
    require(current['request'] == call['request'], 'Trace request differs from exact captured request.')
    require(current['self'].report['calls'][position] == call, 'Trace call differs from capture.')
    require(position == len(traced_calls), 'Provider replay position skipped or repeated.')
    traced_calls.append(position)
    last_call_index = position
    if call['role'] not in {'solver', 'reviewer'}:
        return None
    parent = ancestor(frame, verification.verify_questions.__code__)
    require(parent is not None, 'Checker request is outside actual verification.')
    questions = parent.f_locals['questions']
    payload = user_data(call)
    items = payload['items']
    require(len(questions) == len(items), 'Request inventory differs from runtime question inventory.')
    if call['role'] == 'solver':
        _, exact_user = solver.build_solver_prompt(parent.f_locals['items'], parent.f_locals['request'])
        require(exact_user == call['request']['messages'][0]['content'][0]['text'],
                'Actual solver request does not match production prompt builder bytes.')
    else:
        require(payload == parent.f_locals['data'], 'Actual reviewer request differs from runtime data.')
    response = quality._strict_json_object(call['observation']['response']['text'])
    response_key = 'solutions' if call['role'] == 'solver' else 'reviews'
    response_rows = response[response_key]
    by_index = {row['index']: (index, row) for index, row in enumerate(response_rows)}
    require(len(by_index) == len(response_rows) == len(items), 'Checker response index inventory is ambiguous.')
    for index, (question, item) in enumerate(zip(questions, items, strict=True)):
        record = lookup(sanitized_objects, question)
        require(item['index'] == index and item['prompt'] == question['prompt'], 'Runtime checker index/stem mismatch.')
        runtime_item = parent.f_locals['items'][index] if call['role'] == 'solver' else parent.f_locals['data']['items'][index]
        require(item['choices'] == runtime_item['choices'], 'Runtime checker choice order mismatch.')
        require(sorted(item['choices']) == sorted(question['choices']), 'Runtime checker offered choices changed.')
        row_position, row = by_index[index]
        stage = {'call_index': position, 'question_index': index, 'request_sha256': call['request_sha256'],
                 'request_item': clone(item), 'response_row_position': row_position,
                 'response_index': row['index'], 'response_property_order': list(row),
                 'response_text_sha256': sha(call['observation']['response']['text'].encode()),
                 'response_row_sha256': runtime._hash(row), 'gate': None}
        require(record[call['role']] is None, 'Occurrence reached same checker stage twice.')
        record[call['role']] = stage
        if call['role'] == 'solver':
            stage['response_record'] = clone(row)
            stage['choice_response_property_orders'] = [list(choice) for choice in row['choices']]
        else:
            stage['response_declaration'] = {key: clone(row[key]) for key in ('index', 'valid', 'difficulty') if key in row}
            stage['request_independent_solution'] = clone(payload['independentSolutions'][index])
            require(record['solver'] is not None and record['solver']['gate']['reason'] is None,
                    'Reviewer request contains a solver-excluded occurrence.')
            normalized = clone(record['solver']['validated_record'])
            normalized['index'] = index
            require(normalized == stage['request_independent_solution'], 'Dense solver-to-reviewer record mapping changed.')
            concealed[record['occurrence_id']]['reviewer'] = private_fields(row)
    return None


def on_payload(frame, event, result):
    if event != 'return':
        return on_payload
    call = capture['calls'][last_call_index]
    require(call['role'] in {'author', 'author_json_repair'}, 'Payload is not linked to an author response.')
    require(result == quality._extract_json_object(call['observation']['response']['text']), 'Payload parsing mismatch.')
    for index, question in enumerate(result['questions']):
        record = occurrences[oid(last_call_index, index)]
        remember(raw_objects, question, record)
    return None


def on_sanitize(frame, event, result):
    if event != 'return':
        return on_sanitize
    for index, question in enumerate(result):
        record = lookup(sanitized_objects, question)
        require(record['sanitize']['gate']['reason'] == 'accepted', 'Returned sanitizer item was not accepted.')
        record['sanitize']['dense_index'] = index
    return None


def on_solver_gate(frame, event, result):
    if event != 'return':
        return on_solver_gate
    record = lookup(sanitized_objects, frame.f_locals['question'])
    require(record['solver'] is not None, 'Solver gate lacks exact request lineage.')
    require(record['solver']['question_index'] == frame.f_locals['record']['index'], 'Solver gate index changed.')
    record['solver']['validated_record'] = clone(frame.f_locals['record'])
    record['solver']['gate'] = {'reason': result, 'status': 'eligible' if result is None else 'excluded',
                              'location': source_location(frame)}
    return None


def on_quality(frame):
    values = frame.f_locals
    if values['count'] <= 0:
        return
    parent = frame.f_back
    event = {'stage': values['stage'], 'reason': values['reason'], 'count': values['count'],
             'location': source_location(parent)}
    generation_frame = ancestor(parent, generation._generate_sanitized_questions.__code__)
    require(generation_frame is not None, 'Quality observation outside generation.')
    execute_frame = ancestor(parent, runtime._execute.__code__)
    event['operation_index'] = execute_frame.f_locals['index']
    quality_events.append(clone(event))
    if parent.f_code is quality._sanitize_questions.__code__:
        require(values['count'] == 1 and values['reason'] != 'surplus', 'Unexpected bulk sanitizer event.')
        record = lookup(raw_objects, parent.f_locals['raw_question'])
        require(record['author']['question_index'] == parent.f_locals['candidate_index'], 'Sanitizer candidate index changed.')
        require(record['sanitize'] is None, 'Multiple sanitizer verdicts for occurrence.')
        record['sanitize'] = {'status': 'accepted' if values['reason'] == 'accepted' else 'excluded',
                              'gate': clone(event), 'dense_index': None,
                              'request_sha256': runtime._hash(parent.f_locals['request'])}
        if values['reason'] == 'accepted':
            question = parent.f_locals['question']
            require(parent.f_locals['sanitized'][-1] is question, 'Sanitizer appended a different object.')
            remember(sanitized_objects, question, record)
            record['sanitize'].update(subject=subject(question), question_sha256=runtime._hash(question),
                                      changed_fields=[key for key in set(question) | set(parent.f_locals['raw_question'])
                                                      if question.get(key) != parent.f_locals['raw_question'].get(key)])
            concealed[record['occurrence_id']]['sanitized'] = private_fields(question)
        return
    require(parent.f_code is verification.verify_questions.__code__, 'Unexpected telemetry source.')
    require(values['count'] == 1, 'Unexpected bulk verification event.')
    if 'solution' in parent.f_locals and values['reason'].startswith('solver_'):
        solution = parent.f_locals['solution']
        record = lookup(sanitized_objects, parent.f_locals['questions'][solution['index']])
        require(record['solver']['gate']['reason'] == values['reason'], 'Solver telemetry disagrees with gate.')
        record['solver']['gate']['quality_event'] = clone(event)
        return
    record = lookup(sanitized_objects, parent.f_locals['question'])
    require(record['reviewer'] is not None and record['reviewer']['question_index'] == parent.f_locals['index'],
            'Reviewer telemetry lacks exact question lineage.')
    require(record['reviewer']['gate'] is None, 'Multiple reviewer verdicts for occurrence.')
    record['reviewer']['gate'] = {'status': 'accepted' if values['reason'] == 'accepted' else 'excluded',
                                 'reason': values['reason'], 'quality_event': clone(event)}
    if values['reason'] == 'accepted':
        question = parent.f_locals['verified_question']
        require(parent.f_locals['accepted'][-1] is question, 'Reviewer appended a different object.')
        remember(verified_objects, question, record)
        concealed[record['occurrence_id']]['verified'] = private_fields(question)


def on_generation(frame, event, result):
    if event != 'return':
        return on_generation
    execute_frame = ancestor(frame, runtime._execute.__code__)
    operation_index = execute_frame.f_locals['index']
    require(result == capture['operations'][operation_index]['questions'], 'Generation returned content differs from capture.')
    for index, question in enumerate(result):
        record = lookup(verified_objects, question)
        require(record['operation_index'] == operation_index, 'Returned object has different operation lineage.')
        require(record['returned'] is None, 'Occurrence returned more than once.')
        record['returned'] = {'operation_index': operation_index, 'question_index': index,
                              'question_sha256': runtime._hash(question), 'subject': subject(question),
                              'difficulty': question['difficulty'],
                              'verificationVersion': question.get('verificationVersion'),
                              'verificationPolicyRevision': question.get('verificationPolicyRevision')}
        concealed[record['occurrence_id']]['returned'] = private_fields(question)
    return None


handlers = {runtime._RuntimeClient.converse.__code__: on_call_boundary,
            generation._generate_provider_payload.__code__: on_payload,
            quality._sanitize_questions.__code__: on_sanitize,
            solver.rejection_reason.__code__: on_solver_gate,
            generation._generate_sanitized_questions.__code__: on_generation}


def trace(frame, event, result):
    if event != 'call':
        return None
    if ancestor(frame, runtime._execute.__code__) is None:
        return None
    if frame.f_code is diagnostics.record_quality.__code__:
        try:
            on_quality(frame)
        except Exception:
            traceback.print_exc()
            raise
        return None
    handler = handlers.get(frame.f_code)
    if handler is None:
        return None

    def guarded(local_frame, local_event, local_result):
        try:
            handler(local_frame, local_event, local_result)
        except Exception:
            traceback.print_exc()
            raise
        return guarded
    return guarded


original_capture = clone(capture)
with ExitStack() as stack:
    for target, method in (
        (socket.socket, 'connect'), (socket.socket, 'connect_ex'),
        (boto3, 'client'), (boto3.session.Session, 'client'),
        (runtime.shared, 'new_client'), (runtime.caller, 'observe_request'),
    ):
        stack.enter_context(patch.object(target, method, side_effect=AssertionError('Lineage audit forbids network/provider calls')))
    baseline = runtime.replay_capture(capture)
    require(baseline == original_capture == capture, 'Baseline replay mutated or differed.')
    require(sys.gettrace() is None, 'An existing Python trace must not be overwritten.')
    try:
        sys.settrace(trace)
        replay = runtime.replay_capture(capture)
    finally:
        sys.settrace(None)
    require(replay == baseline == original_capture == capture, 'Passive tracing changed whole replay.')

require(traced_calls == list(range(len(capture['calls']))), 'Replay call coverage incomplete.')
require(len(occurrences) == len(raw_ids) == 25, 'Raw occurrence denominator changed.')
for record in occurrences.values():
    require(record['sanitize'] is not None, 'Unaccounted raw occurrence.')
    if record['sanitize']['status'] == 'excluded':
        require(record['solver'] is record['reviewer'] is record['returned'] is None, 'Sanitizer exclusion reached later stage.')
        record['terminal_outcome'] = {'stage': 'sanitize', 'reason': record['sanitize']['gate']['reason']}
    elif record['solver']['gate']['reason'] is not None:
        require(record['reviewer'] is record['returned'] is None, 'Solver exclusion reached later stage.')
        record['terminal_outcome'] = {'stage': 'solver', 'reason': record['solver']['gate']['reason']}
    elif record['reviewer']['gate']['reason'] != 'accepted':
        require(record['returned'] is None, 'Reviewer exclusion was returned.')
        record['terminal_outcome'] = {'stage': 'reviewer', 'reason': record['reviewer']['gate']['reason']}
    else:
        require(record['returned'] is not None, 'Accepted item disappeared before return.')
        record['terminal_outcome'] = {'stage': 'returned', 'reason': 'accepted'}
    if record['sanitize']['status'] == 'accepted':
        record['sanitize']['changed_fields'].sort()

operations = []
for index, operation in enumerate(capture['operations']):
    rows = [record for record in occurrences.values() if record['operation_index'] == index]
    observed_quality = {}
    for event in quality_events:
        if event['operation_index'] == index:
            stage = observed_quality.setdefault(event['stage'], {})
            stage[event['reason']] = stage.get(event['reason'], 0) + event['count']
    require(observed_quality == operation['metrics']['QuestionQuality'], 'Occurrence trace and runtime counters disagree.')
    returned = [row for row in rows if row['returned'] is not None]
    require(len(returned) == len(operation['questions']), 'Returned denominator mismatch.')
    operations.append({'operation_index': index, 'case_id': operation['case_id'], 'requested_slots': 5,
                       'raw_author_occurrences': len(rows),
                       'sanitized_occurrences': sum(row['sanitize']['status'] == 'accepted' for row in rows),
                       'solver_occurrences': sum(row['solver'] is not None for row in rows),
                       'reviewer_occurrences': sum(row['reviewer'] is not None for row in rows),
                       'returned_occurrences': len(returned), 'generation_shortfall': 5-len(returned),
                       'terminal_gate_counts': dict(Counter(row['terminal_outcome']['stage'] + ':' +
                                                           row['terminal_outcome']['reason'] for row in rows)),
                       'traced_quality_matches_capture': True, 'quality_counters': observed_quality})

author_orders = [row['author']['response_property_order'] for row in occurrences.values()]
solver_orders = [order for row in occurrences.values() if row['solver'] is not None
                 for order in row['solver']['choice_response_property_orders']]
require(all(order[:4] == ['prompt', 'explanation', 'expectedAnswer', 'choices'] for order in author_orders),
        'Observed author property ordering changed.')
require(all(order == ['choice', 'reason', 'judgment'] for order in solver_orders), 'Observed solver row ordering changed.')
for call, census in zip(capture['calls'], call_census, strict=True):
    spec = call['request']['outputConfig']['textFormat']['structure']['jsonSchema']
    schema = json.loads(spec['schema'])
    census['schema_name'] = spec['name']
    census['schema_byte_sha256'] = sha(spec['schema'].encode())
    if call['role'] == 'author':
        row_schema = schema['properties']['questions']['items']
        order = list(row_schema['properties'])
        require(order[:4] == ['prompt', 'explanation', 'expectedAnswer', 'choices'], 'Author wire schema order mismatch.')
        census['schema_item_property_order'] = order
    elif call['role'] == 'solver':
        row_schema = schema['properties']['solutions']['items']['properties']['choices']['items']
        order = list(row_schema['properties'])
        require(order == ['choice', 'reason', 'judgment'], 'Solver wire schema order mismatch.')
        census['schema_choice_property_order'] = order

artifact = {
    'experiment': capture['plan']['experiment'], 'capture_byte_sha256': sha(capture_bytes),
    'capture_canonical_sha256': runtime._hash(capture), 'plan_sha256': capture['plan_sha256'],
    'source_revision': capture['plan']['source_revision'], 'source_sha256': clone(capture['plan']['source_sha256']),
    'delivery_source_sha256': clone(capture['plan']['delivery_source_sha256']),
    'dependencies': clone(capture['plan']['dependencies']),
    'raw_private_mapping_byte_sha256': sha(mapping_bytes), 'trace_script_byte_sha256': sha(Path(__file__).read_bytes()),
    'method': 'Baseline exact replay, then unchanged whole-runtime replay with read-only sys.settrace observations at real provider returns, parsed author payload returns, sanitizer telemetry/return, complete-choice gate returns, reviewer telemetry, and generation return. Runtime object identity retained across transformations and exact request array indices establish lineage; no answer matching. Source and plan checked by existing replay before execution. SDK and socket entry points forbidden. No factual assessment or blind verdicts read.',
    'replay': {'baseline_exact': baseline == original_capture, 'instrumented_exact': replay == original_capture,
               'input_capture_unchanged': capture == original_capture, 'all_call_indices_traced': traced_calls,
               'network_and_provider_calls_forbidden': True, 'runtime_source_files_edited': False},
    'coverage': {'requested_slots': 15, 'author_calls': sum(row['role'] == 'author' for row in call_census),
                 'author_json_repair_calls': sum(row['role'] == 'author_json_repair' for row in call_census),
                 'raw_author_occurrences': len(occurrences), 'unparseable_author_calls': 0,
                 'sanitized_occurrences': sum(r['sanitize']['status'] == 'accepted' for r in occurrences.values()),
                 'solver_occurrences': sum(r['solver'] is not None for r in occurrences.values()),
                 'reviewer_occurrences': sum(r['reviewer'] is not None for r in occurrences.values()),
                 'returned_occurrences': sum(r['returned'] is not None for r in occurrences.values()),
                 'terminal_gate_counts': dict(Counter(r['terminal_outcome']['stage'] + ':' +
                                                     r['terminal_outcome']['reason'] for r in occurrences.values()))},
    'schema_order_observation': {'author_items_count': len(author_orders), 'all_author_items_prompt_explanation_key_choices_first': True,
                                  'solver_choice_rows_count': len(solver_orders), 'all_solver_rows_choice_reason_judgment': True,
                                  'matching_wire_schema_order_verified': True},
    'scope': 'A gate exclusion is a mechanical runtime event, not a factual catch. Reviewer valid declarations and difficulty labels are model outputs. All 25 raw opportunities remain distinct from the 15 requested slots. This private lineage contains runtime judgments and must not enter blinded assessment inputs. Original authored keys and feedback plus sanitized/reviewer/returned teaching are kept only in the separate concealed_key_and_feedback section.',
    'operations': operations, 'calls': call_census, 'occurrences': list(occurrences.values()),
    'concealed_key_and_feedback': list(concealed.values()), 'quality_events': quality_events,
}
with OUTPUT.open('x', encoding='utf-8') as stream:
    json.dump(artifact, stream, ensure_ascii=False, indent=2, allow_nan=False)
    stream.write('\n')
print(json.dumps({'output': str(OUTPUT), 'artifact_byte_sha256': sha(OUTPUT.read_bytes()),
                  'coverage': artifact['coverage'], 'order': artifact['schema_order_observation']}, indent=2))
