"""Draft composed-verifier qualification; no author call or provider on preparation."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from unittest.mock import patch

import boto3
import botocore

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = Path('/tmp/checkpoint-authored-feedback-scope/backend/bedrock-question-service')
SOURCE = HERE.parent / 'final-content-audit-20260922/adversarial-plan.json'
EXPECTATIONS = HERE.parent / 'authored-feedback-20260922/known-control-field-expectations-draft.json'
DRAFT, PLAN, CAPTURE = (HERE / name for name in ('plan-draft.json', 'plan.json', 'capture.json'))
MODEL = 'us.anthropic.claude-sonnet-4-6'
ENVIRONMENT = {
    'BEDROCK_REGION': 'us-east-1', 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native',
    'QUESTION_FEEDBACK_CONTRACT': 'authored_feedback', 'BEDROCK_MODEL_ID': MODEL,
    'BEDROCK_VERIFICATION_MODEL_ID': MODEL, 'BEDROCK_FALLBACK_MODEL_ID': '',
    'BEDROCK_CLAUDE_THINKING': 'adaptive', 'BEDROCK_CLAUDE_EFFORT': 'high',
    'BEDROCK_MAX_TOKENS': '16000', 'BEDROCK_THINKING_MAX_TOKENS': '16000',
    'BEDROCK_CONNECT_TIMEOUT_SECONDS': '3', 'BEDROCK_READ_TIMEOUT_SECONDS': '100',
    'GENERATION_ATTEMPTS': '1', 'BEDROCK_GUARDRAIL_IDENTIFIER': '', 'BEDROCK_GUARDRAIL_VERSION': '',
    'MIN_PROVIDER_REMAINING_MILLISECONDS': '0', 'BEDROCK_TEMPERATURE': '0.2',
}
sys.path.insert(0, str(SERVICE))
import authored_feedback_audit as audit  # noqa: E402
import authored_feedback_contract as author  # noqa: E402
import authored_feedback_verification as verification  # noqa: E402
import complete_question_solution as solver  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from question_verification import _contains_answer_label_references, _has_reviewable_choices  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402


class IntegrityError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode()).hexdigest()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=True, allow_nan=False) + '\n'
    if exclusive:
        with path.open('x') as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix('.partial')
        temporary.write_text(text)
        temporary.replace(path)


def data(text):
    return json.loads(text.split('\n', 1)[1].rsplit('\n', 1)[0])


def source_cases():
    require(sha(SOURCE) == '7c9fcc97e4259758c85a2b36f0d0d508e71d97040daa41dabb0b10918f0ce315', 'Original control source changed.')
    original = json.loads(SOURCE.read_text())
    expected = json.loads(EXPECTATIONS.read_text())
    by_id = {row['case_id']: row for row in expected['cases']}
    require(len(original['cases']) == len(by_id) == 24, 'Expected all24 controls.')
    for case in original['cases']:
        payload = author.freeze_learner_payload(case['learner_item'])
        require(author.learner_content_digest(payload) == case['learner_content_sha256'], 'Original learner hash changed.')
        require(by_id[case['case_id']]['original_gold_unchanged'] == case['gold'], 'Original whole gold changed.')
        require(_has_reviewable_choices(payload), 'A control no longer passes initial choice validation.')
        require(not any(_contains_answer_label_references(text, payload) for text in [payload['explanation'], *payload['choiceExplanations'].values()]),
                'A control no longer passes initial shuffle-safe validation.')
    return original, by_id


def runtime_scope(original_scope):
    scope = copy.deepcopy(original_scope)
    require(scope.get('skillMap') == [] and type(scope.get('skillMap')) is list,
            'Only the exact empty-list no-skill-map representation may be adapted.')
    scope['skillMap'] = None
    require({key: value for key, value in scope.items() if key != 'skillMap'}
            == {key: value for key, value in original_scope.items() if key != 'skillMap'},
            'Nonempty subject scope cannot be discarded.')
    return scope


def build_plan():
    original, _ = source_cases()
    batches = []
    old_scopes = []
    for previous in original['calls']:
        previous_input = data(previous['provider_request']['messages'][0]['content'][0]['text'])
        old_scopes.append({key: value for key, value in previous_input.items() if key != 'items'})
    require(all(scope == old_scopes[0] for scope in old_scopes), 'Original scopes differ; regrouping needs review.')
    original_scope = old_scopes[0]
    require(set(original_scope) == set(audit.SCOPE_FIELDS), 'Unexpected original scope.')
    scope = runtime_scope(original_scope)
    for start in range(0, 24, 5):
        cases = original['cases'][start:start + 5]
        batches.append({'batch': len(batches), 'scope': copy.deepcopy(scope),
                        'controls': [{'case_id': case['case_id'], 'source_case_index': start + offset,
                                      'source_original_batch': case['batch'],
                                      'learner_sha256': case['learner_content_sha256'], 'whole_gold_sha256': digest(case['gold']),
                                      'required_gate_decision': case['gold']['required_gate_decision']}
                                     for offset, case in enumerate(cases)]})
    for module in (audit, author, verification, solver, native, generation):
        require(Path(module.__file__).resolve().is_relative_to(SERVICE.resolve()), 'Wrong runtime imported.')
    return {'plan_state': 'draft_unapproved',
            'experiment': 'Composed actual blind solver and immutable audit on24 unchanged known learner controls',
            'runtime_source_sha256': {str(path): sha(path) for path in sorted(SERVICE.glob('*.py'))},
            'harness_sha256': {name: sha(HERE / name) for name in ('PLAN.md', 'combined_probe.py', 'test_combined_probe.py')},
            'control_sources_sha256': {str(path.relative_to(ROOT)): sha(path) for path in (SOURCE, EXPECTATIONS)},
            'dependencies': {'python': sys.version.split()[0], 'boto3': boto3.__version__, 'botocore': botocore.__version__,
                             'jsonschema_offline_only': importlib.metadata.version('jsonschema')},
            'environment': ENVIRONMENT, 'batches': batches,
            'scope_representation': {'original': original_scope, 'original_sha256': digest(original_scope),
                                     'runtime': scope, 'runtime_sha256': digest(scope),
                                     'sole_transformation': 'skillMap: [] becomes null, the actual runtime representation of no skill map; all goal/source text is unchanged.'},
            'contracts': {'solver_counts': {str(count): native.contract_metadata(native.SolverSlotContract(count)) for count in (4, 5)},
                          'audit_survivor_counts': {str(count): native.contract_metadata(native.AuthoredFeedbackReviewContract(count)) for count in range(1, 6)}},
            'limits': {'fixed_batches': 5, 'originals_per_batch': [5, 5, 5, 5, 4], 'maximum_provider_calls_per_batch': 2,
                       'maximum_provider_calls_total': 10, 'context_milliseconds_per_batch': 240000,
                       'connect_timeout_seconds': 3, 'read_timeout_ceiling_seconds': 100, 'sdk_total_max_attempts': 1},
            'primary_criteria': {'all_five_batches_complete_normally': True, 'all24_admission_decisions_correct': True,
                                 'sound_retained': 12, 'defective_excluded': 12, 'all_selected_learner_fields_exactly_original': True,
                                 'each_dispatched_stage_end_turn': True, 'all_actual_transport_and_batch_deadlines_met': True},
            'difficulty_policy': 'minimumDifficulty1 and no adaptive targets; all valid1..5 assessments pass content gating. Difficulty is diagnostic, not a failure rescue.',
            'procedure': 'Treat originals as frozen trusted author outputs without author inference. Call actual verify_authored_feedback with production _generate_with_bedrock solver/audit closures. Keep actual _bedrock_client and ProviderCallBudget; recording wrapper observes their SDK calls. Dense audit survivors and zero-survivor audit skipping are determined only by the actual runtime. No retry or top-up.',
            'failure_policy': 'Ordinary provider, malformed model output, stop-reason or deadline failure ends only that fixed batch; continue the next independent batch without replacement. Such batches earn no semantic credit. Global credentials/access/setup or source/config/settings/binding/content/budget-integrity failures stop all remaining work. Recheck every runtime, harness and source-artifact pin before and after every actual dispatch. Never resume an existing capture.',
            'diagnostics': 'Preserve every dispatched stage request, safe response JSON, adapted rows, task/choice/pair/feedback labels, short reasons, difficulty, usage if available, actual SDK timeouts and240s remaining time. No provider reasoning text/signature. No missing audit field is counted correct merely because the solver vetoed its item.',
            'claim_limits': 'Repeated known controls regrouped in original source order5+5+5+5+4 to match worker maximum5. Original scope is identical for every source batch. Only empty skillMap [] is represented as null for actual runtime compatibility, prospectively and identically in both stages. Regrouping changes companion context and is not a causal comparison. This combined test cannot rescue prior standalone failures, qualify fresh author generation or worker yield, establish causal architecture improvement or promise deterministic semantic correctness. No question-bank writes or deployment. Full original gold is referenced by hash rather than duplicated.'}


def validate_plan(plan):
    current = build_plan()
    for field in ('limits', 'environment', 'batches', 'runtime_source_sha256', 'harness_sha256', 'control_sources_sha256', 'contracts', 'scope_representation'):
        require(plan[field] == current[field], f'Frozen {field} changed.')
    require([len(batch['controls']) for batch in plan['batches']] == [5, 5, 5, 5, 4], 'Exactly5+5+5+5+4 original controls required.')


def verify_pins(plan):
    paths = {Path(name): value for name, value in plan['runtime_source_sha256'].items()}
    paths.update({HERE / name: value for name, value in plan['harness_sha256'].items()})
    paths.update({ROOT / name: value for name, value in plan['control_sources_sha256'].items()})
    require(all(path.is_file() and sha(path) == value for path, value in paths.items()),
            'A frozen runtime, harness or source-artifact pin changed.')


SETUP_ERROR_CODES = frozenset({
    'ExpiredToken', 'ExpiredTokenException', 'UnrecognizedClientException',
    'InvalidSignatureException', 'InvalidClientTokenId', 'AccessDenied', 'AccessDeniedException',
    'SignatureDoesNotMatch', 'InvalidAccessKeyId', 'IncompleteSignature',
    'MissingAuthenticationToken', 'MissingAuthenticationTokenException', 'UnauthorizedException',
})
SETUP_ERROR_TYPES = frozenset({
    'NoCredentialsError', 'PartialCredentialsError', 'CredentialRetrievalError',
    'UnknownCredentialError', 'TokenRetrievalError', 'UnauthorizedSSOTokenError',
    'SSOTokenLoadError', 'ProfileNotFound', 'ConfigParseError', 'InvalidConfigError',
})


def setup_failure(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        if type(error).__name__ in SETUP_ERROR_TYPES:
            return True
        response = getattr(error, 'response', None)
        if type(response) is dict and type(response.get('Error')) is dict:
            if response['Error'].get('Code') in SETUP_ERROR_CODES:
                return True
        error = error.__cause__
    return False


def safe_text(value, limit, secrets):
    if type(value) is not str:
        return None
    for secret in sorted((x for x in secrets if type(x) is str and x), key=len, reverse=True):
        value = value.replace(secret, '[REDACTED]')
    value = re.sub(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b', '[REDACTED]', value)
    value = re.sub(r'(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]', value)
    value = re.sub(r'(?i)(aws_secret_access_key|aws_session_token|authorization)(\s*[:=]\s*)[^\s,;]+', r'\1\2[REDACTED]', value)
    return value.encode('utf-8', errors='replace').decode()[:limit]


def safe_error(error, secrets=()):
    response = getattr(error, 'response', {})
    response = response if type(response) is dict else {}
    error_data = response.get('Error', {})
    metadata = response.get('ResponseMetadata', {})
    error_data = error_data if type(error_data) is dict else {}
    metadata = metadata if type(metadata) is dict else {}
    return {'type': safe_text(type(error).__name__, 128, secrets),
            'code': safe_text(error_data.get('Code'), 128, secrets),
            'message': safe_text(error_data.get('Message'), 2000, secrets),
            'request_id': safe_text(metadata.get('RequestId'), 128, secrets),
            'http_status': metadata.get('HTTPStatusCode') if type(metadata.get('HTTPStatusCode')) is int else None}


class BatchContext:
    def __init__(self, clock):
        self.clock, self.started = clock, clock()

    def get_remaining_time_in_millis(self):
        return max(0, int(240000 - (self.clock() - self.started) * 1000))


class Session:
    def __init__(self, plan, capture, path, client_factory, clock, secrets):
        self.plan, self.capture, self.path = plan, capture, path
        self.client_factory, self.clock, self.secrets = client_factory, clock, secrets
        self.total_calls = 0
        self.job = self.budget = self.stage = self.current = None

    def factory(self, *args, **kwargs):
        require(args == ('bedrock-runtime',) and kwargs.get('region_name') == 'us-east-1', 'Unexpected client factory.')
        config = kwargs['config']
        require(config.connect_timeout == 3 and 2 <= config.read_timeout <= 100 and config.retries['total_max_attempts'] == 1,
                'Unsafe actual SDK transport configuration.')
        real = self.client_factory(*args, **kwargs)
        session = self
        class ObservedClient:
            meta = real.meta
            def converse(self, **request):
                return session.observe(real, request)
        return ObservedClient()

    def observe(self, client, request):
        require(self.total_calls < 10 and len(self.job['calls']) < 2, 'Global/per-batch call ceiling exceeded.')
        stage = self.stage
        require(stage is not None and self.budget.calls == len(self.job['calls']) + 1, 'Uncharged or misbound stage dispatch.')
        require(request['modelId'] == MODEL and request['inferenceConfig'] == {'maxTokens': 16000}, 'Model/sampling settings changed.')
        require(request['additionalModelRequestFields'] == {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}}, 'Reasoning configuration changed.')
        require(request['system'] == [{'text': native.native_prompt(stage['system'], stage['contract'])}], 'System prompt binding changed.')
        require(request['messages'] == [{'role': 'user', 'content': [{'text': stage['prompt']}]}], 'Input binding changed.')
        require(request['outputConfig'] == native.native_output_config(stage['contract']), 'Native contract changed.')
        require(set(request) == {'modelId', 'system', 'messages', 'inferenceConfig', 'additionalModelRequestFields', 'outputConfig'}, 'Unexpected provider request fields.')
        verify_pins(self.plan)
        self.total_calls += 1
        cfg = client.meta.config
        row = {'stage': stage['name'], 'count': stage['count'], 'source_case_ids': stage['case_ids'],
               'request': copy.deepcopy(request), 'request_sha256': digest(request), 'dispatch_attempted': True,
               'contract': native.contract_metadata(stage['contract']), 'budget_calls': self.budget.calls,
               'remaining_milliseconds_before': self.budget.remaining_milliseconds(),
               'actual_transport': {'connect_timeout': cfg.connect_timeout, 'read_timeout': cfg.read_timeout,
                                    'sdk_total_max_attempts': cfg.retries['total_max_attempts']}}
        self.job['calls'].append(row)
        self.current = row
        save(self.path, self.capture)
        start = self.clock()
        try:
            response = client.converse(**copy.deepcopy(request))
        except Exception as error:
            row['provider_error'] = safe_error(error, self.secrets)
            if setup_failure(error):
                self.capture['global_stop'] = 'provider_credentials_or_access_setup_failure'
            raise
        else:
            blocks = response.get('output', {}).get('message', {}).get('content', [])
            row['raw'] = '\n'.join(block['text'] for block in blocks if type(block) is dict and type(block.get('text')) is str)
            row['provider_reasoning_blocks_omitted'] = sum(type(block) is dict and 'reasoningContent' in block for block in blocks)
            row['stop_reason'] = safe_text(response.get('stopReason'), 128, self.secrets)
            usage = response.get('usage')
            row['usage'] = ({key: usage[key] for key in ('inputTokens', 'outputTokens', 'totalTokens', 'cacheReadInputTokens', 'cacheWriteInputTokens')
                             if type(usage.get(key)) is int and usage[key] >= 0} if type(usage) is dict else None)
            return response  # Production receives the untouched response; capture omits private blocks.
        finally:
            row['elapsed_seconds'] = round(self.clock() - start, 6)
            row['remaining_milliseconds_after'] = self.budget.remaining_milliseconds()
            save(self.path, self.capture)
            verify_pins(self.plan)


def run_batches(plan, capture, path, client_factory, *, clock=time.monotonic, secrets=()):
    validate_plan(plan)
    require(not capture.get('batches') and not path.exists(), 'Fresh capture required; no resume.')
    original, expectations = source_cases()
    all_cases = {case['case_id']: case for case in original['cases']}
    session = Session(plan, capture, path, client_factory, clock, secrets)
    save(path, capture, exclusive=True)
    with patch.dict(os.environ, ENVIRONMENT), patch.object(boto3, 'client', session.factory):
        for batch in plan['batches']:
            try:
                verify_pins(plan)
            except IntegrityError:
                capture['global_stop'] = 'frozen_source_changed_between_batches'
                break
            cases = [all_cases[descriptor['case_id']] for descriptor in batch['controls']]
            originals = [copy.deepcopy(case['learner_item']) for case in cases]
            before = copy.deepcopy(originals)
            request = {**copy.deepcopy(batch['scope']), 'minimumDifficulty': 1, 'adaptiveSkillPlans': [], 'existingQuestionCoverage': []}
            job = {'batch': batch['batch'], 'case_ids': [case['case_id'] for case in cases], 'calls': [], 'status': 'running'}
            capture.setdefault('batches', []).append(job)
            session.job, session.budget = job, generation.ProviderCallBudget(2, context=BatchContext(clock))
            metrics = {'ProviderCalls': 0, 'BedrockInputTokens': 0, 'BedrockOutputTokens': 0}
            survivor_indices = None
            def stage_call(name, system, prompt, count):
                nonlocal survivor_indices
                supplied = data(prompt)
                require(set(supplied) - {'items', 'existingQuestionCoverage'} == set(audit.SCOPE_FIELDS), 'Unexpected stage scope keys.')
                require(all(supplied.get(key) == request[key] for key in audit.SCOPE_FIELDS), 'Stage scope changed.')
                if name == 'solver':
                    require(not job['calls'] and count == len(originals), 'Solver must see all initial controls exactly once.')
                    require([item['index'] for item in supplied['items']] == list(range(len(originals))), 'Solver identities changed.')
                    for item, source in zip(supplied['items'], originals, strict=True):
                        require(item['prompt'] == source['prompt'] and sorted(item['choices'].values()) == sorted(source['choices']), 'Solver source binding changed.')
                        require(set(item) == {'index', 'prompt', 'choices', 'choicePairs'}, 'Unexpected solver metadata or teaching.')
                    ids = job['case_ids']
                    contract = native.SolverSlotContract(count)
                else:
                    require(survivor_indices is not None and len(job['calls']) == 1 and count == len(survivor_indices) > 0, 'Audit survivor count/order changed.')
                    retained = [originals[i] for i in survivor_indices]
                    require(supplied == audit.build_input(retained, batch['scope'], assignments=[{} for _ in retained], history=[]), 'Dense audit payloads/context changed.')
                    ids = [job['case_ids'][i] for i in survivor_indices]
                    contract = native.AuthoredFeedbackReviewContract(count)
                session.stage = {'name': name, 'count': count, 'case_ids': ids, 'system': system, 'prompt': prompt, 'contract': contract}
                adapted = generation._generate_with_bedrock(normalized_request=request, bedrock_client=None, model_id=MODEL,
                                                            system_prompt=system, user_prompt=prompt, call_budget=session.budget,
                                                            request_metrics=metrics, contract=contract)
                row = session.current
                if row['stop_reason'] != 'end_turn':
                    raise ProviderError('Prospective stage completion requires end_turn.')
                if row['elapsed_seconds'] > 100 or row['remaining_milliseconds_after'] <= 0:
                    raise ProviderError('Prospective elapsed limit failed.')
                row['native_adapter_valid'] = True
                row['adapted_response'] = adapted
                if name == 'solver':
                    items = [{'index': i, 'prompt': source['prompt'], 'choices': source['choices']} for i, source in enumerate(originals)]
                    records = solver.validate_batch(adapted, items, audit_choice_pairs=True, choice_slots=True)
                    vetoes = [solver.rejection_reason(record, source, audit_choice_pairs=True) for record, source in zip(records, originals, strict=True)]
                    survivor_indices = [i for i, veto in enumerate(vetoes) if veto is None]
                    diagnostics = []
                    for index, record in enumerate(records):
                        expected = expectations[job['case_ids'][index]]
                        expected_choices = {value['choice']: value['judgment'] for value in expected['answer_set']['offered_choices']}
                        pairs = {frozenset((value['leftChoice'], value['rightChoice'])): value['expected_relation'] for value in expected['all_six_pair_expectations']}
                        diagnostics.append({'case_id': job['case_ids'][index], 'veto': vetoes[index],
                            'choices': [{**value, 'expected_judgment': {'supported': 'supported', 'unsupported': 'refuted', 'uncertain': 'uncertain'}[expected_choices[value['choice']]]} for value in record['choices']],
                            'choicePairs': [{**value, 'expected_relation': pairs[frozenset((value['leftChoice'], value['rightChoice']))]} for value in record['choicePairs']]})
                    row.update(decoded_records=records, vetoes=vetoes, survivor_source_indices=survivor_indices,
                               diagnostic_rows=diagnostics)
                else:
                    records = audit.validate(adapted, count)
                    diagnostics = []
                    for index, source_index in enumerate(survivor_indices):
                        cid = job['case_ids'][source_index]
                        expected, observed = expectations[cid], records[str(index)]
                        diagnostics.append({'case_id': cid, 'source_index': source_index, 'record': observed,
                                            'expected_task': expected['task']['expected_judgment'],
                                            'expected_answerChoice': expected['answer_set']['expected_answerChoice'],
                                            'expected_feedback': {field: value['expected_judgment'] for field, value in expected['feedback'].items()},
                                            'difficulty_used_for_content_gate': False})
                    row.update(decoded_records=records, diagnostic_rows=diagnostics)
                row['local_stage_valid'] = True
                save(path, capture)
                return adapted
            # Define callbacks separately to preserve actual production call signatures.
            try:
                result = verification.verify_authored_feedback(originals, request,
                    lambda system, prompt, count: stage_call('solver', system, prompt, count),
                    lambda system, prompt, count: stage_call('audit', system, prompt, count), metrics)
                if session.budget.remaining_milliseconds() <= 0:
                    raise ProviderError('Prospective batch completion exceeded its240s context.')
                require(originals == before, 'Original learner content mutated.')
                require(survivor_indices is not None, 'Expected solver stage was skipped.')
                selected = []
                for question in result:
                    content = {field: question[field] for field in author.LEARNER_FIELDS}
                    matches = [i for i, source in enumerate(originals) if content == source]
                    require(len(matches) == 1 and matches[0] not in selected, 'Released content changed or duplicated.')
                    selected.append(matches[0])
                require((len(job['calls']) == 1) == (not survivor_indices), 'Audit skipping mismatch.')
                job.update(status='complete', solver_survivor_indices=survivor_indices,
                           selected_indices=selected, selected_originals=[originals[i] for i in selected],
                           selected_original_hashes=[author.learner_content_digest(originals[i]) for i in selected],
                           decisions=[{'case_id': case['case_id'], 'accepted': i in selected,
                                       'expected_accept': case['gold']['required_gate_decision'] == 'accept',
                                       'matches_gold': (i in selected) == (case['gold']['required_gate_decision'] == 'accept')}
                                      for i, case in enumerate(cases)])
            except (IntegrityError, ServiceConfigurationError) as error:
                job.update(status='integrity_failure', failure=safe_error(error, secrets))
                capture['global_stop'] = 'integrity_or_configuration_failure'
            except (ProviderError, SafetyInterventionError, ValueError) as error:
                cause = error
                integrity_cause = False
                while cause is not None:
                    integrity_cause = integrity_cause or isinstance(cause, (IntegrityError, ServiceConfigurationError))
                    cause = cause.__cause__
                setup_cause = setup_failure(error)
                job.update(status='integrity_failure' if integrity_cause or setup_cause else 'batch_failure', failure=safe_error(error, secrets), selected_originals=[])
                if setup_cause:
                    capture['global_stop'] = 'provider_credentials_or_access_setup_failure'
                if integrity_cause:
                    capture['global_stop'] = 'wrapped_integrity_failure'
            except Exception as error:
                job.update(status='integrity_failure', failure=safe_error(error, secrets))
                capture['global_stop'] = 'provider_credentials_or_access_setup_failure' if setup_failure(error) else 'unexpected_failure'
            job['budget_calls'] = session.budget.calls
            job['remaining_milliseconds'] = session.budget.remaining_milliseconds()
            job['provider_calls_recorded'] = len(job['calls'])
            job['quality_metrics'] = {key: value for key, value in metrics.items() if key != 'ProviderObservations'}
            if session.budget.calls != len(job['calls']):
                job['status'] = 'integrity_failure'
                capture['global_stop'] = 'unaccounted_provider_reservation'
            save(path, capture)
            if capture.get('global_stop'):
                break
    capture['status'] = 'stopped_for_integrity' if capture.get('global_stop') else 'complete_fixed_batches_pending_audit'
    capture['completed_at'] = datetime.now(timezone.utc).isoformat()
    completed = [job for job in capture['batches'] if job['status'] == 'complete']
    capture['denominators'] = {'batches_planned': 5, 'batches_attempted': len(capture['batches']), 'batches_completed': len(completed),
                               'items_planned': 24, 'items_scored': sum(len(job['case_ids']) for job in completed),
                               'items_in_failed_batches': sum(len(job['case_ids']) for job in capture['batches'] if job['status'] != 'complete'),
                               'items_unattempted': 24 - sum(len(job['case_ids']) for job in capture['batches']),
                               'maximum_calls': 10, 'calls_dispatched': session.total_calls,
                               'sound_gold': 12, 'defective_gold': 12}
    decisions = [value for job in completed for value in job['decisions']]
    capture['mechanical_results'] = {
        'admission_decisions_correct': sum(value['matches_gold'] for value in decisions),
        'sound_retained': sum(value['accepted'] and value['expected_accept'] for value in decisions),
        'defective_excluded': sum(not value['accepted'] and not value['expected_accept'] for value in decisions),
        'primary_mechanical_pass': len(completed) == 5 and len(decisions) == 24 and all(value['matches_gold'] for value in decisions),
        'all_private_stage_reasons_require_independent_audit': True,
    }
    save(path, capture)


def freeze(expected):
    require(sha(DRAFT) == expected, 'Draft hash mismatch.')
    draft = json.loads(DRAFT.read_text())
    require(draft == build_plan(), 'Draft source/settings changed.')
    save(PLAN, {**draft, 'plan_state': 'frozen'}, exclusive=True)
    return sha(PLAN)


def execute(expected):
    require(sha(PLAN) == expected, 'Plan hash mismatch.')
    plan = json.loads(PLAN.read_text())
    require(plan == {**build_plan(), 'plan_state': 'frozen'}, 'Frozen source/settings changed.')
    require(not CAPTURE.exists(), 'Capture already exists.')
    credentials = json.loads(subprocess.check_output(['aws', 'configure', 'export-credentials', '--format', 'process'], stderr=subprocess.DEVNULL))
    secret_values = tuple(credentials.get(key) for key in ('AccessKeyId', 'SecretAccessKey', 'SessionToken'))
    environment = {'AWS_ACCESS_KEY_ID': credentials['AccessKeyId'], 'AWS_SECRET_ACCESS_KEY': credentials['SecretAccessKey'],
                   'AWS_SESSION_TOKEN': credentials.get('SessionToken', ''), 'AWS_EC2_METADATA_DISABLED': 'true'}
    del credentials
    # Reset default session so the actual factory uses this explicitly supplied
    # credential context rather than an earlier cached SDK session.
    original_session, original_factory = boto3.DEFAULT_SESSION, boto3.client
    try:
        boto3.DEFAULT_SESSION = None
        with patch.dict(os.environ, environment):
            run_batches(plan, {'plan_sha256': expected, 'status': 'running', 'started_at': datetime.now(timezone.utc).isoformat(), 'batches': []},
                        CAPTURE, original_factory, secrets=secret_values)
    finally:
        boto3.DEFAULT_SESSION = original_session


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    options = parser.add_mutually_exclusive_group(required=True)
    options.add_argument('--draft', action='store_true')
    options.add_argument('--freeze', metavar='REVIEWED_DRAFT_SHA256')
    options.add_argument('--execute', metavar='APPROVED_PLAN_SHA256')
    args = parser.parse_args()
    if args.draft:
        save(DRAFT, build_plan())
        print(json.dumps({'draft_sha256': sha(DRAFT), 'provider_calls': 0, 'frozen': False}))
    elif args.freeze:
        print(json.dumps({'plan_sha256': freeze(args.freeze), 'provider_calls': 0}))
    else:
        execute(args.execute)
