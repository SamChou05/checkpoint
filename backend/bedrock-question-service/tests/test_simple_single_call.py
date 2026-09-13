import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals.checkpoint_correctness_trace import SETTINGS
from evals.checkpoint_simple_single_call import jobs, prompt_for, run
from lambda_test_support import _raw_question
from request_contract import _normalize_request


class SimpleSingleCallTests(unittest.TestCase):
    def test_reference_literals_survive_and_fresh_worker_is_selected_before_execution(self):
        planned = jobs()
        self.assertEqual(len(planned), 12)
        self.assertEqual([j['arm'] for j in planned if j['group']=='fresh'], ['worker_kimi']*4)
        for job in planned:
            request = _normalize_request(job['payload'])
            supplied = json.loads(prompt_for(request).split('\n\n', 1)[1])
            for field in ['sourceDocuments', 'skillMap']:
                if request.get(field):
                    self.assertEqual(supplied[field], request[field])
            for field in ['focusAreas', 'questionDirective', 'currentLevel']:
                if request['goal'].get(field):
                    self.assertEqual(supplied['goal'][field], request['goal'][field])

    def test_exactly_one_call_and_no_verification_stamp(self):
        class Client:
            calls = []
            def converse(self, **request):
                self.calls.append(request)
                return {'output':{'message':{'content':[{'text':json.dumps({'questions':[
                    _raw_question('Which quantity follows from the first stated calculation?'),
                    _raw_question('Which quantity follows from the second stated calculation?'),
                ]})}]}}, 'stopReason':'end_turn'}
        client=Client()
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, SETTINGS):
            trace=run(jobs()[2], Path(temp), client)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(len(trace['raw_questions']), 2)
        self.assertEqual(len(trace['compatible_unverified']), 2)
        self.assertEqual(trace['transport_roundtrip'], trace['compatible_unverified'])
        self.assertEqual(trace['metrics']['ProviderCalls'], 1)
        self.assertNotIn('outputConfig', client.calls[0])
        self.assertNotIn('error_type', trace)
        for q in trace['compatible_unverified']:
            self.assertNotIn('verificationVersion', q)
            self.assertNotIn('verificationPolicyRevision', q)
