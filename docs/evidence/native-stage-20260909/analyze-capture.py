"""Account for every fixed native-stage slot; agreement is not factual proof."""
from collections import Counter
from pathlib import Path
import hashlib
import json
import sys

service = Path('/tmp/checkpoint-native-qualification-20260909/backend/bedrock-question-service')
sys.path.insert(0, str(service))
from evals import checkpoint_native_stage_probe as probe

capture_path = Path('/tmp/checkpoint-native-stage-live-20260909/capture.json')
assessment_dir = Path('/tmp/checkpoint-native-stage-assessment-20260909')
capture = json.loads(capture_path.read_text())
assessment = json.loads((assessment_dir / 'independent-subjects.json').read_text())
subjects = {row['id']: row for row in assessment['assessments']}
mapping = {(row['original_call_index'], row['original_item_index']): row['id']
           for row in json.loads((assessment_dir / 'mapping.json').read_text())}
counts = Counter()
observations = []
for call in capture['calls']:
    state = call.get('observation', {})
    job = capture['plan']['jobs'][call['position']]
    counts['attempt_slots_entered'] += 1
    counts['dispatch_observed'] += state.get('provider_dispatch_attempted') is True
    counts['response_observed'] += 'response' in state
    counts['usage_known'] += state.get('usage_known') is True
    counts['clean_terminal_completion'] += probe.runtime._usable_observation(state)
    for name in ('inputTokens', 'outputTokens'):
        counts[name] += (state.get('response', {}).get('usage') or {}).get(name, 0)
    if not probe.runtime._usable_observation(state):
        continue
    content = probe.content_observation(job, state)
    assert content == {key: value for key, value in capture['results'][call['position']].items()
                       if key not in ('position', 'status')}
    for name in ('raw_schema_validation', 'adaptation', 'stage_validation'):
        counts[name + '_passed'] += content[name] == 'passed'
    if content['stage_validation'] != 'passed':
        continue
    adapted = json.loads(probe.native.adapt_native_response(state['response']['text'], job['contract']))
    rows = adapted['solutions' if job['role'] == 'solver' else 'reviews']
    for row in rows:
        identifier = mapping[job['archived_call_index'], row['index']]
        reference = subjects[identifier]
        supported = [c['choice'] for c in reference['choices'] if c['judgment'] == 'supported']
        record = {'position': call['position'], 'original_call_index': job['archived_call_index'],
                  'id': identifier, 'role': job['role'], 'independent_premise': reference['premise_status'],
                  'independent_difficulty': reference['difficulty'], 'independent_supported': supported,
                  'model_record': row}
        if job['role'] == 'solver':
            reference_by_choice = {c['choice']: c['judgment'] for c in reference['choices']}
            record['choice_judgment_disagreements'] = [c['choice'] for c in row['choices']
                if reference_by_choice[c['choice']] != c['judgment']]
            counts['solver_choice_judgments'] += len(row['choices'])
            counts['solver_choice_judgment_disagreements'] += len(record['choice_judgment_disagreements'])
            record['model_supported'] = [c['choice'] for c in row['choices'] if c['judgment'] == 'supported']
            record['declared_unique_with_three_refuted'] = (len(record['model_supported']) == 1
                and sum(c['judgment'] == 'refuted' for c in row['choices']) == 3)
        else:
            record['positive_answer_supported_by_independent_assessor'] = (
                row['valid'] is True and reference['premise_status'] == 'supported'
                and supported == [row['answer']])
        observations.append(record)
summary = {'capture_byte_sha256': hashlib.sha256(capture_path.read_bytes()).hexdigest(),
           'status': capture['status'], 'planned_attempts': len(capture['plan']['jobs']),
           'unattempted_slots': sum(row['status'] == 'unattempted' for row in capture['results']),
           'counts': dict(counts), 'item_occurrences': len(observations), 'observations': observations,
           'scope': 'Direct fixed downstream records only. No authored-key comparison, fresh generation, full default review policy, inventory admission, or factual correctness certification. Independent disagreements require interpretation; token sums cover known responses only.'}
output = Path('/tmp/checkpoint-native-stage-summary-20260909.json')
output.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({key: value for key, value in summary.items() if key != 'observations'}))
