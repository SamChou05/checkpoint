"""Offline packet export: occurrence conservation, blinding and exact teaching."""

import copy
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_complete_teaching_assessment as exporter


def question(index=0):
    choices = [f"{index}: café", f"{index}: cafe\u0301", f"{index}: third", f"{index}: fourth"]
    return {
        "prompt": f"Apply the stated evidence in case {index}.", "choices": choices,
        "expectedAnswer": "KEY_SENTINEL", "explanation": " MAIN_SENTINEL\nExact spacing.  ",
        "choiceFeedback": [{"choice": choice, "explanation": f" FEEDBACK_SENTINEL {position}\n  e\u0301 "}
                           for position, choice in enumerate(reversed(choices))],
        "format": "multiple_choice", "difficulty": 3, "topic": "Application",
        "unexpected_field": {"preserve": [None, True, 2]},
    }


def capture(author_texts=None):
    cases, jobs, operations = [], [], []
    for index in range(3):
        case_id = f"synthetic-complete-{index}"
        payload = {
            "goal": {"title": f"Analyze subject {index}", "category": "Custom",
                     "currentLevel": "Understand fundamentals", "focusAreas": "Apply evidence"},
            "sourceDocuments": [{"name": "Supplied notes", "text": "The original scoped notes.", "truncated": False}],
            "targetCount": 5, "minimumDifficulty": 3, "feedbackContract": "authored_complete",
        }
        cases.append({"case_id": case_id, "payload": payload})
        jobs.append({"case_id": case_id, "kind": "fresh", "maximum_calls": 6, "request": copy.deepcopy(payload)})
        operations.append({"case_id": case_id, "kind": "fresh", "maximum_calls": 6,
                           "status": "completed" if index == 0 else "coverage_failure" if index == 1 else "unattempted",
                           "questions": [], "result_category": "no_returned_questions" if index != 2 else None})
    fixture = {"experiment": exporter.EXPERIMENT, "cases": cases}
    plan = {"experiment": exporter.EXPERIMENT, "fixture": fixture, "fixture_sha256": exporter.runtime._hash(fixture),
            "operations": jobs, "maximum_calls": 18, "source_revision": "a" * 40,
            "source_sha256": {"question_quality.py": exporter.digest((exporter.SERVICE / "question_quality.py").read_bytes())},
            "delivery_source_sha256": {"test-swift-helper.swift": "b" * 64}, "dependencies": {"scripted": "only"}}
    calls = []
    for index, text in enumerate(author_texts or [json.dumps({"questions": [question()]})]):
        request = {"synthetic_request": index}
        calls.append({"operation_index": 0, "operation_call_index": index, "role": "author" if index == 0 else "author_json_repair",
                      "request": request, "request_sha256": exporter.runtime._hash(request), "lifecycle": "completed",
                      "observation": {"response": {"text": text}}})
    return {"status": "completed", "plan": plan, "plan_sha256": exporter.runtime._hash(plan),
            "operations": operations, "calls": calls}


class CompleteTeachingAssessmentTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("Assessment forbids network")))

    def write(self, name, value):
        path = self.directory / name
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return path

    def read(self, output, name):
        return json.loads((output / name).read_text(encoding="utf-8"))

    def bind(self, value):
        return exporter.capture_input(self.write("capture.json", value))

    def assert_blind(self, packet):
        for item in packet["items"]:
            self.assertEqual(set(item), {"id", "goal", "sourceDocuments", "prompt", "choices", "subject_status"})
        serialized = json.dumps(packet, ensure_ascii=False)
        for secret in ("KEY_SENTINEL", "MAIN_SENTINEL", "FEEDBACK_SENTINEL", "NESTED_ANSWER_SENTINEL",
                       "expectedAnswer", "explanation", "choiceFeedback", "choiceExplanations", "verificationPolicyRevision"):
            self.assertNotIn(secret, serialized)

    def assert_manifest(self, output, manifest):
        self.assertEqual(manifest["requested_slots"], 15)
        self.assertEqual(manifest["shuffle"]["seed"], "complete-teaching-20260910")
        for name, expected in manifest["files"].items():
            self.assertEqual(exporter.digest((output / name).read_bytes()), expected)

    def test_every_raw_occurrence_and_all_feedback_fields_survive_without_answer_leak(self):
        complete = question()
        damaged = question(1)
        damaged["choiceFeedback"] = [damaged["choiceFeedback"][0], damaged["choiceFeedback"][0],
                                     {"choice": "unoffered", "explanation": None, "extra": "keep"}, None]
        absent = question(2)
        absent.pop("choiceFeedback")
        absent["choiceExplanations"] = {"legacy": "FEEDBACK_SENTINEL preserve legacy too"}
        incomplete = question(3)
        incomplete["choiceFeedback"].pop()
        malformed = {"prompt": {"expectedAnswer": "NESTED_ANSWER_SENTINEL"},
                     "choices": [{"explanation": "NESTED_ANSWER_SENTINEL"}], "choiceFeedback": "FEEDBACK_SENTINEL"}
        raw_rows = [complete, damaged, absent, incomplete, malformed, None, 5]
        value, binding = self.bind(capture([json.dumps({"questions": raw_rows}, ensure_ascii=False)]))
        before = copy.deepcopy(value)
        output = self.directory / "raw"
        manifest = exporter.raw_packets(value, binding, output)
        self.assertEqual(value, before)
        first = self.read(output, "raw-stems-and-choices.json")
        self.assert_blind(first)
        self.assertEqual(len(first["items"]), 7)
        self.assertEqual(manifest["masked_subject_count"], 7)
        self.assertEqual(manifest["readable_subject_count"], 4)
        self.assertEqual(manifest["malformed_question_occurrence_count"], 3)
        mapping = {row["id"]: row for row in self.read(output, "private-mapping.json")["items"]}
        teaching = self.read(output, "authored-key-teaching.json")["items"]
        for row in teaching:
            self.assertEqual(row["authored"], raw_rows[mapping[row["id"]]["question_index"]])
        indexed = {mapping[row["id"]]["question_index"]: row for row in teaching}
        self.assertTrue(indexed[0]["structure"]["four_exact_feedback_rows"])
        self.assertEqual(indexed[0]["authored"]["choiceFeedback"], complete["choiceFeedback"])
        self.assertFalse(indexed[1]["structure"]["four_exact_feedback_rows"])
        self.assertEqual(indexed[1]["structure"]["malformed_row_indices"], [2, 3])
        self.assertEqual(indexed[1]["structure"]["duplicate_choice_indices"], [3])
        self.assertEqual(indexed[2]["structure"]["field_types"]["choiceFeedback"], "missing")
        self.assertEqual(indexed[3]["structure"]["choice_feedback_row_count"], 3)
        self.assertEqual(sum(row["subject_status"] == "malformed" for row in first["items"]), 3)
        self.assert_manifest(output, manifest)

    def test_repair_topoff_unreadable_and_unattempted_are_explicit_in_denominators(self):
        initial = question()
        repaired = question(1)
        value = capture([json.dumps({"questions": [initial]}),
                         "Here is the recoverable array: " + json.dumps([repaired, None]),
                         "not valid JSON {", None])
        value["calls"][2]["role"] = "author"
        value["status"] = "operational_failure"
        value["operations"][0]["status"] = "operational_failure"
        value, binding = self.bind(value)
        output = self.directory / "raw"
        manifest = exporter.raw_packets(value, binding, output)
        self.assertEqual(manifest["author_call_count"], 4)
        self.assertEqual(manifest["parsed_question_occurrence_count"], 3)
        self.assertEqual(manifest["masked_subject_count"], 3)
        self.assertEqual(manifest["unreadable_author_call_count"], 2)
        self.assertEqual([row["requested_slots"] for row in manifest["operations"]], [5, 5, 5])
        self.assertEqual([row["runtime_status"] for row in manifest["operations"]],
                         ["operational_failure", "coverage_failure", "unattempted"])
        private = self.read(output, "private-malformed-occurrences.json")["occurrences"]
        self.assertEqual([row["raw_text"] for row in private if row["status"] == "unreadable"], ["not valid JSON {", None])
        self.assert_blind(self.read(output, "raw-stems-and-choices.json"))

    def test_seed_is_reproducible_and_existing_packets_cannot_be_overwritten(self):
        value, binding = self.bind(capture([json.dumps({"questions": [question(i) for i in range(15)]})]))
        first, second = self.directory / "first", self.directory / "second"
        one = exporter.raw_packets(value, binding, first)
        two = exporter.raw_packets(value, binding, second)
        self.assertEqual(one, two)
        for path in first.iterdir():
            self.assertEqual(path.read_bytes(), (second / path.name).read_bytes())
        order = [row["question_index"] for row in self.read(first, "private-mapping.json")["items"]]
        self.assertNotEqual(order, list(range(15)))
        with self.assertRaises(FileExistsError):
            exporter.raw_packets(value, binding, first)

    def test_bound_input_rejects_changed_selector_budget_occurrence_or_hash(self):
        mutators = [
            lambda v: v["plan"].update(experiment="native-fresh-workflow-v1"),
            lambda v: v["plan"]["fixture"]["cases"][0]["payload"].pop("feedbackContract"),
            lambda v: v["plan"]["operations"][0]["request"].update(feedbackContract="reviewer_written"),
            lambda v: v["plan"].update(maximum_calls=19),
            lambda v: v["calls"][0].update(operation_call_index=1),
            lambda v: v["calls"][0].update(operation_index=2),
            lambda v: v["calls"][0].update(request_sha256="0" * 64),
            lambda v: v["plan"]["source_sha256"].update({"question_quality.py": "0" * 64}),
        ]
        for mutate in mutators:
            value = capture()
            mutate(value)
            value["plan"]["fixture_sha256"] = exporter.runtime._hash(value["plan"]["fixture"])
            value["plan_sha256"] = exporter.runtime._hash(value["plan"])
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                self.bind(value)
        value, binding = self.bind(capture())
        value["calls"][0]["observation"]["response"]["text"] = "changed"
        with self.assertRaisesRegex(ValueError, "changed after input binding"):
            exporter.raw_packets(value, binding, self.directory / "changed")
        self.assertFalse((self.directory / "changed").exists())

    def delivery_inputs(self):
        value = capture()
        claimed = {**question(), "remoteID": "remote-1", "verificationVersion": 1, "verificationPolicyRevision": 4}
        claimed["choiceExplanations"] = {row["choice"]: row["explanation"] for row in claimed.pop("choiceFeedback")}
        value["operations"][0]["questions"] = [claimed]
        value["operations"][0]["result_category"] = "partial_delivery"
        value, binding = self.bind(value)
        plan = value["plan"]
        bank_operations, client_operations = [], []
        for index, operation in enumerate(value["operations"]):
            questions = copy.deepcopy(operation["questions"])
            bank_operations.append({"operation_index": index, "case_id": operation["case_id"],
                                    "request": copy.deepcopy(plan["fixture"]["cases"][index]["payload"]),
                                    "runtime_questions": questions, "runtime_returned_count": len(questions),
                                    "claim_response": {"questions": questions}, "prepared_count": len(questions),
                                    "bank_claimable_count": len(questions), "bank_feedback_contract": "authored_complete",
                                    "claim_request": {"minimumVerificationVersion": 1, "minimumVerificationPolicyRevision": 4}})
            retained = []
            for q in questions:
                displayed = list(reversed(q["choices"]))
                retained.append({"remoteID": q["remoteID"], "prompt": q["prompt"], "expectedAnswer": q["expectedAnswer"],
                                 "main": "MAIN_SENTINEL actual changed main", "displayed_choices": displayed,
                                 "verificationVersion": 1, "verificationPolicyRevision": 4,
                                 "feedback_displays": [{"choice": choice, "display": f" ACTUAL_SENTINEL {choice}\n Exact e\u0301  ",
                                                        "choice_feedback": f"FEEDBACK_SENTINEL actual {choice}"} for choice in displayed]})
            client_operations.append({"operation_index": index, "case_id": operation["case_id"],
                                      "request_feedback_contract": "authored_complete", "minimum_verification_policy_revision": 4,
                                      "runtime_returned_count": len(questions), "bank_claimable_count": len(questions),
                                      "client_retained_count": len(retained), "retained_questions": retained,
                                      "client_dropped_remote_ids": []})
        native = {"experiment": exporter.EXPERIMENT, "exact_runtime_replay": True,
                  "capture_canonical_sha256": binding["capture_canonical_sha256"],
                  "plan_sha256": binding["plan_sha256"], "source_revision": binding["source_revision"],
                  **{key: plan[key] for key in ("source_sha256", "delivery_source_sha256", "dependencies")}}
        bank = {"native_capture_binding": native, "capture_sha256": binding["capture_byte_sha256"],
                "source_sha256": plan["delivery_source_sha256"], "operations": bank_operations,
                "requested_count": 15, "runtime_returned_count": 1, "bank_claimable_count": 1}
        client = {"source_sha256": bank["source_sha256"], "operations": client_operations,
                  "runtime_returned_count": 1, "bank_claimable_count": 1, "client_retained_count": 1}
        return value, binding, bank, client

    def export_client(self, value, binding, bank, client, name="client"):
        bank_path = self.write("bank.json", bank)
        client["delivery_fixture_sha256"] = exporter.digest(bank_path.read_bytes())
        client_path = self.write("swift.json", client)
        output = self.directory / name
        return output, exporter.client_packets(value, binding, bank_path, client_path, output)

    def test_actual_swift_choice_order_and_every_display_are_preserved_without_recomposition(self):
        value, binding, bank, client = self.delivery_inputs()
        output, manifest = self.export_client(value, binding, bank, client)
        exact = client["operations"][0]["retained_questions"][0]
        first = self.read(output, "client-stems-and-choices.json")
        self.assert_blind(first)
        self.assertEqual(first["items"][0]["choices"], exact["displayed_choices"])
        teaching = self.read(output, "client-teaching.json")["items"][0]
        self.assertEqual(teaching["main"], exact["main"])
        self.assertEqual(teaching["feedback_displays"], exact["feedback_displays"])
        self.assertEqual(len(teaching["feedback_displays"]), 4)
        checks = self.read(output, "private-mapping.json")["items"][0]["claim_client_checks"]
        self.assertFalse(checks["choice_feedback_exact"])
        self.assertEqual(manifest["masked_subject_count"], 1)
        self.assertEqual(manifest["claim_client_mismatch_count"], 1)
        self.assertEqual(manifest["complete_provenance_mismatch_count"], 0)
        self.assertEqual([row["generation_shortfall"] for row in manifest["operations"]], [4, 5, 5])
        self.assert_manifest(output, manifest)

    def test_error_operation_without_request_metadata_retains_all_requested_slots(self):
        value, binding, bank, client = self.delivery_inputs()
        client["operations"][0] = {"operation_index": 0, "runtime_returned_count": 1,
                                   "bank_claimable_count": 1, "client_retained_count": 0, "error": "Synthetic decode failure"}
        client["client_retained_count"] = 0
        output, manifest = self.export_client(value, binding, bank, client)
        self.assertEqual(manifest["masked_subject_count"], 0)
        self.assertEqual(manifest["operations"][0]["client_shortfall"], 1)
        self.assertEqual(manifest["operations"][0]["client_dropped_remote_ids"], ["remote-1"])
        self.assertFalse(manifest["operations"][0]["client_request_provenance_observed"])
        self.assertEqual(self.read(output, "client-teaching.json")["items"], [])
        self.assert_manifest(output, manifest)

    def test_wrong_item_provenance_is_flagged_without_hiding_retained_content(self):
        value, binding, bank, client = self.delivery_inputs()
        client["operations"][0]["retained_questions"][0]["verificationPolicyRevision"] = 2
        output, manifest = self.export_client(value, binding, bank, client)
        self.assertEqual(manifest["complete_provenance_mismatch_count"], 1)
        self.assertEqual(len(self.read(output, "client-teaching.json")["items"]), 1)

    def test_unbound_or_incomplete_client_attachment_is_rejected_before_export(self):
        mutators = [
            lambda bank, client: bank["native_capture_binding"].update(exact_runtime_replay=False),
            lambda bank, client: bank.update(capture_sha256="0" * 64),
            lambda bank, client: bank["operations"][0].update(bank_feedback_contract=None),
            lambda bank, client: client["operations"][0].update(request_feedback_contract=None),
            lambda bank, client: client["operations"][0].update(minimum_verification_policy_revision=2),
            lambda bank, client: client["operations"][0].pop("client_dropped_remote_ids"),
            lambda bank, client: client["operations"][0]["retained_questions"][0]["feedback_displays"].pop(),
            lambda bank, client: client["operations"][0]["retained_questions"][0].update(remoteID="not-claimed"),
        ]
        for index, mutate in enumerate(mutators):
            value, binding, bank, client = self.delivery_inputs()
            mutate(bank, client)
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.export_client(value, binding, bank, client, name=f"bad-{index}")
            self.assertFalse((self.directory / f"bad-{index}").exists())


if __name__ == "__main__":
    unittest.main()
