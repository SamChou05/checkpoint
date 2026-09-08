"""Synthetic capture replay only: no provider, browser, or candidate execution."""

import base64
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_artifact_observation_eval as experiment
from tests.test_html_artifact_question import observation as html_observation
from tests.test_html_artifact_question import spec as html_spec
from tests.test_python_artifact_question import service, spec as python_spec


def complete_capture(candidates=None):
    candidates = candidates or [
        [python_spec(), python_spec("False")],
        [html_spec(), html_spec(nested=True)],
    ]
    packet = {
        "experiment": experiment.author.EXPERIMENT,
        "assessment_only": "PRIVATE RUBRIC",
        "cases": [
            {
                "case_id": family + "-synthetic",
                "family": family,
                "system_prompt": "Author two synthetic test artifacts.",
                "user_data": {
                    "goal": {"title": "Interpret " + family, "focusAreas": "State"},
                    "sourceDocuments": [{"title": "Synthetic", "content": "Premise"}],
                    "candidateCount": 2,
                },
            }
            for family in experiment.author.FAMILIES
        ],
    }
    with patch.object(
        experiment.author.shared, "source_revision", return_value="author-revision"
    ):
        plan = experiment.author.make_plan(packet)
    calls, results = [], []
    for index, job in enumerate(plan["jobs"]):
        parsed = {"candidates": copy.deepcopy(candidates[index])}
        calls.append(
            {
                "case_index": index,
                "case_id": job["case_id"],
                "role": "author",
                "request": copy.deepcopy(job["requests"]["author"]),
                "status": "response_received",
                "response": {
                    "text": ["```json\n" + json.dumps(parsed) + "\n```"],
                    "stopReason": "end_turn",
                },
            }
        )
        results.append(
            {
                "case_id": job["case_id"],
                "family": job["family"],
                "status": "completed",
                "provider_calls": 1,
                "stage_outputs": {"author": parsed},
            }
        )
    return {
        "plan": plan,
        "plan_sha256": experiment.digest(experiment.canonical(plan)),
        "status": "completed",
        "stopped_early": False,
        "calls": calls,
        "results": results,
    }


def python_report(plan, observations=None):
    """Fabricate all lifecycle records; these are not real native evidence."""
    native = plan["python_plan"]
    if native is None:
        return None
    prepared = {slot["slot_id"]: slot["prepared"] for slot in plan["slots"]}
    calls, results = [], []
    for index, job in enumerate(native["jobs"]):
        if not job["eligible"]:
            results.append(
                {
                    "case_id": job["case_id"],
                    "status": "unsupported",
                    "cleanup": "not_started",
                    "reason": job["unsupported_reason"],
                }
            )
            continue
        session = f"synthetic-session-{index}"
        result = (
            observations[index]
            if observations
            else service(
                prepared[job["case_id"]], value={"type": "bool", "value": True}
            )
        )
        response = {
            "sessionId": session,
            "events": [
                {
                    "result": {
                        "isError": False,
                        "structuredContent": {
                            "stdout": result["stdOut"],
                            "stderr": result["stdErr"],
                            "exitCode": result["exitCode"],
                        },
                    }
                }
            ],
        }
        lifecycle = {
            "codeInterpreterIdentifier": experiment.managed.INTERPRETER_ID,
            "sessionId": session,
        }
        for operation, request, received in (
            (
                "StartCodeInterpreterSession",
                {
                    "codeInterpreterIdentifier": experiment.managed.INTERPRETER_ID,
                    "name": "checkpoint-objective-evidence",
                    "sessionTimeoutSeconds": 60,
                    "clientToken": f"start-{index}",
                },
                lifecycle,
            ),
            (
                "InvokeCodeInterpreter",
                {
                    **lifecycle,
                    "name": "executeCode",
                    "arguments": {
                        "language": "python",
                        "runtime": "python",
                        "code": job["harness_code"],
                    },
                },
                response,
            ),
            (
                "StopCodeInterpreterSession",
                {**lifecycle, "clientToken": f"stop-{index}"},
                lifecycle,
            ),
        ):
            calls.append(
                {
                    "operation": operation,
                    "request": copy.deepcopy(request),
                    "response": copy.deepcopy(received),
                    "outcome": "completed",
                    "local_worker_stopped": True,
                }
            )
        evidence = experiment.parse_execution_observation(job, result)
        results.append(
            {
                "case_id": job["case_id"],
                "session_id": session,
                "cleanup": "stopped",
                "evidence": evidence,
                "status": evidence["status"],
            }
        )
    count = sum(job["eligible"] for job in native["jobs"])
    return {
        "plan": copy.deepcopy(native),
        "plan_sha256": plan["python_plan_sha256"],
        "outcome": "completed",
        "operational_failure": False,
        "session_attempts": count,
        "invoke_attempts": count,
        "unattempted_cases": 0,
        "calls": calls,
        "results": results,
    }


