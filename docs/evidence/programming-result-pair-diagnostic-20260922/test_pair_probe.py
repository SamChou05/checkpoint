"""Offline real-request/native-adapter tests; every client is a fake."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError, ReadTimeoutError

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('programming_pair_probe_tested', HERE / 'pair_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class Fake:
    def __init__(self, plan, modify=None, factory_modify=None):
        self.plan, self.modify, self.factory_modify = plan, modify, factory_modify
        self.calls, self.now = [], 0.0

    def factory(self, *args, **kwargs):
        client = SimpleNamespace(meta=SimpleNamespace(config=kwargs['config'], endpoint_url=probe.ENDPOINT, region_name='us-east-1'),
                                 converse=self.converse)
        if self.factory_modify:
            self.factory_modify(client)
        return client

    def converse(self, **request):
        index = len(self.calls)
        self.calls.append(copy.deepcopy(request))
        job = next(j for j in self.plan['jobs'] if j['request'] == request)
        data = json.loads(job['user'].split('\n', 1)[1].rsplit('\n', 1)[0])
        cases = {c['id']: c for c in self.plan['controls']}
        payload = {'solutions': {}}
        for item, case_id in zip(data['items'], job['case_ids'], strict=True):
            gold = cases[case_id]['gold']
            choices = {c['choice']: c for c in gold['choices']}
            pairs = {frozenset([p['leftChoice'], p['rightChoice']]): p for p in gold['choicePairs']}
            payload['solutions'][str(item['index'])] = {
                'choices': {slot: {'reason': choices[text]['proof'], 'judgment': choices[text]['judgment']} for slot, text in item['choices'].items()},
                'choicePairs': {slot: {'reason': pairs[frozenset(endpoints.values())]['proof'],
                                       'relation': pairs[frozenset(endpoints.values())]['relation']}
                                for slot, endpoints in item['choicePairs'].items()}}
        response = {'output': {'message': {'content': [{'text': json.dumps(payload)}]}}, 'stopReason': 'end_turn',
                    'usage': {'inputTokens': 10, 'outputTokens': 20}}
        return self.modify(index, payload, response) if self.modify else response


class PairProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, 'connect', side_effect=AssertionError('No network in preflight')))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'capture.json'
        self.plan = probe.build_plan()

    def run_fake(self, fake=None, pins=lambda: None, **kwargs):
        fake = fake or Fake(self.plan)
        result = probe.run_calls(self.plan, self.path, fake.factory, pins, clock=lambda: fake.now, **kwargs)
        return result, fake

    def test_actual_four_requests_have_only_the_approved_prompt_delta(self):
        self.assertEqual([j['arm'] for j in self.plan['jobs']], ['baseline', 'candidate', 'candidate', 'baseline'])
        addition = (HERE / 'candidate-addition-draft.txt').read_text().rstrip('\n')
        for b, c in ((0, 1), (3, 2)):
            baseline, candidate = self.plan['jobs'][b]['request'], copy.deepcopy(self.plan['jobs'][c]['request'])
            candidate['system'][0]['text'] = candidate['system'][0]['text'].replace('\n\n' + addition, '', 1)
            self.assertEqual(candidate, baseline)
            self.assertEqual(baseline['inferenceConfig'], {'maxTokens': 16000})
            self.assertEqual(baseline['additionalModelRequestFields'], {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}})
            self.assertEqual(baseline['outputConfig']['textFormat']['structure']['jsonSchema']['name'], 'complete_choice_solver_v5_n4')
        for job in self.plan['jobs']:
            data = json.loads(job['user'].split('\n', 1)[1].rsplit('\n', 1)[0])
            for item in data['items']:
                self.assertEqual(set(item), {'index', 'prompt', 'choices', 'choicePairs'})
                for pair, endpoints in item['choicePairs'].items():
                    self.assertEqual(endpoints, {'leftChoice': item['choices'][pair[0]], 'rightChoice': item['choices'][pair[1]]})

    def test_all_gold_runs_through_actual_runtime_native_adapter_and_gate(self):
        result, fake = self.run_fake()
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(len(result['reservations']), 4)
        for arm in result['summary'].values():
            self.assertEqual((arm['eligibility_correct'], arm['choice_correct'], arm['pair_correct']), (8, 32, 48))
            self.assertEqual((arm['eligible_retained_of_5'], arm['defective_excluded_of_3']), (5, 3))
            self.assertFalse(arm['qualified'])
        self.assertTrue(all(r['runtime_budget_calls'] == 1 for r in result['reservations']))

    def test_ordinary_timeout_provider_safety_and_non_end_turn_continue(self):
        for mode in ('timeout', 'throttled', 'safety', 'max_tokens', 'stop_sequence'):
            with self.subTest(mode=mode):
                path = Path(self.directory.name) / (mode + '.json')
                def modify(i, payload, response):
                    if i:
                        return response
                    if mode == 'timeout':
                        raise ReadTimeoutError(endpoint_url=probe.ENDPOINT)
                    if mode == 'throttled':
                        raise ClientError({'Error': {'Code': 'ThrottlingException', 'Message': 'bounded'}}, 'Converse')
                    response['stopReason'] = 'guardrail_intervened' if mode == 'safety' else mode
                    return response
                fake = Fake(self.plan, modify)
                result = probe.run_calls(self.plan, path, fake.factory, lambda: None, clock=lambda: fake.now)
                self.assertEqual(len(fake.calls), 4)
                self.assertNotIn('global_stop', result)
                self.assertEqual(result['summary']['baseline']['failed_items'], 4)
                self.assertEqual(result['summary']['candidate']['assessed_items'], 8)

    def test_malformed_native_and_local_bounds_zero_whole_batch_and_continue(self):
        for mode in ('json', 'unknown_id', 'long_reason', 'blank_reason', 'nonfinite', 'duplicate_json'):
            with self.subTest(mode=mode):
                def modify(i, payload, response):
                    if i:
                        return response
                    if mode == 'json':
                        raw = 'not json'
                    elif mode == 'duplicate_json':
                        raw = '{"solutions":{},"solutions":{}}'
                    else:
                        if mode == 'unknown_id':
                            payload['solutions']['99'] = payload['solutions'].pop('0')
                        elif mode == 'nonfinite':
                            payload['solutions']['0']['choices']['a']['reason'] = float('nan')
                        else:
                            payload['solutions']['0']['choices']['a']['reason'] = 'x' * 601 if mode == 'long_reason' else ' '
                        raw = json.dumps(payload)
                    response['output']['message']['content'][0]['text'] = raw
                    return response
                fake = Fake(self.plan, modify)
                result = probe.run_calls(self.plan, Path(self.directory.name) / (mode + '.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 4)
                self.assertNotIn('global_stop', result)
                self.assertNotIn('assessment', result['calls'][0])
                self.assertEqual(result['summary']['baseline']['eligibility_denominator'], 8)
                self.assertEqual(result['summary']['baseline']['choice_denominator'], 32)
                self.assertEqual(result['summary']['baseline']['pair_denominator'], 48)

    def test_late_normal_output_loses_credit_but_continues(self):
        fake = Fake(self.plan)
        def modify(i, payload, response):
            fake.now += 100.1 if i == 0 else 1
            return response
        fake.modify = modify
        result, _ = self.run_fake(fake)
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(result['calls'][0]['local_error']['type'], 'ElapsedCreditLimit')
        self.assertNotIn('assessment', result['calls'][0])
        self.assertEqual(result['summary']['baseline']['failed_items'], 4)
        self.assertNotIn('global_stop', result)

    def test_wrong_semantic_label_does_not_masquerade_as_structure_failure(self):
        def modify(i, payload, response):
            if i == 0:
                payload['solutions']['0']['choicePairs']['ab']['relation'] = 'uncertain'
                response['output']['message']['content'][0]['text'] = json.dumps(payload)
            return response
        result, _ = self.run_fake(Fake(self.plan, modify))
        self.assertEqual(result['calls'][0]['status'], 'assessed')
        self.assertEqual(result['summary']['baseline']['pair_correct'], 47)

    def test_credentials_and_native_configuration_errors_stop_all_later_calls(self):
        for code in ('ExpiredTokenException', 'AccessDeniedException', 'InvalidSignatureException', 'ValidationException'):
            with self.subTest(code=code):
                def modify(i, payload, response):
                    raise ClientError({'Error': {'Code': code, 'Message': 'safe diagnostic'}}, 'Converse')
                fake = Fake(self.plan, modify)
                result = probe.run_calls(self.plan, Path(self.directory.name) / (code + '.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 1)
                self.assertTrue('global_stop' in result)
                self.assertEqual(sum(a['unattempted_items'] for a in result['summary'].values()), 12)
                self.assertEqual(sum(a['eligibility_denominator'] for a in result['summary'].values()), 16)

    def test_factory_setup_failure_has_full_denominators_and_no_dispatch(self):
        def fail(*args, **kwargs):
            raise RuntimeError('synthetic SDK setup')
        result = probe.run_calls(self.plan, self.path, fail, lambda: None)
        self.assertTrue(all(not c['dispatch_attempted'] for c in result['calls']))
        self.assertEqual(sum(a['unattempted_items'] for a in result['summary'].values()), 16)

    def test_transport_and_request_drift_stop_before_dispatch(self):
        for mode in ('endpoint', 'attempts', 'request'):
            with self.subTest(mode=mode):
                plan = copy.deepcopy(self.plan)
                def modify(client):
                    if mode == 'endpoint':
                        client.meta.endpoint_url = 'https://wrong.invalid'
                    elif mode == 'attempts':
                        client.meta.config.retries['total_max_attempts'] = 2
                if mode == 'request':
                    plan['jobs'][0]['request']['inferenceConfig']['maxTokens'] = 1
                fake = Fake(plan, factory_modify=modify)
                result = probe.run_calls(plan, Path(self.directory.name) / (mode + '.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 0)
                self.assertTrue('global_stop' in result)

    def test_source_pin_change_after_response_removes_credit_and_stops(self):
        changed = False
        def modify(i, payload, response):
            nonlocal changed
            changed = True
            return response
        def pins():
            probe.require(not changed, 'Synthetic mid-call source change.')
        result, fake = self.run_fake(Fake(self.plan, modify), pins=pins)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(sum(a['assessed_items'] for a in result['summary'].values()), 0)
        self.assertTrue('global_stop' in result)

    def test_final_assessment_source_drift_loses_credit_and_stops(self):
        changed = False
        original = probe.assess
        def assess(*args):
            nonlocal changed
            result = original(*args)
            if args[1]['index'] == 3:
                changed = True
            return result
        def pins():
            probe.require(not changed, 'Synthetic final-assessment drift.')
        with patch.object(probe, 'assess', assess):
            result, fake = self.run_fake(pins=pins)
        self.assertEqual(len(fake.calls), 4)
        self.assertTrue('global_stop' in result)
        self.assertNotIn('assessment', result['calls'][3])
        self.assertEqual(result['calls'][3]['status'], 'failed')

    def test_external_capture_change_is_detected_and_not_overwritten(self):
        def modify(i, payload, response):
            self.path.write_text('{}\n')
            return response
        fake = Fake(self.plan, modify)
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(fake)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(self.path.read_text(), '{}\n')

    def test_reasoning_and_unbounded_metadata_are_omitted(self):
        secret = 'SYNTHETIC_PRIVATE_CREDENTIAL'
        def modify(i, payload, response):
            response['output']['message']['content'].append({'reasoningContent': {'text': secret, 'signature': secret}})
            response['usage']['private'] = secret
            response['ResponseMetadata'] = {'RequestId': secret, 'HTTPStatusCode': 200, 'Headers': secret}
            return response
        result, _ = self.run_fake(Fake(self.plan, modify), secrets=(secret,))
        self.assertNotIn(secret, self.path.read_text())
        self.assertTrue(all(c['reasoning_blocks_omitted'] == 1 for c in result['calls']))
        self.assertEqual(result['calls'][0]['response']['usage'], {'inputTokens': 10, 'outputTokens': 20})

    def test_visible_credential_echo_is_not_saved_or_scored(self):
        secret = 'SYNTHETIC_VISIBLE_CREDENTIAL'
        def modify(i, payload, response):
            payload['solutions']['0']['choices']['a']['reason'] = secret
            response['output']['message']['content'][0]['text'] = json.dumps(payload)
            return response
        result, fake = self.run_fake(Fake(self.plan, modify), secrets=(secret,))
        self.assertEqual(len(fake.calls), 1)
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn('response', result['calls'][0])
        self.assertTrue('global_stop' in result)

    def test_pins_bind_gold_source_helpers_and_exact_requests_without_global_plan_assumption(self):
        probe.check_plan(self.plan)
        self.assertIn('/question-reliability-investigation/', self.plan['source_root'])
        self.assertTrue(self.plan['gold_review']['approved'])
        self.assertIn(str(probe.HELPER), self.plan['source_hashes'])
        changed = copy.deepcopy(self.plan)
        changed['jobs'][0]['request']['modelId'] = 'wrong'
        with self.assertRaises(probe.IntegrityError):
            probe.check_plan(changed)
        with patch.dict(probe.IMPORTED_HASHES, {'question_generation.py': 'bad'}):
            with self.assertRaises(probe.IntegrityError):
                probe.build_plan()
        path = Path(self.directory.name) / 'plan.json'
        probe.save(path, self.plan, exclusive=True)
        with self.assertRaises(FileExistsError):
            probe.save(path, self.plan, exclusive=True)
        self.assertEqual(json.loads(path.read_text()), self.plan)

    def test_fixed_ceiling_and_no_resume(self):
        result, fake = self.run_fake()
        with self.assertRaises(FileExistsError):
            self.run_fake(fake)
        self.assertEqual(len(fake.calls), 4)
        changed = copy.deepcopy(self.plan)
        changed['limits']['maximum_calls'] = 5
        with self.assertRaises(probe.IntegrityError):
            probe.run_calls(changed, Path(self.directory.name) / 'bad.json', fake.factory, lambda: None)
        self.assertEqual(len(result['reservations']), 4)

    def test_execute_setup_failure_never_activates_account_and_retains_denominators(self):
        path = Path(self.directory.name) / 'frozen.json'
        plan = {**self.plan, 'state': 'frozen'}
        probe.save(path, plan, exclusive=True)
        with patch.object(probe, 'PLAN', path), patch.object(probe, 'CAPTURE', self.path), \
             patch.object(probe.safe, 'credential_session', side_effect=probe.safe.CaptureBoundaryError('bounded setup')) as credentials:
            probe.execute(probe.sha(path))
        self.assertEqual(credentials.call_count, 1)
        result = json.loads(self.path.read_text())
        self.assertEqual(result['global_stop'], 'credential_setup')
        self.assertEqual(sum(a['unattempted_items'] for a in result['summary'].values()), 16)


if __name__ == '__main__':
    unittest.main()
