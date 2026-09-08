"""Shared iOS wire fixtures and normalization of source omission provenance."""

import copy
import json
from pathlib import Path
import unittest

import lambda_function
from complete_question_solution import build_solver_prompt
from request_contract import (
    MAX_SOURCE_CONTEXT_CHARS,
    _normalize_request,
    _normalize_skill_map_inference_request,
    _normalized_source_documents,
)
from service_errors import BadRequestError
from lambda_test_support import BackendTestCase, FakeBedrockClient, _event, _raw_question, _request_payload


FIXTURE = Path(__file__).parent / "fixtures/source_truncation_contract.json"


class SourceTruncationTests(BackendTestCase):
    def test_wire_sources_reach_actual_author_solver_and_reviewer_callbacks(self):
        documents = [case["expected_wire"] for case in json.loads(FIXTURE.read_text())["cases"]]
        payload = _request_payload(target_count=1)
        payload["sourceDocuments"] = documents
        client = FakeBedrockClient.returning_questions(
            _raw_question("Which conclusion is supported by the stated argument?")
        )
        response = lambda_function.handle_http_request(_event(payload), bedrock_client=client)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual([len(client.calls), len(client.solution_calls), len(client.review_calls)], [1, 1, 1])
        for call, tag in ((client.calls[0], "generation_request_json"),
                          (client.solution_calls[0], "question_solution_json"),
                          (client.review_calls[0], "question_review_json")):
            user = call["messages"][0]["content"][0]["text"]
            supplied = json.loads(user.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])
            self.assertEqual(supplied["sourceDocuments"], documents)

    def test_shared_swift_encoded_wire_survives_normalization_and_solver_context(self):
        cases = json.loads(FIXTURE.read_text())["cases"]
        documents = [case["expected_wire"] for case in cases]
        payload = _request_payload(target_count=1, minimum_difficulty=1)
        # The Swift suite independently encodes these exact same stored records
        # through Goal + BackendQuestionRequest and asserts these wire objects.
        payload["sourceDocuments"] = json.loads(json.dumps(documents))
        request = _normalize_request(payload)
        self.assertEqual(request["sourceDocuments"], documents)
        self.assertEqual(_normalize_skill_map_inference_request(payload)["sourceDocuments"], documents)
        # Model the persisted normalized request loaded for a later bank top-off.
        restored = json.loads(json.dumps(request))
        self.assertEqual(_normalized_source_documents(restored["sourceDocuments"]), documents)
        _, user = build_solver_prompt(
            [{"index": 0, "prompt": "Which literal is returned?", "choices": ["a  b", "a b", "ab", "a   b"]}],
            restored,
        )
        model_input = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(model_input["sourceDocuments"], documents)

    def test_backend_truncation_dominates_known_false_and_legacy_unknown(self):
        for flag in (True, False, "absent"):
            with self.subTest(flag=flag):
                source = {"name": "Long notes", "text": "BEGIN " + "a" * 30000 + " END"}
                if flag != "absent":
                    source["truncated"] = flag
                result = _normalized_source_documents([source])
                self.assertTrue(result[0]["truncated"])
                self.assertTrue(result[0]["text"].startswith("BEGIN"))
                self.assertTrue(result[0]["text"].endswith("END"))
                self.assertLessEqual(len(result[0]["text"]), MAX_SOURCE_CONTEXT_CHARS)
                self.assertEqual(_normalized_source_documents(result), result)

    def test_shared_budget_omission_is_sticky_after_repeated_roundtrip(self):
        sources = [{"name": str(i), "text": str(i) * 10000, "truncated": False} for i in range(3)]
        result = _normalized_source_documents(sources)
        self.assertTrue(all(s["truncated"] for s in result))
        self.assertEqual(sum(len(s["text"]) for s in result), MAX_SOURCE_CONTEXT_CHARS)
        self.assertEqual(_normalized_source_documents(json.loads(json.dumps(result))), result)

    def test_present_flag_requires_actual_boolean(self):
        for value in (None, 0, 1, 0.0, "false", "true", [], {}):
            with self.subTest(value=value):
                source = {"name": "Notes", "text": "The complete supplied text.", "truncated": value}
                with self.assertRaisesRegex(BadRequestError, "truncated must be a boolean"):
                    _normalized_source_documents([source])

    def test_no_inference_from_marker_whitespace_or_untrusted_url_metadata(self):
        source = {"name": "Short", "text": "  def f():\r\n    return 'a  b'\r\n# […truncated…]  ",
                  "url": "https://not-fetched.example/page", "verified": True}
        before = copy.deepcopy(source)
        result = _normalized_source_documents([source])[0]
        self.assertNotIn("truncated", result)
        self.assertNotIn("url", result)
        self.assertNotIn("verified", result)
        self.assertEqual(result["text"], "  def f():\n    return 'a  b'\n# […truncated…]  ")
        self.assertEqual(source, before)


if __name__ == "__main__":
    unittest.main()
