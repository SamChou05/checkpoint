#!/usr/bin/env python3
"""Passive, source-bound offline attribution of actual runtime replay decisions.

Run with the historical Python/SDK environment and an explicit frozen service
directory. No content is repaired, independently admitted, or scored for truth.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import socket
import sys
from contextlib import ExitStack
from unittest.mock import patch


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def validate_source(capture, source):
    source = Path(source).resolve()
    for name, expected in capture["plan"]["source_sha256"].items():
        path = (source / name).resolve()
        if not path.is_relative_to(source) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Frozen source mismatch: {name}")
    return source


def validate_imports(capture, source):
    for relative in capture["plan"]["source_sha256"]:
        if not relative.endswith(".py"):
            continue
        name = relative[:-3].replace("/", ".")
        module = sys.modules.get(name)
        path = getattr(module, "__file__", None)
        if module is not None and (path is None or Path(path).resolve() != (source / relative).resolve()):
            raise ValueError("Historical replay requires a fresh interpreter for the selected source.")


def load_runtime(source):
    # Selection and cached-module validation precede production imports.
    sys.path.insert(0, str(source))
    return importlib.import_module("evals.checkpoint_runtime_qualification")


class StageObserver:
    """Read only exact code-object events; retain references to prevent ID reuse."""

    def __init__(self, runtime, capture, capture_sha256):
        self.runtime, self.capture, self.capture_sha256 = runtime, capture, capture_sha256
        generation = runtime.generation
        quality = importlib.import_module("question_quality")
        verification = importlib.import_module("question_verification")
        self.codes = {
            "execute": runtime._execute.__code__, "call": runtime._RuntimeClient.converse.__code__,
            "payload": generation._generate_provider_payload.__code__,
            "sanitize": quality._sanitize_questions.__code__,
            "verify": verification.verify_questions.__code__,
            "quality": quality.record_quality.__code__,
            "solver": verification.complete_solution_rejection_reason.__code__,
            "freeze": verification.freeze_authored_question.__code__,
        }
        self.executing = False
        self.last_call = None
        self.batch = self.verification = None
        self.objects, self.batches, self.verifications, self.payloads = {}, [], [], []
        self.payload_frames = {}
        self.execution_frame = None

    def bind(self, obj, identity):
        old = self.objects.get(id(obj))
        if old is not None and (old[0] is not obj or old[1] != identity):
            raise ValueError("Ambiguous occurrence identity.")
        self.objects[id(obj)] = (obj, identity)

    def identity(self, obj):
        entry = self.objects.get(id(obj))
        if entry is None or entry[0] is not obj:
            raise ValueError("Question occurrence has no observed predecessor.")
        return entry[1]

    def occurrence(self, operation, call, ordinal):
        return f"{self.capture_sha256}:{operation}:{call}:{ordinal}"

    def __call__(self, frame, event, arg):
        code, local = frame.f_code, frame.f_locals
        if code is self.codes["execute"]:
            if event == "call":
                self.executing = True
                self.execution_frame = frame
            elif event == "return":
                self.executing = False
                self.execution_frame = None
            return
        if not self.executing:
            return
        if code is self.codes["call"] and event == "call":
            client = local["self"]
            self.last_call = len(client.report["calls"])
            saved = self.capture["calls"][self.last_call]
            if self.verification is not None and saved["role"] in {"solver", "reviewer", "teaching_auditor"}:
                active = self.verification[0].f_locals
                tag = "question_solution_json" if saved["role"] == "solver" else "question_review_json"
                text = local["request"]["messages"][0]["content"][0]["text"]
                data = json.loads(text.split(f"<{tag}>\n", 1)[1].split(f"\n</{tag}>", 1)[0])
                questions = active["questions"]
                if len(data["items"]) != len(questions):
                    raise ValueError("Provider batch and actual verifier batch differ.")
                links = [{"index": item["index"], "occurrence": self.identity(q)}
                         for item, q in zip(data["items"], questions, strict=True)]
                if [link["index"] for link in links] != list(range(len(links))):
                    raise ValueError("Unexpected provider index association.")
                self.verification[1]["provider_batches"].append({
                    "call_index": self.last_call, "role": saved["role"],
                    "payload": copy.deepcopy(data), "links": links,
                })
        elif code is self.codes["payload"]:
            calls = self.execution_frame.f_locals["report"]["calls"]
            if event == "call":
                self.payload_frames[id(frame)] = len(calls)
            elif event == "return":
                start = self.payload_frames.pop(id(frame))
                indexes = list(range(start, len(calls)))
                if any(calls[i]["role"] not in {"author", "author_json_repair"} for i in indexes):
                    raise ValueError("Unknown author payload call lineage.")
                self.payloads.append({"call_index": indexes[-1] if indexes else None,
                                      "call_indexes": indexes,
                                      "operation_index": self.execution_frame.f_locals["index"],
                                      "request": copy.deepcopy(local["request"]),
                                      "parsed_payload": copy.deepcopy(arg),
                                      "return_state": "parsed" if isinstance(arg, dict) else "unavailable"})
        elif code is self.codes["sanitize"]:
            if event == "call":
                call = self.capture["calls"][self.last_call]
                if call["role"] not in {"author", "author_json_repair"}:
                    raise ValueError("Sanitizer lacks an author-response predecessor.")
                record = {"operation_index": call["operation_index"], "call_index": self.last_call,
                          "request": copy.deepcopy(local["request"]),
                          "raw_questions": copy.deepcopy(local["raw_questions"]), "events": []}
                self.batches.append(record)
                self.batch = (frame, record)
            elif event == "return":
                self.batch[1]["return_state"] = "returned" if isinstance(arg, list) else "unavailable"
                self.batch[1]["admitted"] = ([{"occurrence": self.identity(q), "question": copy.deepcopy(q)} for q in arg]
                                             if isinstance(arg, list) else None)
                self.batch = None
        elif code is self.codes["verify"]:
            if event == "call":
                operation = self.execution_frame.f_locals["index"]
                for index, q in enumerate(local["questions"]):
                    if id(q) not in self.objects:
                        if self.capture["plan"]["operations"][operation]["kind"] != "fixed":
                            raise ValueError("Verification candidate bypassed observed batch admission.")
                        self.bind(q, self.occurrence(operation, "fixed", index))
                record = {"operation_index": operation,
                          "candidates": [{"occurrence": self.identity(q), "question": copy.deepcopy(q)}
                                         for q in local["questions"]], "provider_batches": [],
                          "solver_decisions": [], "events": []}
                self.verifications.append(record)
                self.verification = (frame, record)
            elif event == "return":
                self.verification[1]["return_state"] = "returned" if isinstance(arg, list) else "unavailable"
                self.verification[1]["returned"] = ([{"occurrence": self.identity(q), "question": copy.deepcopy(q)} for q in arg]
                                                     if isinstance(arg, list) else None)
                self.verification = None
        elif code is self.codes["freeze"] and event == "return" and arg is not None:
            self.bind(arg, self.identity(local["question"]))
        elif code is self.codes["solver"] and event == "return":
            self.verification[1]["solver_decisions"].append({
                "occurrence": self.identity(local["question"]),
                "record": copy.deepcopy(local["record"]), "rejection_reason": arg,
            })
        elif code is self.codes["quality"] and event == "call":
            count = local.get("count", 1)
            if count <= 0:
                return
            parent, reason = frame.f_back, local["reason"]
            state = parent.f_locals
            entry = {"reason": reason, "count": count, "scope": "batch"}
            if parent.f_code is self.codes["sanitize"]:
                record = self.batch[1]
                if "candidate_index" in state and reason != "surplus":
                    index = state["candidate_index"]
                    identity = self.occurrence(record["operation_index"], record["call_index"], index)
                    entry.update(scope="candidate", raw_ordinal=index, occurrence=identity)
                    if count != 1:
                        raise ValueError("Unexpected aggregate candidate diagnostic.")
                    if reason == "accepted":
                        output = state["sanitized"]
                        self.bind(output[-1], identity)
                        entry["admitted_position"] = len(output) - 1
                record["events"].append(entry)
            elif parent.f_code is self.codes["verify"]:
                if "accepted" in state:
                    entry.update(scope="candidate", occurrence=self.identity(state["question"]),
                                 reviewer_index=state["index"])
                    if reason == "accepted":
                        self.bind(state["verified_question"], entry["occurrence"])
                self.verification[1]["events"].append(entry)

    def result(self, replay):
        operations = []
        for index, op in enumerate(replay["operations"]):
            operations.append({"operation_index": index,
                               **{key: copy.deepcopy(op[key]) for key in
                                  ("status", "runtime_error_type", "result_category", "metrics") if key in op},
                               "returned": [
                {"occurrence": self.identity(q), "question": copy.deepcopy(q)} for q in op["questions"]
            ]})
        return {"schema_version": 1, "scope": "Passive exact runtime replay; decisions are not factual scores.",
                "capture_canonical_sha256": self.capture_sha256,
                "capture_status": replay["status"],
                "plan_sha256": replay["plan_sha256"], "source_revision": replay["plan"]["source_revision"],
                "source_sha256": replay["plan"]["source_sha256"], "dependencies": replay["plan"]["dependencies"],
                "exact_replay": True, "call_count": len(replay["calls"]),
                "raw_responses": [{"call_index": i, "operation_index": c["operation_index"], "role": c["role"],
                                   "request_sha256": c["request_sha256"],
                                   "response": copy.deepcopy((c.get("observation") or {}).get("response"))}
                                  for i, c in enumerate(replay["calls"])],
                "author_payloads": self.payloads, "sanitizer_batches": self.batches,
                "verifications": self.verifications, "operations": operations}


def trace_capture(capture, source, *, runtime=None):
    source = validate_source(capture, source)
    validate_imports(capture, source)
    runtime = runtime or load_runtime(source)
    validate_imports(capture, source)
    if Path(runtime.__file__).resolve().parent.parent != source:
        raise ValueError("Runtime was imported from a different source directory.")
    observer = StageObserver(runtime, capture, digest(capture))
    previous = sys.getprofile()
    with ExitStack() as stack:
        import boto3
        for target, method in ((socket.socket, "connect"), (socket.socket, "connect_ex"),
                               (boto3, "client"), (boto3.session.Session, "client"),
                               (runtime.shared, "new_client"), (runtime.caller, "observe_request")):
            stack.enter_context(patch.object(target, method, side_effect=AssertionError("Offline replay forbids dispatch")))
        try:
            sys.setprofile(observer)
            replay = runtime.replay_capture(capture)
        finally:
            sys.setprofile(previous)
    if replay != capture:
        raise ValueError("Exact full capture replay required.")
    return observer.result(replay)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw = args.capture.read_bytes()
    report = trace_capture(json.loads(raw), args.source_dir)
    report["capture_byte_sha256"] = hashlib.sha256(raw).hexdigest()
    report["observer_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    with args.output.open("x") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"exact_replay": True, "call_count": report["call_count"],
                      "returned": sum(len(op["returned"]) for op in report["operations"])}))


if __name__ == "__main__":
    main()
