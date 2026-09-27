"""Socket-free checks for the frozen paired author probe."""

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import author_pair_probe as probe


class FakeSession:
    def __init__(self, response):
        self.response = response
        self.requests = []

    def client(self, name, **kwargs):
        if name == "sts":
            return SimpleNamespace(get_caller_identity=lambda: {"Account": probe.EXPECTED_ACCOUNT})
        if name != "bedrock-runtime":
            raise AssertionError(name)
        config = kwargs["config"]
        meta = SimpleNamespace(endpoint_url=kwargs["endpoint_url"],
                               region_name=kwargs["region_name"], config=config)

        def converse(**request):
            self.requests.append(request)
            return self.response

        return SimpleNamespace(meta=meta, converse=converse)


class AuthorPairProbeTests(unittest.TestCase):
    def test_exact_baseline_and_prompt_only_delta(self):
        result = probe.preflight()
        self.assertEqual(result["wire_difference"], "system[0].text only")
        self.assertEqual(result["native_schema_sha256"],
                         "eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c")
        self.assertEqual(result["provider_calls"], 0)

    def test_two_fake_calls_and_one_shot_artifacts(self):
        prior = json.loads((probe.PRIOR / "capture.json").read_text())
        fake = FakeSession(prior["calls"][0]["response"])
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(probe, "PLAN", Path(directory) / "plan.json"), \
                 patch.object(probe, "CAPTURE", Path(directory) / "capture.json"), \
                 patch.object(probe.secrets, "randbelow", return_value=1), \
                 patch.object(probe, "credential_session", return_value=(
                     fake, (), datetime.now(timezone.utc) + timedelta(seconds=900))):
                frozen = probe.freeze()
                self.assertEqual(frozen["arm_order"], ["v2", "v1"])
                result = probe.execute(frozen["plan_sha256"])
                self.assertEqual(result["state"], "complete")
                self.assertEqual(result["calls"], 2)
                self.assertEqual(len(fake.requests), 2)
                self.assertEqual(fake.requests[0]["system"],
                                 json.loads(probe.PLAN.read_text())["arm_wires"]["v2"]["system"])
                capture = json.loads(probe.CAPTURE.read_text())
                self.assertEqual([call["state"] for call in capture["calls"]],
                                 ["native_adapted", "native_adapted"])
                with self.assertRaises(probe.IntegrityError):
                    probe.execute(frozen["plan_sha256"])


if __name__ == "__main__":
    unittest.main()
