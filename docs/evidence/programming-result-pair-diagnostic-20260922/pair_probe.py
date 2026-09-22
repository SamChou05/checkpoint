"""Four fixed solver-only prompt comparisons; import/prepare never invoke Bedrock."""

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
SERVICE = Path('/Users/samchou/.codex/worktrees/question-reliability-investigation/Checkpoint/backend/bedrock-question-service').resolve()
IMPORTED_HASHES = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(SERVICE.glob('*.py'))}
sys.path.insert(0, str(SERVICE))
import complete_question_solution as solver  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as runtime  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402

HELPER = SERVICE / 'evals/bounded_bedrock_capture.py'
IMPORTED_HELPER_HASH = hashlib.sha256(HELPER.read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location('programming_pair_safe_capture', HELPER)
safe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safe)
PLAN, DRAFT, CAPTURE = (HERE / name for name in ('plan.json', 'plan-draft.json', 'capture.json'))
MODEL = 'us.anthropic.claude-sonnet-4-6'
ENDPOINT = 'https://bedrock-runtime.us-east-1.amazonaws.com'
ANCHOR = 'tests the written representation itself, preserve the requested literal difference.'
ENV = {'BEDROCK_REGION': 'us-east-1', 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native',
       'BEDROCK_CLAUDE_THINKING': 'adaptive', 'BEDROCK_CLAUDE_EFFORT': 'high',
       'BEDROCK_MAX_TOKENS': '16000', 'BEDROCK_THINKING_MAX_TOKENS': '16000',
       'BEDROCK_READ_TIMEOUT_SECONDS': '100', 'BEDROCK_CONNECT_TIMEOUT_SECONDS': '3',
       'BEDROCK_GUARDRAIL_IDENTIFIER': '', 'BEDROCK_GUARDRAIL_VERSION': ''}
ORDER = (('baseline', 0), ('candidate', 0), ('candidate', 1), ('baseline', 1))


class IntegrityError(RuntimeError):
    pass


class _CapturedRequest(Exception):
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
    return runtime._generate_with_bedrock({}, client, MODEL, system_prompt=job['system'],
                                         user_prompt=job['user'], contract=native.SolverSlotContract(4),
                                         call_budget=budget)


def constructed_request(job):
    captured = []

    def converse(**request):
        captured.append(copy.deepcopy(request))
        raise _CapturedRequest()

    with patch.dict(os.environ, ENV, clear=True):
        try:
            generate(job, SimpleNamespace(converse=converse))
        except ProviderError as error:
            require(isinstance(error.__cause__, _CapturedRequest), 'Unexpected offline request construction failure.')
    require(len(captured) == 1, 'Expected one constructed request.')
    return captured[0]


