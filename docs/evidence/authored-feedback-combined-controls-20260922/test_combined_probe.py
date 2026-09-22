"""Offline tests: actual composition and SDK factory, only Converse is fake."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError, NoCredentialsError, PartialCredentialsError, ReadTimeoutError

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('combined_probe', HERE / 'combined_probe.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class Oracle:
    def __init__(self, *, mode=None, clock=None):
        original, self.expected = p.source_cases()
        self.cases = original['cases']
        self.mode, self.clock = mode, clock
        self.batch = -1
        self.requests, self.configs = [], []

    def factory(self, *args, **kwargs):
        self.configs.append(kwargs['config'])
        if self.mode == 'shrinking' and len(self.configs) == 1:
            self.clock.now += 40
        return SimpleNamespace(meta=SimpleNamespace(config=kwargs['config']), converse=self.converse)

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        text = request['messages'][0]['content'][0]['text']
        input_value = p.data(text)
        is_solver = text.startswith('<question_solution_json>')
        if is_solver:
            self.batch += 1
        cases = self.cases[self.batch * 5:self.batch * 5 + 5]
        if len(self.requests) == 1 and self.mode == 'timeout':
            raise ReadTimeoutError(endpoint_url='https://bedrock-runtime.us-east-1.amazonaws.com')
        if len(self.requests) == 1 and self.mode == 'safe_provider_error':
            raise ClientError({'Error': {'Code': 'ValidationException', 'Message': 'Bearer secretvalue AWS_SESSION_TOKEN=anothersecret'},
                               'ResponseMetadata': {'HTTPStatusCode': 400, 'RequestId': 'request-id', 'HTTPHeaders': {'secret': 'never-record'}}}, 'Converse')
        if len(self.requests) == 1 and self.mode == 'shrinking':
            self.clock.now += 95
        if len(self.requests) == 1 and self.mode == 'over_100':
            self.clock.now += 100.1
        if is_solver:
            rows = {}
            for item, case in zip(input_value['items'], cases, strict=True):
                gold = self.expected[case['case_id']]
                labels = {value['choice']: value['judgment'] for value in gold['answer_set']['offered_choices']}
                pairs = {frozenset((value['leftChoice'], value['rightChoice'])): value['expected_relation'] for value in gold['all_six_pair_expectations']}
                choices = {slot: {'reason': 'Oracle test fixture grounded in frozen control gold.',
                                   'judgment': 'refuted' if self.mode == 'zero_survivors' else
                                   {'supported': 'supported', 'unsupported': 'refuted', 'uncertain': 'uncertain'}[labels[choice]]}
                           for slot, choice in item['choices'].items()}
                pair_rows = {slots: {'reason': 'Oracle test fixture checks these exact endpoint meanings.',
                                     'relation': pairs[frozenset((item['choices'][slots[0]], item['choices'][slots[1]]))]}
                             for slots in ('ab', 'ac', 'ad', 'bc', 'bd', 'cd')}
                rows[str(item['index'])] = {'choices': choices, 'choicePairs': pair_rows}
            payload = {'solutions': rows}
        else:
            rows = {}
            scope = {key: input_value[key] for key in p.audit.SCOPE_FIELDS}
            for index, item in input_value['items'].items():
                matches = [case for case in cases if p.audit.build_input([case['learner_item']], scope)['items']['0'] == item]
                assert len(matches) == 1, matches
                gold = self.expected[matches[0]['case_id']]
                rows[index] = {'task': {'reason': gold['task']['proof'], 'judgment': gold['task']['expected_judgment']},
                               'answerChoice': gold['answer_set']['expected_answerChoice'], 'difficulty': 1,
                               'feedback': {field: {'reason': value['proof'], 'judgment': value['expected_judgment']}
                                            for field, value in gold['feedback'].items()}}
            payload = {'reviews': rows}
        if self.mode == 'malformed_audit' and not is_solver and self.batch == 0:
            payload = {'reviews': {}}
        stop = 'stop_sequence' if self.mode == 'stop_sequence' and len(self.requests) == 1 else 'end_turn'
        return {'output': {'message': {'content': [
                    {'reasoningContent': {'reasoningText': {'text': 'PRIVATE-REASONING-MUST-NOT-BE-SAVED', 'signature': 'PRIVATE-SIGNATURE'}}},
                    {'text': json.dumps(payload)}]}},
                'stopReason': stop, 'usage': {'inputTokens': 10, 'outputTokens': 20, 'totalTokens': 30}}


class CombinedProbeTests(unittest.TestCase):
    def run_fake(self, mode=None):
        clock = Clock()
        oracle = Oracle(mode=mode, clock=clock)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.json'
            capture = {'batches': []}
            p.run_batches(p.build_plan(), capture, path, oracle.factory, clock=clock)
            self.assertEqual(capture, json.loads(path.read_text()))
        return capture, oracle

    def test_source_order_scope_gold_and_maximum_worker_size(self):
        plan = p.build_plan()
        original, _ = p.source_cases()
        descriptors = [case for batch in plan['batches'] for case in batch['controls']]
        self.assertEqual([len(batch['controls']) for batch in plan['batches']], [5, 5, 5, 5, 4])
        self.assertEqual([x['case_id'] for x in descriptors], [x['case_id'] for x in original['cases']])
        self.assertEqual([x['source_case_index'] for x in descriptors], list(range(24)))
        self.assertEqual([x['whole_gold_sha256'] for x in descriptors], [p.digest(x['gold']) for x in original['cases']])
        self.assertEqual(plan['scope_representation']['original_sha256'], '6d5f44c5e05aed873a638d7bed3a84e19a88aad2f77e191e21d5e83f1a3ca8c8')
        self.assertTrue(all(batch['scope'] == plan['scope_representation']['runtime'] for batch in plan['batches']))
        self.assertIsNone(plan['batches'][0]['scope']['skillMap'])
        self.assertEqual(plan['limits']['maximum_provider_calls_total'], 10)
        self.assertEqual(plan['plan_state'], 'draft_unapproved')

    def test_scope_adapter_cannot_discard_nonempty_data(self):
        source = {'goal': {'title': 'exact title'}, 'skillMap': [], 'sourceDocuments': [{'text': 'exact source'}]}
        before = copy.deepcopy(source)
        result = p.runtime_scope(source)
        self.assertEqual(source, before)
        self.assertEqual(result, {**source, 'skillMap': None})
        result['goal']['title'] = 'changed'
        self.assertEqual(source, before)
        for invalid in ([{'skills': []}], {'skills': []}, None, False):
            with self.subTest(invalid=invalid), self.assertRaises(p.IntegrityError):
                p.runtime_scope({**source, 'skillMap': invalid})

    def test_oracle_composes_actual_adapters_and_releases_exact_twelve_originals(self):
        capture, oracle = self.run_fake()
        self.assertEqual([job['status'] for job in capture['batches']], ['complete'] * 5, capture)
        self.assertEqual(capture['mechanical_results']['admission_decisions_correct'], 24)
        self.assertEqual(capture['mechanical_results']['sound_retained'], 12)
        self.assertEqual(capture['mechanical_results']['defective_excluded'], 12)
        self.assertTrue(capture['mechanical_results']['primary_mechanical_pass'])
        self.assertEqual(len(oracle.requests), 10)
        self.assertEqual(len(oracle.configs), 10)
        original, _ = p.source_cases()
        expected_hashes = [case['learner_content_sha256'] for case in original['cases'] if case['gold']['required_gate_decision'] == 'accept']
        actual_hashes = [value for job in capture['batches'] for value in job['selected_original_hashes']]
        self.assertEqual(actual_hashes, expected_hashes)
        for job in capture['batches']:
            self.assertEqual(job['budget_calls'], 2)
            self.assertEqual(job['calls'][1]['count'], len(job['solver_survivor_indices']))
            self.assertEqual(job['calls'][1]['source_case_ids'], [job['case_ids'][i] for i in job['solver_survivor_indices']])
            self.assertEqual(job['calls'][0]['contract']['version'], '5')
            self.assertEqual(job['calls'][1]['contract']['version'], '3')

    def test_actual_client_config_no_temperature_and_no_private_reasoning_capture(self):
        capture, oracle = self.run_fake()
        for config in oracle.configs:
            self.assertEqual(config.connect_timeout, 3)
            self.assertEqual(config.read_timeout, 100)
            self.assertEqual(config.retries['total_max_attempts'], 1)
        for request in oracle.requests:
            self.assertEqual(request['modelId'], p.MODEL)
            self.assertEqual(request['inferenceConfig'], {'maxTokens': 16000})
            self.assertEqual(request['additionalModelRequestFields'], {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}})
        self.assertNotIn('PRIVATE-REASONING', json.dumps(capture))
        self.assertNotIn('PRIVATE-SIGNATURE', json.dumps(capture))
        self.assertTrue(all(row['provider_reasoning_blocks_omitted'] == 1 for job in capture['batches'] for row in job['calls']))

    def test_zero_solver_survivors_skip_audit_without_credit_for_sound_items(self):
        capture, oracle = self.run_fake('zero_survivors')
        self.assertEqual(len(oracle.requests), 5)
        self.assertTrue(all(job['status'] == 'complete' and job['solver_survivor_indices'] == [] for job in capture['batches']))
        self.assertEqual(capture['mechanical_results']['admission_decisions_correct'], 12)
        self.assertEqual(capture['mechanical_results']['sound_retained'], 0)
        self.assertFalse(capture['mechanical_results']['primary_mechanical_pass'])

    def test_timeout_is_one_attempt_then_continues_fixed_batches_without_partial_credit(self):
        capture, oracle = self.run_fake('timeout')
        self.assertEqual(len(oracle.requests), 9)
        self.assertEqual([job['status'] for job in capture['batches']], ['batch_failure'] + ['complete'] * 4, capture)
        self.assertEqual(capture['denominators']['items_scored'], 19)
        self.assertEqual(capture['denominators']['items_planned'], 24)
        self.assertNotIn('decisions', capture['batches'][0])
        self.assertNotIn('usage', capture['batches'][0]['calls'][0])
        self.assertFalse(capture['mechanical_results']['primary_mechanical_pass'])

    def test_malformed_audit_rejects_entire_batch_then_continues(self):
        capture, oracle = self.run_fake('malformed_audit')
        self.assertEqual(len(oracle.requests), 10)
        self.assertEqual([job['status'] for job in capture['batches']], ['batch_failure'] + ['complete'] * 4, capture)
        self.assertNotIn('decisions', capture['batches'][0])
        self.assertEqual(capture['denominators']['items_scored'], 19)

    def test_non_end_turn_has_no_semantic_credit(self):
        capture, oracle = self.run_fake('stop_sequence')
        self.assertEqual(len(oracle.requests), 9)
        self.assertEqual(capture['batches'][0]['status'], 'batch_failure', capture)
        self.assertEqual(capture['batches'][0]['calls'][0]['stop_reason'], 'stop_sequence')
        self.assertEqual(capture['denominators']['items_scored'], 19)

    def test_read_timeout_uses_actual_shrinking_production_factory(self):
        capture, oracle = self.run_fake('shrinking')
        self.assertTrue(capture['mechanical_results']['primary_mechanical_pass'], capture)
        self.assertEqual(oracle.configs[0].read_timeout, 100)
        self.assertLess(oracle.configs[1].read_timeout, 100)
        self.assertGreater(oracle.configs[1].read_timeout, 90)
        self.assertEqual(oracle.configs[2].read_timeout, 100)

    def test_stage_elapsed_over_ceiling_fails_then_next_batch_gets_fresh_context(self):
        capture, oracle = self.run_fake('over_100')
        self.assertEqual(capture['batches'][0]['status'], 'batch_failure')
        self.assertEqual(capture['batches'][0]['calls'][0]['elapsed_seconds'], 100.1)
        self.assertEqual(capture['denominators']['items_in_failed_batches'], 5)
        self.assertEqual(capture['denominators']['items_unattempted'], 0)
        self.assertEqual(capture['denominators']['items_scored'], 19)
        self.assertEqual(len(oracle.requests), 9)
        self.assertEqual(capture['batches'][1]['calls'][0]['remaining_milliseconds_before'], 240000)

    def test_existing_capture_is_never_resumed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.json'
            path.write_text('existing immutable output')
            with self.assertRaises(p.IntegrityError):
                p.run_batches(p.build_plan(), {'batches': []}, path, Oracle().factory)
            self.assertEqual(path.read_text(), 'existing immutable output')

    def test_mismatched_plan_fails_before_any_client_or_capture(self):
        plan = p.build_plan()
        plan['limits']['maximum_provider_calls_total'] = 11
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.json'
            with self.assertRaises(p.IntegrityError):
                p.run_batches(plan, {'batches': []}, path, lambda *a, **k: calls.append(k))
            self.assertFalse(path.exists())
        self.assertEqual(calls, [])

    def test_global_integrity_failure_does_not_continue_or_hide_budget_reservation(self):
        original = p.generation._generate_with_bedrock
        def corrupt(**kwargs):
            kwargs['model_id'] = 'unexpected-model'
            return original(**kwargs)
        with patch.object(p.generation, '_generate_with_bedrock', corrupt):
            capture, oracle = self.run_fake()
        self.assertEqual(len(capture['batches']), 1)
        self.assertEqual(capture['status'], 'stopped_for_integrity')
        self.assertFalse(capture['mechanical_results']['primary_mechanical_pass'])
        self.assertEqual(len(oracle.requests), 0)

    def test_credentials_and_access_errors_stop_globally_without_later_dispatch(self):
        errors = [ClientError({'Error': {'Code': code, 'Message': 'Expired or unauthorized'},
                               'ResponseMetadata': {'HTTPStatusCode': 403}}, 'Converse')
                  for code in ('ExpiredTokenException', 'UnrecognizedClientException', 'InvalidSignatureException',
                               'InvalidClientTokenId', 'AccessDeniedException')]
        errors.extend([NoCredentialsError(), PartialCredentialsError(provider='fake', cred_var='secret_key')])
        for error in errors:
            with self.subTest(type=type(error).__name__, code=getattr(error, 'response', {}).get('Error', {}).get('Code')):
                def failure(_self, **request):
                    raise error
                with patch.object(Oracle, 'converse', failure):
                    capture, _ = self.run_fake()
                self.assertEqual(capture['status'], 'stopped_for_integrity', capture)
                self.assertEqual(capture['global_stop'], 'provider_credentials_or_access_setup_failure')
                self.assertEqual(len(capture['batches']), 1)
                self.assertEqual(capture['denominators']['calls_dispatched'], 1)
                self.assertEqual(capture['denominators']['items_scored'], 0)
                self.assertEqual(capture['denominators']['items_unattempted'], 19)
                self.assertEqual(capture['batches'][0]['calls'][0]['provider_error']['type'], type(error).__name__)

    def test_runtime_harness_and_control_pins_rechecked_after_each_dispatch(self):
        original_sha, original_converse = p.sha, Oracle.converse
        for changed_path in (p.SERVICE / 'authored_feedback_audit.py', HERE / 'combined_probe.py', p.SOURCE):
            with self.subTest(path=str(changed_path)):
                changed = [False]
                def fake_sha(path):
                    return '0' * 64 if changed[0] and path == changed_path else original_sha(path)
                def changed_during_dispatch(oracle, **request):
                    response = original_converse(oracle, **request)
                    changed[0] = True
                    return response
                with patch.object(p, 'sha', fake_sha), patch.object(Oracle, 'converse', changed_during_dispatch):
                    capture, oracle = self.run_fake()
                self.assertEqual(capture['status'], 'stopped_for_integrity', capture)
                self.assertEqual(len(oracle.requests), 1)
                self.assertEqual(capture['denominators']['items_scored'], 0)
                self.assertFalse(capture['mechanical_results']['primary_mechanical_pass'])
                self.assertIn('raw', capture['batches'][0]['calls'][0])

    def test_safe_errors_are_bounded_and_do_not_include_raw_headers(self):
        capture, _ = self.run_fake('safe_provider_error')
        row = capture['batches'][0]['calls'][0]
        self.assertEqual(row['provider_error']['code'], 'ValidationException')
        self.assertEqual(row['provider_error']['http_status'], 400)
        self.assertNotIn('secretvalue', json.dumps(capture))
        self.assertNotIn('anothersecret', json.dumps(capture))
        self.assertNotIn('never-record', json.dumps(capture))
        error = ClientError({'Error': {'Code': 'x' * 300, 'Message': 'm' * 4000}, 'ResponseMetadata': {}}, 'Converse')
        sanitized = p.safe_error(error)
        self.assertEqual(len(sanitized['code']), 128)
        self.assertEqual(len(sanitized['message']), 2000)


if __name__ == '__main__':
    unittest.main()