def refresh_html_stdout(record):
    record["stdout"] = json.dumps(record["envelope"]) + "\n"
    for stream in ("stdout", "stderr"):
        raw = record[stream].encode("utf-8")
        record[stream + "_base64"] = base64.b64encode(raw).decode("ascii")
        record[stream + "_bytes_seen"] = record[stream + "_retained_bytes"] = len(raw)


def html_record(job):
    """A fabricated parent process record, never a launched browser."""
    stdin = experiment.canonical(job) + "\n"
    record = {
        "request": copy.deepcopy(job),
        "stdin_text": stdin,
        "stdin_sha256": experiment.digest(stdin),
        "stdin_bytes": len(stdin.encode("utf-8")),
        "stdin_bytes_sent": len(stdin.encode("utf-8")),
        "observer_path": str(experiment.html_transport.OBSERVER),
        "process_deadline_seconds": experiment.html_transport.PROCESS_TIMEOUT_SECONDS,
        "capture_limit_bytes_per_stream": experiment.html_transport.CAPTURE_BYTES,
        "cleanup_grace_seconds": experiment.html_transport.REAP_GRACE_SECONDS * 3,
        "child_started": True,
        "status": "completed",
        "returncode": 0,
        "reason": "",
        "cleanup": {
            "child_reaped": True,
            "termination_attempted": False,
            "browser_cleanup_confirmed": True,
        },
        "envelope": html_observation(job, job["spec"]["alternatives"][0]["values"]),
        "stderr": "",
    }
    refresh_html_stdout(record)
    return record


class ArtifactObservationEvalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.capture_path = self.root / "capture.json"
        self.capture = complete_capture()
        self.save()

    def save(self):
        self.capture_path.write_text(json.dumps(self.capture), encoding="utf-8")

    def prepare(self):
        self.save()
        return experiment.prepare_observation_plan(self.capture_path)

    def html_records(self, plan):
        return {
            slot["slot_id"]: html_record(slot["prepared"])
            for slot in plan["slots"]
            if slot["family"] == "html" and slot["status"] == "prepared"
        }

    def test_fixed_four_slots_limits_runtime_and_exact_native_sources(self):
        plan = self.prepare()
        self.assertEqual(
            [s["slot_id"] for s in plan["slots"]],
            ["python-1", "python-2", "html-1", "html-2"],
        )
        self.assertEqual([s["status"] for s in plan["slots"]], ["prepared"] * 4)
        self.assertEqual(
            plan["runtime"], {"implementation": "cpython", "version": "3.12.13"}
        )
        for name in experiment.SOURCES:
            self.assertEqual(
                plan["source_sha256"][name],
                hashlib.sha256(
                    (experiment.SERVICE_DIR / name).read_bytes()
                ).hexdigest(),
            )
        limits = plan["python_plan"]["limits"]
        for name, expected in (
            ("maximum_sessions", 2),
            ("maximum_invokes", 2),
            ("run_timeout_seconds", 90),
            ("case_timeout_seconds", 30),
            ("cleanup_reserve_seconds", 5),
        ):
            self.assertEqual(limits[name], expected)
        self.assertEqual(
            plan["python_plan_sha256"],
            experiment.managed.digest(experiment.managed._json(plan["python_plan"])),
        )
        for slot in plan["slots"][2:]:
            self.assertEqual(
                slot["prepared"]["observer_source_sha256"],
                plan["source_sha256"]["evals/observe_html_artifact.js"],
            )

    def test_blind_export_has_only_display_context_and_preserves_whitespace(self):
        plan = self.prepare()
        packet = experiment.blind_packet(plan)
        self.assertEqual(len(packet["items"]), 4)
        for index, (item, slot) in enumerate(
            zip(packet["items"], plan["slots"], strict=True)
        ):
            self.assertEqual(
                set(item), {"id", "goal", "sourceDocuments", "prompt", "choices"}
            )
            display = slot["prepared"]["draft"] if index < 2 else slot["prepared"]
            self.assertEqual(item["prompt"], display["prompt"])
            self.assertEqual(item["choices"], display["choices"])
            self.assertEqual(item["goal"], slot["goal"])
        text = experiment.canonical(packet)
        for forbidden in (
            "expectedAnswer",
            "reason",
            "difficulty",
            "PRIVATE",
            "Proposed",
            "feedback_assessment",
        ):
            self.assertNotIn(forbidden, text)

    def test_unsupported_and_overlong_are_not_repaired_or_removed(self):
        self.capture = complete_capture(
            [
                [
                    python_spec("open('never-open-this')"),
                    python_spec("'" + "x" * 320 + "'"),
                ],
                [html_spec(), {}],
            ]
        )
        plan = self.prepare()
        self.assertEqual(
            [s["status"] for s in plan["slots"]],
            ["unsupported", "unsupported", "prepared", "unsupported"],
        )
        self.assertFalse(plan["python_plan"]["jobs"][0]["eligible"])
        self.assertIsNotNone(plan["slots"][0]["prepared"])
        self.assertIsNone(plan["slots"][1]["prepared"])
        items = experiment.blind_packet(plan)["items"]
        self.assertIn("never-open-this", items[0]["prompt"])
        self.assertIsNone(items[1]["prompt"])
        self.assertEqual(items[1]["choices"], [])
        report = experiment.bind_observations(
            plan,
            self.capture_path,
            python_report=python_report(plan),
            html_observations=self.html_records(plan),
        )
        self.assertFalse(report["operational_failure"])
        self.assertEqual(
            [s["status"] for s in report["slots"]],
            ["unsupported", "unsupported", "bound", "unsupported"],
        )

    def test_no_python_jobs_requires_no_native_report(self):
        self.capture = complete_capture([[{}, {}], [html_spec(), html_spec()]])
        plan = self.prepare()
        self.assertIsNone(plan["python_plan"])
        report = experiment.bind_observations(
            plan, self.capture_path, html_observations=self.html_records(plan)
        )
        self.assertFalse(report["operational_failure"])
        self.assertEqual(
            [s["status"] for s in report["slots"]],
            ["unsupported", "unsupported", "bound", "bound"],
        )

    def test_incomplete_author_capture_never_creates_dispatch_plan_or_directory(self):
        self.capture["status"] = "operational_failure"
        self.capture["stopped_early"] = True
        self.capture["results"][1]["status"] = "operational_failure"
        self.capture["results"][1]["stage_outputs"] = {}
        self.save()
        output = self.root / "must-not-exist"
        with self.assertRaisesRegex(ValueError, "author_not_completed"):
            experiment.main(
                ["--author-capture", str(self.capture_path), "--output", str(output)]
            )
        self.assertFalse(output.exists())

    def test_request_raw_result_and_source_joins_are_required(self):
        mutations = [
            lambda c: c["calls"][0]["request"]["inferenceConfig"].update(
                maxTokens=17000
            ),
            lambda c: c["calls"][0].update(case_index=1),
            lambda c: c["calls"][0].update(case_index=False),
            lambda c: c["calls"][1]["response"].update(stopReason="max_tokens"),
            lambda c: c["results"][0]["stage_outputs"]["author"]["candidates"][
                0
            ].update(topic="Changed"),
            lambda c: c["results"][0]["stage_outputs"]["author"]["candidates"][0][
                "options"
            ][0]["value"].update(value=1),
            lambda c: c["plan"]["source_sha256"].update(
                {experiment.author.ADAPTER_SOURCES[0]: "changed"}
            ),
            lambda c: c["calls"].append(copy.deepcopy(c["calls"][0])),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                self.capture = complete_capture()
                mutate(self.capture)
                self.capture["plan_sha256"] = experiment.digest(
                    experiment.canonical(self.capture["plan"])
                )
                with self.assertRaises(ValueError):
                    self.prepare()

    def test_raw_html_integer_cannot_join_a_boolean_stage_output(self):
        parsed = copy.deepcopy(self.capture["results"][1]["stage_outputs"]["author"])
        parsed["candidates"][0]["alternatives"][0]["values"][0] = 0
        # Ordinary Python equality wrongly calls these records equal.
        self.assertEqual(parsed, self.capture["results"][1]["stage_outputs"]["author"])
        self.capture["calls"][1]["response"]["text"] = [json.dumps(parsed)]
        with self.assertRaisesRegex(ValueError, "author_raw_parsed_join"):
            self.prepare()

    def test_git_revision_change_allowed_but_observation_sources_and_capture_are_bound(
        self,
    ):
        plan = self.prepare()
        with patch.object(
            experiment.author.shared,
            "source_revision",
            side_effect=AssertionError("HEAD must not be queried"),
        ):
            self.assertEqual(
                experiment.validate_observation_plan(plan, self.capture_path), plan
            )
        changed = copy.deepcopy(plan)
        changed["slots"][0]["prepared"]["draft"]["prompt"] += " "
        with self.assertRaisesRegex(ValueError, "observation_plan_changed"):
            experiment.validate_observation_plan(changed, self.capture_path)
        self.capture_path.write_text(self.capture_path.read_text() + "\n")
        with self.assertRaisesRegex(ValueError, "observation_plan_changed"):
            experiment.validate_observation_plan(plan, self.capture_path)
        self.save()
        sources = experiment._source_hashes()
        sources["execution_evidence.py"] = "changed"
        with (
            patch.object(experiment, "_source_hashes", return_value=sources),
            self.assertRaisesRegex(ValueError, "observation_plan_changed"),
        ):
            experiment.validate_observation_plan(plan, self.capture_path)

    def test_synthetic_complete_lifecycles_bind_all_four_without_feedback_certification(
        self,
    ):
        plan = self.prepare()
        with (
            patch.object(
                experiment.managed,
                "run_plan",
                side_effect=AssertionError("No dispatch"),
            ),
            patch.object(
                experiment.author.shared,
                "new_client",
                side_effect=AssertionError("No provider"),
            ),
            patch.object(
                experiment.html_transport,
                "observe_html_job",
                side_effect=AssertionError("No browser dispatch"),
            ),
        ):
            report = experiment.bind_observations(
                plan,
                self.capture_path,
                python_report=python_report(plan),
                html_observations=self.html_records(plan),
            )
        self.assertFalse(report["operational_failure"])
        self.assertEqual([r["status"] for r in report["slots"]], ["bound"] * 4)
        for slot, result in zip(plan["slots"], report["slots"], strict=True):
            question = result["bundle"]["question"]
            draft = (
                slot["prepared"]["draft"]
                if slot["family"] == "python"
                else slot["prepared"]
            )
            self.assertEqual(question["prompt"], draft["prompt"])
            self.assertEqual(question["expectedAnswer"], question["choices"][0])
            self.assertNotIn("verificationVersion", question)
            self.assertEqual(
                question["explanation"], slot["prepared"]["spec"]["explanation"]
            )
        self.assertEqual(report["feedback_assessment"], "unassessed")

    def test_missing_malformed_or_unclean_python_never_binds_any_key(self):
        plan = self.prepare()
        mutations = [
            lambda r: r.update(operational_failure=True),
            lambda r: r["calls"].pop(),
            lambda r: r["calls"][1]["request"]["arguments"].update(code="changed"),
            lambda r: r["calls"][1]["response"].update(sessionId="wrong-session"),
            lambda r: r["calls"][2]["response"].update(sessionId="wrong-stop"),
            lambda r: r["calls"][2].update(local_worker_stopped=False),
            lambda r: r["results"][0].update(cleanup="failed"),
            lambda r: r["results"][0]["evidence"].update(status="unsupported"),
            lambda r: r["calls"][1]["response"]["events"][0]["result"][
                "structuredContent"
            ].update(stdout="{}"),
            lambda r: r["calls"].append(copy.deepcopy(r["calls"][0])),
            lambda r: r["results"][0].update(case_id="python-2"),
        ]
        for index, mutate in enumerate([None, *mutations]):
            with self.subTest(index=index):
                native = python_report(plan) if mutate else None
                if mutate:
                    mutate(native)
                report = experiment.bind_observations(
                    plan,
                    self.capture_path,
                    python_report=native,
                    html_observations=self.html_records(plan),
                )
                self.assertTrue(report["operational_failure"])
                self.assertEqual(
                    [r["status"] for r in report["slots"]], ["blocked"] * 4
                )
                self.assertTrue(all(r["bundle"] is None for r in report["slots"]))

    def test_content_mismatch_and_runtime_mismatch_do_not_become_execution_failures(
        self,
    ):
        plan = self.prepare()
        observations = [
            service(slot["prepared"], value={"type": "int", "value": "99"})
            for slot in plan["slots"][:2]
        ]
        record = json.loads(observations[1]["stdOut"])
        record["runtime"]["version"] = record["child"]["runtime"]["version"] = "3.11.1"
        observations[1]["stdOut"] = json.dumps(record)
        html = self.html_records(plan)
        html["html-1"]["envelope"]["values"] = [True, True, True, True]
        refresh_html_stdout(html["html-1"])
        report = experiment.bind_observations(
            plan,
            self.capture_path,
            python_report=python_report(plan, observations),
            html_observations=html,
        )
        self.assertFalse(report["operational_failure"])
        self.assertEqual(
            [r["status"] for r in report["slots"]],
            ["unmatched", "unsupported", "unmatched", "bound"],
        )
        self.assertTrue(
            all(
                r["bundle"] is None or r["bundle"].get("question") is None
                for r in report["slots"][:3]
            )
        )

    def test_html_cleanup_or_correlation_failure_blocks_later_html(self):
        plan = self.prepare()
        mutations = [
            lambda r: r["cleanup"].update(browser_cleanup_confirmed=False),
            lambda r: r["cleanup"].update(child_reaped=False),
            lambda r: r["cleanup"].update(termination_attempted=True),
            lambda r: r.update(returncode=1),
            lambda r: r.update(status="operational_failure"),
            lambda r: r.update(stdin_text="changed"),
            lambda r: r.update(stdin_sha256="changed"),
            lambda r: r.update(stdin_bytes_sent=0),
            lambda r: r["request"].update(job_id="wrong-job"),
            lambda r: r["envelope"].update(job_id="wrong-job"),
            lambda r: r.update(stdout="{}"),
            lambda r: r.update(stdout_base64="not-base64"),
            lambda r: r.update(stdout_bytes_seen=999999),
            lambda r: r.update(stdout_retained_bytes=0),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                html = self.html_records(plan)
                mutate(html["html-1"])
                report = experiment.bind_observations(
                    plan,
                    self.capture_path,
                    python_report=python_report(plan),
                    html_observations=html,
                )
                self.assertTrue(report["operational_failure"])
                self.assertEqual(
                    [r["status"] for r in report["slots"]],
                    ["bound", "bound", "inconclusive", "blocked"],
                )
                self.assertTrue(all(r["bundle"] is None for r in report["slots"][2:]))

    def test_bare_html_envelope_rejected_and_coherent_parent_unsupported_continues(
        self,
    ):
        plan = self.prepare()
        html = self.html_records(plan)
        html["html-1"] = html["html-1"]["envelope"]
        report = experiment.bind_observations(
            plan,
            self.capture_path,
            python_report=python_report(plan),
            html_observations=html,
        )
        self.assertTrue(report["operational_failure"])
        self.assertEqual(
            [r["status"] for r in report["slots"]][2:], ["inconclusive", "blocked"]
        )
        html = self.html_records(plan)
        row = html["html-1"]
        row.update(status="unsupported", returncode=1)
        row["envelope"].update(
            status="unsupported",
            reason="target_not_unique",
            values=None,
            serialized_dom="",
            serialized_dom_sha256="",
            target_outer_html="",
        )
        refresh_html_stdout(row)
        report = experiment.bind_observations(
            plan,
            self.capture_path,
            python_report=python_report(plan),
            html_observations=html,
        )
        self.assertFalse(report["operational_failure"])
        self.assertEqual(
            [r["status"] for r in report["slots"]],
            ["bound", "bound", "unsupported", "bound"],
        )

    def test_missing_html_stays_unattempted_and_unknown_slots_rejected(self):
        plan = self.prepare()
        report = experiment.bind_observations(
            plan, self.capture_path, python_report=python_report(plan)
        )
        self.assertEqual(
            [r["status"] for r in report["slots"]],
            ["bound", "bound", "unattempted", "unattempted"],
        )
        with self.assertRaisesRegex(ValueError, "unexpected_html_slots"):
            experiment.bind_observations(
                plan,
                self.capture_path,
                python_report=python_report(plan),
                html_observations={"html-3": {}},
            )

    def test_prepare_only_cli_writes_exact_plan_jobs_and_blind_packet(self):
        output = self.root / "prepared"
        with (
            patch("sys.stdout", new_callable=io.StringIO),
            patch.object(
                experiment.managed,
                "run_plan",
                side_effect=AssertionError("No dispatch"),
            ),
        ):
            self.assertEqual(
                experiment.main(
                    [
                        "--author-capture",
                        str(self.capture_path),
                        "--output",
                        str(output),
                    ]
                ),
                0,
            )
        self.assertEqual(
            {p.name for p in output.iterdir()},
            {
                "plan.json",
                "python-plan.json",
                "blinded.json",
                "html-1-job.json",
                "html-2-job.json",
            },
        )
        plan = json.loads((output / "plan.json").read_text())
        self.assertEqual(plan, self.prepare())
        self.assertEqual(
            json.loads((output / "blinded.json").read_text()),
            experiment.blind_packet(plan),
        )
        with self.assertRaises(FileExistsError):
            experiment.main(
                ["--author-capture", str(self.capture_path), "--output", str(output)]
            )


if __name__ == "__main__":
    unittest.main()