def build_plan():
    modules = sorted(SERVICE.glob('*.py'))
    require(sha(HELPER) == IMPORTED_HELPER_HASH, 'Capture helper changed after import.')
    require({p.name: sha(p) for p in modules} == IMPORTED_HASHES, 'Frozen service changed during/after import.')
    for p in modules:
        loaded = sys.modules.get(p.stem)
        if loaded is not None:
            require(Path(getattr(loaded, '__file__', '')).resolve() == p, 'Wrong service checkout imported.')
    packet = safe.strict_json((HERE / 'controls-draft.json').read_text())
    cases = packet['cases']
    require(len(cases) == 8 and len({c['id'] for c in cases}) == 8, 'Wrong control count.')
    require(sum(c['gold']['eligible'] is True for c in cases) == 5, 'Gold eligibility denominator changed.')
    addition = (HERE / 'candidate-addition-draft.txt').read_text().rstrip('\n')
    jobs = []
    for arm, batch in ORDER:
        selected = [c for c in cases if c['batch'] == batch]
        require(len(selected) == 4, 'Wrong batch size.')
        items = [dict(copy.deepcopy(c['question']), index=i) for i, c in enumerate(selected)]
        system, user = solver.build_solver_prompt(items, packet['scope'], audit_choice_pairs=True, choice_slots=True)
        require(system.count(ANCHOR) == 1, 'Prompt anchor changed.')
        baseline = system
        if arm == 'candidate':
            system = system.replace(ANCHOR, ANCHOR + '\n\n' + addition)
            require(system.replace('\n\n' + addition, '', 1) == baseline, 'Candidate span drift.')
        job = {'index': len(jobs), 'arm': arm, 'batch': batch, 'case_ids': [c['id'] for c in selected],
               'items': items, 'system': system, 'user': user}
        job['request'] = constructed_request(job)
        job['request_sha256'] = digest(job['request'])
        jobs.append(job)
    for first, second in ((jobs[0], jobs[1]), (jobs[3], jobs[2])):
        modified = copy.deepcopy(second['request'])
        modified['system'][0]['text'] = modified['system'][0]['text'].replace('\n\n' + addition, '', 1)
        require(modified == first['request'], 'Paired request changes beyond one prompt insertion.')
    review_path = HERE / 'independent-gold-review.json'
    review = safe.strict_json(review_path.read_text()) if review_path.exists() else None
    if review:
        require(review.get('approved') is True and review.get('reviewed_packet_sha256') == sha(HERE / 'controls-draft.json'), 'Gold review binding failed.')
    paths = [*modules, SERVICE / 'requirements.txt', HELPER,
             *[HERE / n for n in ('controls-draft.json', 'candidate-addition-draft.txt', 'offline-checks.json',
                                   'ANALYSIS_AND_PLAN_DRAFT.md', 'pair_probe.py', 'test_pair_probe.py')]]
    paths += [review_path] if review else []
    for source in packet['source_files']:
        p = HERE.parents[2] / source['path']
        require(sha(p) == source['sha256'], 'Historical evidence drift.')
        paths.append(p)
    return {'state': 'draft', 'source_root': str(SERVICE), 'source_hashes': {str(p): sha(p) for p in paths},
            'environment': ENV, 'endpoint': ENDPOINT, 'jobs': jobs, 'controls': cases, 'scope': packet['scope'],
            'gold_review': review, 'limits': {'maximum_calls': 4, 'items_per_call': 4, 'read_seconds': 100,
                                              'connect_seconds': 3, 'sdk_total_attempts': 1},
            'native_contract': native.contract_metadata(native.SolverSlotContract(4)),
            'dependencies': {'python': sys.version.split()[0], 'boto3': boto3.__version__, 'botocore': botocore.__version__},
            'per_arm_denominators': {'eligibility': 8, 'choices': 32, 'pairs': 48, 'eligible': 5, 'defective': 3},
            'failure_policy': 'Ordinary provider, safety, timeout, late-output or malformed-response failure gives zero credit for that call and continues fixed independent calls. Only setup/credentials/source/request/capture integrity or actual reservation/call ceiling failure stops globally. No retries, replacements, or global elapsed cap.',
            'claim_limits': 'Matched known controls; not a worker-yield or semantic-determinism qualification. All visible reasons need independent assessment; previous trials remain unchanged.'}


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


def assess(adapted, job, plan):
    records = solver.validate_batch(adapted, job['items'], audit_choice_pairs=True, choice_slots=True)
    cases = {c['id']: c for c in plan['controls']}
    rows = []
    for record, item, id in zip(records, job['items'], job['case_ids'], strict=True):
        gold = cases[id]['gold']
        choices = {c['choice']: c['judgment'] for c in gold['choices']}
        pairs = {frozenset([p['leftChoice'], p['rightChoice']]): p['relation'] for p in gold['choicePairs']}
        veto = solver.rejection_reason(record, item, audit_choice_pairs=True)
        rows.append({'case_id': id, 'eligible': veto is None, 'veto': veto, 'expected_eligible': gold['eligible'],
                     'eligibility_agrees': (veto is None) == gold['eligible'],
                     'choices': [{**c, 'expected_judgment': choices[c['choice']],
                                  'agrees': c['judgment'] == choices[c['choice']]} for c in record['choices']],
                     'pairs': [{**p, 'expected_relation': pairs[frozenset([p['leftChoice'], p['rightChoice']])],
                                'agrees': p['relation'] == pairs[frozenset([p['leftChoice'], p['rightChoice']])]}
                               for p in record['choicePairs']]})
    return {'structural_valid': True, 'rows': rows}


