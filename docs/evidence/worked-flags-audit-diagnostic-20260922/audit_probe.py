"""Two fixed audit calls only; importing/building/testing never contacts AWS."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SOURCE = Path('/Users/samchou/.codex/worktrees/worked-flags-audit-source/Checkpoint')
SERVICE = SOURCE / 'backend/bedrock-question-service'
IMPORTED_HASHES = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob('*.py')}
_HELPER = SERVICE / 'evals/bounded_bedrock_capture.py'
IMPORTED_HASHES[str(_HELPER)] = hashlib.sha256(_HELPER.read_bytes()).hexdigest()
sys.path.insert(0, str(SERVICE))
import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
import question_verification as verification  # noqa: E402
from question_teaching import validate_authored_reviews, authored_review_rejection_reason  # noqa: E402
from quantitative_task_compiler import compile_question  # noqa: E402

_spec = importlib.util.spec_from_file_location('worked_flags_safe', SERVICE / 'evals/bounded_bedrock_capture.py')
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)
MODEL = 'us.anthropic.claude-sonnet-4-6'
ENDPOINT = 'https://bedrock-runtime.us-east-1.amazonaws.com'
CONTROLS = HERE / 'controls-draft.json'
CONTROL_SHA = '3463294975e19e8f1f71a562a77a4f79c57bbea712418ce6eba569a39b97795f'
PLAN, CAPTURE = HERE / 'plan.json', HERE / 'capture.json'
CONTRACT = native.AuthoredSolutionFlagReviewContract(5)
ENVIRONMENT = {'BEDROCK_REGION': 'us-east-1', 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native',
               'BEDROCK_CLAUDE_THINKING': 'adaptive', 'BEDROCK_CLAUDE_EFFORT': 'high',
               'BEDROCK_MAX_TOKENS': '16000', 'BEDROCK_THINKING_MAX_TOKENS': '16000',
               'BEDROCK_GUARDRAIL_IDENTIFIER': '', 'BEDROCK_GUARDRAIL_VERSION': ''}
LIMITS = {'calls': 2, 'items_per_call': 5, 'items_total': 10, 'read_timeout': 100,
          'connect_timeout': 3, 'sdk_attempts': 1, 'successful_elapsed_maximum': 100}


class IntegrityError(RuntimeError):
    pass


class ObservationError(ValueError):
    pass


class RequestCaptured(Exception):
    pass


def require(ok, message):
    if not ok:
        raise IntegrityError(message)


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, allow_nan=False).encode()).hexdigest()


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if exclusive:
        with path.open('x') as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix('.partial')
        with temporary.open('x') as stream:
            stream.write(text)
        temporary.replace(path)


class CaptureWriter:
    def __init__(self, path, capture):
        self.path = path
        save(path, capture, exclusive=True)
        self.expected = file_hash(path)

    def check(self):
        require(self.path.exists() and file_hash(self.path) == self.expected, 'Capture modified externally.')

    def save(self, capture):
        self.check()
        save(self.path, capture)
        self.expected = file_hash(self.path)


def controls():
    require(file_hash(CONTROLS) == CONTROL_SHA, 'Approved controls changed.')
    packet = safe.strict_json(CONTROLS.read_text())
    require(len(packet['cases']) == 10, 'Control count changed.')
    for i in range(5):
        good, bad = packet['cases'][i], packet['cases'][i + 5]
        compiled = compile_question(good['original_spec'])
        require(compiled == good['recompiled_learner'] == bad['recompiled_learner'], 'Compiler reproduction changed.')
        a, b = copy.deepcopy(good['question']), copy.deepcopy(bad['question'])
        a.pop('explanation')
        b.pop('explanation')
        require(a == b and good['batch'] == 0 and bad['batch'] == 1, 'Controlled task identity changed.')
        mutation = bad['controlled_mutation']
        require(good['question']['explanation'].count(mutation['before']) == 1
                and good['question']['explanation'].replace(mutation['before'], mutation['after'], 1)
                == bad['question']['explanation'], 'Controlled main mutation changed.')
    return packet


def subject(prompt, tag):
    first, last = f'<{tag}>\n', f'\n</{tag}>'
    require(prompt.startswith(first) and prompt.endswith(last), 'Unexpected runtime input wrapper.')
    return safe.strict_json(prompt[len(first):-len(last)])


def oracle_native(cases):
    """Synthetic local test fixture, never claimed as provider evidence."""
    return {'reviews': {str(i): {'valid': c['gold']['expected_valid'],
        'answer': c['gold']['unique_answer'], 'difficulty': 2,
        'explanationSupport': c['gold']['main_support'],
        'issueFlags': {flag: flag == 'explanation' and c['gold']['expected_explanation_flag']
                       for flag in native.AUTHORED_ISSUE_FLAGS}}
        for i, c in enumerate(cases)}}


def actual_request(packet, batch):
    """Run actual input and provider request builders with injected recorders only."""
    cases = packet['cases'][batch * 5:batch * 5 + 5]
    observed = []

    def solve(_system, prompt):
        items = subject(prompt, 'question_solution_json')['items']
        require(len(items) == 5, 'Unexpected builder solver count.')
        return json.dumps({'solutions': [{'index': item['index'], 'choices': [
            {'choice': choice, 'judgment': 'supported' if choice == cases[item['index']]['gold']['unique_answer'] else 'refuted',
             'reason': 'Evaluator-authored exact task oracle used only for request construction.'}
            for choice in item['choices']]} for item in items]})

    def review(system, prompt, count):
        require(count == 5, 'Unexpected builder audit count.')
        observed.append((system, prompt))
        raise RequestCaptured()

    try:
        verification.verify_questions(copy.deepcopy([c['question'] for c in cases]), copy.deepcopy(packet['request']),
            lambda *_: require(False, 'Unexpected uncounted review.'), solve=solve,
            review_with_count=review, solver_contract='complete_choices', feedback_contract='authored_solution')
    except RequestCaptured:
        pass
    require(len(observed) == 1, 'Audit input construction failed.')
    system, user = observed[0]
    data = subject(user, 'question_review_json')
    require(set(data) == {'goal', 'skillMap', 'sourceDocuments', 'existingQuestions', 'items'}, 'Unexpected audit context.')
    require(data['existingQuestions'] == [] and len(data['items']) == 5, 'Unexpected history/count.')
    for i, item in enumerate(data['items']):
        require(set(item) == {'index', 'prompt', 'choices', 'skillID', 'objectiveID', 'topic', 'explanation'},
                'Explicit answer/gold/feedback or unexpected fields in auditor input.')
        q = cases[i]['question']
        require(item['index'] == i and item['prompt'] == q['prompt'] and item['explanation'] == q['explanation']
                and sorted(item['choices']) == sorted(q['choices']), 'Audit input text/index binding changed.')
    requests = []

    class Recorder:
        def converse(self, **request):
            requests.append(copy.deepcopy(request))
            return {'stopReason': 'end_turn', 'output': {'message': {'content': [{'text': json.dumps(oracle_native(cases))}]}}}

    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        runtime._generate_with_bedrock(packet['request'], Recorder(), MODEL, user_prompt=user,
            system_prompt=system, contract=CONTRACT, call_budget=runtime.ProviderCallBudget(1))
    require(len(requests) == 1, 'Provider request recorder count changed.')
    request = requests[0]
    require(request['modelId'] == MODEL and request['inferenceConfig'] == {'maxTokens': 16000}
            and request['additionalModelRequestFields'] == {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}},
            'Actual adaptive model configuration changed.')
    require(request['outputConfig'] == native.native_output_config(CONTRACT), 'Actual native schema changed.')
    return {'ordinal': batch, 'case_ids': [c['id'] for c in cases], 'request': request,
            'request_sha256': digest(request), 'input': data}


def source_check():
    require({str(p) for p in SERVICE.glob('*.py')} == {p for p in IMPORTED_HASHES if Path(p).parent == SERVICE},
            'Runtime module inventory changed.')
    for name, expected in IMPORTED_HASHES.items():
        require(file_hash(name) == expected, 'Imported runtime source changed.')
    for path in SERVICE.glob('*.py'):
        loaded = sys.modules.get(path.stem)
        if loaded is not None:
            require(Path(getattr(loaded, '__file__', '')).resolve() == path, 'Wrong runtime module loaded.')


def build_plan():
    source_check()
    packet = controls()
    calls = [actual_request(packet, batch) for batch in range(2)]
    a, b = copy.deepcopy(calls[0]['input']), copy.deepcopy(calls[1]['input'])
    for data in (a, b):
        for item in data['items']:
            item.pop('explanation')
    require(a == b, 'The paired audit inputs differ beyond their main explanations.')
    for key in calls[0]['request']:
        if key != 'messages':
            require(calls[0]['request'][key] == calls[1]['request'][key], 'Paired provider settings differ.')
    gold = safe.strict_json((HERE / 'root-gold-review.json').read_text())
    require(gold['approved'] is True and gold['control_sha256'] == CONTROL_SHA, 'Independent gold review binding failed.')
    paths = [HERE / name for name in ('audit_probe.py', 'test_audit_probe.py', 'PLAN_DRAFT.md', 'controls-draft.json', 'root-gold-review.json')]
    paths.append(SERVICE / 'requirements.txt')
    for source in packet['source_files']:
        path = Path(source['path'])
        if not path.is_absolute():
            path = HERE.parents[2] / path
        require(file_hash(path) == source['sha256'], 'Original control source changed.')
        paths.append(path)
    return {'state': 'draft', 'source_root': str(SOURCE), 'source_commit': packet['source_commit'],
            'source_hashes': IMPORTED_HASHES, 'artifact_hashes': {str(p): file_hash(p) for p in paths},
            'approved_control_sha256': CONTROL_SHA, 'environment': ENVIRONMENT, 'limits': LIMITS,
            'endpoint': ENDPOINT, 'calls': calls,
            'dependencies': {'python': sys.version.split()[0], 'boto3': boto3.__version__, 'botocore': botocore.__version__},
            'criteria': {'structural_calls': 2, 'sound_accepted': 5, 'false_main_rejected': 5,
                         'independent_main_support_matches': 10, 'positive_minimum_difficulty': 2,
                         'independent_flag_and_key_assessment_required': True},
            'limitations': packet['claim_limits']}


def check_plan(plan, path=None, expected_hash=None):
    require(plan.get('state') in {'draft', 'frozen'} and plan == {**build_plan(), 'state': plan['state']}, 'Plan/source drift.')
    if path is not None:
        require(file_hash(path) == expected_hash, 'Frozen plan bytes changed.')


def assess(response, spec, packet):
    text = ''.join(block['text'] for block in response['output']['message']['content'])
    adapted = native.adapt_native_response(text, CONTRACT)
    reviews = validate_authored_reviews(adapted, spec['input']['items'])
    rows = json.loads(text)['reviews']  # Native strict parsing already checked duplicate keys/types/coverage.
    cases = packet['cases'][spec['ordinal'] * 5:spec['ordinal'] * 5 + 5]
    result = []
    for i, (review, case) in enumerate(zip(reviews, cases, strict=True)):
        row, gold = rows[str(i)], case['gold']
        reason = authored_review_rejection_reason(review, case['question'])
        admitted = reason is None and review['difficulty'] >= 2
        match = (admitted and row['valid'] is True and not any(row['issueFlags'].values())
                 and row['answer'] == gold['unique_answer'] and row['explanationSupport'] == 'supported') if spec['ordinal'] == 0 else (
                     not admitted and row['valid'] is False and row['explanationSupport'] == 'unsupported'
                     and row['issueFlags']['explanation'] is True)
        result.append({'id': case['id'], 'admitted_by_audit_only': admitted, 'rejection': reason,
                       'criterion_matches': match, 'answer_matches': row['answer'] == gold['unique_answer'],
                       'support_matches': row['explanationSupport'] == gold['main_support'],
                       'valid_matches': row['valid'] == gold['expected_valid'],
                       'explanation_flag_matches': row['issueFlags']['explanation'] == gold['expected_explanation_flag'],
                       'raw_review': row, 'learner_release': False})
    return result


def setup_failure(error):
    response = getattr(error, 'response', {})
    response = response if type(response) is dict else {}
    problem = response.get('Error', {})
    problem = problem if type(problem) is dict else {}
    return type(error).__name__ in {'NoCredentialsError', 'PartialCredentialsError', 'CredentialRetrievalError',
        'UnauthorizedSSOTokenError', 'TokenRetrievalError', 'NoRegionError', 'ParamValidationError'} or (
        problem.get('Code') in {'ExpiredTokenException', 'UnrecognizedClientException',
        'InvalidSignatureException', 'InvalidClientTokenId', 'AccessDeniedException'})


def finish(capture):
    credit = [] if capture.get('global_stop') else [r for b in capture['batches'] if b.get('structural_pass') for r in b['assessment']]
    capture['status'] = 'stopped_for_integrity' if capture.get('global_stop') else 'completed'
    capture['summary'] = {'planned_calls': 2, 'planned_items': 10, 'attempted_calls': len(capture['calls']),
        'unattempted_calls': 2 - len(capture['calls']), 'structural_pass_calls': sum(b.get('structural_pass', False) for b in capture['batches']),
        'credited_items': len(credit), 'criteria_matching_items': sum(r['criterion_matches'] for r in credit),
        'exact_answer_matches': sum(r['answer_matches'] for r in credit),
        'mechanical_criteria_met': len(credit) == 10 and all(r['criterion_matches'] and r['answer_matches'] for r in credit),
        'qualified': False,  # Root independently reviews exact flags/keys before any conclusion.
        'input_tokens': sum(c.get('response', {}).get('usage', {}).get('inputTokens', 0) for c in capture['calls']),
        'output_tokens': sum(c.get('response', {}).get('usage', {}).get('outputTokens', 0) for c in capture['calls']),
        'calls_without_usage': sum(not c.get('response', {}).get('usage') for c in capture['calls']),
        'missing_usage_is_not_zero': True, 'independent_output_review': 'pending', 'learner_release': False}


def run(plan, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic, writer=None):
    require(capture.get('status') == 'new' and not capture['calls'] and not capture['batches'], 'No resume or repeat.')
    packet = controls()
    writer = writer if writer is not None else CaptureWriter(path, capture)

    def pins():
        try:
            writer.check()
        except Exception:
            capture['global_stop'] = 'capture_integrity'
            raise
        try:
            pin_check()
        except Exception:
            capture['global_stop'] = 'source_or_plan_integrity'
            raise

    for spec in plan['calls']:
        if capture.get('global_stop'):
            break
        row = {'ordinal': spec['ordinal'], 'case_ids': spec['case_ids'], 'status': 'running'}
        capture['batches'].append(row)
        try:
            pins()
            require(len(capture['calls']) < 2 and not any(c['ordinal'] == spec['ordinal'] for c in capture['calls']),
                    'Dispatch budget exceeded.')
            try:
                client = client_factory()
            except Exception:
                capture['global_stop'] = 'client_setup_failure'
                raise
            cfg = client.meta.config
            require(client.meta.endpoint_url == ENDPOINT and client.meta.region_name == 'us-east-1'
                    and cfg.read_timeout == 100 and cfg.connect_timeout == 3
                    and cfg.retries.get('total_max_attempts') == 1, 'Actual SDK configuration drift.')
            require(not capture.get('global_stop') and len(capture['calls']) < 2
                    and not any(c['ordinal'] == spec['ordinal'] for c in capture['calls']), 'Dispatch budget exceeded.')
            request = copy.deepcopy(spec['request'])
            require(digest(request) == spec['request_sha256'], 'Request hash drift.')
            pins()
            call = {'ordinal': spec['ordinal'], 'request': request, 'read_timeout': cfg.read_timeout,
                    'connect_timeout': cfg.connect_timeout, 'sdk_attempts': cfg.retries['total_max_attempts']}
            capture['calls'].append(call)
            writer.save(capture)  # Persist the reservation and exact request before dispatch.
            started = clock()
            try:
                response = client.converse(**copy.deepcopy(request))
            except Exception as error:
                call['error'] = safe.safe_error(error, secrets)
                raise
            finally:
                elapsed = clock() - started
                require(type(elapsed) in {int, float} and math.isfinite(elapsed) and elapsed >= 0, 'Invalid elapsed time.')
                call['elapsed_seconds'] = elapsed
                pins()
            if type(response) is not dict:
                raise ObservationError('Malformed provider response.')
            retained, omitted = safe.safe_response(response, secrets)
            require(not any(secret in json.dumps(retained, ensure_ascii=False) for secret in secrets), 'Credential in visible output.')
            call.update(response=retained, reasoning_blocks_omitted=omitted)
            if retained['stopReason'] != 'end_turn' or elapsed > 100:
                raise ObservationError('Incomplete or late provider response.')
            assessment = assess(retained, spec, packet)
            pins()  # No credit after source drift during local validation/scoring.
            row.update(status='completed', structural_pass=True, assessment=assessment)
        except Exception as error:
            row.update(status='failed', structural_pass=False, error=safe.safe_error(error, secrets))
            if isinstance(error, (IntegrityError, safe.CaptureBoundaryError)) or setup_failure(error):
                capture['global_stop'] = capture.get('global_stop', 'setup_transport_or_capture_integrity')
        finally:
            writer.save(capture)
    try:
        pins()
    except Exception:
        pass  # The sticky integrity stop withholds all credit in finish().
    finish(capture)
    writer.save(capture)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--plan', type=Path, default=PLAN)
    parser.add_argument('--plan-sha256')
    parser.add_argument('--capture', type=Path, default=CAPTURE)
    args = parser.parse_args()
    if not args.execute:
        plan = build_plan()
        print(json.dumps({'draft_sha256': digest(plan), 'maximum_calls': 2, 'execute': False}))
        return
    require(args.plan_sha256 and args.plan.exists() and not args.capture.exists(), 'Frozen plan/hash and fresh capture required.')
    plan = safe.strict_json(args.plan.read_text())
    require(plan['state'] == 'frozen', 'Only root-frozen requests may execute.')
    check_plan(plan, args.plan, args.plan_sha256)
    capture = {'status': 'new', 'plan': plan, 'plan_sha256': args.plan_sha256, 'calls': [], 'batches': [],
               'started_at': datetime.now(timezone.utc).isoformat()}
    writer = CaptureWriter(args.capture, capture)
    secrets = ()
    try:
        session, secrets = safe.credential_session()
        config = Config(read_timeout=100, connect_timeout=3, retries={'total_max_attempts': 1, 'mode': 'standard'})
        run(plan, capture, args.capture, lambda: session.client('bedrock-runtime', region_name='us-east-1',
            endpoint_url=ENDPOINT, config=config), lambda: check_plan(plan, args.plan, args.plan_sha256), secrets=secrets, writer=writer)
    except Exception as error:
        capture['global_stop'] = 'setup_or_unhandled_integrity'
        capture['error'] = safe.safe_error(error, secrets)
        finish(capture)
        try:
            writer.save(capture)
        except Exception:
            pass  # Never overwrite an externally changed or preexisting capture.
        raise IntegrityError('Diagnostic stopped; inspect bounded capture.') from None
    print(json.dumps(capture['summary']))


if __name__ == '__main__':
    main()
