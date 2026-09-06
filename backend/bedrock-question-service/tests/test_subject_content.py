"""Prove that code and source meaning survive the real normalization pipeline."""

import ast
import json
from pathlib import Path

import lambda_function
from lambda_test_support import (
    BackendTestCase,
    FakeBedrockClient,
    _event,
    _request_payload,
)
from question_quality import (
    _prompt_without_trailing_choice_echo,
    _question_coverage_payload,
)
from question_verification import verify_questions
from request_contract import _clean_source_text, _clean_subject_text, _normalize_request

FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures/subject_content_contract.json").read_text()
)


class SubjectContentTests(BackendTestCase):
    def test_shared_layout_control_and_unicode_contract(self):
        for case in FIXTURES["cases"]:
            with self.subTest(raw=case["raw"]):
                self.assertEqual(_clean_subject_text(case["raw"]), case["expected"])
                self.assertEqual(_clean_source_text(case["raw"]), case["expected"])

    def test_source_and_generated_code_reach_author_and_reviewer_unchanged(self):
        question = FIXTURES["question"]
        payload = _request_payload(target_count=1)
        payload["sourceDocuments"] = [{"name": "sample.py", "text": FIXTURES["source"]}]
        client = FakeBedrockClient.returning_questions(question)
        response = lambda_function.handle_http_request(
            _event(payload), bedrock_client=client
        )
        self.assertEqual(response["statusCode"], 200)
        generated = json.loads(response["body"])["questions"]
        self.assertEqual(generated[0]["prompt"], question["prompt"])
        author_prompt = client.calls[0]["messages"][0]["content"][0]["text"]
        author_data = json.loads(
            author_prompt.split("<generation_request_json>\n")[1].split(
                "\n</generation_request_json>"
            )[0]
        )
        self.assertEqual(author_data["sourceDocuments"][0]["text"], FIXTURES["source"])
        observed = []

        def reviewer(_, prompt):
            observed.append(
                json.loads(
                    prompt.split("<question_review_json>\n")[1].split(
                        "\n</question_review_json>"
                    )[0]
                )
            )
            return '{"reviews":[]}'

        verify_questions(generated, _normalize_request(payload), reviewer)
        self.assertEqual(observed[0]["items"][0]["prompt"], question["prompt"])
        self.assertEqual(observed[0]["sourceDocuments"][0]["text"], FIXTURES["source"])
        ast.parse(observed[0]["items"][0]["prompt"].split("\n", 1)[1])
        source_tree = ast.parse(observed[0]["sourceDocuments"][0]["text"])
        self.assertEqual(source_tree.body[1].value.args[0].value, "a  b")

    def test_prompt_history_does_not_change_code_layout(self):
        question = FIXTURES["question"]
        payload = _request_payload(target_count=1)
        payload.update(
            existingPrompts=[question["prompt"]],
            reportedPrompts=[question["prompt"]],
            existingQuestionCoverage=[question],
        )
        request = _normalize_request(payload)
        self.assertEqual(request["existingPrompts"], [question["prompt"]])
        self.assertEqual(request["reportedPrompts"], [question["prompt"]])
        self.assertEqual(
            request["existingQuestionCoverage"][0]["prompt"], question["prompt"]
        )
        self.assertEqual(
            _question_coverage_payload(question)["prompt"], question["prompt"]
        )

    def test_choice_echo_removal_preserves_stem_layout_and_literal_content(self):
        question = FIXTURES["question"]
        for labels in [False, True]:
            echo = "\n".join(
                (f"{chr(65 + index)}. " if labels else "") + choice
                for index, choice in enumerate(question["choices"])
            )
            self.assertEqual(
                _prompt_without_trailing_choice_echo(
                    question["prompt"] + "\n\n" + echo, question["choices"]
                ),
                question["prompt"],
            )
        choices = ['"a  b"', '"one"', '"two"', '"three"']
        non_echo = (
            'Preserve the exact quoted lines below:\n"a b"\n"one"\n"two"\n"three"'
        )
        self.assertEqual(
            _prompt_without_trailing_choice_echo(non_echo, choices), non_echo
        )
