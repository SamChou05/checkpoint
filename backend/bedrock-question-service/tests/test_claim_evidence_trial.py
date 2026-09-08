"""Paired transport/fetch behavior with scripted replies; no live calls."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_claim_evidence_trial as trial
from evals import grounding_transport as grounding
from test_acquired_source_review import capture
from test_question_teaching import question


def provider(text, citations=None):
    blocks = [{"text": text}]
    if citations is not None:
        blocks.append({"citationsContent": {"content": [], "citations": [
            {"location": {"web": {"url": url}}} for url in citations]}})
    return {"output": {"message": {"role": "assistant", "content": blocks}},
            "stopReason": "end_turn", "usage": {"inputTokens": 20, "outputTokens": 30}}


def completed(response):
    return {"status": "completed", "response": response, "provider_dispatch_attempted": True,
            "local_worker_reaped": True, "local_process_group_cleanup_confirmed": True,
            "worker_exitcode": 0, "termination_attempted": False, "usage_known": True}


class ClaimEvidenceTrialTests(unittest.TestCase):
    def fixture(self, count=2):
        return {"experiment": trial.EXPERIMENT, "cases": [
            {"case_id": f"case-{i}", "question": {**question(), "prompt": f"For exercise {i}, what is the sum of two and two?"},
             "context": {"goal": {"title": "Arithmetic"}}, "origin": {"kind": "fixed_mock"}}
            for i in range(count)]}

    def transport(self, request, **kwargs):
        data = json.loads(request["messages"][0]["content"][0]["text"])
        if kwargs["worker"] is grounding.grounding_worker:
            challenge = {"field": "explanation", "choice": None,
                         "quote": data["items"][0]["explanation"], "searchQuery": "addition two objects",
                         "rationale": "Check the displayed arithmetic claim."}
            response = grounding.project_grounding_response(provider(json.dumps({"challenge": challenge}), [
                "https://example.org/rule#one", "https://example.org/rule#two",
                "https://example.org/second", "https://example.org/not-fetched"]))
        else:
            spans = data["acquiredSources"]["spans"]
            cites = [{"source_id": s["source_id"], "quote": s["text"]} for s in spans]
            target = {k: data["challenge"][k] for k in ("field", "choice", "quote")}
            raw = json.dumps({"reviews": [{"index": 0, "valid": True, "answer": "4", "difficulty": 2,
                                          "explanationSupport": "supported", "issues": []}],
                              "evidence": {"item": cites, "mainExplanation": cites,
                                           "target": {**target, "relation": "supported", "citations": cites}}})
            response = trial.caller.recorded._response(provider(raw))
        result = completed(response)
        kwargs["on_progress"](result)
        return result

    def test_paired_round_bounds_native_fetches_and_preserves_display_content(self):
        fixture = self.fixture()
        before = copy.deepcopy(fixture)
        plan = trial.make_plan(fixture)
        fetch = Mock(side_effect=lambda url, **_: capture("Two and two objects total four objects.", requested_url=url))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run"
            result = trial.run(plan, output, transport=self.transport, fetch=fetch)
            self.assertEqual(result["status"], "completed")
            self.assertEqual(len(result["calls"]), 6)
            self.assertEqual([c.args[0] for c in fetch.call_args_list],
                             ["https://example.org/rule#one", "https://example.org/second"] * 2)
            for index, row in enumerate(result["cases"]):
                self.assertFalse(row["reviews"]["without_sources"]["eligible"])
                self.assertTrue(row["reviews"]["without_sources"]["declared_content_eligible"])
                self.assertTrue(row["reviews"]["with_sources"]["eligible"])
                returned = row["reviews"]["with_sources"]["question"]
                for field in ("prompt", "choices", "expectedAnswer", "explanation"):
                    self.assertEqual(returned[field], fixture["cases"][index]["question"][field])
                self.assertNotIn("verificationVersion", returned)
            self.assertEqual([c["role"] for c in result["calls"]],
                             ["discovery", "without_sources", "with_sources", "discovery", "with_sources", "without_sources"])
            self.assertEqual(json.loads((output / "capture.json").read_text()), result)
            with self.assertRaises(FileExistsError):
                trial.run(plan, output, transport=self.transport, fetch=fetch)
        self.assertEqual(fixture, before)

    def test_operational_failure_stops_later_dispatch(self):
        transport = Mock(return_value={"status": "operational_failure", "provider_dispatch_attempted": True})
        fetch = Mock()
        with tempfile.TemporaryDirectory() as directory:
            result = trial.run(trial.make_plan(self.fixture()), Path(directory) / "run", transport=transport, fetch=fetch)
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(len(result["calls"]), 1)
        self.assertTrue(result["calls"][0]["observation"]["provider_dispatch_attempted"])
        transport.assert_called_once()
        fetch.assert_not_called()

    def test_failed_fetch_is_not_evidence_or_a_reason_to_retry(self):
        fetch = Mock(return_value={"status": "failed", "failure_reason": "http_status_not_complete_200"})
        with tempfile.TemporaryDirectory() as directory:
            result = trial.run(trial.make_plan(self.fixture(1)), Path(directory) / "run",
                               transport=self.transport, fetch=fetch)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(result["calls"]), 2)
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(result["cases"][0]["reviews"]["with_sources"], {"status": "no_acquired_evidence"})

    def test_frozen_and_paired_prompt_changes_fail_before_dependent_dispatch(self):
        plan = trial.make_plan(self.fixture(1))
        plan["fixture"]["cases"][0]["question"]["expectedAnswer"] = "5"
        transport = Mock()
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                trial.run(plan, Path(directory) / "run", transport=transport)
        transport.assert_not_called()
        original = trial.audit.review_prompt
        def altered(*args):
            system, user = original(*args)
            return system + (" altered" if args[3] else ""), user
        with tempfile.TemporaryDirectory() as directory, patch.object(trial.audit, "review_prompt", altered):
            result = trial.run(trial.make_plan(self.fixture(1)), Path(directory) / "run",
                               transport=self.transport, fetch=lambda url, **_: capture(requested_url=url))
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(len(result["calls"]), 1)

    def test_lexical_windows_preserve_offsets_and_bound_selected_text(self):
        text = "unrelated boilerplate " * 700 + "distinctive root node cutting " * 200
        challenge = {"challenge": {"searchQuery": "root node cutting", "quote": "distinctive root"}}
        span = trial.select_spans([{"source_text": text}], challenge)[0]
        self.assertGreater(span["start"], 0)
        self.assertLessEqual(span["end"] - span["start"], trial.SPAN_CHARACTERS)
        self.assertEqual(text[span["start"]:span["end"]], text[span["start"]:])

    def test_source_identity_and_serialized_request_limits_are_enforced(self):
        with self.assertRaises(ValueError):
            trial.guard_request(trial.review_request("s", "x" * (trial.MAX_INPUT_BYTES - 1)))
        with self.assertRaises(ValueError):
            trial.make_plan(self.fixture(1), source_revision="0" * 40)
        plan = trial.make_plan(self.fixture(1))
        self.assertIn("evals/question_complete_author.py", plan["source_sha256"])
        with tempfile.TemporaryDirectory() as directory:
            result = trial.run(plan, Path(directory) / "run", transport=self.transport,
                               fetch=lambda _url, **_: capture(requested_url="https://different.example/"))
        self.assertEqual(result["status"], "operational_failure")
        self.assertEqual(len(result["calls"]), 1)
        self.assertEqual(len(result["cases"][0]["fetches"]), 1)
        self.assertEqual(result["cases"][0]["reviews"], {})

    def test_citation_followup_freezes_target_and_excludes_discovery_prose(self):
        fixture = json.loads((trial.SERVICE_DIR / "evals/fixtures/question_citation_discovery.json").read_text())
        fixture["cases"] = fixture["cases"][:1]
        plan = trial.make_plan(fixture)
        question_record = fixture["cases"][0]["question"]
        calls = []
        marker = "DISCOVERY PROSE IS NOT REVIEW EVIDENCE"
        def transport(request, **kwargs):
            calls.append((copy.deepcopy(request), kwargs["timeout"]))
            if kwargs["worker"] is grounding.grounding_worker:
                response = grounding.project_grounding_response(provider(marker, ["https://example.org/rules"]))
            else:
                data = json.loads(request["messages"][0]["content"][0]["text"])
                cites = [{"source_id": s["source_id"], "quote": s["text"]} for s in data["acquiredSources"]["spans"]]
                target = {k: data["challenge"][k] for k in ("field", "choice", "quote")}
                raw = json.dumps({"reviews": [{"index": 0, "valid": True, "answer": question_record["expectedAnswer"],
                                              "difficulty": 2, "explanationSupport": "supported", "issues": []}],
                                  "evidence": {"item": cites, "mainExplanation": cites,
                                               "target": {**target, "relation": "supported", "citations": cites}}})
                response = trial.caller.recorded._response(provider(raw))
            result = completed(response)
            kwargs["on_progress"](result)
            return result
        with tempfile.TemporaryDirectory() as directory, patch.object(trial.audit, "validate_discovery", side_effect=AssertionError):
            result = trial.run(plan, Path(directory) / "run", transport=transport,
                               fetch=lambda url, **_: capture(requested_url=url))
        self.assertEqual(result["status"], "completed")
        self.assertEqual([timeout for _, timeout in calls], [90, 300, 300])
        self.assertNotIn("outputConfig", calls[0][0])
        self.assertEqual(calls[1][0]["outputConfig"], calls[2][0]["outputConfig"])
        self.assertEqual(result["cases"][0]["challenge"], fixture["cases"][0]["challenge"])
        for request, _ in calls[1:]:
            self.assertNotIn(marker, json.dumps(request))
        fixture["cases"][0]["challenge"]["challenge"]["rationale"] += " changed"
        with self.assertRaises(ValueError):
            trial.make_plan(fixture)


if __name__ == "__main__":
    unittest.main()
