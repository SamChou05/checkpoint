"""Offline schema/request checks; no provider client or inference is created."""

import copy
import importlib.util
import json
import unittest

from evals.claim_evidence_schema import output_config

try:
    from jsonschema import Draft202012Validator
except ImportError:
    Draft202012Validator = None


def response():
    citation = {"source_id": "source-é", "quote": '  Exact "quoted" text.\n'}
    return {
        "reviews": [
            {
                "index": 0,
                "valid": True,
                "answer": 'An exact choice: `é  x`',
                "difficulty": 3,
                "explanationSupport": "supported",
                "issues": [],
            }
        ],
        "evidence": {
            "item": [copy.deepcopy(citation)],
            "mainExplanation": [copy.deepcopy(citation)],
            "target": {
                "field": "explanation",
                "choice": None,
                "quote": "A challenged claim.",
                "relation": "supported",
                "citations": [copy.deepcopy(citation)],
            },
        },
    }


class ClaimEvidenceSchemaTests(unittest.TestCase):
    def schema(self):
        return json.loads(output_config()["textFormat"]["structure"]["jsonSchema"]["schema"])

    def test_static_config_is_fresh_and_all_objects_are_closed(self):
        config = output_config()
        saved = copy.deepcopy(config)
        config["textFormat"]["structure"]["jsonSchema"]["schema"] = "changed"
        config["textFormat"]["type"] = "changed"
        self.assertEqual(output_config(), saved)
        self.assertEqual(set(saved), {"textFormat"})
        self.assertEqual(saved["textFormat"]["type"], "json_schema")
        definition = saved["textFormat"]["structure"]["jsonSchema"]
        self.assertEqual(set(definition), {"name", "schema"})
        self.assertIsInstance(definition["schema"], str)
        objects = []

        def visit(value):
            if isinstance(value, dict):
                if value.get("type") == "object":
                    objects.append(value)
                    self.assertIs(value["additionalProperties"], False)
                    self.assertEqual(set(value["required"]), set(value["properties"]))
                for key, child in value.items():
                    self.assertNotIn(key, {
                        "minimum", "maximum", "multipleOf", "minLength", "maxLength",
                        "minItems", "maxItems", "uniqueItems", "$ref", "pattern",
                    })
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)

        visit(self.schema())
        self.assertEqual(len(objects), 7)
        self.assertNotIn("An exact choice", definition["schema"])
        self.assertNotIn("source-é", definition["schema"])

    @unittest.skipUnless(Draft202012Validator, "Optional offline jsonschema unavailable")
    def test_complete_positive_negative_and_uncertain_declarations(self):
        schema = self.schema()
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        baseline = response()
        original = copy.deepcopy(baseline)
        validator.validate(baseline)
        self.assertEqual(baseline, original)
        for support, relation in (
            ("unsupported", "contradicted"), ("uncertain", "unresolved")
        ):
            value = response()
            value["reviews"][0].update(
                valid=False, answer="", explanationSupport=support,
                issues=["The unchanged claim lacks the required condition."],
            )
            value["evidence"]["target"]["relation"] = relation
            value["evidence"]["item"] = []
            value["evidence"]["mainExplanation"] = []
            value["evidence"]["target"]["citations"] = []
            validator.validate(value)
        for field in ("prompt", "choice", "explanation"):
            value = response()
            value["evidence"]["target"].update(
                field=field, choice="A literal choice" if field == "choice" else None,
            )
            validator.validate(value)

    @unittest.skipUnless(Draft202012Validator, "Optional offline jsonschema unavailable")
    def test_reject_missing_extra_wrong_types_and_wrong_statuses(self):
        validator = Draft202012Validator(self.schema())
        mutations = [
            ((), "replacement", "New teaching"),
            (("reviews", 0), "explanation", "New teaching"),
            (("reviews", 0), "verificationPolicyRevision", 3),
            (("reviews", 0), "index", True),
            (("reviews", 0), "valid", 1),
            (("reviews", 0), "difficulty", 6),
            (("reviews", 0), "explanationSupport", "contradicted"),
            (("reviews", 0), "issues", [False]),
            (("evidence",), "choiceExplanations", {}),
            (("evidence", "target"), "relation", "uncertain"),
            (("evidence", "target"), "field", "expectedAnswer"),
            (("evidence", "target"), "choice", 1),
            (("evidence", "item", 0), "offset", 0),
            (("evidence", "mainExplanation", 0), "source_id", None),
            (("evidence", "target", "citations", 0), "quote", []),
        ]
        for path, field, replacement in mutations:
            with self.subTest(path=path, field=field, value=replacement):
                value = response()
                target = value
                for key in path:
                    target = target[key]
                target[field] = replacement
                self.assertFalse(validator.is_valid(value))
        for path in (
            (), ("reviews", 0), ("evidence",), ("evidence", "target"),
            ("evidence", "item", 0), ("evidence", "mainExplanation", 0),
            ("evidence", "target", "citations", 0),
        ):
            original = response()
            target = original
            for key in path:
                target = target[key]
            for field in target:
                with self.subTest(path=path, missing=field):
                    value = copy.deepcopy(original)
                    changed = value
                    for key in path:
                        changed = changed[key]
                    del changed[field]
                    self.assertFalse(validator.is_valid(value))

    @unittest.skipUnless(Draft202012Validator, "Optional offline jsonschema unavailable")
    def test_schema_does_not_replace_application_content_validation(self):
        from question_teaching import AuthoredTeachingFormatError, validate_authored_reviews

        # These satisfy the supported schema subset but still fail the existing
        # application validator. Schema compliance cannot authorize a question.
        validator = Draft202012Validator(self.schema())
        items = [{
            "index": 0,
            "prompt": "Which exact literal has two spaces between its letters?",
            "choices": [response()["reviews"][0]["answer"], "One space", "No spaces", "Three spaces"],
            "explanation": "The displayed literal contains exactly two adjacent spaces.",
        }]
        validate_authored_reviews(json.dumps({"reviews": response()["reviews"]}), items)
        value = response()
        value["reviews"] = []
        validator.validate(value)
        with self.assertRaises(AuthoredTeachingFormatError):
            validate_authored_reviews(json.dumps({"reviews": value["reviews"]}), items)
        for change in ({"index": -1}, {"answer": "not offered"}, {"issues": ["x" * 601]}):
            value = response()
            value["reviews"][0].update(change)
            validator.validate(value)
            with self.subTest(change=change), self.assertRaises(AuthoredTeachingFormatError):
                validate_authored_reviews(json.dumps({"reviews": value["reviews"]}), items)

    @unittest.skipUnless(importlib.util.find_spec("botocore"), "Optional offline botocore unavailable")
    def test_converse_service_model_accepts_exact_request_shape_without_client(self):
        from botocore.session import get_session
        from botocore.validate import validate_parameters

        model = get_session().get_service_model("bedrock-runtime")
        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6",
            "messages": [{"role": "user", "content": [{"text": "Offline fixture."}]}],
            "outputConfig": output_config(),
        }
        for operation in ("Converse", "ConverseStream"):
            validate_parameters(request, model.operation_model(operation).input_shape)


if __name__ == "__main__":
    unittest.main()
