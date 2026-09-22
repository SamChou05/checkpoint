"""Four fixed author-only prompt comparisons; import/prepare never invoke Bedrock."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace
from unittest.mock import patch

import boto3
import botocore

HERE = Path(__file__).resolve().parent
SERVICE = Path('/Users/samchou/.codex/worktrees/constructed-quantitative-authoring/Checkpoint/backend/bedrock-question-service').resolve()
IMPORTED_HASHES = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(SERVICE.glob('*.py'))}
sys.path.insert(0, str(SERVICE))
from request_contract import _normalize_request  # noqa: E402
from quantitative_authoring import CONSTRUCTED_AUTHOR_CONTRACT, prepare_mixed_rows  # noqa: E402
from question_quality import _sanitize_questions  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError, ProviderCallBudgetExceededError  # noqa: E402

HELPER = SERVICE / 'evals/bounded_bedrock_capture.py'
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location('prose_author_safe_capture', HELPER)
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)
PLAN, DRAFT, CAPTURE = (HERE / name for name in ('plan.json', 'plan-draft.json', 'capture.json'))
MODEL = 'moonshotai.kimi-k2.5'
ENDPOINT = 'https://bedrock-runtime.us-east-1.amazonaws.com'
ENV = {'BEDROCK_REGION': 'us-east-1', 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native',
       'BEDROCK_MODEL_ID': MODEL, 'BEDROCK_FALLBACK_MODEL_ID': '',
       'QUESTION_AUTHOR_MODE': 'constructed_quantitative', 'QUESTION_FEEDBACK_CONTRACT': 'authored_solution',
       'BEDROCK_KIMI_THINKING': 'disabled', 'BEDROCK_CLAUDE_THINKING': 'disabled',
       'BEDROCK_MAX_TOKENS': '6000', 'BEDROCK_THINKING_MAX_TOKENS': '16000',
       'BEDROCK_TEMPERATURE': '0.2', 'GENERATION_ATTEMPTS': '1', 'MAX_PROVIDER_CALLS_PER_REQUEST': '1',
       'BEDROCK_READ_TIMEOUT_SECONDS': '100', 'BEDROCK_CONNECT_TIMEOUT_SECONDS': '3',
       'BEDROCK_GUARDRAIL_IDENTIFIER': '', 'BEDROCK_GUARDRAIL_VERSION': ''}
ORDER = ('baseline', 'candidate', 'candidate', 'baseline')
IMPORTED_NATIVE_PROMPT = runtime.native_prompt



class IntegrityError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    allow_nan=False, separators=(',', ':')).encode()).hexdigest()


def save(path, value, exclusive=False):
    text = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + '\n'
    if exclusive:
        with path.open('x') as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix('.partial')
        temporary.write_text(text)
        temporary.replace(path)


class CaptureWriter:
    def __init__(self, path, capture):
        self.path = path
        save(path, capture, exclusive=True)
        self.expected = sha(path)

    def check(self):
        require(self.path.exists() and sha(self.path) == self.expected, 'Capture modified externally.')

    def save(self, capture):
        self.check()
        save(self.path, capture)
        self.expected = sha(self.path)


def generate(job, client=None, budget=None):
    def prompt(system, contract):
        require(contract == CONSTRUCTED_AUTHOR_CONTRACT, 'Unexpected stage: author-only diagnostic.')
        baseline = IMPORTED_NATIVE_PROMPT(system, contract)
        return baseline + ('\n\n' + job['addition'] if job['arm'] == 'candidate' else '')

    with patch.object(runtime, 'native_prompt', side_effect=prompt):
        return runtime._generate_provider_payload(copy.deepcopy(job['normalized_request']), client, budget)


def constructed_request(job):
    captured = []

    def converse(**request):
        captured.append(copy.deepcopy(request))
        return {'stopReason': 'end_turn', 'output': {'message': {'content': [{'text': '{"questions":[]}'}]}}}

    with patch.dict(os.environ, ENV, clear=True):
        generate(job, SimpleNamespace(converse=converse), runtime.ProviderCallBudget(1))
    require(len(captured) == 1, 'Expected one constructed author request.')
    request = captured[0]
    require(request['modelId'] == MODEL and request['inferenceConfig'] == {'maxTokens': 6000, 'temperature': 0.2},
            'Author model/sampling changed.')
    require(request['additionalModelRequestFields'] == {'thinking': {'type': 'disabled'}}, 'Author thinking drift.')
    require(request['outputConfig'] == native.native_output_config(CONSTRUCTED_AUTHOR_CONTRACT), 'Author schema drift.')
    return request


def build_plan():
    modules = sorted(SERVICE.glob('*.py'))
    require(sha(HELPER) == IMPORTED_HELPER_HASH, 'Capture helper changed after import.')
    require({p.name: sha(p) for p in modules} == IMPORTED_HASHES, 'Service changed during/after import.')
    for p in modules:
        loaded = sys.modules.get(p.stem)
        if loaded is not None:
            require(Path(getattr(loaded, '__file__', '')).resolve() == p, 'Wrong service checkout imported.')
    raw_job = safe.strict_json((HERE / 'job-draft.json').read_text())
    normalized = _normalize_request(raw_job)
    require(normalized['targetCount'] == 5 and normalized['minimumDifficulty'] == 2, 'Fixed author job changed.')
    addition = (HERE / 'candidate-addition-draft.txt').read_text().rstrip('\n')
    require(addition and len(addition) < 4000, 'Candidate addition missing/oversized.')
    jobs = []
    for arm in ORDER:
        job = {'index': len(jobs), 'arm': arm, 'normalized_request': normalized, 'addition': addition}
        job['request'] = constructed_request(job)
        job['request_sha256'] = digest(job['request'])
        jobs.append(job)
    require(jobs[0]['request'] == jobs[3]['request'] and jobs[1]['request'] == jobs[2]['request'],
            'Repeated-arm request drift.')
    candidate = copy.deepcopy(jobs[1]['request'])
    baseline = jobs[0]['request']
    require(candidate['system'][0]['text'] == baseline['system'][0]['text'] + '\n\n' + addition,
            'Candidate is not a sole final system append.')
    candidate['system'] = baseline['system']
    require(candidate == baseline, 'Request delta beyond candidate append.')
    paths = [*modules, SERVICE / 'requirements.txt', HELPER,
             *[HERE / n for n in ('job-draft.json', 'candidate-addition-draft.txt', 'PLAN.md',
                                   'author_probe.py', 'test_author_probe.py')]]
    return {'state': 'draft', 'source_root': str(SERVICE), 'source_commit': '0e4619f1696b848073f1a4d551c364ed3fbfbeb0',
            'source_hashes': {str(p): sha(p) for p in paths}, 'environment': ENV, 'endpoint': ENDPOINT,
            'jobs': jobs, 'limits': {'maximum_calls': 4, 'items_per_call': 5, 'read_seconds': 100,
                                    'connect_seconds': 3, 'sdk_total_attempts': 1},
            'native_contract': native.contract_metadata(CONSTRUCTED_AUTHOR_CONTRACT),
            'dependencies': {'python': sys.version.split()[0], 'boto3': boto3.__version__, 'botocore': botocore.__version__},
            'criteria': {'primary_candidate_usable_of_10': 10, 'per_call_variety': {'agreement': 2, 'reference': 2, 'tense': 1},
                         'content_uncertainty_fails': True, 'prompt_maximum': 320, 'choice_maximum': 140,
                         'author_main_instruction_maximum': 320, 'runtime_main_maximum': 420,
                         'format_length_time_scored_separately': True, 'example_copy_usable_credit': False,
                         'independent_blind_task_lock_then_key_main_audit': True,
                         'observed_descriptive_improvement_required_before_prompt_promotion': True},
            'per_arm_denominators': {'requested_slots': 10, 'planned_calls': 2},
            'failure_policy': 'Ordinary provider/safety/timeout/late/malformed response zeros five affected slots and continues independent calls. Global stop only credentials/setup/source/request/capture integrity or actual reservation/call ceiling violation. No retry or total wall-time ceiling.',
            'claim_limits': 'Author-only repeated-scope diagnostic; different generated items, not paired identical items or worker qualification. All20 raw slots and extra rows retained. Sanitization is diagnostic, never repair credit.'}


def check_plan(plan, path=None, expected_hash=None):
    require(plan['state'] in {'draft', 'frozen'} and plan == {**build_plan(), 'state': plan['state']}, 'Plan/source/request drift.')
    if path is not None:
        require(sha(path) == expected_hash, 'Frozen plan bytes changed.')


def setup_failure(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        if isinstance(error, (IntegrityError, safe.CaptureBoundaryError, ServiceConfigurationError)):
            return True
        if type(error).__name__ in {'NoCredentialsError', 'PartialCredentialsError', 'CredentialRetrievalError',
                                   'UnauthorizedSSOTokenError', 'TokenRetrievalError', 'NoRegionError', 'ParamValidationError'}:
            return True
        response = getattr(error, 'response', {})
        if isinstance(response, dict) and response.get('Error', {}).get('Code') in {
            'ExpiredTokenException', 'UnrecognizedClientException', 'InvalidSignatureException',
            'InvalidClientTokenId', 'AccessDeniedException'}:
            return True
        error = error.__cause__
    return False


def contains_credential(value, secrets):
    pending = [value]
    while pending:
        item = pending.pop()
        if type(item) is str and any(secret and secret in item for secret in secrets):
            return True
        if type(item) is dict:
            pending.extend(item.keys())
            pending.extend(item.values())
        elif type(item) is list:
            pending.extend(item)
    return False


def decoded_credential_echo(response, secrets):
    """Inspect the runtime's exact text concatenation without retaining it.

    Preserve duplicate JSON members during this scan so a later member cannot
    hide an earlier decoded string. Parsing failure grants no format approval;
    the unchanged native adapter handles malformed output as an ordinary failure.
    """
    content = response.get("output", {}).get("message", {}).get("content", [])
    text = "\n".join(block["text"] for block in content
                     if isinstance(block, dict) and isinstance(block.get("text"), str)).strip()
    if len(text.encode("utf-8")) > safe.VISIBLE_RESPONSE_MAX_BYTES:
        raise safe.CaptureBoundaryError("Visible runtime text exceeds capture allowance.")
    try:
        decoded = json.loads(text, object_pairs_hook=list)
    except (ValueError, RecursionError):
        return False
    pending = [decoded]
    while pending:
        value = pending.pop()
        if isinstance(value, str) and any(secret and secret in value for secret in secrets):
            return True
        if isinstance(value, (list, tuple)):
            pending.extend(value)
    return False


def raw_rows(response):
    try:
        text = '\n'.join(block['text'] for block in response['output']['message']['content']).strip()
        value = safe.strict_json(text)
        return value['questions'] if type(value) is dict and type(value.get('questions')) is list else None
    except (ValueError, KeyError, TypeError):
        return None


def lengths(question):
    fields = {'prompt': (question['prompt'], 12, 320), 'explanation': (question['explanation'], 12, 420),
              **{f'choice_{key}': (question['choices'][key], 1, 140) for key in 'abcd'}}
    observed = {key: {'characters': len(text), 'minimum': minimum, 'maximum': maximum,
                      'within_bounds': len(text.strip()) >= minimum and len(text) <= maximum}
                for key, (text, minimum, maximum) in fields.items()}
    return {'fields': observed, 'runtime_bounds_pass': all(x['within_bounds'] for x in observed.values()),
            'author_main_320_pass': len(question['explanation']) <= 320}


def assess(adapted, job, plan):
    # This is an observation of the original native rows, never semantic approval.
    originals = copy.deepcopy(adapted['questions'])
    require(type(originals) is list, 'Adapter envelope changed unexpectedly.')
    prepared, sidecars, failures = prepare_mixed_rows(adapted, construct_choices=True)
    metrics = {'ProviderCalls': 0}
    sanitized = _sanitize_questions(prepared, job['normalized_request'], metrics,
                                    preserve_authored_explanation=True,
                                    compiled_candidates=sidecars, compiled_output={})
    require(adapted['questions'] == originals, 'Local diagnostics mutated native rows.')
    records = [{'question_ordinal': i, 'kind': row['kind'], 'raw_row_sha256': digest(row),
                'lengths': lengths(row['question']) if row['kind'] == 'prose' else None,
                'semantic_review': 'pending_blind_task_lock_then_key_main_audit'} for i, row in enumerate(originals)]
    return {'native_adapter_valid': True, 'exact_five_rows': len(originals) == 5,
            'raw_rows': originals, 'rows': records,
            'sanitizer_diagnostic': {'retained_count': len(sanitized), 'retained': sanitized,
                                     'compile_failures': failures,
                                     'quality': copy.deepcopy(metrics.get('QuestionQuality', {}))},
            'semantic_credit': None}


def summarize(capture):
    result = {}
    for arm in ('baseline', 'candidate'):
        calls = [c for c in capture['calls'] if c['arm'] == arm]
        result[arm] = {'planned_calls': 2, 'requested_slots': 10,
                       'attempted_calls': sum(c['dispatch_attempted'] for c in calls),
                       'exact_five_native_endturn_timely_calls': sum(c['status'] == 'assessed' for c in calls),
                       'unattempted_slots': sum(5 for c in calls if not c['dispatch_attempted']),
                       'failed_slots': sum(5 for c in calls if c['dispatch_attempted'] and c['status'] != 'assessed'),
                       'structurally_assessed_slots': sum(5 for c in calls if c['status'] == 'assessed'),
                       'raw_rows_observed': sum(len(c.get('raw_rows') or []) for c in calls),
                       'extra_raw_rows': sum(max(0, len(c.get('raw_rows') or []) - 5) for c in calls),
                       'independent_content_and_variety': 'pending', 'qualified': False}
    return result


def blind_projection(capture):
    seed = digest(capture['plan'])
    worksheet, mapping = [], []
    for call in capture['calls']:
        rows = call.get('raw_rows') or []
        for ordinal in range(max(5, len(rows))):
            identity = digest({'plan_sha256': seed, 'call': call['index'], 'question': ordinal})
            row = rows[ordinal] if ordinal < len(rows) else None
            question = row.get('question') if type(row) is dict and row.get('kind') == 'prose' else None
            choices = question.get('choices') if type(question) is dict else None
            valid = (type(question) is dict and type(question.get('prompt')) is str
                     and type(choices) is dict and set(choices) == set('abcd')
                     and all(type(v) is str for v in choices.values()))
            rotation = int(identity[:8], 16) % 4
            offered = [choices[k] for k in 'abcd'] if valid else []
            offered = offered[rotation:] + offered[:rotation]
            worksheet.append({'id': identity, 'requested_slot': ordinal < 5,
                              'raw_stem': question['prompt'] if type(question) is dict and type(question.get('prompt')) is str else None,
                              'choices': offered, 'projection_shape': 'readable_prose' if valid else 'missing_or_malformed_or_nonprose',
                              'review': {'literal_task': None, 'premises': None, 'supported_choice_texts': None,
                                         'six_pair_judgments': None, 'uncertainty': None}})
            mapping.append({'id': identity, 'call_ordinal': call['index'], 'question_ordinal': ordinal,
                            'arm': call['arm'], 'rotation': rotation})
    worksheet.sort(key=lambda x: x['id'])
    mapping.sort(key=lambda x: x['id'])
    return ({'capture_sha256': digest(capture), 'requested_slot_denominator': 20, 'items': worksheet,
             'instruction': 'Lock literal task/premises, offered solutions and all six pair meanings before opening raw capture or unblind mapping. Missing shapes remain failures. Keys, explanations and arm/call grouping are withheld.'},
            {'capture_sha256': digest(capture), 'items': mapping})


def run_calls(plan, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic):
    require(len(plan['jobs']) == 4 and plan['limits']['maximum_calls'] == 4, 'Fixed call ceiling changed.')
    capture = {'plan': copy.deepcopy(plan), 'started_at': datetime.now(timezone.utc).isoformat(),
               'status': 'running', 'reservations': [], 'calls': [
                   {'index': j['index'], 'arm': j['arm'],
                    'status': 'unattempted', 'dispatch_attempted': False} for j in plan['jobs']]}
    writer = CaptureWriter(path, capture)

    def guard(condition, message):
        if not condition:
            capture['global_stop'] = 'integrity_or_call_budget'
            raise IntegrityError(message)

    def pins():
        try:
            writer.check()
            pin_check()
        except Exception:
            capture['global_stop'] = 'source_or_capture_integrity'
            raise

    for job, row in zip(plan['jobs'], capture['calls'], strict=True):
        if capture.get('global_stop'):
            break
        budget = runtime.ProviderCallBudget(1)
        row['status'] = 'preparing'

        class Recorder:
            def __init__(self, client):
                self.client, self.meta = client, client.meta

            def converse(self, **request):
                guard(not capture.get('global_stop'), 'Dispatch after global stop.')
                pins()
                cfg = self.meta.config
                guard(self.meta.endpoint_url == ENDPOINT and self.meta.region_name == 'us-east-1'
                      and cfg.read_timeout == 100 and cfg.connect_timeout == 3
                      and cfg.retries.get('total_max_attempts') == 1, 'SDK endpoint/configuration drift.')
                guard(request == job['request'] and digest(request) == job['request_sha256'], 'Actual request drift.')
                guard(not row['dispatch_attempted'] and budget.calls == 1 and len(capture['reservations']) < 4,
                      'Missing reservation or repeated/excess call.')
                capture['reservations'].append({'call_index': job['index'], 'runtime_budget_calls': budget.calls})
                row.update(dispatch_attempted=True, status='dispatching', request=copy.deepcopy(request),
                           request_sha256=digest(request), read_timeout=100, connect_timeout=3, sdk_attempts=1)
                writer.save(capture)
                started = clock()
                try:
                    response = self.client.converse(**request)
                    if (type(response) is not dict or type(response.get('output')) is not dict
                            or type(response['output'].get('message')) is not dict
                            or type(response['output']['message'].get('content')) is not list):
                        raise ProviderError('Malformed provider response envelope.')
                    guard(not decoded_credential_echo(response, secrets), 'Credential echo in decoded native output.')
                    retained, omitted = safe.safe_response(response, secrets)
                    guard(not contains_credential(retained, secrets), 'Credential echo in visible output.')
                    row.update(response=retained, reasoning_blocks_omitted=omitted)
                    return response
                except Exception as error:
                    row['provider_error'] = safe.safe_error(error, secrets)
                    if setup_failure(error):
                        capture['global_stop'] = 'provider_setup_or_capture_integrity'
                    raise
                finally:
                    row['elapsed_seconds'] = round(clock() - started, 6)
                    pins()
                    writer.save(capture)

        def factory(*args, **kwargs):
            pins()
            guard(not capture.get('global_stop'), 'Client after global stop.')
            try:
                client = client_factory(*args, **kwargs)
            except Exception:
                capture['global_stop'] = 'sdk_setup'
                raise
            return Recorder(client)

        try:
            pins()
            with patch.dict(os.environ, ENV, clear=True), patch.object(boto3, 'client', factory):
                adapted = generate(job, budget=budget)
            require(row['dispatch_attempted'] and budget.calls == 1, 'Runtime skipped its reserved call.')
            pins()
            if row['response']['stopReason'] != 'end_turn':
                raise ProviderError('Non-end-turn response.')
            if row['elapsed_seconds'] > 100:
                row.update(status='failed', local_error={'type': 'ElapsedCreditLimit'})
            else:
                assessment = assess(adapted, job, plan)
                pins()
                row['assessment'] = assessment
                row['status'] = 'assessed' if assessment['exact_five_rows'] else 'failed'
        except Exception as error:
            row.update(status='failed', local_error=safe.safe_error(error, secrets))
            if setup_failure(error) or isinstance(error, ProviderCallBudgetExceededError):
                capture['global_stop'] = capture.get('global_stop', 'setup_or_integrity')
            elif not isinstance(error, (ProviderError, SafetyInterventionError, IntegrityError)):
                capture['global_stop'] = 'unexpected_harness_failure'
        finally:
            row['raw_rows'] = raw_rows(row['response']) if 'response' in row else None
            capture['summary'] = summarize(capture)
            writer.save(capture)
    try:
        pins()
    except Exception as error:
        capture['global_stop'] = 'completion_integrity'
        if row['status'] == 'assessed':
            row.pop('assessment', None)
            row.update(status='failed', local_error=safe.safe_error(error, secrets))
    capture['status'] = 'globally_stopped' if capture.get('global_stop') else 'complete_pending_independent_audit'
    capture['completed_at'] = datetime.now(timezone.utc).isoformat()
    capture['summary'] = summarize(capture)
    writer.save(capture)
    return capture


def execute(expected_hash):
    plan = safe.strict_json(PLAN.read_text())
    require(plan['state'] == 'frozen', 'Reviewed frozen plan required.')
    check_plan(plan, PLAN, expected_hash)
    require(not CAPTURE.exists(), 'No resume or overwrite.')
    try:
        session, secrets = safe.credential_session()
    except Exception as error:
        capture = {'plan': plan, 'status': 'globally_stopped', 'global_stop': 'credential_setup',
                   'error': safe.safe_error(error), 'calls': [
                       {'index': j['index'], 'arm': j['arm'], 'status': 'unattempted', 'dispatch_attempted': False} for j in plan['jobs']]}
        capture['summary'] = summarize(capture)
        save(CAPTURE, capture, exclusive=True)
        return
    run_calls(plan, CAPTURE, session.client, lambda: check_plan(plan, PLAN, expected_hash), secrets=secrets)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--freeze', metavar='DRAFT_SHA256')
    mode.add_argument('--execute', metavar='PLAN_SHA256')
    mode.add_argument('--project', metavar='CAPTURE_PATH')
    args = parser.parse_args()
    if args.prepare:
        plan = build_plan()
        save(DRAFT, plan)
        print(json.dumps({'draft_sha256': sha(DRAFT), 'digest': digest(plan)}))
    elif args.freeze:
        plan = safe.strict_json(DRAFT.read_text())
        require(sha(DRAFT) == args.freeze, 'Reviewed exact draft required.')
        check_plan(plan)
        save(PLAN, {**plan, 'state': 'frozen'}, exclusive=True)
        print(sha(PLAN))
    elif args.project:
        captured = safe.strict_json(Path(args.project).read_text())
        worksheet, mapping = blind_projection(captured)
        save(HERE / 'blind-worksheet.json', worksheet, exclusive=True)
        save(HERE / 'unblind-mapping.json', mapping, exclusive=True)
    else:
        execute(args.execute)
