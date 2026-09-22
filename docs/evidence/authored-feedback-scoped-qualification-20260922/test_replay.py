"""Synthetic replay checks; these fixtures are not provider evidence."""

import copy
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import audit_scoped as probe
import replay
from test_audit_scoped import oracle_raw


class ReplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = json.loads(probe.PLAN.read_text())

    def setUp(self):
        self.enterContext(patch.object(probe.boto3, 'client', side_effect=AssertionError('No network')))
        self.enterContext(patch.object(probe.subprocess, 'check_output', side_effect=AssertionError('No credentials')))

    def completed_oracle(self):
        calls = []
        for job in self.plan['calls']:
            raw = oracle_raw(self.plan, job['sequence'])
            adapted = probe.native.adapt_native_response(raw, probe.native.AuthoredFeedbackReviewContract(6))
            calls.append({'sequence': job['sequence'], 'request': copy.deepcopy(job['request']),
                          'request_sha256': job['request_sha256'], 'raw': raw,
                          'stop_reason': 'end_turn', 'elapsed_seconds': 1.0,
                          'assessment': probe.assess(adapted, job, self.plan)})
        capture = {'calls': calls}
        with patch.object(probe, 'save'):
            probe.finish_capture(capture, Path('unused'))
        return capture

    def test_all_four_exact_oracle_batches_pass_without_network(self):
        capture = self.completed_oracle()
        result = replay.summarize(self.plan, capture)
        self.assertTrue(result['primary_component_criteria_passed'])
        self.assertEqual(result['admission']['correct'], 24)
        self.assertEqual(result['selected_original_count'], 12)
        self.assertEqual(result['denominators']['reasons_strictly_assessed'], 144)
        self.assertEqual(result['actual_reason_before_judgment_fields'], 144)
        self.assertEqual(result['unknown_usage_calls'], 4)
        self.assertIn('Independent audit required', result['private_reason_semantics'])

    def test_malformed_batch_has_zero_credit_while_later_batches_survive(self):
        capture = self.completed_oracle()
        failed = capture['calls'][1]
        broken = json.loads(failed['raw'])
        del broken['reviews']['5']
        failed['raw'] = json.dumps(broken)
        del failed['assessment']
        failed['failure_reason'] = 'native_schema_failure'
        try:
            probe.native.adapt_native_response(failed['raw'], probe.native.AuthoredFeedbackReviewContract(6))
        except Exception as error:
            failed['validation_error_type'] = type(error).__name__
        with patch.object(probe, 'save'):
            probe.finish_capture(capture, Path('unused'))
        result = replay.summarize(self.plan, capture)
        self.assertFalse(result['primary_component_criteria_passed'])
        self.assertEqual(result['denominators']['calls_strictly_valid'], 3)
        self.assertEqual(result['denominators']['items_in_failed_batches'], 6)
        self.assertEqual(result['denominators']['items_unattempted'], 0)
        self.assertTrue(result['request_and_replay_checks'][1]['same_validation_failure_reproduced'])

    def test_changed_request_or_assessment_is_not_repaired(self):
        capture = self.completed_oracle()
        changed = copy.deepcopy(capture)
        changed['calls'][0]['request']['modelId'] = 'different'
        with self.assertRaises(AssertionError):
            replay.summarize(self.plan, changed)
        changed = copy.deepcopy(capture)
        changed['calls'][0]['assessment']['accepted_indices'] = []
        with self.assertRaises(AssertionError):
            replay.summarize(self.plan, changed)

    def test_setup_failure_preserves_empty_denominator_and_vacuous_selection(self):
        capture = {'calls': [], 'stop_reason': 'credentials_or_setup_failure'}
        with patch.object(probe, 'save'):
            probe.finish_capture(capture, Path('unused'))
        result = replay.summarize(self.plan, capture)
        self.assertFalse(result['primary_component_criteria_passed'])
        self.assertEqual(result['denominators']['items_unattempted'], 24)
        self.assertEqual(result['denominators']['reasons_planned'], 144)
        self.assertIsNone(result['selected_content_unchanged'])
        self.assertTrue(result['all_selected_content_checks_are_vacuous'])

    def test_fake_audit_cannot_claim_coverage_with_wrong_bindings(self):
        result = {'plan_sha256': 'synthetic-plan', 'capture_sha256': 'synthetic-capture',
                  **replay.summarize(self.plan, self.completed_oracle())}
        findings = []
        for row in result['diagnostic_rows']:
            for field, value in [('task', row['task']), *row['feedback'].items()]:
                findings.append({'case_id': row['case_id'], 'field': field,
                                 'reason_sha256': hashlib.sha256(value['reason'].encode()).hexdigest(),
                                 'judgment': value['judgment'], 'expected_judgment': value['expected_judgment'],
                                 'review': 'synthetic_fixture_only', 'finding': 'Binding test, not a semantic review.'})
        audit = {'plan_sha256': 'synthetic-plan', 'capture_sha256': 'synthetic-capture',
                 'returned_reason_count': 144, 'reason_denominator': 144, 'missing_reason_count': 0,
                 'all_144_returned_reasons_reviewed': True, 'primary_component_criteria_passed': True,
                 'structural_calls': {'valid': 4, 'planned': 4}, 'selected_original_count': 12,
                 'selected_original_content_unchanged': True, 'findings': findings,
                 'review_categories': {'synthetic_fixture_only': 144}}
        bound = replay.bind_independent_audit(result, audit, 'synthetic-audit-hash')
        self.assertEqual(bound['denominators']['reason_semantics_independently_assessed'], 144)
        self.assertEqual(result['denominators']['reason_semantics_independently_assessed'], 0)
        mutations = [lambda value: value.update(plan_sha256='other-plan'),
                     lambda value: value.update(capture_sha256='other-capture'),
                     lambda value: value.update(returned_reason_count=143),
                     lambda value: value.update(missing_reason_count=1),
                     lambda value: value['findings'].__setitem__(1, copy.deepcopy(value['findings'][0])),
                     lambda value: value['findings'][0].update(reason_sha256='wrong-reason'),
                     lambda value: value['review_categories'].update(synthetic_fixture_only=143)]
        for mutate in mutations:
            changed = copy.deepcopy(audit)
            mutate(changed)
            with self.subTest(mutation=mutate), self.assertRaises(AssertionError):
                replay.bind_independent_audit(result, changed, 'untrusted-audit-hash')
            self.assertEqual(result['denominators']['reason_semantics_independently_assessed'], 0)

    def test_completed_real_audit_keeps_failed_primary_and_missing_reasons(self):
        capture = json.loads(probe.CAPTURE.read_text())
        result = {'plan_sha256': probe.sha(probe.PLAN), 'capture_sha256': probe.sha(probe.CAPTURE),
                  **replay.summarize(self.plan, capture)}
        audit_path = probe.HERE / 'independent-output-audit.json'
        audit = json.loads(audit_path.read_text())
        bound = replay.bind_independent_audit(result, audit, probe.sha(audit_path))
        self.assertFalse(bound['primary_component_criteria_passed'])
        self.assertEqual(bound['denominators']['reason_semantics_independently_assessed'], 72)
        self.assertEqual(bound['independent_reason_review']['missing_unassessed'], 72)
        self.assertEqual(bound['independent_reason_review']['review_categories']['grounded_for_exact_claim'], 62)
        self.assertEqual(bound['independent_audit_sha256'], '9f53dbd5e4ed01d7f654ffa22773be02acfe010033e488111bfc98d303703acc')


if __name__ == '__main__':
    unittest.main()
