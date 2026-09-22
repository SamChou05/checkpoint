"""Trusted batch identities preserve fixed-choice solving and fail closed."""

import copy
import json
import unittest
from unittest.mock import Mock

from botocore.session import get_session
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

import question_generation as generation
import test_native_pipeline as pipeline
from complete_question_solution import (
    COMPLETE_SOLUTION_SLOT_SYSTEM_PROMPT, CompleteSolutionFormatError,
    build_solver_prompt, validate_batch,
)
from native_output_contracts import (
    SolverSlotContract, adapt_native_response, contract_metadata,
    native_output_config, native_prompt,
)
from question_verification import verify_questions
from service_errors import (
    ProviderDeadlineExceededError, ProviderError, ProviderQuotaLimitError,
    ServiceConfigurationError,
)
from test_native_pipeline import (
    AUTHOR, REVIEWER, ScriptedNativeClient, author_payload, review, review_map,
    solver_map, solver_record, task_data,
)


def row():
    return {
        "choices": {slot: {"reason": f"  Exact cafe\u0301 reasoning for {slot}.\n",
                            "judgment": "supported" if slot == "a" else "refuted"}
                    for slot in ("a", "b", "c", "d")},
        "choicePairs": {slot: {"reason": f" Exact distinction {slot}.\n", "relation": "distinct"}
                        for slot in ("ab", "ac", "ad", "bc", "bd", "cd")},
    }


def payload(count):
    return {"solutions": {str(index): row() for index in range(count)}}


def expand_owned_references(schema):
    def expand(value):
        if isinstance(value, dict):
            if "$ref" in value:
                assert set(value) == {"$ref"} and value["$ref"].startswith("#/$defs/")
                return expand(schema["$defs"][value["$ref"].rsplit("/", 1)[1]])
            return {key: expand(child) for key, child in value.items() if key != "$defs"}
        if isinstance(value, list):
            return [expand(child) for child in value]
        return value
    return expand(schema)


