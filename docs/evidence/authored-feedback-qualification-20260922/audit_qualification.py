"""Prospective known-control audit qualification; preparing never dispatches."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import subprocess
import sys
import time

import boto3
import botocore
from botocore.config import Config

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = Path('/tmp/checkpoint-authored-feedback-integration/backend/bedrock-question-service')
HISTORICAL = HERE.parent / 'final-content-audit-20260922'
ANNOTATIONS = HERE.parent / 'authored-feedback-20260922'
DRAFT = HERE / 'plan-draft.json'
PLAN = HERE / 'plan.json'
CAPTURE = HERE / 'capture.json'
MAX_CALLS = 4
COUNT = 6
MODEL = 'us.anthropic.claude-sonnet-4-6'
sys.path.insert(0, str(SERVICE))
import authored_feedback_audit as audit  # noqa: E402
import authored_feedback_contract as author  # noqa: E402
import authored_feedback_verification as verification  # noqa: E402
import native_output_contracts as native  # noqa: E402


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False, separators=(',', ':'))


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def save(path, value, *, exclusive=False):
    # Escaping non-ASCII also preserves malformed surrogate output safely as JSON
    # evidence; decoded learner/request strings are never changed.
    text = json.dumps(value, indent=2, ensure_ascii=True, allow_nan=False) + '\n'
    if exclusive:
        with path.open('x') as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix('.partial')
        temporary.write_text(text)
        temporary.replace(path)


def tagged_data(request):
    text = request['messages'][0]['content'][0]['text']
    return json.loads(text.split('\n', 1)[1].rsplit('\n', 1)[0])


def build_plan():
    old_path = HISTORICAL / 'adversarial-plan.json'
    annotations_path = ANNOTATIONS / 'known-control-field-expectations-draft.json'
    old, expected = json.loads(old_path.read_text()), json.loads(annotations_path.read_text())
    assert sha(old_path) == '7c9fcc97e4259758c85a2b36f0d0d508e71d97040daa41dabb0b10918f0ce315'
    assert len(old['cases']) == len(expected['cases']) == 24
    for path, pinned in expected['source_files'].items():
        assert sha(ROOT / path) == pinned
    expectations = {row['case_id']: row for row in expected['cases']}
    assert len(expectations) == 24
    cases, calls = copy.deepcopy(old['cases']), []
    contract = native.AuthoredFeedbackReviewContract(COUNT)
    assert native.native_prompt(verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT, contract) == verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT
    for sequence, previous in enumerate(old['calls']):
        batch_cases = [case for case in cases if case['batch'] == sequence]
        assert len(batch_cases) == COUNT
        assert previous['batch'] == previous['sequence'] == sequence
        assert previous['case_ids'] == [case['case_id'] for case in batch_cases]
        assert [case['slot'] for case in batch_cases] == [str(i) for i in range(COUNT)]
        previous_data = tagged_data(previous['provider_request'])
        assert set(previous_data) == {'goal', 'skillMap', 'sourceDocuments', 'items'}
        scope = {key: copy.deepcopy(value) for key, value in previous_data.items() if key != 'items'}
        originals = []
        for index, case in enumerate(batch_cases):
            original = author.freeze_learner_payload(case['learner_item'])
            assert original == previous_data['items'][str(index)]
            assert author.learner_content_digest(original) == case['learner_content_sha256']
            annotation = expectations[case['case_id']]
            assert annotation['learner_content_sha256'] == case['learner_content_sha256']
            assert annotation['original_gold_unchanged'] == case['gold']
            originals.append(original)
        data = audit.build_input(originals, scope)
        prompt = '<authored_feedback_audit_json>\n' + json.dumps(data, ensure_ascii=False, allow_nan=False) + '\n</authored_feedback_audit_json>'
        assert prompt == audit.build_user_prompt(originals, scope)
        request = {
            'modelId': MODEL,
            'system': [{'text': native.native_prompt(verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT, contract)}],
            'messages': [{'role': 'user', 'content': [{'text': prompt}]}],
            'inferenceConfig': {'maxTokens': 16000},
            'additionalModelRequestFields': {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}},
            'outputConfig': native.native_output_config(contract),
        }
        calls.append({'sequence': sequence, 'case_ids': previous['case_ids'], 'scope': scope,
                      'request': request, 'request_sha256': digest(request),
                      'source_request_sha256': previous['request_sha256'],
                      'learner_content_sha256': [case['learner_content_sha256'] for case in batch_cases]})
    for module in (audit, author, verification, native):
        assert Path(module.__file__).resolve().is_relative_to(SERVICE.resolve())
    source_pins = {str(path): sha(path) for path in sorted(SERVICE.glob('*.py'))}
    evidence_paths = [old_path, annotations_path, ANNOTATIONS / 'KNOWN_CONTROLS_REVIEW.md']
    evidence_pins = {str(path.relative_to(ROOT)): sha(path) for path in evidence_paths}
    return {
        'plan_state': 'draft_unapproved',
        'experiment': 'Actual immutable authored-feedback audit on 24 unchanged known learner controls',
        'runtime_source_sha256': source_pins,
        'harness_source_sha256': {name: sha(HERE / name) for name in ('PLAN.md', 'audit_qualification.py', 'test_audit_qualification.py')},
        'evidence_sha256': evidence_pins,
        'dependencies': {'python': sys.version.split()[0], 'boto3': boto3.__version__, 'botocore': botocore.__version__,
                         'jsonschema_offline_tests_only': importlib.metadata.version('jsonschema')},
        'cases': cases, 'field_expectations': copy.deepcopy(expected['cases']), 'calls': calls,
        'native_contract': native.contract_metadata(contract),
        'runtime_system_prompt_sha256': hashlib.sha256(verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT.encode()).hexdigest(),
        'limits': {'maximum_calls': MAX_CALLS, 'items_per_call': COUNT, 'planned_items': 24, 'region': 'us-east-1',
                   'connect_timeout_seconds': 3, 'read_timeout_seconds': 75, 'sdk_total_max_attempts': 1,
                   'max_shared_tokens': 16000, 'thinking': 'adaptive', 'effort': 'high', 'temperature': 'omitted'},
        'primary_prospective_criteria': {'structurally_valid_calls': 4, 'all_end_turn': True,
                                       'each_provider_call_at_most_seconds': 75, 'correct_admission_decisions': 24,
                                       'sound_accepted': 12, 'defective_rejected': 12,
                                       'all_selected_payloads_equal_exact_originals': True},
        'diagnostic_reporting': {'task_labels': 24, 'answer_choices': 24, 'feedback_labels': 120, 'concrete_reasons': 144,
                                 'difficulty_values': 24, 'expected_uncertain_feedback_fields': 2,
                                 'uncertainties': copy.deepcopy(expected['root_review_issues']),
                                 'difficulty_gate': 'Permissive predicate always returns True; difficulty is reported independently, not used to rescue or explain admission errors.',
                                 'reason_audit': 'Independent factual and exact-item grounding audit of every task/feedback reason; report errors separately from primary learner admission. No provider reasoningContent is retained.'},
        'failure_policy': 'Stop after the first provider, non-end_turn, elapsed-over-75, native-schema, local-bound/type/identity, or binding failure. No retry, warmup, repair, resume or replacement. Semantic errors alone do not stop the remaining planned calls. Keep all 4 calls/24 items/144 reasons in the denominator.',
        'request_provenance': 'Exact old 24 learner payloads, batch order, choice order and scope. Actual runtime builder hides explicit author keys and difficulty; teaching itself may reveal the intended answer. Gold, expected labels, pair relationships and previous model judgments are never sent.',
        'claim_limits': 'Repeated known diagnostic controls, including paired variants; not fresh controls, worker qualification, an author/solver trial, a controlled causal comparison with prior architectures, semantic determinism, or deployment approval. No old result or criterion is relabeled. No question-bank write occurs.',
    }


def validate_dispatch_plan(plan):
    if len(plan['calls']) != MAX_CALLS or plan['limits']['maximum_calls'] != MAX_CALLS:
        raise ValueError('Exactly four immutable planned calls are required.')
    if len(plan['cases']) != 24 or len(plan['field_expectations']) != 24:
        raise ValueError('All 24 original controls and expectations are required.')
    ordered_ids = [case['case_id'] for case in plan['cases']]
    if len(set(ordered_ids)) != 24 or [cid for job in plan['calls'] for cid in job['case_ids']] != ordered_ids:
        raise ValueError('Every original control must appear exactly once in its original order.')
    by_id = {case['case_id']: case for case in plan['cases']}
    for sequence, job in enumerate(plan['calls']):
        if job['sequence'] != sequence or len(job['case_ids']) != COUNT or len(set(job['case_ids'])) != COUNT:
            raise ValueError('Each call needs six unique controls and its fixed sequence.')
        if digest(job['request']) != job['request_sha256']:
            raise ValueError('Request hash does not match the planned request.')
        data = tagged_data(job['request'])
        originals = [by_id[cid]['learner_item'] for cid in job['case_ids']]
        if data != audit.build_input(originals, job['scope']):
            raise ValueError('Exact source learner content or scope binding changed.')
        if job['learner_content_sha256'] != [author.learner_content_digest(item) for item in originals]:
            raise ValueError('Exact original learner hashes changed.')
        if set(data['items']) != {str(i) for i in range(COUNT)}:
            raise ValueError('Input identities must be exact and closed.')
        for item in data['items'].values():
            if set(item) != {'prompt', 'choices', 'feedback'}:
                raise ValueError('Review input must hide explicit keys, metadata and gold.')


def assess(adapted, job, plan):
    cases = {case['case_id']: case for case in plan['cases']}
    expected = {case['case_id']: case for case in plan['field_expectations']}
    originals = [cases[cid]['learner_item'] for cid in job['case_ids']]
    rows = audit.validate(adapted, COUNT)
    accepted = audit.accepted_indices(adapted, originals, difficulty_gate=lambda _index, _difficulty: True)
    selected = audit.select_accepted(adapted, originals, difficulty_gate=lambda _index, _difficulty: True)
    assert selected == [originals[index] for index in accepted]
    diagnostics = []
    for index, cid in enumerate(job['case_ids']):
        row, gold = rows[str(index)], expected[cid]
        feedback = {}
        for slot in ('main', 'a', 'b', 'c', 'd'):
            expectation = gold['feedback'][slot]['expected_judgment']
            feedback[slot] = {**copy.deepcopy(row['feedback'][slot]), 'expected_judgment': expectation,
                              'label_matches_draft': row['feedback'][slot]['judgment'] == expectation,
                              'interpretation_dependent_expectation': expectation == 'uncertain'}
        actual_accept = index in accepted
        diagnostics.append({'case_id': cid, 'trusted_id': str(index), 'accepted': actual_accept,
                            'expected_accept': gold['original_required_gate_decision'] == 'accept',
                            'admission_matches_gold': actual_accept == (gold['original_required_gate_decision'] == 'accept'),
                            'task': {**copy.deepcopy(row['task']), 'expected_judgment': gold['task']['expected_judgment'],
                                     'label_matches_draft': row['task']['judgment'] == gold['task']['expected_judgment']},
                            'answerChoice': row['answerChoice'], 'expected_answerChoice': gold['answer_set']['expected_answerChoice'],
                            'answer_matches_draft': row['answerChoice'] == gold['answer_set']['expected_answerChoice'],
                            'feedback': feedback, 'difficulty': row['difficulty'], 'difficulty_used_for_content_gate': False})
    selected_hashes = [author.learner_content_digest(value) for value in selected]
    assert selected_hashes == [job['learner_content_sha256'][index] for index in accepted]
    return {'structural_valid': True, 'trusted_identities': COUNT,
            'accepted_indices': accepted, 'selected_originals': selected, 'selected_original_hashes': selected_hashes,
            'all_selected_originals_unchanged': True, 'diagnostic_rows': diagnostics,
            'private_reason_semantics': 'Pending independent output audit; label agreement alone grants no reason-fidelity credit.'}


def _safe_text(value, limit, sensitive_values):
    if type(value) is not str:
        return None
    for secret in sorted((s for s in sensitive_values if type(s) is str and s), key=len, reverse=True):
        value = value.replace(secret, '[REDACTED]')
    value = re.sub(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b', '[REDACTED]', value)
    value = re.sub(r'(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]', value)
    value = re.sub(r'(?i)(aws_secret_access_key|aws_session_token|authorization)(\s*[:=]\s*)[^\s,;]+',
                   r'\1\2[REDACTED]', value)
    return value.encode('utf-8', errors='replace').decode('utf-8')[:limit]


def safe_error_details(error, *, sensitive_values=()):
    response = getattr(error, 'response', None)
    response = response if type(response) is dict else {}
    failure, metadata = response.get('Error'), response.get('ResponseMetadata')
    failure = failure if type(failure) is dict else {}
    metadata = metadata if type(metadata) is dict else {}
    status = metadata.get('HTTPStatusCode')
    return {'type': _safe_text(type(error).__name__, 128, sensitive_values),
            'Error': {'Code': _safe_text(failure.get('Code'), 128, sensitive_values),
                      'Message': _safe_text(failure.get('Message'), 2000, sensitive_values)},
            'HTTPStatus': status if type(status) is int else None,
            'RequestId': _safe_text(metadata.get('RequestId'), 128, sensitive_values)}


def safe_usage(value):
    if type(value) is not dict:
        return None
    return {key: value[key] for key in ('inputTokens', 'outputTokens', 'totalTokens', 'cacheReadInputTokens', 'cacheWriteInputTokens')
            if type(value.get(key)) is int and value[key] >= 0}


def run_calls(client, plan, capture, path, *, sensitive_values=(), monotonic=time.monotonic):
    validate_dispatch_plan(plan)
    if capture.get('calls') or path.exists():
        raise ValueError('A new capture path and empty calls are required; no resume.')
    save(path, capture, exclusive=True)
    for job in plan['calls']:
        row = {'sequence': job['sequence'], 'request': copy.deepcopy(job['request']),
               'request_sha256': job['request_sha256'], 'dispatch_attempted': True}
        capture['calls'].append(row)
        save(path, capture)
        started = monotonic()
        try:
            response = client.converse(**copy.deepcopy(job['request']))
        except Exception as error:
            row['elapsed_seconds'] = round(monotonic() - started, 6)
            row['provider_error'] = safe_error_details(error, sensitive_values=sensitive_values)
            capture['stop_reason'] = 'provider_failure'
        else:
            elapsed = monotonic() - started
            row['elapsed_seconds'] = round(elapsed, 6)
            # Keep learner-visible JSON text only; never persist the response,
            # reasoningContent text/signature, headers, or arbitrary metadata.
            try:
                blocks = response.get('output', {}).get('message', {}).get('content', [])
                row['raw'] = '\n'.join(block['text'] for block in blocks if 'text' in block)
                row['reasoning_content_blocks_omitted'] = sum('reasoningContent' in block for block in blocks)
                row['usage'] = safe_usage(response.get('usage'))
                row['stop_reason'] = _safe_text(response.get('stopReason'), 128, sensitive_values)
            except (TypeError, KeyError, AttributeError):
                capture['stop_reason'] = 'invalid_provider_response'
            if not capture.get('stop_reason'):
                if row['stop_reason'] != 'end_turn':
                    capture['stop_reason'] = 'non_end_turn'
                elif elapsed > 75:
                    capture['stop_reason'] = 'provider_elapsed_limit'
                else:
                    try:
                        adapted = native.adapt_native_response(row['raw'], native.AuthoredFeedbackReviewContract(COUNT))
                        row['native_schema_valid'] = True
                        row['assessment'] = assess(adapted, job, plan)
                    except (ValueError, TypeError, AssertionError) as error:
                        row['validation_error_type'] = type(error).__name__
                        capture['stop_reason'] = 'local_or_binding_failure' if row.get('native_schema_valid') else 'native_schema_failure'
                    except Exception as error:
                        # Runtime ProviderError is not a ValueError. Do not leak
                        # exception strings or accidentally continue a bad batch.
                        row['validation_error_type'] = type(error).__name__
                        capture['stop_reason'] = 'local_or_binding_failure' if row.get('native_schema_valid') else 'native_schema_failure'
        save(path, capture)
        print(json.dumps({key: row.get(key) for key in ('sequence', 'elapsed_seconds', 'native_schema_valid', 'validation_error_type')}), flush=True)
        if capture.get('stop_reason'):
            break
    capture['status'] = 'stopped_after_failure' if capture.get('stop_reason') else 'complete_pending_independent_audit'
    capture['completed_at'] = datetime.now(timezone.utc).isoformat()
    valid = [row for row in capture['calls'] if row.get('assessment', {}).get('structural_valid')]
    capture['denominators'] = {'calls_planned': 4, 'calls_attempted': len(capture['calls']), 'calls_strictly_valid': len(valid),
                               'calls_failed': len(capture['calls']) - len(valid), 'calls_unattempted': 4 - len(capture['calls']),
                               'items_planned': 24, 'items_strictly_assessed': COUNT * len(valid),
                               'items_in_failed_batches': COUNT * (len(capture['calls']) - len(valid)),
                               'items_unattempted': COUNT * (4 - len(capture['calls'])),
                               'reasons_planned': 144, 'reasons_strictly_assessed': 36 * len(valid),
                               'reason_semantics_independently_assessed': 0}
    save(path, capture)


def freeze(expected_draft_hash):
    if sha(DRAFT) != expected_draft_hash:
        raise ValueError('Draft hash mismatch.')
    draft = json.loads(DRAFT.read_text())
    if draft != build_plan():
        raise ValueError('Runtime, evidence or harness changed; root must review a new draft.')
    frozen = {**draft, 'plan_state': 'frozen'}
    save(PLAN, frozen, exclusive=True)
    return sha(PLAN)


def execute(expected_hash):
    if sha(PLAN) != expected_hash:
        raise ValueError('Frozen plan hash mismatch.')
    plan = json.loads(PLAN.read_text())
    if plan != {**build_plan(), 'plan_state': 'frozen'}:
        raise ValueError('Frozen source, evidence, settings or requests changed.')
    validate_dispatch_plan(plan)
    if CAPTURE.exists():
        raise ValueError('The capture already exists; retries/resume are forbidden.')
    credentials = json.loads(subprocess.check_output(['aws', 'configure', 'export-credentials', '--format', 'process'], stderr=subprocess.DEVNULL))
    sensitive_values = tuple(credentials.get(key) for key in ('AccessKeyId', 'SecretAccessKey', 'SessionToken'))
    client = boto3.client('bedrock-runtime', region_name='us-east-1', aws_access_key_id=credentials['AccessKeyId'],
                         aws_secret_access_key=credentials['SecretAccessKey'], aws_session_token=credentials.get('SessionToken'),
                         config=Config(connect_timeout=3, read_timeout=75, retries={'total_max_attempts': 1}))
    del credentials
    assert (client.meta.config.connect_timeout, client.meta.config.read_timeout, client.meta.config.retries['total_max_attempts']) == (3, 75, 1)
    capture = {'plan_sha256': expected_hash, 'status': 'running', 'calls': [], 'started_at': datetime.now(timezone.utc).isoformat()}
    run_calls(client, plan, capture, CAPTURE, sensitive_values=sensitive_values)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--draft', action='store_true')
    actions.add_argument('--freeze', metavar='REVIEWED_DRAFT_SHA256')
    actions.add_argument('--execute', metavar='APPROVED_FROZEN_PLAN_SHA256')
    args = parser.parse_args()
    if args.draft:
        save(DRAFT, build_plan())
        print(json.dumps({'draft_sha256': sha(DRAFT), 'provider_calls': 0, 'frozen': False}))
    elif args.freeze:
        print(json.dumps({'plan_sha256': freeze(args.freeze), 'provider_calls': 0}))
    else:
        execute(args.execute)
