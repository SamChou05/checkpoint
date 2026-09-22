"""No-network checks of actual runtime SDK timeout shrinking and call admission."""
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("adaptive_pipeline_under_test", HERE / "adaptive_pipeline_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
runtime = probe.runtime


class ManualClock:
    def __init__(self):
        self.seconds = 0

    def __call__(self):
        return self.seconds


class FakeClient:
    def __init__(self, config, dispatches):
        self.meta = SimpleNamespace(config=config)
        self.dispatches = dispatches

    def converse(self, **request):
        self.dispatches.append(request)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"solutions":[]}'}]}}}


def run_checks():
    clock = ManualClock()
    deadline = probe.Deadline(clock)
    budget = runtime.ProviderCallBudget(6, context=deadline)
    configs, dispatches = [], []
    reduce_during_setup = False

    def factory(_service, **kwargs):
        config = kwargs["config"]
        assert config.retries["total_max_attempts"] == 1
        configs.append(config)
        if reduce_during_setup:
            clock.seconds = 234  # Six seconds remain after SDK construction.
        return FakeClient(config, dispatches)

    def invoke():
        return runtime._generate_with_bedrock({}, None, "us.anthropic.claude-sonnet-4-6",
                                             user_prompt="Offline deadline test.", system_prompt="Offline test.",
                                             call_budget=budget, contract="complete_choice_solver_v3")

    outcomes = []
    with patch.dict(os.environ, probe.ENVIRONMENT), patch("boto3.client", factory):
        for elapsed, expected_read in ((0, 75), (180, 53.999), (230, 3.999)):
            clock.seconds = elapsed
            invoke()
            actual = configs[-1].read_timeout
            assert abs(actual - expected_read) < 0.000001, (actual, expected_read)
            assert configs[-1].connect_timeout == 3
            outcomes.append({"remaining_before_client_ms": 240000 - elapsed * 1000,
                             "actual_read_timeout_seconds": actual, "sdk_total_max_attempts": 1,
                             "provider_budget_calls": budget.calls})
        assert len(dispatches) == budget.calls == 3
        assert all(request["inferenceConfig"] == {"maxTokens": 16000} for request in dispatches)
        assert all(request["additionalModelRequestFields"] == {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}} for request in dispatches)
        clock.seconds = 235
        before = len(configs)
        try:
            invoke()
        except runtime.ProviderDeadlineExceededError:
            pass
        else:
            raise AssertionError("Late call was admitted.")
        assert len(configs) == before and len(dispatches) == budget.calls == 3
        clock.seconds = 230
        reduce_during_setup = True
        try:
            invoke()
        except runtime.ProviderDeadlineExceededError:
            pass
        else:
            raise AssertionError("Deadline was not rechecked after SDK setup.")
        assert len(configs) == before + 1 and len(dispatches) == budget.calls == 3
        reduce_during_setup = False
        clock.seconds = 0
        for _ in range(3):
            invoke()
        assert len(dispatches) == budget.calls == 6
        try:
            invoke()
        except runtime.ProviderCallBudgetExceededError:
            pass
        else:
            raise AssertionError("Seventh call was admitted.")
        assert len(dispatches) == budget.calls == 6
    response = {"output": {"message": {"content": [{"reasoningContent": {"reasoningText": {"text": "private", "signature": "sig"}}}, {"text": '{"solutions":[]}'}]}}}
    retained, count = probe.safe_response(response)
    assert count == 1 and "reasoningContent" not in json.dumps(retained)
    assert "reasoningContent" in json.dumps(response)
    return {"provider_network_calls": 0, "synthetic_dispatches": 6, "deadline_sequence": outcomes,
            "too_late_rejected_before_sdk_setup": True, "deadline_rechecked_after_sdk_setup": True,
            "seventh_provider_call_blocked": True, "one_sdk_attempt_per_call": True,
            "adaptive_actual_runtime_request_verified": True, "reasoning_text_not_retained": True}


if __name__ == "__main__":
    print(json.dumps(run_checks(), indent=2))
