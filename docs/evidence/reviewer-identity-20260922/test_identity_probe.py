"""Fake-client execution checks; no credentials or model calls."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('identity_probe_tests_target', HERE / 'identity_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class IdentityProbeTests(unittest.TestCase):
    def setUp(self):
        self.plan = probe.load_plan()
        self.enterContext(patch.object(probe, 'save'))
        self.enterContext(patch.object(probe.boto3, 'client', side_effect=AssertionError('No SDK client')))
        self.enterContext(patch.object(probe.subprocess, 'check_output', side_effect=AssertionError('No credentials')))
        self.gold = {row['prompt']: row for row in self.plan['gold_items']}

    def response(self, request, mutate=None):
        text = request['messages'][0]['content'][0]['text']
        data = json.loads(text.split('<question_review_json>\n', 1)[1].split('\n</question_review_json>', 1)[0])
        reviews = {}
        for item in data['items']:
            valid = self.gold[item['prompt']]['expected_valid']
            reviews[str(item['index'])] = {
                'valid': valid, 'answer': self.gold[item['prompt']]['author_key'] if valid else '',
                'difficulty': 2 if valid else 0, 'explanation': 'A bounded offline explanation.' if valid else '',
                'choiceFeedback': [{'choice': c, 'explanation': 'A bounded offline choice explanation.'}
                                   for c in item['choices']] if valid else [],
            }
        if mutate:
            mutate(reviews)
        return {'stopReason': 'end_turn', 'output': {'message': {'content': [{'text': json.dumps({'reviews': reviews})}]}}}

    def run_fake(self, respond):
        calls = []
        class Client:
            def converse(self, **request):
                calls.append(copy.deepcopy(request))
                return respond(request)
        capture = {'calls': []}
        probe.run(Client(), self.plan, capture, Path('/unused'))
        return calls, capture

    def test_exact_two_requests_and_identity_mapping(self):
        calls, capture = self.run_fake(self.response)
        self.assertEqual(calls, [c['provider_request'] for c in self.plan['calls']])
        self.assertEqual(capture['status'], 'dispatch_complete_pending_semantic_audit')
        for row in capture['calls']:
            self.assertTrue(row['assessment']['structural_identity_pass'])
            self.assertEqual([x['index'] for x in row['assessment']['items']], list(range(5)))
            self.assertTrue(all(x['validity_agreement'] for x in row['assessment']['items']))
            self.assertTrue(all(x['semantic_audit'] == 'pending' for x in row['assessment']['items']))

    def test_phantom_missing_embedded_or_duplicate_keys_stop_first_call(self):
        for mutate in (lambda rows: rows.update({'-1': copy.deepcopy(rows['0'])}),
                       lambda rows: rows.pop('0'), lambda rows: rows['0'].update(index=-1)):
            with self.subTest(mutate=mutate):
                calls, capture = self.run_fake(lambda r: self.response(r, mutate))
                self.assertEqual(len(calls), 1)
                self.assertEqual(capture['stop_reason'], 'structure_or_mapping_failure')
                self.assertIn('response', capture['calls'][0])
        def duplicate(request):
            response = self.response(request)
            response['output']['message']['content'][0]['text'] = response['output']['message']['content'][0]['text'].replace('"0": {', '"0": {}, "0": {', 1)
            return response
        calls, capture = self.run_fake(duplicate)
        self.assertEqual(len(calls), 1)
        self.assertEqual(capture['stop_reason'], 'structure_or_mapping_failure')

    def test_semantic_failure_does_not_relabel_structural_result_or_retry(self):
        def mutate(rows):
            rows['0']['answer'] = 'incorrect key'
            rows['1']['explanation'] = 'x' * 421
            rows['2'].update(valid=False, answer='', difficulty=0, explanation='', choiceFeedback=[])
        calls, capture = self.run_fake(lambda r: self.response(r, mutate))
        self.assertEqual(len(calls), 2)
        for row in capture['calls']:
            self.assertTrue(row['assessment']['structural_identity_pass'])
            self.assertFalse(row['assessment']['items'][0]['exact_author_key'])
            self.assertFalse(row['assessment']['items'][1]['feedback_bounds'])
        self.assertFalse(capture['calls'][0]['assessment']['items'][2]['validity_agreement'])

    def test_transport_and_non_end_turn_stop_without_retry(self):
        def error(_request):
            raise TimeoutError('synthetic')
        for callback, reason in ((error, 'transport_failure'), (lambda _: {'stopReason': 'max_tokens'}, 'non_end_turn')):
            calls, capture = self.run_fake(callback)
            self.assertEqual(len(calls), 1)
            self.assertEqual(capture['stop_reason'], reason)

    def test_reasoning_and_signatures_are_removed_before_capture_not_assessment(self):
        responses = []
        def respond(request):
            response = self.response(request)
            response['usage'] = {'inputTokens': 7, 'outputTokens': 9}
            response['output']['message']['content'].insert(0, {
                'reasoningContent': {'reasoningText': {'text': 'PRIVATE_TRACE', 'signature': 'PRIVATE_SIGNATURE'}},
            })
            response['output']['message']['content'].append({
                'reasoningContent': {'redactedContent': b'PRIVATE_REDACTED_BYTES'},
            })
            responses.append(copy.deepcopy(response))
            return response
        with patch.object(probe, 'assess', wraps=probe.assess) as assessment:
            calls, capture = self.run_fake(respond)
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(assessment.call_args_list[0].args[0]['output']['message']['content']), 3)
        for index, call in enumerate(capture['calls']):
            self.assertEqual(call['reasoning_content_block_count'], 2)
            expected = copy.deepcopy(responses[index])
            expected['output']['message']['content'] = [expected['output']['message']['content'][1]]
            self.assertEqual(call['response'], expected)
            self.assertTrue(call['assessment']['structural_identity_pass'])
        self.assertNotIn('PRIVATE_', json.dumps(capture))
        self.assertNotIn('reasoningContent', json.dumps(capture))

    def test_two_call_ceiling_refuses_further_dispatch(self):
        class Client:
            def converse(self, **_request):
                raise AssertionError('Should not dispatch')
        with self.assertRaises(RuntimeError):
            probe.run(Client(), self.plan, {'calls': [{}, {}]}, Path('/unused'))


if __name__ == '__main__':
    unittest.main()
