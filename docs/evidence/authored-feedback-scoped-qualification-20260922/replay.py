"""Strict no-network replay with independent batch failures and full denominators."""

import copy
from collections import Counter
import hashlib
import json
from unittest.mock import patch

import jsonschema

import audit_scoped as probe


def bind_independent_audit(result, audit, audit_sha256):
    """Grant review coverage only after exact capture, count, and reason joins."""
    assert audit['plan_sha256'] == result['plan_sha256']
    assert audit['capture_sha256'] == result['capture_sha256']
    counts = result['denominators']
    observed = counts['reasons_strictly_assessed']
    planned = counts['reasons_planned']
    for field, expected in (('returned_reason_count', observed), ('reason_denominator', planned),
                            ('missing_reason_count', planned - observed)):
        assert type(audit[field]) is int and audit[field] == expected
    assert audit[f'all_{observed}_returned_reasons_reviewed'] is True
    assert audit['primary_component_criteria_passed'] is result['primary_component_criteria_passed']
    assert audit['structural_calls'] == {'valid': counts['calls_strictly_valid'], 'planned': counts['calls_planned']}
    assert audit['selected_original_count'] == result['selected_original_count']
    assert audit['selected_original_content_unchanged'] is result['selected_content_unchanged']

    expected_findings = {}
    for row in result['diagnostic_rows']:
        for field, value in [('task', row['task']), *row['feedback'].items()]:
            key = (row['case_id'], field)
            assert key not in expected_findings
            expected_findings[key] = {
                'reason_sha256': hashlib.sha256(value['reason'].encode()).hexdigest(),
                'judgment': value['judgment'], 'expected_judgment': value['expected_judgment'],
            }
    assert len(expected_findings) == observed
    assert type(audit['findings']) is list and len(audit['findings']) == observed
    seen, categories = set(), Counter()
    for finding in audit['findings']:
        key = (finding['case_id'], finding['field'])
        assert key in expected_findings and key not in seen
        seen.add(key)
        assert {field: finding[field] for field in expected_findings[key]} == expected_findings[key]
        assert type(finding['review']) is str and finding['review'].strip()
        assert type(finding['finding']) is str and finding['finding'].strip()
        categories[finding['review']] += 1
    assert seen == set(expected_findings)
    assert type(audit['review_categories']) is dict
    assert all(type(value) is int and value > 0 for value in audit['review_categories'].values())
    assert dict(categories) == audit['review_categories']
    assert sum(categories.values()) == observed

    bound = copy.deepcopy(result)
    bound['independent_audit_sha256'] = audit_sha256
    bound['denominators']['reason_semantics_independently_assessed'] = observed
    bound['private_reason_semantics'] = (
        f'Independent audit completed for all {observed} returned reasons; '
        f'{planned - observed} missing reasons remain unassessed. Review does not change primary qualification.'
    )
    bound['independent_reason_review'] = {
        'exact_plan_capture_count_and_reason_bindings_verified': True,
        'reviewed': observed, 'planned': planned, 'missing_unassessed': planned - observed,
        'review_categories': dict(categories),
        'capture_recorded_reason_audit_count': counts['reason_semantics_independently_assessed'],
    }
    return bound


