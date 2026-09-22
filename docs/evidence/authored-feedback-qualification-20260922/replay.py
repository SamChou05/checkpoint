"""No-network replay of the failed first immutable-feedback audit dispatch."""

import contextlib
import copy
import io
import json
from pathlib import Path
import socket
import tempfile
from unittest.mock import patch

from botocore.exceptions import ReadTimeoutError

import audit_qualification as probe

PLAN_HASH = '8c0eaaeec121b11ea9ba6aaf6bc8acbca1d47ac441d7d42845dc8e7b441b7b09'
CAPTURE_HASH = 'ea422ad2447e2fab468af1457a2c043dbb0df71350bdbc3d24e0e90363fe857b'


class RecordedFailure:
    def __init__(self, request):
        self.request = request
        self.calls = 0

    def converse(self, **request):
        self.calls += 1
        assert self.calls == 1 and request == self.request
        raise ReadTimeoutError(endpoint_url='https://bedrock-runtime.us-east-1.amazonaws.com')


def replay():
    with patch.object(socket.socket, 'connect', side_effect=AssertionError('No network in replay')), patch.object(
        probe.boto3, 'client', side_effect=AssertionError('No SDK client in replay')
    ), patch.object(probe.subprocess, 'check_output', side_effect=AssertionError('No credentials in replay')):
        assert probe.sha(probe.PLAN) == PLAN_HASH
        assert probe.sha(probe.CAPTURE) == CAPTURE_HASH
        plan, capture = json.loads(probe.PLAN.read_text()), json.loads(probe.CAPTURE.read_text())
        assert capture['plan_sha256'] == PLAN_HASH
        assert plan == {**probe.build_plan(), 'plan_state': 'frozen'}
        probe.validate_dispatch_plan(plan)
        assert len(capture['calls']) == 1
        observed = capture['calls'][0]
        assert observed['sequence'] == 0 and observed['dispatch_attempted'] is True
        assert observed['request'] == plan['calls'][0]['request']
        assert observed['request_sha256'] == probe.digest(observed['request']) == plan['calls'][0]['request_sha256']
        assert observed['provider_error'] == {
            'type': 'ReadTimeoutError', 'Error': {'Code': None, 'Message': None},
            'HTTPStatus': None, 'RequestId': None,
        }
        assert not set(observed) & {'raw', 'assessment', 'usage', 'stop_reason', 'native_schema_valid'}
        client = RecordedFailure(observed['request'])
        fresh = {'plan_sha256': PLAN_HASH, 'calls': [], 'status': 'running', 'started_at': capture['started_at']}
        ticks = iter([0, observed['elapsed_seconds']])
        with tempfile.TemporaryDirectory(prefix='checkpoint-audit-replay-') as tmp, contextlib.redirect_stdout(io.StringIO()):
            probe.run_calls(client, plan, fresh, Path(tmp) / 'capture.json', monotonic=ticks.__next__)
        assert client.calls == 1
        old, new = copy.deepcopy(capture), copy.deepcopy(fresh)
        del old['completed_at'], new['completed_at']
        assert old == new
        return {
            'plan_sha256': PLAN_HASH, 'capture_sha256': CAPTURE_HASH,
            'runtime_and_harness_and_evidence_bindings_match_frozen_plan': True,
            'exact_captured_request_replayed': True,
            'same_error_path_stop_and_all_denominators_reproduced': True,
            'provider_calls_in_replay': 0,
            'fake_callback_calls': 1,
            'denominators': capture['denominators'],
            'field_denominators': {
                'tasks_planned': 24, 'tasks_returned': 0,
                'answer_choices_planned': 24, 'answer_choices_returned': 0,
                'feedback_labels_planned': 120, 'feedback_labels_returned': 0,
                'difficulty_values_planned': 24, 'difficulty_values_returned': 0,
                'reasons_planned': 144, 'reasons_returned': 0,
                'reasons_not_produced_in_failed_batch': 36, 'reasons_unattempted': 108,
            },
            'usage': None, 'usage_status': 'Unavailable, not zero.',
            'provider_elapsed_seconds': observed['elapsed_seconds'],
            'provider_error': observed['provider_error'],
            'primary_qualification_passed': False,
            'semantic_assessment': 'No model JSON or labels/reasons were returned; no semantic credit or failure attribution is possible.',
            'selected_originals': [], 'selected_payload_hash_identity': 'Not exercised: no payload was selected.',
            'no_rescue_of_previous_trials': True,
        }


if __name__ == '__main__':
    result = replay()
    probe.save(probe.HERE / 'replay-summary.json', result)
    print(json.dumps(result))
