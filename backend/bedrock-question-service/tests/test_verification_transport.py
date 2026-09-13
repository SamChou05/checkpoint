import json
import os
import unittest
from unittest.mock import Mock, patch

from lambda_test_support import _complete_solution, _raw_question, _request_payload
from native_output_contracts import output_mode
from question_generation import ProviderCallBudget, _generate_sanitized_questions, _generate_with_bedrock
from request_contract import _normalize_request
from service_errors import ServiceConfigurationError


class VerificationTransportTests(unittest.TestCase):
    def test_stage_override_preserves_author_maps_and_all_verification_stages(self):
        for base in ['legacy', 'native']:
            for override in ['', 'inherit', 'legacy', 'native']:
                with self.subTest(base=base, override=override), patch.dict(os.environ, {
                    'BEDROCK_STRUCTURED_OUTPUT_MODE': base,
                    'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': override,
                }):
                    self.assertEqual(output_mode(), base)
                    for contract in ['question_author_v1', 'skill_map_inference_v1', 'skill_map_evolution_v1']:
                        self.assertEqual(output_mode(contract), base)
                    for contract in ['complete_choice_solver_v1', 'default_reviewer_v1', 'authored_solution_reviewer_v1']:
                        self.assertEqual(output_mode(contract), override if override in ['legacy', 'native'] else base)

    def test_nova_author_and_native_sonnet_verification_use_three_calls_and_preserve_reviewed_text(self):
        question = _raw_question('Which conclusion follows from the stated conditions?')
        teaching = 'Apply the stated relation.\n    The indicated conclusion follows.'
        calls = []
        class Client:
            def converse(self, **request):
                calls.append(request)
                text = request['messages'][0]['content'][0]['text']
                if '<generation_request_json>' in text:
                    payload = {'questions': [question]}
                else:
                    tag = 'question_solution_json' if '<question_solution_json>' in text else 'question_review_json'
                    data = json.loads(text.split(f'<{tag}>\n')[1].split(f'\n</{tag}>')[0])
                    item = data['items'][0]
                    payload = {'solutions': [_complete_solution(item, question['expectedAnswer'])]} if tag == 'question_solution_json' else {'reviews': [{
                        'index': 0, 'valid': True, 'answer': question['expectedAnswer'], 'difficulty': 3,
                        'explanation': teaching, 'choiceFeedback': [
                            {'choice': c, 'explanation': 'The stated relation determines whether this conclusion follows.'}
                            for c in item['choices']
                        ],
                    }]}
                return {'stopReason': 'end_turn', 'output': {'message': {'content': [{'text': json.dumps(payload)}]}}}
        with patch.dict(os.environ, {
            'BEDROCK_MODEL_ID': 'amazon.nova-lite-v1:0',
            'BEDROCK_VERIFICATION_MODEL_ID': 'us.anthropic.claude-sonnet-4-6',
            'BEDROCK_STRUCTURED_OUTPUT_MODE': 'legacy',
            'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native',
            'BEDROCK_FALLBACK_MODEL_ID': '', 'GENERATION_ATTEMPTS': '1',
            'QUESTION_FEEDBACK_CONTRACT': 'reviewer_written',
        }):
            result = _generate_sanitized_questions(_normalize_request(_request_payload(target_count=1)), Client(), ProviderCallBudget(3))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['explanation'], teaching)
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0]['modelId'], 'amazon.nova-lite-v1:0')
        self.assertNotIn('outputConfig', calls[0])
        self.assertEqual([c['outputConfig']['textFormat']['structure']['jsonSchema']['name'] for c in calls[1:]],
                         ['complete_choice_solver_v1', 'default_reviewer_v1'])

    def test_invalid_verification_override_or_model_spends_no_author_call(self):
        for changes in [
            {'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'relaxed'},
            {'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native', 'BEDROCK_VERIFICATION_MODEL_ID': 'amazon.nova-lite-v1:0'},
        ]:
            client = Mock()
            with self.subTest(changes=changes), patch.dict(os.environ, {'BEDROCK_STRUCTURED_OUTPUT_MODE': 'legacy', **changes}), self.assertRaises(ServiceConfigurationError):
                _generate_sanitized_questions(_normalize_request(_request_payload(target_count=1)), client, ProviderCallBudget(3))
            client.converse.assert_not_called()

    def test_explicit_legacy_eval_remains_legacy_under_native_verifier_override(self):
        client = Mock()
        client.converse.return_value = {'output': {'message': {'content': [{'text': '{}'}]}}}
        with patch.dict(os.environ, {'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native'}):
            _generate_with_bedrock({}, client, 'amazon.nova-lite-v1:0', user_prompt='task', system_prompt='rules', legacy_transport=True)
        self.assertNotIn('outputConfig', client.converse.call_args.kwargs)
