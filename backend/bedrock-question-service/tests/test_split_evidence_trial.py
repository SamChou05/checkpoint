"""Frozen split-review orchestration with synthetic origins; no provider calls."""

import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_claim_evidence_trial as trial
from test_acquired_source_review import capture
from test_claim_evidence_trial import completed, provider
from test_question_teaching import question


class SplitEvidenceTrialTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.origin_path = self.root / "origin.json"
        cases, results, calls = [], [], []
        for index in range(4):
            q = {**question(), "prompt": f"In exercise {index}, what is the sum of two and two?",
                 "explanation": "AUTHORED MAIN: Two objects and two more objects total four objects."}
            context = {"goal": {"title": "Arithmetic"}, "sourceDocuments": [{"text": "OLD SUMMARY SECRET"}]}
            challenge = trial.audit.validate_discovery(json.dumps({"challenge": {
                "field": "explanation", "choice": None, "quote": q["explanation"],
                "searchQuery": "addition objects", "rationale": "HYPOTHESIS SECRET"}}), q)
            url = f"https://example.org/rule-{index}"
            record = capture("Two objects joined to two more objects total four objects.", requested_url=url)
            selections = [{"record_index": 0, "start": 0, "end": record["text_characters"]}]
            locator = {"block_index": 1, "citation_index": 0, "url": url}
            cases.append({"case_id": f"case-{index}", "question": q, "context": context,
                          "origin": {"expected": "ASSESSMENT SECRET"}, "challenge": challenge})
            results.append({"case_id": f"case-{index}", "status": "completed", "selections": selections,
                            "discovery": {"citation_urls": [locator]},
                            "fetches": [{"native_citation": locator, "capture": record}]})
            for role in ("discovery", "without_sources", "with_sources"):
                request = trial.review_request(*trial.audit.review_prompt(
                    q, context, challenge, [record], selections), structured=True)
                calls.append({"case_index": index, "role": role, "request": request,
                              "request_sha256": trial._hash(request),
                              "observation": completed(trial.caller.recorded._response(provider("{}")))})
        old_plan = {"experiment": trial.CITATION_EXPERIMENT,
                    "source_revision": trial.SPLIT_SOURCE_REVISION,
                    "fixture": {"cases": cases}}
        self.origin = {"status": "completed", "plan": old_plan,
                       "plan_sha256": trial._hash(old_plan), "cases": results, "calls": calls}
        self.origin_path.write_text(json.dumps(self.origin))
        for name, value in (("SPLIT_CAPTURE", self.origin_path),
                            ("SPLIT_CAPTURE_SHA256", hashlib.sha256(self.origin_path.read_bytes()).hexdigest())):
            patcher = patch.object(trial, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fixture = {"experiment": trial.SPLIT_EXPERIMENT}
        self.plan = trial.make_plan(self.fixture)

    def transport(self, request, **kwargs):
        data = json.loads(request["messages"][0]["content"][0]["text"])
        name = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        self.assertIs(kwargs["worker"], trial.structured_review_worker)
        self.assertEqual(kwargs["timeout"], 300)
        if name.endswith("choices_v1"):
            # A semantic veto and a format rejection must both leave the separate
            # teaching call intact. Neither outcome is a factual-catch score.
            statuses = {key: "supported" if text == "4" else "refuted"
                        for key, text in data["item"]["choices"].items()}
            if "exercise 0" in data["item"]["prompt"]:
                statuses = dict.fromkeys(statuses, "uncertain")
            value = {"task": "Count the objects.", "choices": {
                key: {"reason": "SOLVER OUTPUT SECRET", "status": status, "evidence": []}
                for key, status in statuses.items()}, "issues": []}
            if "exercise 1" in data["item"]["prompt"]:
                value = {"bad": "format"}
        elif name.endswith("teaching_v1"):
            value = {"assessment": {"reason": "The main correctly combines the two groups.",
                                     "status": "supported", "evidence": []},
                     "issues": [], "difficulty": 2}
        else:
            spans = data["acquiredSources"]["spans"]
            citations = [{"source_id": span["source_id"], "quote": span["text"]} for span in spans]
            value = {"reviews": [{"index": 0, "valid": True, "answer": "4", "difficulty": 2,
                                   "explanationSupport": "supported", "issues": []}],
                     "evidence": {"item": citations, "mainExplanation": citations,
                                  "target": {**{key: data["challenge"][key] for key in ("field", "choice", "quote")},
                                             "relation": "supported", "citations": citations}}}
        result = completed(trial.caller.recorded._response(provider(json.dumps(value))))
        kwargs["on_progress"](copy.deepcopy(result))
        return result

    def test_twelve_calls_keep_old_requests_and_independent_sources_then_replay(self):
        output = self.root / "run"
        fetch = Mock(side_effect=AssertionError("No acquisition is allowed."))
        observed = []
        def transport(request, **kwargs):
            durable = json.loads((output / "capture.json").read_text())
            self.assertEqual(durable["calls"][-1]["request"], request)
            self.assertEqual(durable["calls"][-1]["status"], "launch_intent")
            observed.append(copy.deepcopy(request))
            return self.transport(request, **kwargs)
        result = trial.run(self.plan, output, transport=transport, fetch=fetch)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(observed), 12)
        fetch.assert_not_called()
        self.assertEqual([call["role"] for call in result["calls"]],
                         ["old_review", "choices", "teaching", "choices", "teaching", "old_review"] * 2)
        self.assertEqual([row["candidate"]["reason"] for row in result["cases"]],
                         ["solver_uncertain", "invalid_review", None, None])
        self.assertEqual(self.plan["maximum_calls"], 12)
        self.assertEqual(self.plan["maximum_fetches"], 0)
        for index, job in enumerate(self.plan["jobs"]):
            self.assertEqual(job["requests"]["old_review"], self.origin["calls"][index * 3 + 2]["request"])
            choices, teaching = (json.loads(job["requests"][role]["messages"][0]["content"][0]["text"])
                                 for role in ("choices", "teaching"))
            self.assertNotIn("explanation", choices["item"])
            self.assertEqual(teaching["item"].pop("explanation"), self.origin["plan"]["fixture"]["cases"][index]["question"]["explanation"])
            self.assertEqual(choices, teaching)
            for payload in (choices, teaching):
                text = json.dumps(payload)
                for secret in ("expectedAnswer", "difficulty", "HYPOTHESIS SECRET", "ASSESSMENT SECRET", "OLD SUMMARY SECRET", "SOLVER OUTPUT SECRET"):
                    self.assertNotIn(secret, text)
            self.assertTrue(job["source_units"])
        for row, case in zip(result["cases"][2:], self.plan["frozen_cases"][2:], strict=True):
            self.assertEqual(row["candidate"]["question"]["explanation"], case["question"]["explanation"])
            self.assertNotIn("verificationVersion", row["candidate"]["question"])
        with patch.object(trial.caller.shared, "new_client", side_effect=AssertionError("No replay clients.")):
            self.assertEqual(trial.replay_split_capture(result), result)
        with self.assertRaises(FileExistsError):
            trial.run(self.plan, output, transport=transport)

    def test_plan_origin_and_recorded_request_tampering_fail_closed(self):
        transport = Mock()
        for mutate in (
            lambda p: p.update(maximum_calls=13),
            lambda p: p["frozen_cases"][0]["records"][0].update(source_text="changed"),
            lambda p: p["jobs"][0]["requests"]["choices"].update(modelId="different-model"),
            lambda p: p["source_sha256"].update({"evals/split_evidence_review.py": "0" * 64}),
        ):
            plan = copy.deepcopy(self.plan)
            mutate(plan)
            with self.assertRaises(ValueError):
                trial.run(plan, self.root / "forbidden", transport=transport)
        transport.assert_not_called()
        self.assertFalse((self.root / "forbidden").exists())
        with self.assertRaises(ValueError):
            trial.make_plan({**self.fixture, "maximum_calls": 13})
        self.origin_path.write_text(self.origin_path.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "exact terminal v2"):
            trial.make_plan(self.fixture)

    def test_provider_cleanup_and_persistence_failures_stop_without_repair(self):
        for failure in ({"status": "operational_failure", "provider_dispatch_attempted": True},
                        {**completed(trial.caller.recorded._response(provider("{}"))),
                         "local_process_group_cleanup_confirmed": False}):
            transport = Mock(return_value=failure)
            output = self.root / ("failure-" + str(len(list(self.root.iterdir()))))
            result = trial.run(self.plan, output, transport=transport)
            self.assertEqual(result["status"], "operational_failure")
            self.assertEqual(len(result["calls"]), 1)
            transport.assert_called_once()
            self.assertEqual(trial.replay_split_capture(result), result)
            changed = copy.deepcopy(result)
            changed["calls"][0]["request"]["inferenceConfig"]["maxTokens"] = 1
            with self.assertRaises(ValueError):
                trial.replay_split_capture(changed)
        transport = Mock()
        with patch.object(trial.shared, "write_json", side_effect=OSError("fixed disk failure")), self.assertRaises(OSError):
            trial.run(self.plan, self.root / "disk-failure", transport=transport)
        transport.assert_not_called()

    def test_dry_cli_and_explicit_settings_use_no_client(self):
        fixture_path, plan_path = self.root / "fixture.json", self.root / "plan.json"
        fixture_path.write_text(json.dumps(self.fixture))
        with patch("sys.argv", ["trial", "--fixture", str(fixture_path), "--plan", str(plan_path)]), \
                patch.object(trial.shared, "new_client", side_effect=AssertionError("No dry clients.")):
            trial.main()
            loaded = trial.load_plan(plan_path, trial._hash(self.plan))
        self.assertEqual(loaded, self.plan)
        with self.assertRaises(ValueError):
            trial.load_plan(plan_path, "0" * 64)
        with patch.object(trial.caller, "_worker") as worker:
            trial.structured_review_worker("connection", "request", {"BEDROCK_READ_TIMEOUT_SECONDS": "1"}, False, 123)
        self.assertEqual(worker.call_args.args[2], {
            "BEDROCK_REGION": "us-east-1", "BEDROCK_READ_TIMEOUT_SECONDS": "300",
            "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3"})
        for job in self.plan["jobs"]:
            for role, request in job["requests"].items():
                self.assertEqual(request["modelId"], trial.REVIEW_MODEL)
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
                self.assertEqual(job["request_sha256"][role], trial._hash(request))
                self.assertLessEqual(len(trial.shared.canonical(request).encode()), 65536)
        self.assertIn("evals/split_evidence_review.py", self.plan["source_sha256"])


if __name__ == "__main__":
    unittest.main()