class SolverSlotContractTests(unittest.TestCase):
    def test_all_counts_close_identities_preserve_v3_inner_bytes_and_validate_sdk(self):
        old_config = native_output_config("complete_choice_solver_v3")
        old_schema = json.loads(old_config["textFormat"]["structure"]["jsonSchema"]["schema"])
        expected_row = old_schema["properties"]["solutions"]["items"]
        del expected_row["properties"]["index"]
        expected_row["required"].remove("index")
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for count in range(1, 41):
            with self.subTest(count=count):
                contract = SolverSlotContract(count)
                configured = native_output_config(contract)
                schema = json.loads(configured["textFormat"]["structure"]["jsonSchema"]["schema"])
                Draft202012Validator.check_schema(schema)
                self.assertEqual(set(schema["$defs"]), {"choiceJudgment", "pairRelation", "solution"})
                self.assertLess(len(configured["textFormat"]["structure"]["jsonSchema"]["schema"]), 3100)
                solutions = expand_owned_references(schema)["properties"]["solutions"]
                self.assertEqual(list(solutions["properties"]), list(map(str, range(count))))
                self.assertEqual(solutions["required"], list(map(str, range(count))))
                self.assertIs(solutions["additionalProperties"], False)
                for value in solutions["properties"].values():
                    self.assertEqual(json.dumps(value), json.dumps(expected_row))
                data = payload(count)
                data["solutions"] = dict(reversed(list(data["solutions"].items())))
                Draft202012Validator(schema).validate(data)
                decoded = json.loads(adapt_native_response(json.dumps(data), contract))
                self.assertEqual(decoded["solutions"], [{"index": index, **row()} for index in range(count)])
                self.assertEqual(contract_metadata(contract)["version"], "5")
                validate_parameters({"modelId": "us.anthropic.claude-sonnet-4-6",
                                     "messages": [{"role": "user", "content": [{"text": "synthetic"}]}],
                                     "outputConfig": configured}, shape)
                configured["textFormat"]["structure"]["jsonSchema"]["schema"] = "mutated"
                self.assertNotEqual(configured, native_output_config(contract))
        self.assertEqual(contract_metadata("complete_choice_solver_v3")["sha256"],
                         "5747a0c1019044acd98caade2133929bb1a6c4b741c101a4665986c586c567b7")

    def test_invalid_counts_cannot_build_a_request(self):
        for count in (False, True, 0, -1, 41, 5.0, "5", None, float("nan"), float("inf")):
            with self.subTest(count=count), self.assertRaises(ServiceConfigurationError):
                SolverSlotContract(count)

    def test_missing_unknown_duplicate_and_nested_identities_are_rejected(self):
        for count in range(1, 41):
            bad = []
            data = payload(count)
            del data["solutions"][str(count - 1)]
            bad.append(json.dumps(data))
            for key in ("-1", str(count), "01", "1.0", "true", "x"):
                data = payload(count)
                data["solutions"][key] = row()
                bad.append(json.dumps(data))
            data = payload(count)
            data["solutions"]["0"]["index"] = 0
            bad.append(json.dumps(data))
            for raw in bad:
                with self.subTest(count=count, raw=raw), self.assertRaises(ProviderError):
                    adapt_native_response(raw, SolverSlotContract(count))
        for raw in ('{"solutions":{"0":{},"0":{}}}', '{"solutions":{},"solutions":{}}',
                    json.dumps(payload(1)).replace('"judgment": "supported"',
                                                  '"judgment":"refuted","judgment":"supported"')):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, SolverSlotContract(1))

    def test_types_fields_json_and_enum_constraints_remain_strict(self):
        bad = ['[]', '{}', '{"solutions":[]}', '```json\n{}\n```']
        for field in ("choices", "choicePairs"):
            data = payload(1)
            del data["solutions"]["0"][field]
            bad.append(json.dumps(data))
        for group, slot, field, values in (
            ("choices", "a", "judgment", [True, 1, None, "yes", "accepted"]),
            ("choices", "a", "reason", [True, 1, None, [], {}]),
            ("choicePairs", "ab", "relation", [True, 1, None, "supported", "same"]),
        ):
            for value in values:
                data = payload(1)
                data["solutions"]["0"][group][slot][field] = value
                bad.append(json.dumps(data))
        for group, key in (("choices", "e"), ("choicePairs", "aa"), ("choicePairs", "ba")):
            data = payload(1)
            data["solutions"]["0"][group][key] = {}
            bad.append(json.dumps(data))
        for constant in ("NaN", "Infinity", "1e309"):
            bad.append(json.dumps(payload(1)).replace('"supported"', constant, 1))
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                adapt_native_response(raw, SolverSlotContract(1))

    def test_historical_v3_keeps_schema_valid_outer_errors_and_local_veto(self):
        items = [{"index": i, "prompt": f"Which exact integer follows from rule {i}?",
                  "choices": ["One", "Two", "Three", "Four"]} for i in range(2)]
        rows = [{"index": i, **row()} for i in range(2)]
        for records in ([dict(rows[0], index=-1), rows[1]],
                        [rows[0], dict(rows[1], index=0)], rows[:1], rows + [dict(rows[0], index=2)]):
            raw = json.dumps({"solutions": records})
            self.assertEqual(adapt_native_response(raw, "complete_choice_solver_v3"), raw)
            with self.assertRaises(CompleteSolutionFormatError):
                validate_batch(raw, items, choice_slots=True, audit_choice_pairs=True)

    def test_only_transport_override_changes_and_logical_decode_stays_exact(self):
        for count in (1, 5, 40):
            contract = SolverSlotContract(count)
            prefix = native_prompt(COMPLETE_SOLUTION_SLOT_SYSTEM_PROMPT, "complete_choice_solver_v3")
            prompt = native_prompt(COMPLETE_SOLUTION_SLOT_SYSTEM_PROMPT, contract)
            self.assertTrue(prompt.startswith(prefix + "\n\nNATIVE SOLVER IDENTITY OVERRIDE"))
            self.assertIn(contract.name, prompt)
        items = [{"index": i, "prompt": f"Which exact spelling belongs to case {i}?",
                  "choices": ["cafe\u0301  one", "café two", "Cafe three", "CAFÉ four"]} for i in range(2)]
        _, prompt = build_solver_prompt(items, {}, choice_slots=True, audit_choice_pairs=True)
        data = json.loads(prompt.removeprefix("<question_solution_json>\n").removesuffix("\n</question_solution_json>"))
        records = [solver_record(item, "cafe\u0301  one") for item in data["items"]]
        old = json.dumps({"solutions": records}, ensure_ascii=False)
        new = json.dumps(solver_map(*reversed(records)), ensure_ascii=False)
        decoded = adapt_native_response(new, SolverSlotContract(2))
        self.assertEqual(json.loads(decoded), json.loads(old))
        self.assertEqual(validate_batch(decoded, items, choice_slots=True, audit_choice_pairs=True),
                         validate_batch(old, items, choice_slots=True, audit_choice_pairs=True))


