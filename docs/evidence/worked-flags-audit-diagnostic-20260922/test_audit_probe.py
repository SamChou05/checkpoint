"""Small offline guards; no provider factory is called by real request construction."""

import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('worked_audit_probe', Path(__file__).with_name('audit_probe.py'))
p = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(p)
from botocore.exceptions import ClientError, NoCredentialsError, ReadTimeoutError  # noqa: E402
from quantitative_authoring import CompiledCandidate, QuantitativeAuthoringError  # noqa: E402


def response(payload, stop='end_turn'):
    return {'stopReason': stop, 'output': {'message': {'content': [{'text': json.dumps(payload)}]}},
            'usage': {'inputTokens': 10, 'outputTokens': 20}}


class Fake:
    def __init__(self, result, observed, **config):
        self.result, self.observed = result, observed
        self.meta = SimpleNamespace(endpoint_url=p.ENDPOINT, region_name='us-east-1',
            config=SimpleNamespace(read_timeout=config.get('read_timeout', 100), connect_timeout=3,
                                   retries={'total_max_attempts': 1}))

    def converse(self, **request):
        self.observed.append(copy.deepcopy(request))
        if isinstance(self.result, Exception):
            raise self.result
        return self.result() if callable(self.result) else copy.deepcopy(self.result)


