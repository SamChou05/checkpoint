"""Author-only request, capture, denominator and blind-projection tests; no network."""
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
spec = importlib.util.spec_from_file_location('prose_task_probe_tested', HERE / 'author_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def prose(index=0):
    # Synthetic transport fixture, not semantic evaluation gold.
    return {'kind': 'prose', 'question': {
        'prompt': f"At school{index}, replace [walk] with the simple-past form: 'Yesterday the students [walk] home.'",
        'choices': {'a': 'walks', 'b': 'walked', 'c': 'walking', 'd': 'will walk'},
        'correctChoice': 'b', 'explanation': 'The simple-past form of this regular verb is walked.',
        'topic': 'Standard written English', 'difficulty': 2, 'format': 'Multiple Choice'}}


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
        payload = {'questions': [prose(i) for i in range(5)]}
        response = {'output': {'message': {'content': [{'text': json.dumps(payload)}]}}, 'stopReason': 'end_turn',
                    'usage': {'inputTokens': 10, 'outputTokens': 20}}
        return self.modify(index, payload, response) if self.modify else response


class AuthorProbeTests(unittest.TestCase):
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

    def test_actual_native_constructed_requests_differ_only_final_append(self):
        self.assertEqual([j['arm'] for j in self.plan['jobs']], ['baseline', 'candidate', 'candidate', 'baseline'])
        baseline = self.plan['jobs'][0]['request']
        candidate = copy.deepcopy(self.plan['jobs'][1]['request'])
        addition = (HERE / 'candidate-addition-draft.txt').read_text().rstrip('\n')
        self.assertEqual(candidate['system'][0]['text'], baseline['system'][0]['text'] + '\n\n' + addition)
        candidate['system'] = baseline['system']
        self.assertEqual(candidate, baseline)
        self.assertEqual(baseline['inferenceConfig'], {'maxTokens': 6000, 'temperature': 0.2})
        self.assertEqual(baseline['additionalModelRequestFields'], {'thinking': {'type': 'disabled'}})
        self.assertEqual(baseline['outputConfig']['textFormat']['structure']['jsonSchema']['name'], probe.CONSTRUCTED_AUTHOR_CONTRACT)
        self.assertIn('Code constructs quantitative choices', baseline['system'][0]['text'])
        self.assertIn('two testing subject-verb agreement', baseline['messages'][0]['content'][0]['text'])

    def test_actual_frozen_pin_rebuilding_inside_candidate_dispatch_does_not_nest_append(self):
        original = probe.runtime.native_prompt
        result, fake = self.run_fake(pins=lambda: probe.check_plan(self.plan))
        self.assertEqual(len(fake.calls), 4)
        self.assertNotIn('global_stop', result)
        self.assertTrue(all(c['status'] == 'assessed' for c in result['calls']))
        self.assertIs(probe.runtime.native_prompt, original)

    def test_four_author_callbacks_no_solver_and_no_invented_semantic_credit(self):
        result, fake = self.run_fake()
        self.assertEqual(len(fake.calls), 4)
        self.assertEqual(len(result['reservations']), 4)
        for arm in result['summary'].values():
            self.assertEqual(arm['structurally_assessed_slots'], 10)
            self.assertEqual(arm['independent_content_and_variety'], 'pending')
            self.assertFalse(arm['qualified'])
        self.assertTrue(all(r['runtime_budget_calls'] == 1 for r in result['reservations']))
        self.assertTrue(all(c['assessment']['semantic_credit'] is None for c in result['calls']))
        self.assertNotIn('verificationPolicyRevision', json.dumps(result['calls']))

    def test_ordinary_timeout_provider_safety_and_non_end_turn_continue(self):
        for mode in ('timeout', 'throttled', 'safety', 'max_tokens', 'stop_sequence'):
            with self.subTest(mode=mode):
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
                result = probe.run_calls(self.plan, Path(self.directory.name)/(mode+'.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 4)
                self.assertNotIn('global_stop', result)
                self.assertEqual(result['summary']['baseline']['failed_slots'], 5)
                self.assertEqual(result['summary']['candidate']['structurally_assessed_slots'], 10)

    def test_bad_json_native_shape_missing_extra_counts_retain_denominator_without_retry(self):
        for mode in ('json', 'duplicate_json', 'wrong_key', 'missing', 'extra', 'nonfinite'):
            with self.subTest(mode=mode):
                def modify(i, payload, response):
                    if i:
                        return response
                    if mode == 'json':
                        raw = 'not json'
                    elif mode == 'duplicate_json':
                        raw = '{"questions":[],"questions":[]}'
                    elif mode == 'nonfinite':
                        raw = '{"questions":NaN}'
                    else:
                        if mode == 'wrong_key':
                            payload['questions'][0]['question']['correctChoice'] = 'e'
                        elif mode == 'missing':
                            payload['questions'].pop()
                        else:
                            payload['questions'].append(prose(5))
                        raw = json.dumps(payload)
                    response['output']['message']['content'][0]['text'] = raw
                    return response
                fake = Fake(self.plan, modify)
                result = probe.run_calls(self.plan, Path(self.directory.name)/(mode+'.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 4)
                self.assertNotIn('global_stop', result)
                self.assertEqual(result['summary']['baseline']['failed_slots'], 5)
                self.assertEqual(sum(a['requested_slots'] for a in result['summary'].values()), 20)
                projected, mapping = probe.blind_projection(result)
                self.assertEqual(sum(r['requested_slot'] for r in projected['items']), 20)
                self.assertEqual(len(mapping['items']), 21 if mode == 'extra' else 20)
                if mode in ('wrong_key', 'missing', 'extra'):
                    self.assertEqual(len(result['calls'][0]['raw_rows']), {'wrong_key': 5, 'missing': 4, 'extra': 6}[mode])

    def test_malformed_provider_envelope_is_an_ordinary_independent_failure(self):
        for shape in (None, [], {'output': []}, {'output': {'message': []}},
                      {'output': {'message': {'content': None}}}):
            with self.subTest(shape=shape):
                def modify(i, payload, response):
                    return shape if i == 0 else response
                fake = Fake(self.plan, modify)
                path = Path(self.directory.name) / (probe.digest(shape) + '.json')
                result = probe.run_calls(self.plan, path, fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 4)
                self.assertNotIn('global_stop', result)
                self.assertEqual(result['summary']['baseline']['failed_slots'], 5)
                worksheet, _ = probe.blind_projection(result)
                self.assertEqual(len(worksheet['items']), 20)

    def test_late_output_zero_credit_continues_fixed_independent_calls(self):
        def modify(i, payload, response):
            if i == 0:
                fake.now = 100.1
            return response
        fake = Fake(self.plan, modify)
        result, _ = self.run_fake(fake)
        self.assertEqual(len(fake.calls), 4)
        self.assertNotIn('global_stop', result)
        self.assertEqual(result['calls'][0]['local_error']['type'], 'ElapsedCreditLimit')
        self.assertNotIn('assessment', result['calls'][0])

    def test_instruction320_runtime420_bounds_are_separate_and_raw_text_not_repaired(self):
        def modify(i, payload, response):
            for ordinal, count in enumerate((320, 321, 420, 421, 12)):
                payload['questions'][ordinal]['question']['explanation'] = 'x' * count
            response['output']['message']['content'][0]['text'] = json.dumps(payload)
            return response
        result, _ = self.run_fake(Fake(self.plan, modify))
        rows = result['calls'][0]['assessment']['rows']
        self.assertEqual([r['lengths']['author_main_320_pass'] for r in rows], [True, False, False, False, True])
        self.assertEqual([r['lengths']['runtime_bounds_pass'] for r in rows], [True, True, True, False, True])
        self.assertEqual(len(result['calls'][0]['raw_rows'][3]['question']['explanation']), 421)
        self.assertEqual(result['calls'][0]['status'], 'assessed')
        retained = result['calls'][0]['assessment']['sanitizer_diagnostic']['retained']
        self.assertFalse(any(len(q['explanation']) == 421 for q in retained))
        self.assertEqual(result['calls'][0]['assessment']['sanitizer_diagnostic']['quality']['sanitize']['invalid_content'], 1)

    def test_blind_ids_and_rotation_are_position_only_with_separate_unblind_mapping(self):
        result, _ = self.run_fake()
        worksheet, mapping = probe.blind_projection(result)
        self.assertEqual(len(worksheet['items']), 20)
        self.assertEqual([r['id'] for r in worksheet['items']], sorted(r['id'] for r in worksheet['items']))
        self.assertEqual(len({r['id'] for r in worksheet['items']}), 20)
        for row in worksheet['items']:
            self.assertEqual(set(row), {'id', 'requested_slot', 'raw_stem', 'choices', 'projection_shape', 'review'})
        changed = copy.deepcopy(result)
        for call in changed['calls']:
            for row in call['raw_rows']:
                row['question']['correctChoice'] = 'd'
                row['question']['explanation'] = 'HIDDEN NEW KEY MAIN'
        changed_worksheet, changed_map = probe.blind_projection(changed)
        self.assertEqual(worksheet['items'], changed_worksheet['items'])
        self.assertEqual(mapping['items'], changed_map['items'])
        self.assertNotIn('HIDDEN NEW KEY MAIN', json.dumps(changed_worksheet))
        by_id = {r['id']: r for r in worksheet['items']}
        for row in mapping['items']:
            raw = result['calls'][row['call_ordinal']]['raw_rows'][row['question_ordinal']]['question']
            values = [raw['choices'][k] for k in 'abcd']
            self.assertEqual(by_id[row['id']]['choices'], values[row['rotation']:] + values[:row['rotation']])

    def test_credentials_and_native_configuration_errors_stop_all_later_calls(self):
        for code in ('ExpiredTokenException', 'AccessDeniedException', 'InvalidSignatureException', 'ValidationException'):
            with self.subTest(code=code):
                def modify(i, payload, response):
                    raise ClientError({'Error': {'Code': code, 'Message': 'safe diagnostic'}}, 'Converse')
                fake = Fake(self.plan, modify)
                result = probe.run_calls(self.plan, Path(self.directory.name) / (code + '.json'), fake.factory, lambda: None)
                self.assertEqual(len(fake.calls), 1)
                self.assertTrue('global_stop' in result)
                self.assertEqual(sum(a['unattempted_slots'] for a in result['summary'].values()), 15)
                self.assertEqual(sum(a['requested_slots'] for a in result['summary'].values()), 20)

    def test_factory_setup_failure_has_full_denominators_and_no_dispatch(self):
        def fail(*args, **kwargs):
            raise RuntimeError('synthetic SDK setup')
        result = probe.run_calls(self.plan, self.path, fail, lambda: None)
        self.assertTrue(all(not c['dispatch_attempted'] for c in result['calls']))
        self.assertEqual(sum(a['unattempted_slots'] for a in result['summary'].values()), 20)

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
        self.assertEqual(sum(a['structurally_assessed_slots'] for a in result['summary'].values()), 0)
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
            payload['questions'][0]['question']['explanation'] = secret
            response['output']['message']['content'][0]['text'] = json.dumps(payload)
            return response
        result, fake = self.run_fake(Fake(self.plan, modify), secrets=(secret,))
        self.assertEqual(len(fake.calls), 1)
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn('response', result['calls'][0])
        self.assertTrue('global_stop' in result)

    def test_unicode_escaped_credential_echo_stops_before_raw_or_adapted_content_is_saved(self):
        secret = 'SYNTHETIC_ESCAPED_CREDENTIAL'
        def modify(i, payload, response):
            payload['questions'][0]['question']['explanation'] = secret
            raw = json.dumps(payload).replace(secret, ''.join('\\u%04x' % ord(c) for c in secret))
            self.assertNotIn(secret, raw)
            cut = raw.index(' \"')
            response['output']['message']['content'] = [{'text': raw[:cut]}, {'text': raw[cut:]}]
            return response
        result, fake = self.run_fake(Fake(self.plan, modify), secrets=(secret,))
        self.assertEqual(len(fake.calls), 1)
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn('response', result['calls'][0])
        self.assertIsNone(result['calls'][0]['raw_rows'])
        self.assertNotIn('assessment', result['calls'][0])
        self.assertIn('global_stop', result)
        self.assertEqual(sum(a['unattempted_slots'] for a in result['summary'].values()), 15)

    def test_duplicate_json_members_cannot_hide_an_escaped_credential(self):
        secret = 'SYNTHETIC_DUPLICATE_MEMBER_CREDENTIAL'
        escaped = ''.join('\\u%04x' % ord(c) for c in secret)
        def modify(i, payload, response):
            raw = '{"questions":"' + escaped + '","questions":[]}'
            response['output']['message']['content'][0]['text'] = raw
            return response
        result, fake = self.run_fake(Fake(self.plan, modify), secrets=(secret,))
        self.assertEqual(len(fake.calls), 1)
        self.assertIn('global_stop', result)
        self.assertNotIn('response', result['calls'][0])
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn(escaped, self.path.read_text())

    def test_multi_block_assembly_matches_actual_runtime_in_guard_adapter_and_projection(self):
        def modify(i, payload, response):
            raw = response['output']['message']['content'][0]['text']
            cut = raw.index(' "')
            response['output']['message']['content'] = [{'text': raw[:cut]}, {'text': raw[cut:]}]
            return response
        result, fake = self.run_fake(Fake(self.plan, modify))
        self.assertEqual(len(fake.calls), 4)
        self.assertTrue(all(c['status'] == 'assessed' for c in result['calls']))
        self.assertTrue(all(c['raw_rows'] == c['assessment']['raw_rows'] for c in result['calls']))
        worksheet, _ = probe.blind_projection(result)
        self.assertTrue(all(r['projection_shape'] == 'readable_prose' for r in worksheet['items']))
        # A split inside a JSON string must retain the runtime's newline and fail;
        # concatenation without that newline would incorrectly make valid JSON.
        response = {'output': {'message': {'content': [{'text': '{"questions":"a'}, {'text': 'b"}'}]}}}
        self.assertIsNone(probe.raw_rows(response))

    def test_pins_bind_gold_source_helpers_and_exact_requests_without_global_plan_assumption(self):
        probe.check_plan(self.plan)
        self.assertIn('/constructed-quantitative-authoring/', self.plan['source_root'])
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
        self.assertEqual(sum(a['unattempted_slots'] for a in result['summary'].values()), 20)


if __name__ == '__main__':
    unittest.main()
