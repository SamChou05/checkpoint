from contextlib import redirect_stdout, redirect_stderr
import copy
import io
import json
from pathlib import Path
import tempfile
import types
import time
import unittest
from unittest.mock import patch

from evals import checkpoint_execution_evidence_eval as experiment


def job(case_id="literal"):
    return {
        "case_id": case_id,
        "eligible": True,
        "unsupported_reason": None,
        "harness_code": 'TRUSTED_HARNESS_DATA = "e\u0301  x"\n',
        "harness_sha256": experiment.digest('TRUSTED_HARNESS_DATA = "e\u0301  x"\n'),
        "artifact_sha256": "a" * 64,
        "input_sha256": "b" * 64,
        "mode": "exec",
        "job_id": "fixture-id",
    }


def successful_response(operation, request):
    response = {
        "codeInterpreterIdentifier": experiment.INTERPRETER_ID,
        "sessionId": request.get("sessionId", "session-1"),
    }
    if operation == "InvokeCodeInterpreter":
        response = {
            "sessionId": request["sessionId"],
            "events": [
                {
                    "result": {
                        "isError": False,
                        "structuredContent": {
                            "stdout": '{"compile_exception": "SyntaxError"}',
                            "stderr": "",
                            "exitCode": 0,
                        },
                    }
                }
            ],
        }
    return {"outcome": "completed", "reason": None, "response": response}


def parse_observation(prepared, result):
    assert set(result) == {"stdOut", "stdErr", "exitCode", "isError"}
    return {"status": "observed", "observation": json.loads(result["stdOut"])}


class FakeClock:
    now = 0

    def __call__(self):
        return self.now


class FakeExecutor:
    def __init__(self, capture, callback=None):
        self.capture, self.callback, self.calls = capture, callback, []

    def __call__(self, operation, request, timeout, limits, on_progress):
        record = json.loads(self.capture.read_text())["calls"][-1]
        assert record["operation"] == operation
        assert record["request"] == request
        assert record["outcome"] == "dispatch_pending"
        assert record["attempted_remote_usage"] is None
        self.calls.append((operation, copy.deepcopy(request), timeout))
        if self.callback:
            return self.callback(operation, request, timeout, on_progress)
        return successful_response(operation, request)


def blocked_worker(connection, operation, request, region, timeout, limits):
    experiment._send_message(
        connection,
        {"kind": "response", "response": {"sessionId": "known", "events": []}},
    )
    experiment._send_message(
        connection, {"kind": "event", "event": {"partial": "retained"}}
    )
    time.sleep(30)


def too_many_events_worker(connection, operation, request, region, timeout, limits):
    experiment._send_message(
        connection,
        {"kind": "response", "response": {"sessionId": "known", "events": []}},
    )
    for _ in range(3):
        experiment._send_message(
            connection, {"kind": "event", "event": {"partial": "x"}}
        )
    experiment._send_message(connection, {"kind": "complete"})
    connection.close()


def partial_frame_worker(connection, operation, request, region, timeout, limits):
    connection.sendall(b'{"kind":"response","response":')
    time.sleep(30)


class ExecutionEvidenceEvalTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / "capture.json"

    def run_jobs(
        self,
        jobs=None,
        callback=None,
        parser=parse_observation,
        limits=None,
        clock=None,
    ):
        self.executor = FakeExecutor(self.output, callback)
        self.plan = experiment.prepare_plan(jobs or [job()], limits)
        return experiment.run_plan(
            self.plan,
            self.output,
            parser,
            executor=self.executor,
            **({"clock": clock} if clock else {}),
        )

    def test_exact_requests_precede_send_and_session_has_one_invoke_and_stop(self):
        original = job()
        report = self.run_jobs([original])
        self.assertEqual(report["outcome"], "completed")
        self.assertEqual(report["results"][0]["status"], "observed")
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertEqual(
            [item[0] for item in self.executor.calls],
            [
                "StartCodeInterpreterSession",
                "InvokeCodeInterpreter",
                "StopCodeInterpreterSession",
            ],
        )
        start, invoke, stop = [item[1] for item in self.executor.calls]
        self.assertEqual(start["sessionTimeoutSeconds"], 60)
        self.assertEqual(start["codeInterpreterIdentifier"], "aws.codeinterpreter.v1")
        self.assertEqual(len(start["clientToken"]), 36)
        self.assertEqual(
            invoke["arguments"]["code"].encode(), original["harness_code"].encode()
        )
        self.assertEqual(invoke["sessionId"], stop["sessionId"])
        self.assertNotIn("filesystemConfigurations", start)
        self.assertEqual(report["session_attempts"], 1)
        self.assertEqual(report["invoke_attempts"], 1)
        self.assertEqual(json.loads(self.output.read_text()), report)
        self.assertTrue(all(value is None for value in report["usage"].values()))

    def test_intentional_syntax_error_is_observation_not_content_rejection(self):
        report = self.run_jobs()
        result = report["results"][0]
        self.assertEqual(
            result["evidence"]["observation"]["compile_exception"], "SyntaxError"
        )
        self.assertEqual(result["status"], "observed")
        self.assertNotIn("accepted", result)
        self.assertNotIn("passed", result)
        self.assertFalse(report["operational_failure"])

    def test_unsupported_case_uses_no_session(self):
        report = self.run_jobs(
            [
                {
                    "case_id": "missing",
                    "eligible": False,
                    "unsupported_reason": "missing input",
                }
            ]
        )
        self.assertEqual(report["results"][0]["status"], "unsupported")
        self.assertEqual(report["session_attempts"], 0)
        self.assertEqual(self.executor.calls, [])

    def test_caps_reject_plan_before_output_or_operation(self):
        for limits in [
            experiment.Limits(maximum_sessions=1),
            experiment.Limits(maximum_invokes=1),
        ]:
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                experiment.prepare_plan([job("one"), job("two")], limits)
        for limits in [
            experiment.Limits(maximum_sessions=17),
            experiment.Limits(maximum_invokes=True),
            experiment.Limits(cleanup_reserve_seconds=20),
            experiment.Limits(max_events=129),
        ]:
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                experiment.prepare_plan([job()], limits)
        self.assertFalse(self.output.exists())

    def test_ineligible_or_oversized_harness_is_not_executable(self):
        for item in [
            {**job(), "eligible": None},
            {**job(), "harness_sha256": "incorrect"},
            {**job(), "harness_code": "x" * (experiment.MAX_HARNESS_BYTES + 1)},
            {"case_id": "missing", "eligible": False},
        ]:
            with self.assertRaises(ValueError):
                experiment.prepare_plan([item])

    def test_existing_capture_is_not_overwritten(self):
        self.output.write_text("previous evidence")
        with self.assertRaises(FileExistsError):
            self.run_jobs()
        self.assertEqual(self.output.read_text(), "previous evidence")
        self.assertEqual(self.executor.calls, [])

    def test_plan_ttl_and_provider_changes_are_rejected(self):
        plan = experiment.prepare_plan([job()])
        for field, value in [
            ("session_ttl_seconds", 900),
            ("sdk_total_max_attempts", 2),
            ("interpreter_id", "custom"),
        ]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                experiment.run_plan(
                    {**plan, field: value}, self.output, parse_observation
                )
        self.assertFalse(self.output.exists())

    def test_unknown_start_timeout_does_not_retry_or_admit_next_case(self):
        report = self.run_jobs(
            [job("one"), job("two")],
            lambda *args: {
                "outcome": "inconclusive",
                "reason": "deadline",
                "response": None,
            },
        )
        self.assertEqual(report["outcome"], "failed")
        self.assertEqual(len(self.executor.calls), 1)
        self.assertEqual(report["invoke_attempts"], 0)
        self.assertEqual(report["unattempted_cases"], 1)
        self.assertEqual(report["results"][0]["cleanup"], "session_id_unknown")
        self.assertIsNone(report["calls"][0]["attempted_remote_usage"])

    def test_known_start_id_survives_uncertain_completion(self):
        def callback(operation, request, budget, progress):
            if operation == "StartCodeInterpreterSession":
                progress(successful_response(operation, request))
                durable = json.loads(self.output.read_text())["calls"][-1]
                self.assertEqual(
                    durable["partial"]["response"]["sessionId"], "session-1"
                )
                raise TimeoutError("sensitive provider message")
            return successful_response(operation, request)

        report = self.run_jobs(callback=callback)
        self.assertEqual(
            [item[0] for item in self.executor.calls],
            ["StartCodeInterpreterSession", "StopCodeInterpreterSession"],
        )
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertEqual(report["outcome"], "failed")
        self.assertNotIn("sensitive", self.output.read_text())

    def test_invoke_exception_always_stops_and_keeps_unknown_usage(self):
        def callback(operation, request, budget, progress):
            if operation == "InvokeCodeInterpreter":
                raise TimeoutError("private data")
            return successful_response(operation, request)

        report = self.run_jobs(callback=callback)
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertEqual(report["results"][0]["status"], "inconclusive")
        self.assertEqual(report["calls"][1]["error_type"], "TimeoutError")
        self.assertIsNone(report["calls"][1]["attempted_remote_usage"])
        self.assertNotIn("private data", self.output.read_text())

    def test_late_error_or_duplicate_result_cannot_pass(self):
        for suffix in [{"throttlingException": {}}, "duplicate"]:
            self.output = (
                Path(self.directory.name)
                / f"events-{len(list(Path(self.directory.name).iterdir()))}.json"
            )

            def callback(operation, request, budget, progress):
                result = successful_response(operation, request)
                if operation == "InvokeCodeInterpreter":
                    events = result["response"]["events"]
                    events.append(
                        copy.deepcopy(events[0]) if suffix == "duplicate" else suffix
                    )
                return result

            report = self.run_jobs(callback=callback)
            self.assertEqual(report["outcome"], "failed")
            self.assertEqual(report["results"][0]["cleanup"], "stopped")

    def test_bad_tool_results_fail_before_evidence_parser(self):
        parsed = []

        def parser(*args):
            parsed.append(args)
            return {"status": "observed"}

        for defect in [
            "wrong-session",
            "isError",
            "missing-success",
            "nonzero-exit",
            "stderr",
        ]:
            self.output = Path(self.directory.name) / f"{defect}.json"

            def callback(operation, request, budget, progress):
                result = successful_response(operation, request)
                if operation == "InvokeCodeInterpreter":
                    response = result["response"]
                    event = response["events"][0]["result"]
                    if defect == "wrong-session":
                        response["sessionId"] = "different"
                    elif defect == "isError":
                        event["isError"] = True
                    elif defect == "missing-success":
                        event.pop("isError")
                    elif defect == "nonzero-exit":
                        event["structuredContent"]["exitCode"] = 1
                    else:
                        event["structuredContent"]["stderr"] = "failure"
                return result

            report = self.run_jobs(callback=callback, parser=parser)
            self.assertEqual(parsed, [])
            self.assertEqual(report["outcome"], "failed")
            self.assertEqual(report["results"][0]["cleanup"], "stopped")

    def test_cleanup_failure_downgrades_observation_and_stops_run(self):
        for wrong_id in [True, False]:
            self.output = Path(self.directory.name) / f"cleanup-{wrong_id}.json"

            def callback(operation, request, budget, progress):
                result = successful_response(operation, request)
                if operation == "StopCodeInterpreterSession":
                    if wrong_id:
                        result["response"]["sessionId"] = "different"
                    else:
                        return {
                            "outcome": "inconclusive",
                            "reason": "deadline",
                            "response": None,
                        }
                return result

            report = self.run_jobs([job("one"), job("two")], callback)
            self.assertEqual(report["results"][0]["status"], "inconclusive")
            self.assertEqual(report["results"][0]["cleanup"], "failed")
            self.assertEqual(report["unattempted_cases"], 1)
            self.assertEqual(report["outcome"], "failed")

    def test_parser_mismatch_is_operational_failure(self):
        for malformed in [None, {"status": "accepted"}, {"status": "inconclusive"}]:
            self.output = (
                Path(self.directory.name)
                / f"parse-{len(list(Path(self.directory.name).iterdir()))}.json"
            )
            report = self.run_jobs(parser=lambda *args: malformed)
            self.assertEqual(report["outcome"], "failed")
            self.assertEqual(report["results"][0]["cleanup"], "stopped")
            self.assertEqual(report["results"][0]["status"], "inconclusive")

    def test_work_deadline_preserves_cleanup_reserve(self):
        clock = FakeClock()

        def callback(operation, request, budget, progress):
            if operation == "StartCodeInterpreterSession":
                self.assertEqual(budget, 15)
                clock.now += 2
            elif operation == "InvokeCodeInterpreter":
                self.assertEqual(budget, 13)
                clock.now += 13
                return {
                    "outcome": "inconclusive",
                    "reason": "deadline",
                    "response": None,
                }
            else:
                self.assertEqual(budget, 5)
            return successful_response(operation, request)

        report = self.run_jobs(callback=callback, clock=clock)
        self.assertEqual([call[2] for call in self.executor.calls], [15, 13, 5])
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertEqual(report["outcome"], "failed")

    def test_no_next_case_without_full_remaining_budget(self):
        clock = FakeClock()

        def callback(operation, request, budget, progress):
            clock.now += 1
            return successful_response(operation, request)

        report = self.run_jobs(
            [job("one"), job("two")],
            callback,
            limits=experiment.Limits(run_timeout_seconds=20),
            clock=clock,
        )
        self.assertEqual(report["session_attempts"], 1)
        self.assertEqual(report["results"][1]["reason"], "admission_deadline")
        self.assertEqual(report["outcome"], "failed")

    def test_capture_failure_prevents_first_send(self):
        with patch.object(
            experiment.DurableCapture, "write", side_effect=OSError("full disk")
        ):
            with self.assertRaises(OSError):
                self.run_jobs()
        self.assertEqual(self.executor.calls, [])

    def test_utf8_capture_limit_counts_bytes(self):
        with self.assertRaises(ValueError):
            experiment._bounded_json({"text": "é" * 10}, 25)
        self.assertEqual(
            experiment._bounded_json({"text": "e\u0301"}, 100)["text"].encode(),
            "e\u0301".encode(),
        )

    def test_blocked_stream_retains_partial_and_terminates_local_wait(self):
        execute = experiment.SubprocessExecutor(worker=blocked_worker)
        observations = []
        started = time.monotonic()
        result = execute(
            "InvokeCodeInterpreter", {}, 0.8, experiment.Limits(), observations.append
        )
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result["outcome"], "inconclusive")
        self.assertEqual(result["reason"], "deadline")
        self.assertTrue(result["local_worker_stopped"])
        self.assertEqual(result["response"]["events"], [{"partial": "retained"}])
        self.assertTrue(observations)

    def test_parent_bounds_event_count(self):
        execute = experiment.SubprocessExecutor(worker=too_many_events_worker)
        result = execute(
            "InvokeCodeInterpreter",
            {},
            2,
            experiment.Limits(max_events=2),
            lambda value: None,
        )
        self.assertEqual(result["reason"], "capture_limit")
        self.assertEqual(len(result["response"]["events"]), 2)
        self.assertTrue(result["local_worker_stopped"])

    def test_partial_ipc_frame_cannot_hold_the_caller_past_deadline(self):
        execute = experiment.SubprocessExecutor(worker=partial_frame_worker)
        started = time.monotonic()
        result = execute(
            "StartCodeInterpreterSession",
            {},
            0.5,
            experiment.Limits(),
            lambda value: None,
        )
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result["reason"], "deadline")
        self.assertTrue(result["local_worker_stopped"])
        self.assertIsNone(result["response"])

    def test_failed_capture_after_start_still_stops_known_session(self):
        original_write = experiment.DurableCapture.write
        sent = []
        failed = False

        def write(capture, report):
            nonlocal failed
            if any(
                call.get("response", {}).get("sessionId") for call in report["calls"]
            ):
                failed = True
            if failed:
                raise OSError("disk unavailable")
            original_write(capture, report)

        def execute(operation, request, timeout, limits, progress):
            sent.append(operation)
            return successful_response(operation, request)

        with patch.object(experiment.DurableCapture, "write", write):
            report = experiment.run_plan(
                experiment.prepare_plan([job()]),
                self.output,
                parse_observation,
                executor=execute,
            )
        self.assertEqual(
            sent, ["StartCodeInterpreterSession", "StopCodeInterpreterSession"]
        )
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertTrue(report["capture_failed"])
        self.assertEqual(report["outcome"], "failed")
        self.assertEqual(report["results"][0]["status"], "inconclusive")

    def test_failed_partial_capture_adopts_session_before_emergency_stop(self):
        original_write = experiment.DurableCapture.write
        sent = []

        def write(capture, report):
            if any(call.get("partial") for call in report["calls"]):
                raise OSError("disk unavailable")
            original_write(capture, report)

        def execute(operation, request, timeout, limits, progress):
            sent.append(operation)
            response = successful_response(operation, request)
            if operation == "StartCodeInterpreterSession":
                progress(response)
            return response

        with patch.object(experiment.DurableCapture, "write", write):
            report = experiment.run_plan(
                experiment.prepare_plan([job()]),
                self.output,
                parse_observation,
                executor=execute,
            )
        self.assertEqual(
            sent, ["StartCodeInterpreterSession", "StopCodeInterpreterSession"]
        )
        self.assertEqual(report["results"][0]["cleanup"], "stopped")
        self.assertEqual(report["outcome"], "failed")

    def test_completed_result_uses_exact_exit_code_type_and_optional_task_status(self):
        valid = successful_response("InvokeCodeInterpreter", {"sessionId": "s"})[
            "response"
        ]
        for update in [
            {"exitCode": False},
            {"exitCode": "0"},
            {"taskStatus": "working"},
            {"taskStatus": "failed"},
            {"taskStatus": "canceled"},
            {"taskId": "t"},
            {"taskStatus": "completed", "taskId": ""},
        ]:
            response = copy.deepcopy(valid)
            response["events"][0]["result"]["structuredContent"].update(update)
            with self.subTest(update=update), self.assertRaises(ValueError):
                experiment._result_from_events(response, "s")
        valid["events"][0]["result"]["structuredContent"].update(
            taskStatus="completed", taskId="t"
        )
        self.assertEqual(experiment._result_from_events(valid, "s")["exitCode"], 0)

    def test_sdk_worker_retains_only_bounded_results_and_no_response_headers(self):
        class Connection:
            def __init__(self):
                self.messages = []

            def sendall(self, data):
                self.messages.append(json.loads(data))

            def close(self):
                pass

        class Stream(list):
            closed = False

            def close(self):
                self.closed = True

        class Client:
            closed = False

            def invoke_code_interpreter(self, **request):
                self.request = request
                return {
                    "sessionId": "s",
                    "stream": stream,
                    "ResponseMetadata": {
                        "RequestId": "request-1",
                        "HTTPHeaders": {"SECRET": "never capture"},
                    },
                }

            def start_code_interpreter_session(self, **request):
                raise AssertionError()

            def stop_code_interpreter_session(self, **request):
                raise AssertionError()

            def close(self):
                self.closed = True

        for oversized in (False, True):
            stream = Stream([{"result": {"text": "x" * (500 if oversized else 2)}}])
            client, connection = Client(), Connection()
            module = types.SimpleNamespace(client=lambda *args, **kwargs: client)
            with (
                patch.dict("sys.modules", {"boto3": module}),
                patch.object(experiment, "_client_config", return_value=None),
            ):
                experiment._sdk_worker(
                    connection,
                    "InvokeCodeInterpreter",
                    {"sessionId": "s"},
                    "us-east-1",
                    1,
                    experiment.Limits(max_capture_bytes=100),
                )
            self.assertTrue(client.closed)
            self.assertTrue(stream.closed)
            self.assertNotIn("SECRET", json.dumps(connection.messages))
            self.assertEqual(connection.messages[0]["request_id"], "request-1")
            if oversized:
                self.assertEqual(connection.messages[-1]["reason"], "capture_limit")
                self.assertFalse(
                    any(message["kind"] == "event" for message in connection.messages)
                )
            else:
                self.assertEqual(connection.messages[-1]["kind"], "complete")
                self.assertEqual(connection.messages[1]["event"], stream[0])

    def test_cli_is_dry_by_default_even_with_credential_flag(self):
        plan_path = Path(self.directory.name) / "plan.json"
        plan = experiment.prepare_plan(
            [job()], experiment.Limits(maximum_sessions=8, maximum_invokes=8)
        )
        plan_path.write_text(json.dumps(plan))
        stream = io.StringIO()
        with redirect_stdout(stream), patch.object(experiment, "run_plan") as run:
            self.assertEqual(
                experiment.main(["--plan", str(plan_path), "--aws-cli-credentials"]), 0
            )
            run.assert_not_called()
        summary = json.loads(stream.getvalue())
        self.assertEqual(summary["mode"], "dry_run")
        self.assertEqual(
            summary["plan_sha256"], experiment.digest(experiment._json(plan))
        )
        self.assertEqual(summary["limits"]["maximum_sessions"], 8)
        self.assertFalse(self.output.exists())

    def test_cli_execute_requires_matching_hash_before_any_run(self):
        plan_path = Path(self.directory.name) / "plan.json"
        plan_path.write_text(json.dumps(experiment.prepare_plan([job()])))
        with (
            redirect_stderr(io.StringIO()),
            patch.object(experiment, "run_plan") as run,
        ):
            with self.assertRaises(SystemExit) as raised:
                experiment.main(
                    [
                        "--plan",
                        str(plan_path),
                        "--execute",
                        "--output",
                        str(self.output),
                        "--approved-plan-sha256",
                        "wrong",
                    ]
                )
            self.assertEqual(raised.exception.code, 2)
            run.assert_not_called()

    def test_undocumented_result_alias_is_inconclusive_with_raw_event_retained(self):
        def callback(operation, request, budget, progress):
            result = successful_response(operation, request)
            if operation == "InvokeCodeInterpreter":
                structured = result["response"]["events"][0]["result"][
                    "structuredContent"
                ]
                structured["exit_code"] = structured.pop("exitCode")
            return result

        report = self.run_jobs(callback=callback)
        self.assertEqual(report["outcome"], "failed")
        raw = report["calls"][1]["response"]["events"][0]["result"]["structuredContent"]
        self.assertEqual(raw["exit_code"], 0)
        self.assertNotIn("exitCode", raw)

    def test_cli_matching_hash_dispatches_once_and_returns_operational_failure(self):
        plan = experiment.prepare_plan([job()])
        plan_path = Path(self.directory.name) / "plan.json"
        plan_path.write_text(json.dumps(plan))
        fake_module = types.SimpleNamespace(
            parse_execution_observation=parse_observation
        )
        with (
            patch.dict("sys.modules", {"execution_evidence": fake_module}),
            redirect_stdout(io.StringIO()),
            patch.object(
                experiment,
                "run_plan",
                return_value={
                    "outcome": "failed",
                    "operational_failure": True,
                    "session_attempts": 1,
                    "invoke_attempts": 0,
                },
            ) as run,
        ):
            result = experiment.main(
                [
                    "--plan",
                    str(plan_path),
                    "--execute",
                    "--output",
                    str(self.output),
                    "--approved-plan-sha256",
                    experiment.digest(experiment._json(plan)),
                ]
            )
        self.assertEqual(result, 1)
        run.assert_called_once_with(plan, self.output, parse_observation)

    def test_actual_harness_parser_accepts_compiler_observation_and_rejects_mismatch(
        self,
    ):
        from execution_evidence import (
            PROTOCOL,
            prepare_execution_job,
            parse_execution_observation,
        )

        prepared = prepare_execution_job("syntax", "def f(): if True: return 1")
        for wrong_hash in (False, True):
            self.output = Path(self.directory.name) / f"artifact-{wrong_hash}.json"
            record = {
                key: copy.deepcopy(prepared[key])
                for key in (
                    "job_id",
                    "artifact_sha256",
                    "input_sha256",
                    "mode",
                    "limits",
                )
            }
            record.update(
                protocol=PROTOCOL,
                status="observed",
                reason=None,
                runtime={"version": "3.12.0", "implementation": "CPython"},
                compile={"valid": False, "exception": "SyntaxError"},
                child=None,
                timed_out=False,
                transport_truncated=False,
                child_reaped=True,
            )
            if wrong_hash:
                record["artifact_sha256"] = "different"

            def callback(operation, request, budget, progress):
                result = successful_response(operation, request)
                if operation == "InvokeCodeInterpreter":
                    result["response"]["events"][0]["result"]["structuredContent"][
                        "stdout"
                    ] = json.dumps(record)
                return result

            report = self.run_jobs(
                [prepared], callback, parser=parse_execution_observation
            )
            self.assertEqual(report["outcome"], "failed" if wrong_hash else "completed")
            self.assertEqual(
                report["results"][0]["status"],
                "inconclusive" if wrong_hash else "observed",
            )
            self.assertEqual(report["results"][0]["cleanup"], "stopped")

    def test_sdk_provider_error_code_is_captured_without_message_or_headers(self):
        class Denied(Exception):
            response = {
                "Error": {
                    "Code": "AccessDeniedException",
                    "Message": "private context",
                },
                "ResponseMetadata": {"HTTPHeaders": {"secret": "hidden"}},
            }

        def denied(**request):
            raise Denied("private context")

        client = types.SimpleNamespace(
            start_code_interpreter_session=denied,
            invoke_code_interpreter=denied,
            stop_code_interpreter_session=denied,
            close=lambda: None,
        )
        messages = []
        connection = types.SimpleNamespace(
            sendall=lambda data: messages.append(json.loads(data)), close=lambda: None
        )
        with (
            patch.dict(
                "sys.modules",
                {"boto3": types.SimpleNamespace(client=lambda *args, **kwargs: client)},
            ),
            patch.object(experiment, "_client_config", return_value=None),
        ):
            experiment._sdk_worker(
                connection,
                "StartCodeInterpreterSession",
                {},
                "us-east-1",
                1,
                experiment.Limits(),
            )
        self.assertEqual(messages[-1]["provider_error_code"], "AccessDeniedException")
        self.assertNotIn("private", json.dumps(messages))
        self.assertNotIn("hidden", json.dumps(messages))

    def test_sdk_disables_hidden_retries(self):
        try:
            config = experiment._client_config(10)
        except ImportError:
            self.skipTest("Botocore is optional for offline lifecycle tests")
        self.assertEqual(config.retries["total_max_attempts"], 1)
        self.assertLessEqual(config.connect_timeout + config.read_timeout, 10)


if __name__ == "__main__":
    unittest.main()