class SolverSlotRoutingTests(unittest.TestCase):
    setUp = pipeline.NativePipelineTests.setUp

    def test_actual_count_ignores_target_and_dropped_candidates_then_reviewer_densifies(self):
        invalid = {**self.question, "prompt": "Which other result follows from these exact facts?",
                   "choices": ["same"] * 4, "expectedAnswer": "same"}
        rejected = {**self.question, "prompt": "Which second conclusion follows from these exact facts?"}
        observed = []
        def solve(request):
            data = task_data(request, "question_solution_json")
            self.assertEqual(len(data["items"]), 2)
            self.assertEqual([item["index"] for item in data["items"]], [0, 1])
            records = []
            for item in data["items"]:
                record = solver_record(item, self.question["expectedAnswer"])
                if item["prompt"] == rejected["prompt"]:
                    for value in record["choices"].values():
                        value["judgment"] = "uncertain"
                records.append(record)
            observed.append(copy.deepcopy(data))
            return solver_map(*reversed(records))
        def reviewer(request):
            items = task_data(request, "question_review_json")["items"]
            self.assertEqual([(item["index"], item["prompt"]) for item in items], [(0, self.question["prompt"])])
            return review_map(review(self.question))
        client = ScriptedNativeClient((AUTHOR, author_payload(invalid, rejected, self.question)),
                                      ("complete_choice_solver_v5_n2", solve), (REVIEWER, reviewer))
        reserve = Mock()
        budget = generation.ProviderCallBudget(3, reserve_call=reserve)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        result = generation._generate_sanitized_questions({**self.request, "targetCount": 4}, client, budget, metrics)
        self.assertEqual([question["prompt"] for question in result], [self.question["prompt"]])
        self.assertEqual(result[0]["verificationPolicyRevision"], 4)
        self.assertEqual((len(client.calls), budget.calls, reserve.call_count), (3, 3, 3))
        self.assertEqual(metrics["ProviderObservations"][1]["structuredOutput"],
                         {"mode": "native", **contract_metadata(SolverSlotContract(2))})
        self.assertNotIn("expectedAnswer", json.dumps(observed))

    def test_verified_filter_supplies_count_directly_and_empty_batch_calls_nothing(self):
        solve = Mock(side_effect=AssertionError("Legacy callback must not run"))
        bound = Mock(return_value="{}")
        invalid = {**self.question, "choices": ["repeated"] * 4}
        result = verify_questions([invalid, self.question], {**self.request, "targetCount": 40}, Mock(),
                                  solve=solve, solve_with_count=bound, solver_contract="complete_choices",
                                  choice_slots=True, audit_choice_pairs=True)
        self.assertEqual(result, [])
        self.assertEqual(bound.call_args.args[2], 1)
        solve.assert_not_called()
        bound.reset_mock()
        self.assertEqual(verify_questions([invalid], self.request, Mock(), solve=solve, solve_with_count=bound,
                                         solver_contract="complete_choices", choice_slots=True, audit_choice_pairs=True), [])
        bound.assert_not_called()

    def test_deadline_or_quota_before_solver_dispatch_spends_no_extra_call(self):
        for quota in (False, True):
            client = ScriptedNativeClient((AUTHOR, author_payload(self.question)))
            budget = generation.ProviderCallBudget(3)
            if quota:
                def reserve():
                    if budget.calls == 1:
                        raise ProviderQuotaLimitError
                budget.reserve_call = reserve
                expected = ProviderQuotaLimitError
            else:
                budget.context = Mock(get_remaining_time_in_millis=lambda: 240000 if budget.calls == 0 else 0)
                expected = ProviderDeadlineExceededError
            with self.subTest(quota=quota), self.assertRaises(expected):
                generation._generate_sanitized_questions(self.request, client, budget)
            self.assertEqual((len(client.calls), budget.calls), (1, 1))


if __name__ == "__main__":
    unittest.main()
