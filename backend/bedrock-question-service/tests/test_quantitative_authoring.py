import copy
from dataclasses import replace
import itertools
import json
import unittest

from native_output_contracts import (
    _contract_schema, adapt_native_response, native_output_config, native_prompt,
)
from quantitative_authoring import (
    CompiledCandidate, MIXED_AUTHOR_CONTRACT, QuantitativeAuthoringError,
    checked_provenance, flat_task_spec, prepare_mixed_rows,
)
from quantitative_task_compiler import QuantitativeTaskError, compile_question
from service_errors import ProviderError


def exact_task(value="2", choices=("3", "4", "5", "6")):
    return {"kind": "exact_value", "unit": "unitless", "nodes": [
        {"kind": "literal", "value": value},
        {"kind": "binary", "op": "add", "left": 0, "right": 0},
    ], "root": 1, "choices": dict(zip("abcd", choices, strict=True))}


def scalar_task(nonnegative=True):
    return {"kind": "scalar_condition", "unit": "unitless", "nodes": [
        {"kind": "variable"}, {"kind": "binary", "op": "mul", "left": 0, "right": 0},
        {"kind": "literal", "value": "49"},
    ], "condition": {"left": 1, "relation": "eq", "right": 2},
        "selection": "any_satisfying", "domain": {"kind": "integer_interval", "lower": 0 if nonnegative else -10, "upper": 10},
        "choices": {"a": "-7", "b": "7", "c": "0", "d": "14"}}


def quantitative_row(task=None, **metadata):
    return {"kind": "quantitative", "task": task or exact_task(), "topic": "Arithmetic", "difficulty": 2, **metadata}


