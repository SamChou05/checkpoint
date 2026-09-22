"""Exercise the selected real runtime using fake provider responses only."""

import copy
import importlib.util
import json
from pathlib import Path
import re
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("compiled_proof_mixed_probe_tested", HERE / "mixed_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)
from quantitative_authoring import CompiledCandidate  # noqa: E402


def data(request):
    text = request["messages"][0]["content"][0]["text"]
    match = re.search(r"<[^>]*_json>\n(.*?)\n</[^>]*_json>", text, re.S)
    return json.loads(match.group(1))


class FakeNetwork:
    def __init__(self, modify=None, factory_modify=None):
        self.calls, self.known, self.authors = [], {}, 0
        self.modify, self.factory_modify = modify, factory_modify

    def client(self, *args, **kwargs):
        client = SimpleNamespace(meta=SimpleNamespace(config=kwargs["config"], endpoint_url=probe.ENDPOINT, region_name="us-east-1"),
                                 converse=self.converse)
        if self.factory_modify:
            self.factory_modify(client)
        return client

    def converse(self, **request):
        index = len(self.calls)
        self.calls.append(copy.deepcopy(request))
        name = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        given = data(request)
        if name == probe.MIXED_AUTHOR_CONTRACT:
            rows = []
            self.authors += 1
            skills = given.get("skillMap", {}).get("skills", []) if given.get("skillMap") else []
            allocations = given.get("requestedSkillAllocation", {})
            assignments = [skill for skill in skills for _ in range(allocations.get(skill["id"], 0))]
            for number in range(given["targetCount"]):
                value = 10 * self.authors + number
                skill = assignments[number] if assignments else None
                prose = "Python" in given["goal"]["title"] or (skill and "English" in skill["name"])
                metadata = {"topic": skill["name"] if skill else "Arithmetic", "difficulty": 2}
                if skill:
                    metadata.update(skillID=skill["id"], objectiveID=skill["objectives"][0]["id"], objective=skill["objectives"][0]["name"])
                if prose:
                    prompt = f'In Python 3, what is the value of len("{"a" * value}")?'
                    choices = [str(value + 1), str(value), str(value + 2), str(value + 3)]
                    if skill:
                        prompt = f"Choose the grammatically correct sentence about the players on team {value}."
                        choices = ["The players runs.", "The players run.", "The player run.", "The players running."]
                    question = {"prompt": prompt, "choices": dict(zip("abcd", choices)), "correctChoice": "b",
                                "explanation": "Synthetic authored explanation for a fake transport fixture.",
                                "format": "Multiple Choice", **metadata}
                    rows.append({"kind": "prose", "question": question})
                    self.known[prompt] = choices[1]
                else:
                    task = {"kind": "exact_value", "unit": "unitless",
                            "nodes": [{"kind": "literal", "value": str(value)}, {"kind": "literal", "value": "3"},
                                      {"kind": "binary", "op": "add", "left": 0, "right": 1}], "root": 2,
                            "choices": dict(zip("abcd", map(str, (value + 3, value + 4, value + 2, value + 5))))}
                    rows.append({"kind": "quantitative", "task": task, **metadata})
                    content = CompiledCandidate.from_task(task).content()
                    self.known[content["prompt"]] = content["expectedAnswer"]
            payload = {"questions": rows}
        elif name.startswith("complete_choice_solver"):
            payload = {"solutions": {str(item["index"]): {
                "choices": {slot: {"reason": "Synthetic fixed answer judgment.",
                                   "judgment": "supported" if choice == self.known[item["prompt"]] else "refuted"}
                            for slot, choice in item["choices"].items()},
                "choicePairs": {pair: {"reason": "Synthetic distinct-pair judgment.", "relation": "distinct"}
                                for pair in item["choicePairs"]}} for item in given["items"]}}
        else:
            payload = {"reviews": {str(item["index"]): {
                "valid": True, "answer": self.known[item["prompt"]], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": {flag: False for flag in ("answer_or_ambiguity", "explanation", "distractors", "scope_assignment", "novelty", "other")}} for item in given["items"]}}
        response = {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps(payload)}]}},
                    "usage": {"inputTokens": 100, "outputTokens": 200}}
        return self.modify(index, request, payload, response) if self.modify else response


class MixedProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No network in offline preflight")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.plan = probe.build_plan()
        self.capture = {"plan": self.plan, "calls": [], "jobs": [], "reservations": []}

    def run_fake(self, network=None, **kwargs):
        network = network or FakeNetwork()
        probe.run_jobs(self.plan, self.capture, self.path, network.client, kwargs.pop("pin_check", lambda: None), **kwargs)
        return network

    def test_three_real_mixed_jobs_use_eight_calls_and_preserve_compiler_fields(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 8)
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [5, 5, 5])
        for row in self.capture["jobs"]:
            for question, source in zip(row["returned"], row["returned_provenance"], strict=True):
                if source:
                    self.assertEqual(probe.learner(question), source["learner"])
                    self.assertNotIn("Synthetic reviewer", question["explanation"])
                else:
                    self.assertEqual(question["verificationPolicyRevision"], 7)
                    self.assertEqual(question["choiceExplanations"], {})
                    self.assertEqual(question["explanation"], "Synthetic authored explanation for a fake transport fixture.")
            self.assertEqual(len(row["returned_sources"]), len(row["returned"]))
        for call in network.calls:
            author = call["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"] == probe.MIXED_AUTHOR_CONTRACT
            self.assertEqual(call["modelId"], "moonshotai.kimi-k2.5" if author else "us.anthropic.claude-sonnet-4-6")
            self.assertEqual(call["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2} if author else {"maxTokens": 16000})
            self.assertEqual(call["additionalModelRequestFields"], {"thinking": {"type": "disabled"}} if author else {
                "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
        self.assertFalse(any(call["stage"].startswith("complete_choice_solver") for call in self.capture["calls"] if call["job"] == "quantitative"))
        mixed_solver = next(call for call in self.capture["calls"] if call["job"] == "mixed" and call["stage"].startswith("complete_choice_solver"))
        self.assertEqual(len(data(mixed_solver["request"])["items"]), 2)

    def test_partial_return_survives_failed_topup_and_other_jobs_continue(self):
        def modify(index, request, payload, response):
            if index == 1:
                for key in ("3", "4"):
                    payload["reviews"][key].update(valid=False, answer="")
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            if index == 2:
                raise TimeoutError("Synthetic failed top-up")
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [3, 5, 5])
        self.assertFalse(self.capture.get("global_stop"))
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertEqual(self.capture["summary"]["reported_token_usage"]["calls_without_reported_usage"], 1)

    def test_native_configuration_failure_in_topup_stops_globally_despite_partial_return(self):
        def modify(index, request, payload, response):
            if index == 1:
                for key in ("3", "4"):
                    payload["reviews"][key].update(valid=False, answer="")
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            if index == 2:
                raise ClientError({"Error": {"Code": "ValidationException", "Message": "Synthetic unsupported schema"}}, "Converse")
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertEqual(len(self.capture["jobs"][0]["returned"]), 3)
        self.assertEqual(self.capture["calls"][2]["error"]["code"], "ValidationException")
        self.assertEqual(self.capture["global_stop"], "native_stage_configuration")
        self.assertEqual(self.capture["status"], "globally_aborted")
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_endpoint_or_request_drift_latches_before_runtime_can_wrap_it(self):
        network = FakeNetwork(factory_modify=lambda client: setattr(client.meta, "endpoint_url", "https://invalid.example.test"))
        self.run_fake(network)
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])
        self.capture = {"plan": self.plan, "calls": [], "jobs": [], "reservations": []}
        original = probe.runtime.native_output_config
        with patch.object(probe.runtime, "native_output_config", side_effect=lambda contract: {**original(contract), "unexpected": True}):
            network = self.run_fake()
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_ordinary_provider_failure_preserves_all_jobs_in_denominator(self):
        def modify(index, request, payload, response):
            if index == 0:
                raise TimeoutError("Synthetic timeout")
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(self.capture["jobs"]), 3)
        self.assertEqual(self.capture["jobs"][0]["status"], "failed")
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)

    def test_guardrail_intervention_ends_only_the_affected_independent_job(self):
        def modify(index, request, payload, response):
            if index == 0:
                response["stopReason"] = "guardrail_intervened"
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 7)
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [0, 5, 5])
        self.assertEqual(self.capture["jobs"][0]["error"]["type"], "SafetyInterventionError")
        self.assertEqual(self.capture["calls"][0]["response"]["stopReason"], "guardrail_intervened")
        self.assertFalse(self.capture.get("global_stop"))
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_source_change_after_dispatch_stops_globally(self):
        changed = False
        def modify(index, request, payload, response):
            nonlocal changed
            changed = True
            return response
        def pin_check():
            if changed:
                raise probe.IntegrityError("Synthetic source drift")
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(FakeNetwork(modify), pin_check=pin_check)
        self.assertEqual(len(self.capture["calls"]), 1)
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_raw_runtime_usage_cannot_bypass_response_filter(self):
        def modify(index, request, payload, response):
            response["usage"]["unrecognized"] = "PRIVATE_USAGE"
            response["output"]["message"]["content"].append({"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASON", "signature": "PRIVATE_SIGNATURE"}}})
            response["ResponseMetadata"] = {"HTTPHeaders": {"authorization": "PRIVATE_HEADER"}}
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertNotIn("PRIVATE_", self.path.read_text())

    def test_runtime_stop_reason_cannot_echo_credentials_outside_safe_response(self):
        secret = "SYNTHETIC_EXPORTED_CREDENTIAL"
        def modify(index, request, payload, response):
            if index == 0:
                response["stopReason"] = secret
            return response
        self.run_fake(FakeNetwork(modify), secrets=(secret,))
        persisted_text = self.path.read_text()
        self.assertNotIn(secret, persisted_text)
        persisted = json.loads(persisted_text)
        self.assertEqual(persisted["calls"][0]["response"]["stopReason"], "[REDACTED_CREDENTIAL]")
        observations = persisted["jobs"][0]["metrics"]["ProviderObservations"]
        self.assertTrue(observations)
        self.assertTrue(all("stopReason" not in observation for observation in observations))
        self.assertEqual(persisted["summary"]["planned_questions"], 15)
        self.assertEqual(persisted["jobs"][0]["status"], "failed")

    def test_late_return_is_retained_for_audit_but_earns_no_yield_credit(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 1:
                now = 241
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        self.assertEqual(len(self.capture["jobs"][0]["returned"]), 5)
        self.assertFalse(self.capture["jobs"][0]["within_deadline"])
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)

    def test_bad_plan_or_existing_capture_prevents_credentials(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"})
        with patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe.safe, "credential_session") as credentials:
            with self.assertRaises(probe.IntegrityError):
                probe.execute("0" * 64)
            probe.save(self.path, {"existing": True})
            with self.assertRaises(FileExistsError):
                probe.execute(probe.file_hash(plan_path))
            credentials.assert_not_called()

    def test_mixed_prose_solver_filtering_keeps_compiled_provenance_and_dense_audit(self):
        filtered = False
        def modify(index, request, payload, response):
            nonlocal filtered
            items = data(request).get("items", [])
            if "solutions" in payload and not filtered and any("grammatically" in item["prompt"] for item in items):
                filtered = True
                for choice in payload["solutions"]["0"]["choices"].values():
                    choice["judgment"] = "uncertain"
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        mixed = self.capture["jobs"][2]
        self.assertEqual(mixed["provider_calls"], 6)
        self.assertEqual(len(mixed["returned"]), 5)
        sources = mixed["returned_provenance"]
        self.assertEqual([source["source"][1:] for source in sources if source], [[0, 0], [0, 1], [0, 2]])
        reviewer = next(c for c in self.capture["calls"] if c["job"] == "mixed" and c["stage"].startswith("authored_solution_reviewer"))
        self.assertEqual(len(data(reviewer["request"])["items"]), 4)
        self.assertEqual(reviewer["stage"], probe.native.contract_metadata(probe.native.AuthoredSolutionFlagReviewContract(4))["name"])

    def test_invalid_specs_use_only_bounded_author_attempts_without_falling_back(self):
        def modify(index, request, payload, response):
            if index < 3:
                self.assertEqual(request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"], probe.MIXED_AUTHOR_CONTRACT)
                for row in payload["questions"]:
                    row["task"]["choices"]["b"] = row["task"]["choices"]["a"]
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual(self.capture["jobs"][0]["provider_calls"], 3)
        self.assertEqual(self.capture["jobs"][0]["returned"], [])
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)

    def test_actual_runtime_shrinks_the_final_socket_read_timeout(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 2:
                now += 70
            if index == 3:
                now += 75
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        self.assertEqual(self.capture["calls"][0]["read_timeout"], 100)
        self.assertGreater(self.capture["calls"][4]["read_timeout"], 2)
        self.assertLess(self.capture["calls"][4]["read_timeout"], 90)
        self.assertEqual(self.capture["jobs"][1]["provider_calls"], 3)
        self.assertTrue(self.capture["jobs"][1]["within_deadline"])

    def test_normal_attempts_exhaust_exactly_eighteen_reservations(self):
        def modify(index, request, payload, response):
            # Force all prose only in this synthetic call-ceiling fixture. The
            # real mixed author cannot promise its next pass needs only two calls.
            for index, row in enumerate(payload.get("questions", [])):
                if row["kind"] == "quantitative":
                    content = CompiledCandidate.from_task(row["task"]).content()
                    metadata = {key: value for key, value in row.items() if key not in {"kind", "task"}}
                    payload["questions"][index] = {"kind": "prose", "question": {
                        **metadata, "prompt": content["prompt"], "choices": dict(zip("abcd", content["choices"])),
                        "correctChoice": "abcd"[content["choices"].index(content["expectedAnswer"])],
                        "explanation": content["explanation"], "format": "Multiple Choice"}}
            if "reviews" in payload:
                for key, row in payload["reviews"].items():
                    if int(key) >= 2:
                        row.update(valid=False, answer="")
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 18)
        self.assertEqual(len(self.capture["reservations"]), 18)
        self.assertEqual([row["provider_calls"] for row in self.capture["jobs"]], [6, 6, 6])
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [4, 4, 4])
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(network)
        self.assertEqual(len(network.calls), 18)

    def test_sdk_factory_failure_cannot_be_swallowed_as_an_ordinary_job_failure(self):
        def fail(_):
            raise RuntimeError("Synthetic factory setup failure")
        network = self.run_fake(FakeNetwork(factory_modify=fail))
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_execute_setup_failure_still_records_all_fifteen_planned_items(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"})
        with patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe.safe, "credential_session", side_effect=probe.safe.CaptureBoundaryError("Synthetic credential failure")):
            result = probe.execute(probe.file_hash(plan_path))
        self.assertEqual(result["summary"]["planned_questions"], 15)
        self.assertEqual(result["summary"]["returned_questions"], 0)
        self.assertEqual(result["summary"]["attempted_calls"], 0)
        self.assertFalse(result["summary"]["qualified"])

    def test_repeated_raw_surplus_candidate_binds_to_actual_later_accepted_pass(self):
        repeated = None
        def modify(index, request, payload, response):
            nonlocal repeated
            if index == 0:
                repeated = copy.deepcopy(payload["questions"][0])
                repeated["task"]["nodes"][0]["value"] = "777"
                repeated["task"]["choices"] = dict(zip("abcd", ("780", "781", "779", "782")))
                content = CompiledCandidate.from_task(repeated["task"]).content()
                network.known[content["prompt"]] = content["expectedAnswer"]
                payload["questions"].append(copy.deepcopy(repeated))
            if index == 1:
                payload["reviews"]["4"].update(valid=False, answer="")
            if index == 2:
                payload["questions"] = [copy.deepcopy(repeated)]
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        network = FakeNetwork(modify)
        self.run_fake(network)
        first = self.capture["jobs"][0]
        self.assertEqual(first["provider_calls"], 4)
        self.assertEqual(len(first["returned"]), 5)
        self.assertEqual(first["passes"][0]["author_payload"]["questions"][5],
                         first["passes"][1]["author_payload"]["questions"][0])
        self.assertEqual(first["returned_provenance"][-1]["source"], ["quantitative", 1, 0])
        self.assertEqual(first["returned_sources"][-1], ["quantitative", 1, 0])
        self.assertFalse(self.capture.get("global_stop"))

    def test_repeated_rejected_content_obeys_actual_topup_deduplication(self):
        repeated = None
        def modify(index, request, payload, response):
            nonlocal repeated
            if index == 0:
                repeated = copy.deepcopy(payload["questions"][0])
            if index == 1:
                payload["reviews"]["0"].update(valid=False, answer="")
            if index == 2:
                payload["questions"] = [copy.deepcopy(repeated)]
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        first = self.capture["jobs"][0]
        self.assertEqual((first["provider_calls"], len(first["returned"])), (5, 5))
        self.assertEqual(first["passes"][1]["sanitized"], [])
        self.assertEqual(first["passes"][1]["verified"], [])
        self.assertTrue(all(source[1] == 0 for source in first["returned_sources"][:4]))
        # The saved solver calls leave enough budget for a third fresh author pass.
        self.assertEqual(first["returned_sources"][-1], ["quantitative", 2, 0])
        self.assertEqual(len(first["passes"]), 3)
        self.assertFalse(self.capture.get("global_stop"))

    def test_authored_crlf_main_and_reversed_review_maps_preserve_dense_items(self):
        main = "  Exact authored main teaching remains unchanged.\r\nThis is a synthetic fixture.  "
        def modify(index, request, payload, response):
            for row in payload.get("questions", []):
                if row["kind"] == "prose":
                    row["question"]["explanation"] = main
            if "reviews" in payload:
                payload["reviews"] = dict(reversed(list(payload["reviews"].items())))
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        for job in self.capture["jobs"]:
            for question, provenance in zip(job["returned"], job["returned_provenance"], strict=True):
                if provenance is None:
                    self.assertEqual(question["explanation"].encode(), main.encode())
                    self.assertEqual(question["choiceExplanations"], {})
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)

    def test_immutable_audit_replacement_is_not_repaired_and_support_vetoes_remain(self):
        for invalid in ("replacement", "support", "issues"):
            self.capture = {"plan": self.plan, "calls": [], "jobs": [], "reservations": []}
            def modify(index, request, payload, response):
                if index == 1:
                    if invalid == "replacement":
                        payload["reviews"]["0"]["explanation"] = "An unauthorized replacement."
                    elif invalid == "support":
                        payload["reviews"]["0"]["explanationSupport"] = "uncertain"
                    else:
                        payload["reviews"]["0"]["issueFlags"]["scope_assignment"] = True
                    response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
                return response
            with self.subTest(invalid=invalid):
                self.run_fake(FakeNetwork(modify))
                first = self.capture["jobs"][0]
                if invalid == "replacement":
                    self.assertEqual(first["status"], "failed")
                    self.assertEqual(first["provider_calls"], 2)
                    self.assertEqual(first["returned"], [])
                else:
                    self.assertEqual(len(first["passes"][0]["verified"]), 4)
                    self.assertEqual(first["provider_calls"], 4)
                    self.assertEqual(len(first["returned"]), 5)
                self.assertFalse(self.capture.get("global_stop"))

    def test_visible_credential_echo_stops_before_capture_or_runtime_adaptation(self):
        secret = "SYNTHETIC_VISIBLE_EXPORTED_CREDENTIAL"
        def modify(index, request, payload, response):
            response["output"]["message"]["content"] = [{"text": secret}]
            return response
        network = FakeNetwork(modify)
        self.run_fake(network, secrets=(secret,))
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(self.capture.get("global_stop"))
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn("response", self.capture["calls"][0])
        self.assertEqual(self.capture["jobs"][0]["passes"], [])

    def test_external_capture_change_is_not_overwritten_or_followed_by_dispatch(self):
        def modify(index, request, payload, response):
            self.path.write_text("external capture modification")
            return response
        network = FakeNetwork(modify)
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(network)
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(self.capture.get("global_stop"))
        self.assertEqual(self.path.read_text(), "external capture modification")

    def test_imported_runtime_cannot_be_pinned_to_newer_or_foreign_source(self):
        with patch.object(probe, "IMPORTED_SERVICE_HASHES", {}), self.assertRaises(probe.IntegrityError):
            probe.build_plan()
        with patch.object(probe, "IMPORTED_HELPER_HASH", "0" * 64), self.assertRaises(probe.IntegrityError):
            probe.build_plan()
        with patch.object(probe.runtime, "__file__", "/tmp/foreign/question_generation.py"), self.assertRaises(probe.IntegrityError):
            probe.build_plan()


if __name__ == "__main__":
    unittest.main()
