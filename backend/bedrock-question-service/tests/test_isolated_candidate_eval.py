import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_isolated_candidate_eval as experiment
from question_generation import ProviderCallBudget
from question_quality import _extract_json_object
from service_errors import ProviderError


def judgment(
    status="supported", reason="The premises establish the answer.", detail=""
):
    return {
        "status": status,
        "reason": reason,
        "qualification_or_counterexample": detail,
    }


def response(text, stop="end_turn"):
    return {
        "output": {
            "message": {
                "content": [
                    {
                        "reasoningContent": {
                            "reasoningText": {"text": "PRIVATE REASONING"}
                        }
                    },
                    {"text": text},
                ]
            }
        },
        "stopReason": stop,
        "usage": {"inputTokens": 12, "outputTokens": 20},
    }


class FakeClient:
    def __init__(self, callback):
        self.callback = callback
        self.requests = []

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        return self.callback(request)


class IsolatedCandidateEvalTests(unittest.TestCase):
    def setUp(self):
        self.packet = experiment.load_fixture()
        self.case = self.packet["cases"][0]
        self.references = self.packet["evidence_by_case_id"][self.case["case_id"]]
        self.job = experiment.make_job(self.case, self.references, 0)

    def result(self, index, status, case_id=None):
        return {
            "case_id": case_id or self.case["case_id"],
            "choice_index": index,
            "outcome": "judged",
            "judgment": judgment(
                status,
                detail=""
                if status == "supported"
                else "A necessary condition fails or is unresolved.",
            ),
        }

    def test_fixture_reuses_exact_existing_controls_and_packets(self):
        original = json.loads(
            (
                experiment.FIXTURE_PATH.parent / "question_evidence_feasibility.json"
            ).read_text()
        )
        self.assertEqual(self.packet["cases"], original["cases"])
        self.assertEqual(
            self.packet["evidence_by_case_id"], original["evidence_by_case_id"]
        )
        self.assertEqual(
            sum(len(case["question"]["choices"]) for case in self.packet["cases"]), 16
        )

    def test_context_whitelists_one_candidate_without_author_metadata(self):
        context = json.loads(self.job["user_prompt"])
        self.assertEqual(set(context), {"goal", "stem", "candidate", "references"})
        self.assertEqual(context["stem"], self.case["question"]["prompt"])
        self.assertEqual(context["candidate"], self.case["question"]["choices"][0])
        self.assertEqual(context["goal"], self.case["goal"])
        for other in self.case["question"]["choices"][1:]:
            self.assertNotIn(other, self.job["user_prompt"])
        for forbidden in (
            "expectedAnswer",
            "explanation",
            "rationale",
            "expected_accept",
            "choice_index",
            "case_id",
        ):
            self.assertNotIn(forbidden, context)

    def test_other_choices_key_explanation_verdicts_cannot_change_candidate_prompt(
        self,
    ):
        changed = copy.deepcopy(self.case)
        changed["question"].update(
            expectedAnswer="KEY SECRET", explanation="EXPLANATION SECRET"
        )
        changed["question"]["choices"][1:] = [
            "OTHER1 SECRET",
            "OTHER2 SECRET",
            "OTHER3 SECRET",
        ]
        changed.update(
            expected_accept=True,
            rationale="RATIONALE SECRET",
            solver_feedback="SOLVER SECRET",
        )
        changed["goal"]["review_verdict"] = "VERDICT SECRET"
        self.assertEqual(experiment.make_job(changed, self.references, 0), self.job)

    def test_subject_whitespace_is_preserved_in_stem_candidate_and_reference(self):
        case = copy.deepcopy(self.case)
        case["question"]["prompt"] = 'if True:\n    print("a  b")\nWhat prints?'
        case["question"]["choices"][0] = '"a  b"'
        references = [{"name": "Python", "text": 'if True:\n    print("a  b")'}]
        context = json.loads(experiment.make_job(case, references, 0)["user_prompt"])
        self.assertEqual(context["stem"], case["question"]["prompt"])
        self.assertEqual(context["candidate"], '"a  b"')
        self.assertEqual(context["references"][0]["text"], references[0]["text"])

    def test_runtime_fences_and_prose_wrappers_have_identical_parsing(self):
        raw = json.dumps(judgment())
        for wrapped in (
            raw,
            f"```json\n{raw}\n```",
            f"```\n{raw}\n```",
            f"Result: {raw}",
        ):
            with self.subTest(wrapped=wrapped):
                self.assertEqual(
                    experiment.parse_judgment(wrapped), _extract_json_object(wrapped)
                )

    def test_malformed_judgments_fail_without_becoming_content_rejections(self):
        examples = [
            "broken JSON",
            json.dumps({}),
            json.dumps({**judgment(), "status": "maybe"}),
            json.dumps({**judgment(), "reason": " "}),
            json.dumps(judgment(detail="Only if an unstated condition holds.")),
            json.dumps(judgment("undetermined")),
            json.dumps(judgment("refuted")),
            json.dumps({**judgment(), "qualification_or_counterexample": []}),
        ]
        for raw in examples:
            with (
                self.subTest(raw=raw),
                self.assertRaises(experiment.CandidateFormatError),
            ):
                experiment.parse_judgment(raw)

    def test_exactly_one_supported_and_three_refuted_is_required(self):
        for states, accepted in [
            (["supported", "refuted", "refuted", "refuted"], True),
            (["supported", "undetermined", "refuted", "refuted"], False),
            (["supported", "supported", "refuted", "refuted"], False),
            (["refuted"] * 4, False),
            (["undetermined"] * 4, False),
        ]:
            result = experiment.aggregate(
                [self.result(i, state) for i, state in enumerate(states)]
            )
            self.assertTrue(result["evaluable"])
            self.assertEqual(result["accepted"], accepted)
            self.assertEqual(result["selected_choice_index"], 0 if accepted else None)

    def test_missing_duplicate_mixed_or_failed_judgments_are_not_evaluable(self):
        good = [self.result(i, "supported" if i == 0 else "refuted") for i in range(4)]
        bad_groups = [
            good[:-1],
            good[:-1] + [good[0]],
            good[:-1] + [{**good[-1], "case_id": "another"}],
        ]
        bad_groups += [
            good[:-1] + [{**good[-1], "outcome": outcome}]
            for outcome in ("provider_error", "judgment_format_error")
        ]
        for group in bad_groups:
            result = experiment.score_case(self.case, group)
            self.assertFalse(result["evaluable"])
            self.assertFalse(result["passed"])
            self.assertIsNone(result["accepted"])

    def test_cannot_determine_can_be_supported_with_countermodels_refuting_guesses(
        self,
    ):
        case = {
            "case_id": "hidden_marble",
            "goal": {"title": "Reason from incomplete information"},
            "question": {
                "prompt": "One hidden marble is either red or blue. From this information, what color is it?",
                "choices": ["Red", "Blue", "Green", "Cannot be determined"],
                "expectedAnswer": "Cannot be determined",
            },
            "expected_accept": True,
        }
        judgments = [
            judgment(
                "refuted",
                "A blue marble satisfies the premises; red is not established.",
                "The blue model is a counterexample to this determinate answer.",
            ),
            judgment(
                "refuted",
                "A red marble satisfies the premises; blue is not established.",
                "The red model is a counterexample to this determinate answer.",
            ),
            judgment(
                "refuted",
                "The premise permits only red or blue.",
                "Green contradicts the stated possibilities.",
            ),
            judgment(
                "supported",
                "Both red and blue models satisfy the premises and give different colors.",
            ),
        ]
        results = []
        for index, value in enumerate(judgments):
            job = experiment.make_job(case, [], index)
            with patch.object(
                experiment, "_generate_with_bedrock", return_value=json.dumps(value)
            ):
                results.append(experiment.capture(job, None, ProviderCallBudget(1)))
        self.assertTrue(experiment.score_case(case, results)["passed"])
        self.assertEqual(experiment.aggregate(results)["selected_choice_index"], 3)

    def test_provider_exception_truncation_and_malformed_output_do_not_pass_bad_control(
        self,
    ):
        outputs = [ProviderError("provider failed"), "invalid", json.dumps(judgment())]
        for item in outputs:
            if isinstance(item, Exception):
                client = FakeClient(lambda request: (_ for _ in ()).throw(item))
            else:
                client = FakeClient(
                    lambda request: response(
                        item, "max_tokens" if item != "invalid" else "end_turn"
                    )
                )
            with patch.dict("os.environ", experiment.SETTINGS):
                captured = experiment.capture(
                    self.job, experiment.RecordingClient(client), ProviderCallBudget(1)
                )
            self.assertNotEqual(captured["outcome"], "judged")
            group = [captured] + [
                self.result(index, "refuted") for index in range(1, 4)
            ]
            self.assertFalse(experiment.score_case(self.case, group)["passed"])

    def test_full_fake_run_has_sixteen_fresh_requests_exact_prompts_and_no_reasoning_text(
        self,
    ):
        by_stem = {case["question"]["prompt"]: case for case in self.packet["cases"]}

        def answer(request):
            context = json.loads(request["messages"][0]["content"][0]["text"])
            case = by_stem[context["stem"]]
            supported = (
                case["expected_accept"]
                and context["candidate"] == case["question"]["expectedAnswer"]
            )
            return response(
                json.dumps(
                    judgment(
                        "supported" if supported else "refuted",
                        detail="" if supported else "A requirement is contradicted.",
                    )
                )
            )

        client = FakeClient(answer)
        with tempfile.TemporaryDirectory() as directory, patch("builtins.print"):
            output = Path(directory) / "capture.json"
            report = experiment.run_experiment(self.packet, output, client)
            self.assertEqual(
                json.loads(output.read_text()), json.loads(json.dumps(report))
            )
        self.assertEqual(len(client.requests), 16)
        self.assertEqual(report["attempted_calls"], 16)
        self.assertFalse(report["stopped_early"])
        self.assertTrue(
            all(score["passed"] for score in report["case_scores"].values())
        )
        self.assertNotIn("PRIVATE REASONING", json.dumps(report))
        for request in client.requests:
            self.assertEqual(len(request["messages"]), 1)
            self.assertEqual(request["messages"][0]["role"], "user")
            self.assertEqual(
                request["system"], [{"text": experiment.ISOLATED_SYSTEM_PROMPT}]
            )
            self.assertNotIn("outputConfig", request)
            self.assertEqual(
                request["additionalModelRequestFields"],
                {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            )

    def test_first_provider_failure_stops_whole_run_without_retry(self):
        client = FakeClient(lambda request: (_ for _ in ()).throw(TimeoutError()))
        with tempfile.TemporaryDirectory() as directory, patch("builtins.print"):
            report = experiment.run_experiment(
                self.packet, Path(directory) / "capture.json", client
            )
        self.assertEqual(len(client.requests), 1)
        self.assertEqual(report["attempted_calls"], 1)
        self.assertEqual(report["unattempted_candidates"], 15)
        self.assertTrue(report["stopped_early"])
        self.assertTrue(
            all(
                not score["evaluable"] and not score["passed"]
                for score in report["case_scores"].values()
            )
        )

    def test_request_is_durable_before_network_attempt_begins(self):
        with tempfile.TemporaryDirectory() as directory, patch("builtins.print"):
            output = Path(directory) / "capture.json"

            def observe_then_fail(request):
                pending = json.loads(output.read_text())
                self.assertEqual(pending["attempted_calls"], 1)
                self.assertEqual(pending["unattempted_candidates"], 15)
                self.assertEqual(pending["calls"], [{"request": request}])
                self.assertEqual(pending["results"], [])
                raise TimeoutError()

            experiment.run_experiment(
                self.packet, output, FakeClient(observe_then_fail)
            )
            finished = json.loads(output.read_text())
        self.assertEqual(finished["calls"][0]["error_type"], "TimeoutError")

    def test_refusal_and_other_nonterminal_stops_fail_even_with_valid_judgment_json(
        self,
    ):
        for stop in ("refusal", "stop_sequence", "tool_use", None):
            with self.subTest(stop=stop):
                client = FakeClient(
                    lambda request: response(json.dumps(judgment()), stop)
                )
                with (
                    tempfile.TemporaryDirectory() as directory,
                    patch("builtins.print"),
                ):
                    report = experiment.run_experiment(
                        self.packet, Path(directory) / "capture.json", client
                    )
                self.assertEqual(report["attempted_calls"], 1)
                self.assertTrue(report["stopped_early"])
                self.assertEqual(report["results"][0]["outcome"], "provider_error")
                self.assertEqual(report["results"][0]["stop_reason"], stop)
                self.assertNotIn("judgment", report["results"][0])

    def test_recording_client_never_makes_seventeenth_call(self):
        client = FakeClient(lambda request: response("{}"))
        recording = experiment.RecordingClient(client)
        for _ in range(16):
            recording.converse(messages=[])
        with self.assertRaises(RuntimeError):
            recording.converse(messages=[])
        self.assertEqual(len(client.requests), 16)


if __name__ == "__main__":
    unittest.main()
