import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError
import jsonschema

import audit_qualification as probe


class FakeClient:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


def oracle_raw(plan, sequence, *, difficulty=1):
    expected = {row['case_id']: row for row in plan['field_expectations']}
    rows = {}
    for index, cid in enumerate(plan['calls'][sequence]['case_ids']):
        gold = expected[cid]
        rows[str(index)] = {
            'task': {'reason': gold['task']['proof'], 'judgment': gold['task']['expected_judgment']},
            'answerChoice': gold['answer_set']['expected_answerChoice'], 'difficulty': difficulty,
            'feedback': {slot: {'reason': field['proof'], 'judgment': field['expected_judgment']}
                         for slot, field in gold['feedback'].items()},
        }
    return json.dumps({'reviews': rows}, ensure_ascii=False)


def response(raw, *, stop='end_turn'):
    return {'output': {'message': {'content': [
        {'reasoningContent': {'reasoningText': {'text': 'PROVIDER_PRIVATE_REASONING', 'signature': 'PRIVATE_SIGNATURE'}}},
        {'text': raw},
    ]}}, 'stopReason': stop, 'usage': {'inputTokens': 100, 'outputTokens': 200, 'totalTokens': 300,
                                     'unexpected_private_field': 'DO_NOT_SAVE'},
        'ResponseMetadata': {'HTTPHeaders': {'authorization': 'DO_NOT_SAVE_HEADER'}}}


class QualificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = probe.build_plan()

    def run_fake(self, replies, *, plan=None, clocks=None):
        plan = copy.deepcopy(plan or self.plan)
        client, capture = FakeClient(replies), {'calls': [], 'status': 'running', 'plan_sha256': 'unit-test-only'}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'capture.json'
            kwargs = {'monotonic': iter(clocks).__next__} if clocks else {}
            with contextlib.redirect_stdout(io.StringIO()):
                probe.run_calls(client, plan, capture, path, **kwargs)
            persisted = path.read_text()
            self.assertEqual(json.loads(persisted), capture)
        return client, capture, persisted

    def test_exact_scope_order_text_and_hidden_fields(self):
        old = json.loads((probe.HISTORICAL / 'adversarial-plan.json').read_text())
        self.assertEqual(self.plan['cases'], old['cases'])
        for call, previous in zip(self.plan['calls'], old['calls'], strict=True):
            self.assertEqual(call['case_ids'], previous['case_ids'])
            data = probe.tagged_data(call['request'])
            before = probe.tagged_data(previous['provider_request'])
            self.assertEqual({key: data[key] for key in ('goal', 'skillMap', 'sourceDocuments')}, call['scope'])
            self.assertEqual(call['scope'], {key: before[key] for key in call['scope']})
            for index, item in data['items'].items():
                original = before['items'][index]
                self.assertEqual(set(item), {'prompt', 'choices', 'feedback'})
                self.assertEqual(item['prompt'], original['prompt'])
                self.assertEqual(list(item['choices'].values()), original['choices'])
                self.assertEqual(item['feedback']['main'], original['explanation'])
                self.assertEqual({text: item['feedback'][slot] for slot, text in item['choices'].items()}, original['choiceExplanations'])

    def test_actual_prompt_contract_model_and_settings(self):
        contract = probe.native.AuthoredFeedbackReviewContract(6)
        self.assertEqual(self.plan['native_contract'], probe.native.contract_metadata(contract))
        for call in self.plan['calls']:
            request = call['request']
            self.assertEqual(request['system'], [{'text': probe.verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT}])
            self.assertIn('Difficulty rubric:', request['system'][0]['text'])
            self.assertEqual(request['modelId'], probe.MODEL)
            self.assertEqual(request['inferenceConfig'], {'maxTokens': 16000})
            self.assertEqual(request['additionalModelRequestFields'], {'thinking': {'type': 'adaptive'}, 'output_config': {'effort': 'high'}})
            self.assertEqual(request['outputConfig'], probe.native.native_output_config(contract))
            self.assertEqual(probe.digest(request), call['request_sha256'])

    def test_all_four_oracle_batches_exactly_preserve_twelve_selected(self):
        before = copy.deepcopy(self.plan)
        replies = [response(oracle_raw(self.plan, i)) for i in range(4)]
        client, capture, persisted = self.run_fake(replies)
        self.assertEqual(self.plan, before)
        self.assertEqual(client.requests, [job['request'] for job in self.plan['calls']])
        self.assertEqual(len(client.requests), 4)
        self.assertEqual(capture['status'], 'complete_pending_independent_audit')
        self.assertEqual(capture['denominators']['items_strictly_assessed'], 24)
        self.assertEqual(capture['denominators']['reasons_strictly_assessed'], 144)
        selected = []
        for row in capture['calls']:
            result = row['assessment']
            selected.extend(result['selected_originals'])
            self.assertTrue(all(item['admission_matches_gold'] for item in result['diagnostic_rows']))
        self.assertEqual(selected, [case['learner_item'] for case in self.plan['cases'] if case['gold']['required_gate_decision'] == 'accept'])
        self.assertEqual(len(selected), 12)
        for hidden in ('PROVIDER_PRIVATE_REASONING', 'PRIVATE_SIGNATURE', 'DO_NOT_SAVE', 'HTTPHeaders'):
            self.assertNotIn(hidden, persisted)
        self.assertTrue(all(row['reasoning_content_blocks_omitted'] == 1 for row in capture['calls']))

    def test_semantic_errors_do_not_stop_or_repair(self):
        replies = []
        for i in range(4):
            raw = json.loads(oracle_raw(self.plan, i))
            for row in raw['reviews'].values():
                row['task']['judgment'] = 'supported'
                row['answerChoice'] = 'a'
                for field in row['feedback'].values():
                    field['judgment'] = 'supported'
            replies.append(response(json.dumps(raw)))
        client, capture, _ = self.run_fake(replies)
        self.assertEqual(len(client.requests), 4)
        self.assertEqual(capture['status'], 'complete_pending_independent_audit')
        self.assertTrue(any(not item['admission_matches_gold'] for call in capture['calls'] for item in call['assessment']['diagnostic_rows']))
        self.assertTrue(all(call['assessment']['all_selected_originals_unchanged'] for call in capture['calls']))

    def test_difficulty_separate_and_permissive(self):
        for difficulty in (1, 5):
            result = probe.assess(oracle_raw(self.plan, 0, difficulty=difficulty), self.plan['calls'][0], self.plan)
            self.assertEqual(result['accepted_indices'], [2, 3, 4])
            self.assertTrue(all(item['difficulty'] == difficulty and not item['difficulty_used_for_content_gate'] for item in result['diagnostic_rows']))

    def test_provider_failure_stops_and_bounds_safe_error(self):
        error = ClientError({'Error': {'Code': 'ValidationException', 'Message': 'ASIAABCDEFGHIJKLMNOP ' + 'x' * 2500},
                             'ResponseMetadata': {'HTTPStatusCode': 400, 'RequestId': 'r' * 300, 'HTTPHeaders': {'secret': 'HIDDEN'}}}, 'Converse')
        client, capture, persisted = self.run_fake([error], clocks=[0, 0.5])
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(capture['stop_reason'], 'provider_failure')
        self.assertEqual(capture['denominators']['calls_unattempted'], 3)
        self.assertEqual(capture['denominators']['items_strictly_assessed'], 0)
        self.assertEqual(capture['denominators']['items_in_failed_batches'], 6)
        self.assertEqual(capture['denominators']['items_unattempted'], 18)
        failure = capture['calls'][0]['provider_error']
        self.assertEqual(len(failure['Error']['Message']), 2000)
        self.assertEqual(len(failure['RequestId']), 128)
        self.assertNotIn('ASIAABCDEFGHIJKLMNOP', persisted)
        self.assertNotIn('HIDDEN', persisted)
        self.assertNotIn('raw', capture['calls'][0])
        self.assertNotIn('usage', capture['calls'][0])

    def test_known_credentials_are_redacted_and_arbitrary_exception_text_ignored(self):
        secret = 'unit-test-session-value'
        error = ClientError({'Error': {'Code': secret, 'Message': f'{secret} Bearer another-secret authorization=hidden'},
                             'ResponseMetadata': {'RequestId': secret, 'HTTPStatusCode': True}}, 'Converse')
        safe = probe.safe_error_details(error, sensitive_values=(secret,))
        self.assertNotIn(secret, json.dumps(safe))
        self.assertNotIn('another-secret', json.dumps(safe))
        self.assertNotIn('hidden', json.dumps(safe))
        self.assertIsNone(safe['HTTPStatus'])
        self.assertIsNone(probe.safe_error_details(RuntimeError('arbitrary-secret'))['Error']['Message'])

    def test_stop_reason_and_elapsed_boundary(self):
        raw = oracle_raw(self.plan, 0)
        for stop, clocks, expected in [('max_tokens', [0, 1], 'non_end_turn'), ('end_turn', [0, 75.000001], 'provider_elapsed_limit')]:
            client, capture, _ = self.run_fake([response(raw, stop=stop)], clocks=clocks)
            self.assertEqual(len(client.requests), 1)
            self.assertEqual(capture['stop_reason'], expected)
            self.assertNotIn('assessment', capture['calls'][0])
        replies = [response(oracle_raw(self.plan, i)) for i in range(4)]
        _, capture, _ = self.run_fake(replies, clocks=[0, 75, 100, 175, 200, 275, 300, 375])
        self.assertEqual(capture['denominators']['calls_strictly_valid'], 4)

    def test_native_and_local_failures_are_distinct_whole_batch_failures(self):
        raw = json.loads(oracle_raw(self.plan, 0))
        missing = copy.deepcopy(raw)
        del missing['reviews']['5']
        oversized = copy.deepcopy(raw)
        oversized['reviews']['0']['feedback']['a']['reason'] = 'x' * 241
        wrong_type = copy.deepcopy(raw)
        wrong_type['reviews']['0']['difficulty'] = True
        legacy = {'reviews': list(raw['reviews'].values())}
        extra = copy.deepcopy(raw)
        extra['reviews']['6'] = copy.deepcopy(extra['reviews']['0'])
        duplicates = json.dumps(raw).replace('"reviews": {', '"reviews": {"0": {},', 1)
        for bad, native_valid in [(json.dumps(missing), False), (json.dumps(oversized), True),
                                  (json.dumps(wrong_type), False), (json.dumps(legacy), False),
                                  (json.dumps(extra), False), (duplicates, False)]:
            client, capture, _ = self.run_fake([response(bad)])
            self.assertEqual(len(client.requests), 1)
            self.assertEqual(bool(capture['calls'][0].get('native_schema_valid')), native_valid)
            self.assertNotIn('assessment', capture['calls'][0])
            self.assertEqual(capture['denominators']['items_strictly_assessed'], 0)
            self.assertEqual(capture['stop_reason'], 'local_or_binding_failure' if native_valid else 'native_schema_failure')

    def test_request_count_hash_and_hidden_field_preflight(self):
        for mutate in (lambda p: p['calls'].append(copy.deepcopy(p['calls'][0])),
                       lambda p: p['calls'].pop(),
                       lambda p: p['calls'][0].update(request_sha256='wrong'),
                       lambda p: p['calls'][0]['case_ids'].append('extra')):
            plan = copy.deepcopy(self.plan)
            mutate(plan)
            with self.assertRaises(ValueError):
                self.run_fake([], plan=plan)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'capture.json'
            path.write_text('{}')
            client = FakeClient([])
            with self.assertRaises(ValueError):
                probe.run_calls(client, self.plan, {'calls': []}, path)
            self.assertEqual(client.requests, [])

    def test_source_pins_all_match_and_draft_is_not_frozen(self):
        self.assertEqual(self.plan['plan_state'], 'draft_unapproved')
        for path, expected in self.plan['runtime_source_sha256'].items():
            self.assertEqual(probe.sha(Path(path)), expected)
        for path, expected in self.plan['evidence_sha256'].items():
            self.assertEqual(probe.sha(probe.ROOT / path), expected)
        for name, expected in self.plan['harness_source_sha256'].items():
            self.assertEqual(probe.sha(probe.HERE / name), expected)

    def test_source_or_plan_drift_blocks_before_credentials_or_sdk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'plan.json'
            frozen = {**copy.deepcopy(self.plan), 'plan_state': 'frozen'}
            probe.save(path, frozen)
            with patch.object(probe, 'PLAN', path), patch.object(probe.subprocess, 'check_output') as credentials, patch.object(probe.boto3, 'client') as sdk:
                with self.assertRaises(ValueError):
                    probe.execute('wrong-hash')
                changed = copy.deepcopy(self.plan)
                changed['runtime_source_sha256']['changed.py'] = 'different'
                with patch.object(probe, 'build_plan', return_value=changed):
                    with self.assertRaises(ValueError):
                        probe.execute(probe.sha(path))
                credentials.assert_not_called()
                sdk.assert_not_called()

    def test_freeze_requires_unchanged_reviewed_draft_and_is_exclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            draft, plan = Path(tmp) / 'draft.json', Path(tmp) / 'plan.json'
            probe.save(draft, self.plan)
            with patch.object(probe, 'DRAFT', draft), patch.object(probe, 'PLAN', plan):
                with self.assertRaises(ValueError):
                    probe.freeze('wrong-hash')
                with patch.object(probe, 'build_plan', return_value={}):
                    with self.assertRaises(ValueError):
                        probe.freeze(probe.sha(draft))
                self.assertFalse(plan.exists())
                frozen_hash = probe.freeze(probe.sha(draft))
                self.assertEqual(frozen_hash, probe.sha(plan))
                self.assertEqual(json.loads(plan.read_text()), {**self.plan, 'plan_state': 'frozen'})
                with self.assertRaises(FileExistsError):
                    probe.freeze(probe.sha(draft))

    def test_failure_after_two_valid_calls_preserves_exact_partial_denominators(self):
        replies = [response(oracle_raw(self.plan, i)) for i in range(2)] + [RuntimeError('do not save this')]
        client, capture, persisted = self.run_fake(replies)
        self.assertEqual(len(client.requests), 3)
        self.assertEqual(capture['denominators']['calls_strictly_valid'], 2)
        self.assertEqual(capture['denominators']['items_strictly_assessed'], 12)
        self.assertEqual(capture['denominators']['items_in_failed_batches'], 6)
        self.assertEqual(capture['denominators']['items_unattempted'], 6)
        self.assertNotIn('do not save this', persisted)

    def test_malformed_unicode_reason_is_preserved_as_raw_evidence_and_rejected(self):
        raw = json.loads(oracle_raw(self.plan, 0))
        raw['reviews']['0']['task']['reason'] = chr(0xD800)
        serialized = json.dumps(raw, ensure_ascii=False)
        _, capture, persisted = self.run_fake([response(serialized)])
        self.assertEqual(capture['stop_reason'], 'local_or_binding_failure')
        self.assertEqual(capture['calls'][0]['raw'], serialized)
        self.assertEqual(json.loads(persisted)['calls'][0]['raw'], serialized)
        self.assertEqual(capture['denominators']['items_strictly_assessed'], 0)

    def test_bound_request_content_cannot_be_changed_even_with_new_request_hash(self):
        plan = copy.deepcopy(self.plan)
        request = plan['calls'][0]['request']
        data = probe.tagged_data(request)
        data['items']['0']['feedback']['a'] = 'Changed learner content.'
        request['messages'][0]['content'][0]['text'] = '<authored_feedback_audit_json>\n' + json.dumps(data) + '\n</authored_feedback_audit_json>'
        plan['calls'][0]['request_sha256'] = probe.digest(request)
        with self.assertRaises(ValueError):
            self.run_fake([], plan=plan)

    def test_execute_uses_one_sdk_client_with_exact_timeouts_and_no_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, capture_path = Path(tmp) / 'plan.json', Path(tmp) / 'capture.json'
            frozen = {**copy.deepcopy(self.plan), 'plan_state': 'frozen'}
            probe.save(path, frozen)
            client = FakeClient([response(oracle_raw(self.plan, i)) for i in range(4)])
            import types
            client.meta = types.SimpleNamespace(config=probe.Config(connect_timeout=3, read_timeout=75, retries={'total_max_attempts': 1}))
            credentials = json.dumps({'AccessKeyId': 'fake-key', 'SecretAccessKey': 'fake-secret', 'SessionToken': 'fake-session'}).encode()
            with patch.object(probe, 'PLAN', path), patch.object(probe, 'CAPTURE', capture_path), patch.object(probe.subprocess, 'check_output', return_value=credentials), patch.object(probe.boto3, 'client', return_value=client) as sdk, contextlib.redirect_stdout(io.StringIO()):
                probe.execute(probe.sha(path))
            self.assertEqual(sdk.call_count, 1)
            self.assertEqual(len(client.requests), 4)
            configured = sdk.call_args.kwargs['config']
            self.assertEqual((configured.connect_timeout, configured.read_timeout, configured.retries['total_max_attempts']), (3, 75, 1))
            self.assertEqual(sdk.call_args.args, ('bedrock-runtime',))
            self.assertEqual(sdk.call_args.kwargs['region_name'], 'us-east-1')
            for value in ('fake-key', 'fake-secret', 'fake-session'):
                self.assertNotIn(value, capture_path.read_text())

    def test_native_json_schema_validates_every_oracle_batch(self):
        schema = json.loads(self.plan['calls'][0]['request']['outputConfig']['textFormat']['structure']['jsonSchema']['schema'])
        for sequence in range(4):
            jsonschema.Draft202012Validator(schema).validate(json.loads(oracle_raw(self.plan, sequence)))


if __name__ == '__main__':
    unittest.main()