class QuantitativeAuthoringTests(unittest.TestCase):
    def test_flat_adapter_matches_exact_tree_compiler_for_every_operation(self):
        for op, answer in (("add", "17/6"), ("sub", "-7/6"), ("mul", "5/3"), ("div", "5/12")):
            task = exact_task()
            task.update(nodes=[{"kind": "literal", "value": "5/6"}, {"kind": "literal", "value": "2"},
                               {"kind": "binary", "op": op, "left": 0, "right": 1}], root=2,
                        choices=dict(zip("abcd", (answer, "0", "4", "-4"), strict=True)))
            expected = {"kind": "exact_value", "unit": "unitless", "choices": [answer, "0", "4", "-4"],
                        "expression": {"op": op, "left": {"value": "5/6"}, "right": {"value": "2"}}}
            self.assertEqual(flat_task_spec(task), expected)
            self.assertEqual(CompiledCandidate.from_task(task).content(), compile_question(expected))

    def test_scalar_operators_selection_and_shared_x_match_tree_contract(self):
        for relation, selection, domain in itertools.product(("lt", "le", "gt", "ge", "eq", "ne"),
                                                               ("any_satisfying", "minimum", "maximum"),
                                                               ({"kind": "offered"}, scalar_task()["domain"])):
            task = scalar_task()
            task["condition"]["relation"] = relation
            task["domain"] = domain
            task["selection"] = selection
            expected = {"kind": "scalar_condition", "unit": "unitless", "choices": ["-7", "7", "0", "14"],
                        "condition": {"left": {"op": "mul", "left": {"variable": "x"}, "right": {"variable": "x"}},
                                      "relation": relation, "right": {"value": "49"}},
                        "selection": selection, "domain": task["domain"]}
            self.assertEqual(flat_task_spec(task), expected)
            try:
                result = compile_question(expected)
            except QuantitativeTaskError:
                with self.assertRaises(QuantitativeTaskError):
                    CompiledCandidate.from_task(task)
            else:
                self.assertEqual(CompiledCandidate.from_task(task).content(), result)

    def test_bad_refs_and_roots_never_construct_a_tree(self):
        for ref in (-1, 1, 2, 10**100, True, 0.0, "0", None):
            task = exact_task()
            task["nodes"][1]["left"] = ref
            with self.subTest(ref=ref), self.assertRaises(QuantitativeAuthoringError):
                flat_task_spec(task)
        for root in (-1, 2, True, 1.0, "1"):
            task = exact_task()
            task["root"] = root
            with self.assertRaises(QuantitativeAuthoringError):
                flat_task_spec(task)

    def test_empty_oversized_unreachable_and_unknown_nodes_rejected(self):
        for nodes in ([], [{"kind": "literal", "value": "2"}] * 32,
                      exact_task()["nodes"] + [{"kind": "literal", "value": "9"}],
                      [{"kind": "variable"}, {"kind": "binary", "op": "add", "left": 0, "right": 0}],
                      [{"kind": "literal", "value": "2", "approved": True}]+
                      exact_task()["nodes"][1:],
                      [{"kind": "code", "value": "2+2"}]):
            task = exact_task()
            task["nodes"] = nodes
            with self.assertRaises(QuantitativeAuthoringError):
                flat_task_spec(task)

    def test_expanded_dag_budget_and_depth_checked_before_materialization(self):
        task = exact_task()
        task["nodes"] = [{"kind": "literal", "value": "1"}]
        for index in range(1, 5):
            task["nodes"].append({"kind": "binary", "op": "add", "left": index-1, "right": index-1})
        task["root"] = 4  # 31 expanded nodes, depth 5.
        self.assertEqual(flat_task_spec(task)["kind"], "exact_value")
        task["nodes"].append({"kind": "binary", "op": "add", "left": 4, "right": 4})
        task["root"] = 5  # 63 expanded nodes, despite only six flat entries.
        with self.assertRaises(QuantitativeAuthoringError):
            flat_task_spec(task)
        task = exact_task()
        task["nodes"] = [{"kind": "literal", "value": "0"}]
        for index in range(1, 6):
            task["nodes"].append({"kind": "binary", "op": "add", "left": index-1, "right": 0})
        task["root"] = 5
        flat_task_spec(task)  # depth 6, expanded size 11.
        task["nodes"].append({"kind": "binary", "op": "add", "left": 5, "right": 0})
        task["root"] = 6
        with self.assertRaises(QuantitativeAuthoringError):
            flat_task_spec(task)

    def test_condition_shared_roots_count_twice_and_local_math_limits_apply(self):
        task = scalar_task()
        task["nodes"] = [{"kind": "variable"}]
        for index in range(1, 5):
            task["nodes"].append({"kind": "binary", "op": "add", "left": index-1, "right": index-1})
        task["condition"].update(left=4, right=4)  # 31+31, not one shared 31-node tree.
        with self.assertRaises(QuantitativeAuthoringError):
            flat_task_spec(task)
        task = scalar_task()
        task["nodes"][1]["op"] = "div"  # x/x undefined at the unoffered domain value 0.
        with self.assertRaisesRegex(QuantitativeTaskError, "undefined_expression"):
            CompiledCandidate.from_task(task)
        task = exact_task("1" * 10000)
        with self.assertRaises(QuantitativeTaskError):
            CompiledCandidate.from_task(task)

    def test_hostile_domain_is_rejected_without_deepcopying_unbounded_content(self):
        task = scalar_task()
        nested = {}
        for _ in range(2000):
            nested = {"nested": nested}
        for domain in (nested, {"kind": "integer_interval", "lower": nested, "upper": 10}):
            task["domain"] = domain
            with self.assertRaises(QuantitativeTaskError):
                CompiledCandidate.from_task(task)
        cycle = {"kind": "integer_interval", "upper": 10}
        cycle["lower"] = cycle
        task["domain"] = cycle
        with self.assertRaises(QuantitativeTaskError):
            CompiledCandidate.from_task(task)

    def test_combined_root_boundary_is_30_or_32_expanded_nodes(self):
        task = scalar_task()
        task["nodes"] = [{"kind": "variable"}]
        for index in range(1, 4):
            task["nodes"].append({"kind": "binary", "op": "add", "left": index-1, "right": index-1})
        task["condition"].update(left=3, right=3)  # 15 + 15.
        flat_task_spec(task)
        task["nodes"].append({"kind": "binary", "op": "add", "left": 3, "right": 0})
        task["condition"]["right"] = 4  # 15 + 17.
        with self.assertRaises(QuantitativeAuthoringError):
            flat_task_spec(task)

    def test_sdk_models_exact_shared_schema_request_without_network(self):
        from botocore.session import get_session
        from botocore.validate import validate_parameters
        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6",
            "messages": [{"role": "user", "content": [{"text": "synthetic task"}]}],
            "outputConfig": native_output_config(MIXED_AUTHOR_CONTRACT),
        }
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        validate_parameters(request, shape)

    def test_compiler_failure_is_a_hole_not_prose_or_repaired_key(self):
        rows, sidecar, failures = prepare_mixed_rows({"questions": [quantitative_row(scalar_task(False)), quantitative_row()]})
        self.assertIsNone(rows[0])
        self.assertEqual(set(sidecar), {1})
        self.assertEqual(failures, ["multiple_answers"])
        self.assertEqual(rows[1]["expectedAnswer"], "4")
        bad = quantitative_row(scalar_task(False))
        bad["question"] = {"prompt": "fallback is forbidden"}
        with self.assertRaises(QuantitativeAuthoringError):
            prepare_mixed_rows({"questions": [bad]})

    def test_provenance_recompiles_and_rejects_field_or_spec_mutation(self):
        task = exact_task()
        before = copy.deepcopy(task)
        provenance = CompiledCandidate.from_task(task)
        question = provenance.content()
        self.assertEqual(task, before)
        for field in question:
            changed = copy.deepcopy(question)
            changed[field] = [] if isinstance(changed[field], list) else "changed"
            with self.assertRaises(QuantitativeAuthoringError):
                provenance.content(changed)
        spec = json.loads(provenance.spec_json)
        spec["unit"] = "m"
        with self.assertRaises(QuantitativeAuthoringError):
            replace(provenance, spec_json=json.dumps(spec)).content()
        for mapping in ({True: provenance}, {-1: provenance}, {1: provenance}, {0: {"compiled": True}}):
            with self.assertRaises(QuantitativeAuthoringError):
                checked_provenance(mapping, 1)

    def test_native_shared_schema_expands_exactly_and_is_nonrecursive(self):
        schema = json.loads(native_output_config(MIXED_AUTHOR_CONTRACT)["textFormat"]["structure"]["jsonSchema"]["schema"])
        def expand(value, stack=()):
            if isinstance(value, list):
                return [expand(child, stack) for child in value]
            if not isinstance(value, dict):
                return value
            if "$ref" in value:
                name = value["$ref"].removeprefix("#/$defs/")
                self.assertNotIn(name, stack)
                return expand(schema["$defs"][name], (*stack, name))
            return {key: expand(child, stack) for key, child in value.items() if key != "$defs"}
        self.assertEqual(expand(schema), _contract_schema(MIXED_AUTHOR_CONTRACT))
        exact, scalar = schema["$defs"]["task"]["anyOf"]
        self.assertEqual(list(exact["properties"]), ["kind", "unit", "nodes", "root", "choices"])
        self.assertEqual(list(scalar["properties"]), ["kind", "unit", "nodes", "condition", "selection", "domain", "choices"])

    def test_native_example_and_payload_validate_without_conflicting_legacy_example(self):
        import question_generation
        system = native_prompt(question_generation._system_prompt(), MIXED_AUTHOR_CONTRACT)
        line = next(line for line in system.splitlines() if line.startswith('{"questions":['))
        payload = json.loads(line)
        adapt_native_response(line, MIXED_AUTHOR_CONTRACT)
        prepare_mixed_rows(payload)
        self.assertNotIn('"expectedAnswer":"..."', system)
        self.assertNotIn("expectedAnswer exactly equals", system)
        valid = json.dumps({"questions": [quantitative_row()]})
        self.assertEqual(adapt_native_response(valid, MIXED_AUTHOR_CONTRACT), valid)
        for key in ("expectedAnswer", "verificationPolicyRevision", "compiled", "hash"):
            bad = quantitative_row()
            bad[key] = "untrusted"
            with self.assertRaises(ProviderError):
                adapt_native_response(json.dumps({"questions": [bad]}), MIXED_AUTHOR_CONTRACT)


if __name__ == "__main__":
    unittest.main()