class AuditProbeTests(unittest.TestCase):
    def setUp(self):
        self.plan = p.build_plan()
        self.packet = p.controls()
        self.good = [response(p.oracle_native(self.packet['cases'][i:i + 5])) for i in (0, 5)]
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.capture_path = Path(self.temp.name) / 'capture.json'
        self.observed = []

    def run_fake(self, results=None, *, pins=lambda: None, config=None, clock=None, secrets=()):
        self.capture_path.unlink(missing_ok=True)
        remaining = list(results if results is not None else self.good)
        capture = {'status': 'new', 'calls': [], 'batches': []}
        def factory():
            self.assertTrue(remaining, 'Unexpected third factory.')
            result = remaining.pop(0)
            return Fake(result, self.observed, **(config or {}))
        kwargs = {} if clock is None else {'clock': clock}
        p.run(self.plan, capture, self.capture_path, factory, pins, secrets=secrets, **kwargs)
        return capture

    def test_actual_request_building_is_offline_exact_and_has_no_gold(self):
        with patch.object(p.runtime, '_bedrock_client', side_effect=AssertionError('Live factory')), \
             patch.object(p.safe, 'credential_session', side_effect=AssertionError('Credentials')):
            rebuilt = p.build_plan()
        self.assertEqual(rebuilt, self.plan)
        self.assertEqual(self.plan['limits']['items_total'], 10)
        for spec in self.plan['calls']:
            request = spec['request']
            self.assertEqual(request['modelId'], p.MODEL)
            self.assertEqual(request['inferenceConfig'], {'maxTokens': 16000})
            self.assertEqual(request['additionalModelRequestFields']['thinking'], {'type': 'adaptive'})
            self.assertEqual(request['additionalModelRequestFields']['output_config'], {'effort': 'high'})
            self.assertEqual(request['outputConfig'], p.native.native_output_config(p.CONTRACT))
            self.assertEqual([q['index'] for q in spec['input']['items']], list(range(5)))
            for item in spec['input']['items']:
                self.assertTrue({'expectedAnswer', 'difficulty', 'gold', 'spec', 'choiceExplanations',
                                 'independentSolutions', 'source'}.isdisjoint(item))
            self.assertNotIn('independentSolutions', spec['input'])
        a, b = [copy.deepcopy(c['input']) for c in self.plan['calls']]
        for i in range(5):
            self.assertNotEqual(a['items'][i].pop('explanation'), b['items'][i].pop('explanation'))
        self.assertEqual(a, b)

    def test_dry_cli_does_not_create_plan_capture_or_credentials(self):
        plan_path = Path(self.temp.name) / 'absent-plan.json'
        with patch('sys.argv', ['probe', '--plan', str(plan_path), '--capture', str(self.capture_path)]), \
             patch.object(p.safe, 'credential_session', side_effect=AssertionError('Credentials')), \
             patch('sys.stdout', io.StringIO()):
            p.main()
        self.assertFalse(plan_path.exists())
        self.assertFalse(self.capture_path.exists())

    def test_compiled_provenance_rejects_every_corrupt_main(self):
        for good, bad in zip(self.packet['cases'][:5], self.packet['cases'][5:]):
            learner = good['recompiled_learner']
            provenance = CompiledCandidate(json.dumps(good['original_spec']), json.dumps(learner))
            self.assertEqual(provenance.content(learner), learner)
            mutated = {**learner, 'explanation': bad['question']['explanation']}
            with self.assertRaises(QuantitativeAuthoringError):
                provenance.content(mutated)
            for case in (good, bad):
                self.assertTrue(12 <= len(case['question']['explanation']) <= 420)

    def test_two_exact_calls_and_ten_correct_flags_get_only_provisional_credit(self):
        capture = self.run_fake(pins=lambda: p.check_plan(self.plan))
        self.assertEqual(self.observed, [c['request'] for c in self.plan['calls']])
        self.assertEqual(capture['summary']['credited_items'], 10)
        self.assertEqual(capture['summary']['exact_answer_matches'], 10)
        self.assertTrue(capture['summary']['mechanical_criteria_met'])
        self.assertFalse(capture['summary']['qualified'])
        self.assertFalse(capture['summary']['learner_release'])
        self.assertEqual(capture['summary']['input_tokens'], 20)
        self.assertEqual(capture['summary']['output_tokens'], 40)

    def test_timeout_non_end_turn_and_malformed_schema_continue_without_rescue(self):
        payload = p.oracle_native(self.packet['cases'][:5])
        payload['reviews'].pop('4')
        malformed = response(payload)
        for first in (ReadTimeoutError(endpoint_url=p.ENDPOINT), response(payload, 'max_tokens'), malformed):
            with self.subTest(first=type(first).__name__):
                self.observed.clear()
                capture = self.run_fake([first, self.good[1]])
                self.assertEqual(len(self.observed), 2)
                self.assertEqual(capture['batches'][0]['status'], 'failed')
                self.assertEqual(capture['summary']['credited_items'], 5)
                self.assertEqual(capture['summary']['planned_items'], 10)
                self.assertFalse(capture['summary']['mechanical_criteria_met'])
                self.assertNotIn('global_stop', capture)

    def test_late_exact_response_earns_zero_credit_but_second_call_runs(self):
        ticks = iter((0, 100.001, 200, 210))
        capture = self.run_fake(clock=lambda: next(ticks))
        self.assertEqual(len(self.observed), 2)
        self.assertFalse(capture['batches'][0]['structural_pass'])
        self.assertEqual(capture['summary']['credited_items'], 5)

    def test_material_flags_answers_and_ratings_cannot_be_overridden_by_valid(self):
        payload = p.oracle_native(self.packet['cases'][:5])
        payload['reviews']['0']['issueFlags']['explanation'] = True
        payload['reviews']['1']['explanationSupport'] = 'uncertain'
        payload['reviews']['2']['answer'] = '9/4'
        payload['reviews']['3']['difficulty'] = 1
        capture = self.run_fake([response(payload), self.good[1]])
        self.assertFalse(capture['summary']['mechanical_criteria_met'])
        self.assertEqual(capture['summary']['criteria_matching_items'], 6)
        self.assertTrue(all(not r['admitted_by_audit_only'] for r in capture['batches'][0]['assessment'][:4]))

    def test_false_mains_require_unsupported_explanation_flag_and_negative_validity(self):
        payload = p.oracle_native(self.packet['cases'][5:])
        payload['reviews']['0']['valid'] = True
        payload['reviews']['1']['explanationSupport'] = 'uncertain'
        payload['reviews']['2']['issueFlags']['explanation'] = False
        capture = self.run_fake([self.good[0], response(payload)])
        self.assertEqual(capture['summary']['criteria_matching_items'], 7)
        self.assertFalse(capture['summary']['mechanical_criteria_met'])

    def test_wrong_flag_type_is_whole_batch_failure_and_not_filled(self):
        payload = p.oracle_native(self.packet['cases'][:5])
        payload['reviews']['0']['issueFlags']['other'] = 'false'
        capture = self.run_fake([response(payload), self.good[1]])
        self.assertEqual(capture['summary']['credited_items'], 5)
        self.assertNotIn('assessment', capture['batches'][0])

    def test_setup_and_transport_failures_stop_globally(self):
        for error in (NoCredentialsError(), ClientError({'Error': {'Code': 'ExpiredTokenException'}}, 'Converse')):
            capture = self.run_fake([error, self.good[1]])
            self.assertEqual(len(capture['calls']), 1)
            self.assertIn('global_stop', capture)
            self.assertEqual(capture['summary']['credited_items'], 0)
        capture = self.run_fake(config={'read_timeout': 99})
        self.assertEqual(capture['summary']['attempted_calls'], 0)
        self.assertIn('global_stop', capture)

    def test_final_dispatch_source_drift_and_scoring_drift_withhold_all_credit(self):
        for phase in ('provider', 'score'):
            state = {'drift': False}
            def pins():
                p.require(not state['drift'], 'Fake source drift.')
            def last():
                state['drift'] = True
                return self.good[1]
            if phase == 'provider':
                capture = self.run_fake([self.good[0], last], pins=pins)
            else:
                original = p.assess
                def scoring(response, spec, packet):
                    result = original(response, spec, packet)
                    if spec['ordinal'] == 1:
                        state['drift'] = True
                    return result
                with patch.object(p, 'assess', side_effect=scoring):
                    capture = self.run_fake(pins=pins)
            self.assertEqual(capture['summary']['attempted_calls'], 2)
            self.assertEqual(capture['summary']['credited_items'], 0)
            self.assertIn('global_stop', capture)

    def test_completion_pin_is_checked_after_both_assessments(self):
        state = {'checks': 0}
        def pins():
            state['checks'] += 1
            p.require(state['checks'] < 9, 'Final source drift.')
        capture = self.run_fake(pins=pins)
        self.assertEqual(state['checks'], 9)
        self.assertEqual(capture['summary']['credited_items'], 0)
        self.assertIn('global_stop', capture)

    def test_request_hash_resume_and_third_dispatch_are_forbidden(self):
        self.plan['calls'][0]['request']['modelId'] = 'wrong-model'
        capture = self.run_fake()
        self.assertEqual(capture['summary']['attempted_calls'], 0)
        self.assertIn('global_stop', capture)
        self.plan = p.build_plan()
        capture = self.run_fake()
        with self.assertRaises(p.IntegrityError):
            p.run(self.plan, capture, self.capture_path, lambda: self.fail('No resume'), lambda: None)
        self.plan['calls'].append(copy.deepcopy(self.plan['calls'][0]))
        capture = self.run_fake()
        self.assertEqual(capture['summary']['attempted_calls'], 2)
        self.assertIn('global_stop', capture)

    def test_capture_omits_reasoning_headers_and_bounded_errors_redact_credentials(self):
        token = 'sentinel-private-session-token'
        first = copy.deepcopy(self.good[0])
        first['output']['message']['content'].append({'reasoningContent': {'reasoningText': {'text': token, 'signature': token}}})
        first['ResponseMetadata'] = {'RequestId': 'test', 'HTTPStatusCode': 200, 'HTTPHeaders': {'Authorization': token}}
        error = ClientError({'Error': {'Code': 'ThrottlingException', 'Message': token + ' https://private.example/path'}}, 'Converse')
        capture = self.run_fake([first, error], secrets=(token,))
        output = self.capture_path.read_text()
        self.assertNotIn(token, output)
        self.assertNotIn('private.example', output)
        self.assertNotIn('reasoningContent', output)
        self.assertEqual(capture['calls'][0]['reasoning_blocks_omitted'], 1)
        self.assertEqual(capture['summary']['calls_without_usage'], 1)
        self.assertNotIn('global_stop', capture)

    def test_calls_are_persisted_before_dispatch_and_external_changes_not_overwritten(self):
        def persisted():
            saved = json.loads(self.capture_path.read_text())
            self.assertEqual(len(saved['calls']), 1)
            self.assertEqual(saved['calls'][0]['request'], self.plan['calls'][0]['request'])
            self.assertNotIn('response', saved['calls'][0])
            return self.good[0]
        capture = self.run_fake([persisted, self.good[1]])
        self.assertEqual(capture['summary']['credited_items'], 10)
        def tamper():
            self.capture_path.write_text('EXTERNAL EDIT')
            return self.good[0]
        with self.assertRaises(p.IntegrityError):
            self.run_fake([tamper, self.good[1]])
        self.assertEqual(self.capture_path.read_text(), 'EXTERNAL EDIT')
        with self.assertRaises(FileExistsError):
            p.CaptureWriter(self.capture_path, {'status': 'new'})
        self.assertEqual(self.capture_path.read_text(), 'EXTERNAL EDIT')

    def test_any_client_factory_failure_is_global_without_dispatch(self):
        def factory():
            raise RuntimeError('generic SDK setup failure')
        capture = {'status': 'new', 'calls': [], 'batches': []}
        p.run(self.plan, capture, self.capture_path, factory, lambda: None)
        self.assertEqual(capture['summary']['attempted_calls'], 0)
        self.assertEqual(capture['summary']['credited_items'], 0)
        self.assertEqual(capture['global_stop'], 'client_setup_failure')

    def test_root_gold_binding_and_requirements_are_pinned(self):
        self.assertIn(str(p.SERVICE / 'requirements.txt'), self.plan['artifact_hashes'])
        self.assertIn(str(p.HERE / 'root-gold-review.json'), self.plan['artifact_hashes'])
        original = p.safe.strict_json
        def changed(text):
            value = original(text)
            if type(value) is dict and value.get('reviewer') == 'root':
                value['control_sha256'] = 'wrong'
            return value
        with patch.object(p.safe, 'strict_json', side_effect=changed):
            with self.assertRaises(p.IntegrityError):
                p.build_plan()

    def test_wrong_key_on_negative_control_blocks_mechanical_success(self):
        bad = p.oracle_native(self.packet['cases'][5:])
        bad['reviews']['0']['answer'] = '1/2'
        capture = self.run_fake([self.good[0], response(bad)])
        self.assertEqual(capture['summary']['criteria_matching_items'], 10)
        self.assertEqual(capture['summary']['exact_answer_matches'], 9)
        self.assertFalse(capture['summary']['mechanical_criteria_met'])
        self.assertFalse(capture['summary']['qualified'])

    def test_unsafe_visible_output_stops_before_it_can_be_saved(self):
        for text, secrets in (('sentinel-private-session-token', ('sentinel-private-session-token',)),
                              ('x' * (p.safe.VISIBLE_RESPONSE_MAX_BYTES + 1), ())):
            first = copy.deepcopy(self.good[0])
            first['output']['message']['content'][0]['text'] = text
            capture = self.run_fake([first, self.good[1]], secrets=secrets)
            self.assertEqual(capture['summary']['attempted_calls'], 1)
            self.assertIn('global_stop', capture)
            self.assertNotIn('response', capture['calls'][0])
            self.assertNotIn(text, self.capture_path.read_text())


if __name__ == '__main__':
    unittest.main()
