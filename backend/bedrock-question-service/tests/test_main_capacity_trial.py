"""Frozen author-only transport tests; scripted text is not accuracy evidence."""

import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_main_capacity_trial as trial
from test_runtime_qualification import completed


class MainCapacityTrialTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.fixture = {
            "experiment": trial.EXPERIMENT,
            "assessment_contract": "ASSESSOR SECRET",
            "cases": [{
                "case_id": f"fresh-{i}", "assessment_scope": "CASE ASSESSOR SECRET",
                "payload": {
                    "goal": {"title": f"Study synthetic rule system {i}",
                             "currentLevel": "I know the individual rules."},
                    "targetCount": 2, "minimumDifficulty": 3,
                    "sourceDocuments": [{"name": "Supplied partial rules",
                                         "text": "A token counts twice when it is blue and once otherwise.",
                                         "truncated": True}],
                },
            } for i in range(3)],
        }
        self.plan = trial.make_plan(self.fixture)

    def test_actual_requests_differ_only_in_single_main_guidance(self):
        self.assertEqual(len(self.plan["jobs"]), 6)
        self.assertEqual([j["arm"] for j in self.plan["jobs"]],
                         ["main_320", "main_900", "main_900", "main_320", "main_320", "main_900"])
        self.assertEqual(self.plan["maximum_calls"], 6)
        self.assertEqual(self.plan["worker_timeout_seconds"], 90)
        self.assertEqual(self.plan["sdk_read_timeout_seconds"], 75)
        self.assertEqual(self.plan["sdk_total_max_attempts"], 1)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 6 * 32768)
        for index in range(3):
            pair = {j["arm"]: j for j in self.plan["jobs"] if j["case_index"] == index}
            baseline, expanded = pair["main_320"], pair["main_900"]
            self.assertEqual(baseline["normalized_request"], expanded["normalized_request"])
            request = baseline["request"]
            with patch.dict(os.environ, trial.SETTINGS):
                self.assertEqual(request, trial.runtime._first_request(
                    baseline["normalized_request"], settings=trial.SETTINGS))
            modified = copy.deepcopy(request)
            modified["system"][0]["text"] = modified["system"][0]["text"].replace(
                trial.INSTRUCTION, "explanation at most 900")
            self.assertEqual(modified, expanded["request"])
            self.assertEqual(request["modelId"], "moonshotai.kimi-k2.5")
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
            self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
            system = request["system"][0]["text"]
            self.assertIn("complete worked solution", system)
            self.assertIn("320 characters, each choice at most 140", system)
            user = request["messages"][0]["content"][0]["text"]
            data = json.loads(user.split("<generation_request_json>\n", 1)[1].split(
                "\n</generation_request_json>", 1)[0])
            self.assertEqual(data["targetCount"], 2)
            self.assertEqual(data["minimumDifficulty"], 3)
            self.assertEqual(data["sourceDocuments"][0]["text"],
                             self.fixture["cases"][index]["payload"]["sourceDocuments"][0]["text"])
            self.assertNotIn("ASSESSOR SECRET", json.dumps(request))

    def test_all_complete_raw_text_is_durable_without_content_filtering(self):
        output = self.root / "raw"
        texts = ["not JSON at all", "{\"questions\":[]}",
                 json.dumps({"questions": [{"explanation": "x" * 1300}]}),
                 "[]", "{\"questions\":[null,null,null]}", "finished non-JSON"]
        seen = []

        def transport(request, **kwargs):
            self.assertIs(kwargs["worker"], trial.author_worker)
            self.assertEqual(kwargs["timeout"], 90)
            durable = json.loads((output / "capture.json").read_text())
            self.assertEqual(durable["calls"][-1]["request"], request)
            self.assertEqual(durable["calls"][-1]["request_sha256"], trial._hash(request))
            self.assertEqual(durable["calls"][-1]["status"], "launch_intent")
            progress = {"status": "running", "provider_dispatch_attempted": True,
                        "usage_known": False}
            kwargs["on_progress"](progress)
            saved = json.loads((output / "capture.json").read_text())
            self.assertEqual(saved["calls"][-1]["observation"], progress)
            state = completed(texts[len(seen)])
            seen.append(request)
            return state

        with patch.object(trial.runtime, "_sanitize_questions", side_effect=AssertionError("No filters.")):
            report = trial.run(self.plan, output, transport=transport)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(seen), 6)
        self.assertEqual([c["observation"]["response"]["text"] for c in report["calls"]], texts)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No replay client.")):
            self.assertEqual(trial.replay_capture(report), report)

    def test_operational_unfinished_and_cleanup_failure_stop_later_jobs(self):
        unfinished = completed("partial JSON")
        unfinished["response"]["stopReason"] = "max_tokens"
        failed = {"status": "operational_failure", "error_type": "ExpiredTokenException",
                  "provider_dispatch_attempted": True, "usage_known": False,
                  "local_worker_reaped": True, "local_process_group_cleanup_confirmed": True,
                  "worker_exitcode": 0, "termination_attempted": False}
        for index, state in enumerate((failed, unfinished, completed("{}", worker_exitcode=1))):
            with self.subTest(index=index):
                transport = Mock(return_value=state)
                report = trial.run(self.plan, self.root / f"failure-{index}", transport=transport)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(report["calls"]), 1)
                self.assertEqual(report["calls"][0]["observation"], state)
                transport.assert_called_once()
                self.assertEqual(trial.replay_capture(report), report)

    def test_empty_final_text_and_usage_survive_failure_and_replay(self):
        for index, text in enumerate(("", " \n\t", "normal unchanged final text")):
            with self.subTest(text=repr(text)):
                provider = {
                    "output": {"message": {"role": "assistant", "content": [{"text": text}]}},
                    "stopReason": "end_turn", "usage": {"inputTokens": 23, "outputTokens": 7},
                }
                projected = trial.author_response(provider)
                trial.runtime.recorded._validate_response_record(projected)
                self.assertEqual(projected["text"], text)
                self.assertEqual(projected["usage"], provider["usage"])
                self.assertTrue(trial.runtime.recorded._usage_known(projected))
                if text.strip():
                    self.assertEqual(projected, trial.runtime.recorded._response(provider))
                    continue
                self.assertFalse(projected["content_valid"])
                state = completed(text)
                state["response"] = projected
                transport = Mock(return_value=state)
                report = trial.run(self.plan, self.root / f"empty-{index}", transport=transport)
                self.assertEqual(report["status"], "operational_failure")
                self.assertEqual(len(report["calls"]), 1)
                transport.assert_called_once()
                observation = report["calls"][0]["observation"]
                self.assertEqual(observation["response"], projected)
                self.assertTrue(observation["usage_known"])
                self.assertEqual(trial.replay_capture(report), report)

    def test_plan_and_replay_tampering_is_refused(self):
        transport = Mock(return_value=completed("{}"))
        for mutate in (
            lambda p: p.update(maximum_calls=7),
            lambda p: p["jobs"][0]["request"]["inferenceConfig"].update(maxTokens=16000),
            lambda p: p["fixture"]["cases"][0].update(assessment_scope="changed"),
            lambda p: p["source_sha256"].update({"question_generation.py": "0" * 64}),
        ):
            changed = copy.deepcopy(self.plan)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.run(changed, self.root / "forbidden", transport=transport)
        transport.assert_not_called()
        self.assertFalse((self.root / "forbidden").exists())
        report = trial.run(self.plan, self.root / "original", transport=transport)
        for mutate in (
            lambda r: r["calls"][0].update(worker_timeout_seconds=91),
            lambda r: r["calls"][0].update(arm="main_900"),
            lambda r: r["calls"].append(copy.deepcopy(r["calls"][-1])),
            lambda r: r["calls"][0]["request"]["messages"][0]["content"][0].update(text="changed"),
        ):
            changed = copy.deepcopy(report)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.replay_capture(changed)

    def test_dry_freeze_load_and_persistence_failure_need_no_client(self):
        fixture_path, plan_path = self.root / "fixture.json", self.root / "plan.json"
        trial.shared.write_json(fixture_path, self.fixture)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No dry client.")):
            self.assertEqual(trial.main(["--fixture", str(fixture_path), "--plan", str(plan_path)]), 0)
            self.assertEqual(trial.load_plan(plan_path, trial._hash(self.plan)), self.plan)
        transport = Mock()
        with patch.object(trial.shared, "write_json", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                trial.run(self.plan, self.root / "disk-failure", transport=transport)
        transport.assert_not_called()
        with self.assertRaises(ValueError):
            trial.load_plan(plan_path, "0" * 64)

    def test_input_scope_and_worker_settings_are_enforced(self):
        for mutate in (
            lambda p: p["cases"].pop(),
            lambda p: p["cases"][0]["payload"].update(targetCount=3),
            lambda p: p["cases"][0]["payload"].update(minimumDifficulty=2),
            lambda p: p["cases"][0]["payload"].update(existingPrompts=["old item"]),
        ):
            changed = copy.deepcopy(self.fixture)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.make_plan(changed)
        with self.assertRaises(ValueError):
            trial._input_bytes({"text": "é" * 17000})
        inherited = copy.deepcopy(trial.caller.SETTINGS)
        with patch.object(trial.caller, "_worker") as worker:
            trial.author_worker("connection", {"request": "fixed"}, {"legacy": "ignored"}, True, 90)
        worker.assert_called_once_with("connection", {"request": "fixed"}, trial.SETTINGS, True, 90,
                                       response_projector=trial.author_response)
        self.assertEqual(trial.caller.SETTINGS, inherited)


if __name__ == "__main__":
    unittest.main()