def summarize(plan, capture):
    assert len(capture['calls']) <= 4
    assert capture['status'] != 'running' and capture['status'] != 'preflight'
    checks, assessments = [], []
    actual_order = 0
    for sequence, call in enumerate(capture['calls']):
        job = plan['calls'][sequence]
        assert call['sequence'] == sequence == job['sequence']
        assert call['request'] == job['request']
        assert probe.digest(call['request']) == call['request_sha256'] == job['request_sha256']
        check = {'sequence': sequence, 'exact_request': True,
                 'failure_reason': call.get('failure_reason'), 'strict_credit': False}
        if 'assessment' in call:
            assert not call.get('failure_reason')
            assert call['stop_reason'] == 'end_turn' and call['elapsed_seconds'] <= 100
            schema = json.loads(job['request']['outputConfig']['textFormat']['structure']['jsonSchema']['schema'])
            received = json.loads(call['raw'])
            jsonschema.Draft202012Validator(schema).validate(received)
            adapted = probe.native.adapt_native_response(call['raw'], probe.native.AuthoredFeedbackReviewContract(6))
            assessed = probe.assess(adapted, job, plan)
            assert assessed == call['assessment']
            assessments.append(assessed)
            actual_order += sum(list(value) == ['reason', 'judgment']
                                for row in received['reviews'].values()
                                for value in [row['task'], *row['feedback'].values()])
            check['strict_credit'] = True
            check['actual_native_local_replay_matches'] = True
        elif call.get('failure_reason') in {'native_schema_failure', 'local_or_binding_failure'}:
            try:
                adapted = probe.native.adapt_native_response(call['raw'], probe.native.AuthoredFeedbackReviewContract(6))
                probe.assess(adapted, job, plan)
            except Exception as error:
                assert type(error).__name__ == call['validation_error_type']
                check['same_validation_failure_reproduced'] = True
            else:
                raise AssertionError('Historical malformed-output failure did not recur.')
        else:
            assert call.get('failure_reason')
            check['operational_or_integrity_failure_preserved'] = True
        checks.append(check)

    rows = [row for result in assessments for row in result['diagnostic_rows']]
    selected = [item for result in assessments for item in result['selected_originals']]
    selected_hashes = [value for result in assessments for value in result['selected_original_hashes']]
    assert [probe.author.learner_content_digest(item) for item in selected] == selected_hashes
    exact_content = all(result['all_selected_originals_unchanged'] for result in assessments) if assessments else None
    accepted_good = sum(row['expected_accept'] and row['accepted'] for row in rows)
    rejected_bad = sum(not row['expected_accept'] and not row['accepted'] for row in rows)
    correct_admission = sum(row['admission_matches_gold'] for row in rows)
    denominators = {'calls_planned': 4, 'calls_attempted': len(capture['calls']),
                    'calls_strictly_valid': len(assessments),
                    'calls_failed': len(capture['calls']) - len(assessments),
                    'calls_unattempted': 4 - len(capture['calls']),
                    'items_planned': 24, 'items_strictly_assessed': len(rows),
                    'items_in_failed_batches': 6 * (len(capture['calls']) - len(assessments)),
                    'items_unattempted': 6 * (4 - len(capture['calls'])),
                    'reasons_planned': 144, 'reasons_strictly_assessed': 6 * len(rows),
                    'reason_semantics_independently_assessed': 0}
    assert denominators == capture['denominators']
    primary = (not capture.get('stop_reason') and len(assessments) == 4
               and correct_admission == 24 and accepted_good == rejected_bad == 12 and exact_content is True)
    feedback = [value for row in rows for value in row['feedback'].values()]
    known_usages = [row['usage'] for row in capture['calls'] if row.get('usage') is not None]
    return {'primary_component_criteria_passed': primary,
            'global_stop_reason': capture.get('stop_reason'), 'request_and_replay_checks': checks,
            'denominators': denominators,
            'admission': {'correct': correct_admission, 'denominator': 24,
                          'sound_retained': accepted_good, 'sound_denominator': 12,
                          'defective_rejected': rejected_bad, 'defective_denominator': 12,
                          'false_accepts': [row['case_id'] for row in rows if row['accepted'] and not row['expected_accept']],
                          'false_rejects': [row['case_id'] for row in rows if not row['accepted'] and row['expected_accept']]},
            'labels_diagnostic_only': {'task_matches': sum(row['task']['label_matches_draft'] for row in rows),
                                       'task_denominator': 24,
                                       'answer_matches': sum(row['answer_matches_draft'] for row in rows),
                                       'answer_denominator': 24,
                                       'feedback_matches': sum(value['label_matches_draft'] for value in feedback),
                                       'feedback_denominator': 120,
                                       'interpretation_dependent_fields_assessed': sum(value['interpretation_dependent_expectation'] for value in feedback)},
            'actual_reason_before_judgment_fields': actual_order, 'reason_order_denominator': 144,
            'private_reason_semantics': 'Independent audit required; no fidelity credit inferred from label matches.',
            'difficulty_values': dict(sorted(Counter(row['difficulty'] for row in rows).items())),
            'difficulty_used_for_content_gate': False,
            'selected_original_count': len(selected), 'selected_original_hashes': selected_hashes,
            'selected_content_unchanged': exact_content,
            'all_selected_content_checks_are_vacuous': not selected,
            'input_tokens_known': sum(usage.get('inputTokens', 0) for usage in known_usages),
            'output_tokens_known': sum(usage.get('outputTokens', 0) for usage in known_usages),
            'unknown_usage_calls': len(capture['calls']) - len(known_usages),
            'total_elapsed_seconds': round(sum(row['elapsed_seconds'] for row in capture['calls']), 6),
            'maximum_elapsed_seconds': max((row['elapsed_seconds'] for row in capture['calls']), default=None),
            'reasoning_blocks_omitted': sum(row.get('reasoning_content_blocks_omitted', 0) for row in capture['calls']),
            'diagnostic_rows': copy.deepcopy(rows)}


def main():
    with patch.object(probe.boto3, 'client', side_effect=AssertionError('No network')), patch.object(
        probe.subprocess, 'check_output', side_effect=AssertionError('No credentials')
    ):
        plan = json.loads(probe.PLAN.read_text())
        capture = json.loads(probe.CAPTURE.read_text())
        assert capture['plan_sha256'] == probe.sha(probe.PLAN)
        assert {**probe.build_plan(), 'plan_state': 'frozen'} == plan
        probe.check_integrity(plan)
        result = {'plan_sha256': probe.sha(probe.PLAN), 'capture_sha256': probe.sha(probe.CAPTURE),
                  'provider_calls_in_replay': 0, **summarize(plan, capture)}
        audit = probe.HERE / 'independent-output-audit.json'
        if audit.exists():
            result = bind_independent_audit(result, json.loads(audit.read_text()), probe.sha(audit))
        probe.save(probe.HERE / 'replay-summary.json', result)
    print(json.dumps({key: value for key, value in result.items() if key not in {'diagnostic_rows', 'selected_original_hashes'}}))


if __name__ == '__main__':
    main()
