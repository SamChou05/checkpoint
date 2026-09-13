"""Preserve subject facts across request carriers without exposing author metadata."""
import copy
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from complete_question_solution import build_solver_prompt, SUBJECT_REFERENCE_SYSTEM_PROMPT
from lambda_test_support import _raw_question
import question_generation as generation
from request_contract import _normalize_request
from test_objective_context import request as mapped_request

EVIDENCE = Path(__file__).resolve().parents[3] / 'docs/evidence/correctness-continuation-20260912/goal-reference'


def data(prompt):
    return json.loads(prompt.split('\n', 1)[1].rsplit('\n', 1)[0])


class SubjectReferenceSolverTests(unittest.TestCase):
    def test_goal_skill_objective_and_source_literals_all_reach_solver(self):
        request = mapped_request(mapped=True)
        literal = 'In this exercise, f(x) uses:\n    return "a  b"\nC++ != C#; cafe\u0301.'
        request['goal']['focusAreas'] = literal
        request['goal']['learningTarget'] = literal
        request['goal']['questionDirective'] = literal
        request['skillMap']['skills'][0]['detail'] = literal
        request['skillMap']['skills'][0]['objectives'][0]['detail'] = literal
        request['sourceDocuments'] = [{'name': 'Reference', 'text': literal, 'truncated': False}]
        item = {**_raw_question('Which result follows from the stated reference?'), 'index': 0,
                'objective': 'AUTHORED OBJECTIVE MUST NOT LEAK',
                'skillID': 'AUTHORED SKILL MUST NOT LEAK', 'objectiveID': 'AUTHORED ID MUST NOT LEAK'}
        original = copy.deepcopy((item, request))
        system, prompt = build_solver_prompt([item], request, context='subject')
        supplied = data(prompt)
        self.assertEqual(system, SUBJECT_REFERENCE_SYSTEM_PROMPT)
        for field in ['goal', 'skillMap', 'sourceDocuments']:
            self.assertEqual(supplied[field], request[field])
        self.assertEqual(supplied['items'], [{k: item[k] for k in ['index', 'prompt', 'choices', 'topic']}])
        self.assertNotIn('AUTHORED', prompt)
        self.assertEqual((item, request), original)

    def test_production_builder_matches_exact_qualified_reference_input(self):
        plan = json.loads((EVIDENCE/'plan.json').read_text())
        trace = json.loads((EVIDENCE/'trace.json').read_text())
        call = trace['calls'][1]['request']
        items = data(call['messages'][0]['content'][0]['text'])['items']
        system, prompt = build_solver_prompt(items, plan['request'], context='subject')
        self.assertEqual(system, plan['candidate_system'])
        self.assertEqual(prompt, call['messages'][0]['content'][0]['text'])
        _, old = build_solver_prompt(items, plan['request'], context='source')
        self.assertNotIn(plan['request']['goal']['focusAreas'], old)

    def test_recorded_solver_and_review_replay_through_current_runtime_with_own_stamp(self):
        plan = json.loads((EVIDENCE/'plan.json').read_text())
        trace = json.loads((EVIDENCE/'trace.json').read_text())
        replies = trace['calls'][1:]
        calls = []
        test = self
        class Client:
            def converse(self, **request):
                index = len(calls)
                calls.append(request)
                test.assertLess(index, len(replies))
                prompt = request['messages'][0]['content'][0]['text']
                supplied = data(prompt)
                test.assertEqual(supplied['goal'], plan['request']['goal'])
                test.assertEqual(supplied['sourceDocuments'], [])
                if index == 0:
                    test.assertEqual(request['system'], replies[0]['request']['system'])
                    for item in supplied['items']:
                        test.assertEqual(set(item), {'index', 'prompt', 'choices', 'topic'})
                return {'stopReason': 'end_turn', 'output': {'message': {'content': [
                    {'text': text} for text in replies[index]['response']['text']
                ]}}}
        with (patch.dict(os.environ, {**plan['settings'], 'GENERATION_ATTEMPTS': '1'}),
              patch.object(generation, '_generate_provider_payload', return_value={'questions': copy.deepcopy(plan['questions'])})):
            returned = generation._generate_sanitized_questions(
                _normalize_request(plan['payload']), Client(), generation.ProviderCallBudget(3))
        self.assertEqual(len(calls), 2)
        self.assertEqual([q['prompt'] for q in returned], [q['prompt'] for q in trace['candidate_final']])
        for current, historical in zip(returned, trace['candidate_final'], strict=True):
            self.assertEqual(current['verificationPolicyRevision'], 8)
            self.assertEqual(historical['verificationPolicyRevision'], 2)
            for key in ['prompt', 'expectedAnswer', 'explanation', 'choiceExplanations']:
                self.assertEqual(current[key], historical[key])