def summarize(capture):
    result = {}
    for arm in ('baseline', 'candidate'):
        calls = [c for c in capture['calls'] if c['arm'] == arm]
        rows = [r for c in calls if c['status'] == 'assessed' for r in c['assessment']['rows']]
        result[arm] = {'planned_calls': 2, 'attempted_calls': sum(c['dispatch_attempted'] for c in calls),
                       'structurally_valid_calls': sum(c['status'] == 'assessed' for c in calls),
                       'unattempted_items': sum(4 for c in calls if not c['dispatch_attempted']),
                       'failed_items': sum(4 for c in calls if c['dispatch_attempted'] and c['status'] != 'assessed'),
                       'assessed_items': len(rows), 'eligibility_denominator': 8, 'choice_denominator': 32, 'pair_denominator': 48,
                       'eligibility_correct': sum(r['eligibility_agrees'] for r in rows),
                       'choice_correct': sum(c['agrees'] for r in rows for c in r['choices']),
                       'pair_correct': sum(p['agrees'] for r in rows for p in r['pairs']),
                       'eligible_retained_of_5': sum(r['eligible'] and r['expected_eligible'] for r in rows),
                       'defective_excluded_of_3': sum(not r['eligible'] and not r['expected_eligible'] for r in rows),
                       'independent_reason_audit': 'pending', 'qualified': False}
    return result


def run_calls(plan, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic):
    require(len(plan['jobs']) == 4 and plan['limits']['maximum_calls'] == 4, 'Fixed call ceiling changed.')
    capture = {'plan': copy.deepcopy(plan), 'started_at': datetime.now(timezone.utc).isoformat(),
               'status': 'running', 'reservations': [], 'calls': [
                   {'index': j['index'], 'arm': j['arm'], 'batch': j['batch'], 'case_ids': j['case_ids'],
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
                    retained, omitted = safe.safe_response(response, secrets)
                    visible = json.dumps(retained, ensure_ascii=False)
                    guard(not any(s and s in visible for s in secrets), 'Credential echo in visible output.')
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
                row['status'] = 'assessed'
        except Exception as error:
            row.update(status='failed', local_error=safe.safe_error(error, secrets))
            if setup_failure(error):
                capture['global_stop'] = capture.get('global_stop', 'setup_or_integrity')
            elif not isinstance(error, (ProviderError, SafetyInterventionError, solver.CompleteSolutionFormatError, IntegrityError)):
                capture['global_stop'] = 'unexpected_harness_failure'
        finally:
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
    require(plan['state'] == 'frozen' and plan['gold_review'] is not None, 'Reviewed frozen plan required.')
    check_plan(plan, PLAN, expected_hash)
    require(not CAPTURE.exists(), 'No resume or overwrite.')
    try:
        session, secrets = safe.credential_session()
    except Exception as error:
        capture = {'plan': plan, 'status': 'globally_stopped', 'global_stop': 'credential_setup',
                   'error': safe.safe_error(error), 'calls': [
                       {'arm': j['arm'], 'status': 'unattempted', 'dispatch_attempted': False} for j in plan['jobs']]}
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
    args = parser.parse_args()
    if args.prepare:
        plan = build_plan()
        save(DRAFT, plan)
        print(json.dumps({'draft_sha256': sha(DRAFT), 'digest': digest(plan)}))
    elif args.freeze:
        plan = safe.strict_json(DRAFT.read_text())
        require(sha(DRAFT) == args.freeze and plan['gold_review'] is not None, 'Reviewed exact draft required.')
        check_plan(plan)
        save(PLAN, {**plan, 'state': 'frozen'}, exclusive=True)
        print(sha(PLAN))
    else:
        execute(args.execute)
