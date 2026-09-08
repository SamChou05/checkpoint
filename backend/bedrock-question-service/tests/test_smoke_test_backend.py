"""Synchronous release smoke checks against fake HTTP responses; no live calls."""

import contextlib
import copy
import io
import json
import sys
import unittest
from unittest import mock

import smoke_test_backend as smoke
from verification_policy import VERIFICATION_POLICY_REVISION, VERIFICATION_VERSION


class SynchronousSmokeTests(unittest.TestCase):
    def question(self, index=0, **changes):
        red, blue = 3 + index * 10, 2 + index * 10
        total = red + blue
        return {
            "prompt": f"A box contains {red} red counters and {blue} blue counters. How many counters are in the box?",
            "expectedAnswer": str(total),
            "choices": [str(total + offset) for offset in (0, -1, 1, 2)],
            "explanation": f"Adding the two groups gives {red} + {blue} = {total} counters.",
            "choiceExplanations": {
                str(
                    total + offset
                ): "Compare this count with the sum of the two groups."
                for offset in (0, -1, 1, 2)
            },
            "topic": "Counting",
            "difficulty": 1,
            "format": "Multiple Choice",
            "verificationVersion": VERIFICATION_VERSION,
            "verificationPolicyRevision": VERIFICATION_POLICY_REVISION,
            **changes,
        }

    def run_smoke(self, questions, *, target=1, arguments=(), envelope=None):
        fixture = {
            "case_id": "counting",
            "payload": {
                "goal": {
                    "title": "Learn counting",
                    "contentTopics": ["Counting"],
                    "needsSkillMap": False,
                },
                "targetCount": target,
                "minimumDifficulty": 1,
            },
            "expect": {"forbidden_terms": ["forbidden-signal"]},
        }
        response = io.BytesIO(
            json.dumps(
                envelope if envelope is not None else {"questions": questions}
            ).encode()
        )
        response.status = 200
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(
                sys,
                "argv",
                [
                    "smoke_test_backend.py",
                    "--case-id",
                    "counting",
                    "--target-count",
                    str(target),
                    *arguments,
                ],
            ),
            mock.patch.object(
                smoke,
                "backend_configuration",
                return_value=(
                    "https://unit.invalid/v1/questions",
                    "synthetic-token",
                ),
            ),
            mock.patch.object(
                smoke, "load_fixture", return_value=copy.deepcopy(fixture)
            ),
            mock.patch.object(
                smoke.urllib.request, "urlopen", return_value=response
            ) as http,
            mock.patch.object(
                smoke.lambda_function,
                "_sanitize_questions",
                wraps=smoke.lambda_function._sanitize_questions,
            ) as sanitizer,
            mock.patch.object(
                smoke.checkpoint_question_eval,
                "score_case_response",
                wraps=smoke.checkpoint_question_eval.score_case_response,
            ) as evaluator,
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            code = smoke.main()
        http.assert_called_once()
        self.assertEqual(
            http.call_args.args[0].full_url, "https://unit.invalid/v1/questions"
        )
        self.assertEqual(json.loads(http.call_args.args[0].data)["targetCount"], target)
        self.assertNotIn("synthetic-token", stdout.getvalue() + stderr.getvalue())
        return code, stdout.getvalue(), stderr.getvalue(), sanitizer, evaluator

    def test_current_policy_is_checked_on_raw_response_before_stamps_are_removed(self):
        question = self.question()
        code, output, _, sanitizer, evaluator = self.run_smoke([question])
        self.assertEqual(code, 0)
        self.assertEqual(sanitizer.call_args.args[0][0], question)
        scored = evaluator.call_args.args[1]["questions"][0]
        self.assertNotIn("verificationVersion", scored)
        self.assertNotIn("verificationPolicyRevision", scored)
        self.assertIn(f"policy >= {VERIFICATION_POLICY_REVISION}", output)
        self.assertIn(
            "Asynchronous bank flow and factual correctness are not established", output
        )

    def test_missing_null_bool_and_other_malformed_metadata_fail_before_sanitization(
        self,
    ):
        for field, invalid in (
            ("verificationVersion", (None, True, False, 1.0, "1", [], {})),
            ("verificationPolicyRevision", (None, True, False, 2.0, "2", [], {})),
        ):
            for value in invalid:
                with self.subTest(field=field, value=value):
                    code, _, error, sanitizer, evaluator = self.run_smoke(
                        [self.question(**{field: value})]
                    )
                    self.assertEqual(code, 1)
                    self.assertIn("response provenance at item 1", error)
                    sanitizer.assert_not_called()
                    evaluator.assert_not_called()
            with self.subTest(field=field, value="missing"):
                question = self.question()
                question.pop(field)
                result = self.run_smoke([question])
                self.assertEqual(result[0], 1)
                result[3].assert_not_called()

    def test_stale_policy_and_unsupported_wire_fail(self):
        for changes in (
            {"verificationPolicyRevision": 0},
            {"verificationPolicyRevision": VERIFICATION_POLICY_REVISION - 1},
            {"verificationVersion": 0},
            {"verificationVersion": VERIFICATION_VERSION + 1},
        ):
            with self.subTest(changes=changes):
                self.assertEqual(self.run_smoke([self.question(**changes)])[0], 1)

    def test_future_integer_revision_uses_same_at_least_policy_rule_as_client(self):
        self.assertEqual(
            self.run_smoke(
                [
                    self.question(
                        verificationPolicyRevision=VERIFICATION_POLICY_REVISION + 1
                    )
                ]
            )[0],
            0,
        )

    def test_explicit_legacy_diagnostic_keeps_typed_stamps_and_labels_actual_floor(
        self,
    ):
        legacy_args = ("--minimum-policy-revision", "1")
        result = self.run_smoke(
            [self.question(verificationPolicyRevision=1)], arguments=legacy_args
        )
        self.assertEqual(result[0], 0)
        self.assertIn("policy >= 1", result[1])
        self.assertEqual(
            self.run_smoke(
                [self.question(verificationPolicyRevision=True)], arguments=legacy_args
            )[0],
            1,
        )

    def test_invalid_cli_policy_fails_without_request_or_configuration_access(self):
        for value in ("0", "-1", "true", str(VERIFICATION_POLICY_REVISION + 1)):
            with (
                self.subTest(value=value),
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "smoke_test_backend.py",
                        "--minimum-policy-revision",
                        value,
                    ],
                ),
                mock.patch.object(smoke, "backend_configuration") as config,
                mock.patch.object(smoke.urllib.request, "urlopen") as http,
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit) as raised,
            ):
                smoke.main()
            self.assertEqual(raised.exception.code, 2)
            config.assert_not_called()
            http.assert_not_called()

    def test_stray_unverified_item_after_sufficient_valid_inventory_cannot_hide(self):
        questions = [self.question(i) for i in range(6)]
        questions[-1].pop("verificationPolicyRevision")
        code, _, error, sanitizer, _ = self.run_smoke(questions, target=5)
        self.assertEqual(code, 1)
        self.assertIn("item 6", error)
        sanitizer.assert_not_called()

    def test_non_question_item_and_malformed_response_envelope_fail(self):
        for questions in ([self.question(), None], ["question"], [False]):
            with self.subTest(questions=questions):
                self.assertEqual(self.run_smoke(questions)[0], 1)
        for envelope in ({}, {"questions": {}}, {"questions": None}):
            with self.subTest(envelope=envelope):
                self.assertEqual(self.run_smoke([], envelope=envelope)[0], 1)

    def test_no_sanitizer_rejected_duplicate_or_surplus_can_hide_in_passing_subset(
        self,
    ):
        for questions, target in (
            ([self.question(), self.question(1, prompt="short")], 2),
            ([self.question(), self.question()], 2),
            ([self.question(), self.question(1)], 1),
        ):
            with self.subTest(target=target, questions=questions):
                code, _, error, _, evaluator = self.run_smoke(questions, target=target)
                self.assertEqual(code, 1)
                self.assertIn("structural validation", error)
                evaluator.assert_not_called()

    def test_every_item_is_scored_even_after_five_meet_existing_count_threshold(self):
        questions = [self.question(i) for i in range(6)]
        questions[-1]["topic"] = "forbidden-signal"
        code, _, error, _, evaluator = self.run_smoke(questions, target=6)
        self.assertEqual(len(evaluator.call_args.args[1]["questions"]), 6)
        self.assertEqual(code, 1)
        self.assertIn("5/6 returned items usable", error)

    def test_existing_minimum_counts_are_preserved(self):
        for count, target, code in (
            (0, 1, 1),
            (1, 2, 1),
            (4, 6, 1),
            (5, 6, 0),
            (6, 6, 0),
        ):
            with self.subTest(count=count, target=target):
                self.assertEqual(
                    self.run_smoke(
                        [self.question(i) for i in range(count)], target=target
                    )[0],
                    code,
                )


if __name__ == "__main__":
    unittest.main()
