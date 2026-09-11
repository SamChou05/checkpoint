#!/usr/bin/env python3
"""Offline delivery of captured operations through the real prepare/claim code.

python evals/checkpoint_delivery_check.py --capture capture.json --output delivery.json
The output is also an input fixture for QuestionDeliveryCaptureTests.swift.
No provider, cloud client, production storage, or per-item admission is used.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
from unittest.mock import patch

SERVICE = Path(__file__).resolve().parents[1]
ROOT = SERVICE.parents[1]
sys.path[:0] = [str(SERVICE), str(SERVICE / "tests")]

import question_bank  # noqa: E402
import question_bank_worker  # noqa: E402
from question_bank_test_support import (  # noqa: E402
    SECRET, ClaimDynamo, FakeQueue, _claim_records, _event,
)
from verification_policy import (  # noqa: E402
    COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION,
    MAX_SUPPORTED_VERIFICATION_POLICY_REVISION,
    VERIFICATION_POLICY_REVISION,
)

SOURCE_FILES = sorted({
    str(path.relative_to(ROOT))
    for path in [
        *SERVICE.glob("*.py"),
        *(ROOT / "Checkpoint").rglob("*.swift"),
        *(ROOT / "CheckpointTests/TestSupport").rglob("*.swift"),
        Path(__file__).resolve(),
        SERVICE / "tests/question_bank_test_support.py",
        ROOT / "CheckpointTests/QuestionDeliveryCaptureTests.swift",
    ]
})

LOCAL_SETTINGS = {
    "ALLOW_UNAUTHENTICATED_BACKEND": "true",
    "QUESTION_BANK_TABLE_NAME": "question-banks",
    "QUESTION_BANK_QUEUE_URL": "https://sqs.example/question-banks",
    "QUOTA_HASH_SECRET": SECRET,
}


def _without_remote(question):
    return {key: value for key, value in question.items() if key != "remoteID"}


def check_operation(operation, request, index):
    """Keep every returned item, including any lost at a later boundary."""
    questions = copy.deepcopy(operation["questions"])
    if not isinstance(questions, list) or not all(isinstance(q, dict) for q in questions):
        raise ValueError("Each operation must contain a questions array of objects.")
    contract = request.get("feedbackContract")
    if contract is not None and contract != "authored_complete":
        raise ValueError("Unsupported delivery feedback contract.")
    for question in questions:
        revision = question.get("verificationPolicyRevision")
        if revision is not None and (type(revision) is not int or not 0 <= revision <= MAX_SUPPORTED_VERIFICATION_POLICY_REVISION):
            raise ValueError("Unsupported delivery verification policy revision.")
    minimum_policy = (
        COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION
        if contract == "authored_complete" else VERIFICATION_POLICY_REVISION
    )
    result = {
        "operation_index": index,
        "case_id": operation.get("case_id"),
        "request": copy.deepcopy(request),
        "runtime_questions": questions,
        "runtime_returned_count": len(questions),
        "content_observation": "returned_questions" if questions else "no_runtime_questions",
        "client_retained_count": None,
        "client_check": "pending XCTest; backend delivery is not client admission",
    }
    with patch.dict(os.environ, LOCAL_SETTINGS), patch.object(
        socket.socket, "connect", side_effect=AssertionError("Delivery check forbids network")
    ):
        bank_id, meta, pointer, template = _claim_records(low=0)
        if contract is not None:
            meta["feedbackContract"] = {"S": contract}
        original_bank_contract = copy.deepcopy(meta.get("feedbackContract"))
        result["bank_feedback_contract"] = contract
        prepared = question_bank_worker._prepare_questions(bank_id, questions, [])
        result["prepared_questions"] = prepared
        result["prepared_count"] = len(prepared)
        # A fresh, completed finite test bank holds only this returned operation.
        # This isolates claim delivery; it does not simulate target-five refill.
        meta["readyCount"] = {"N": str(len(prepared))}
        meta["desiredCount"] = meta["generatedCount"] = {"N": str(max(1, len(prepared)))}
        meta["initialFillComplete"] = {"BOOL": True}
        rows = []
        for question in prepared:
            row = copy.deepcopy(template)
            row["sk"] = {"S": "QUESTION#" + question["remoteID"]}
            row["remoteID"] = {"S": question["remoteID"]}
            row["questionJSON"] = {"S": json.dumps(question, ensure_ascii=False)}
            rows.append(row)
        dynamo, queue = ClaimDynamo(meta, pointer, rows), FakeQueue()
        claim = {
            "bankID": bank_id, "claimID": f"delivery-operation-{index}",
            "limit": min(question_bank.MAX_CLAIM_COUNT, max(1, len(questions))),
            "minimumVerificationVersion": 1,
            "minimumVerificationPolicyRevision": minimum_policy,
        }
        result["claim_request"] = claim
        first = second = None
        transactions_after_first = None
        try:
            first = question_bank.claim_questions(
                claim, _event(), dynamodb_client=dynamo, sqs_client=queue,
            )
            transactions_after_first = len(dynamo.transactions)
            second = question_bank.claim_questions(
                claim, _event(), dynamodb_client=dynamo, sqs_client=queue,
            )
        except Exception as error:
            result["delivery_error"] = {"type": type(error).__name__, "message": str(error)}
        result.update(
            claim_response=first, repeat_claim_response=second,
            bank_claimable_count=len(first["questions"]) if first else 0,
            transaction_count=len(dynamo.transactions), queued_message_count=len(queue.messages),
        )
        claimed = first["questions"] if first else []
        result["checks"] = {
            "prepare_preserves_all_returned_items": len(prepared) == len(questions),
            "prepared_content_exact_except_assigned_remote_id": all(
                any(_without_remote(q) == _without_remote(original) for original in questions)
                for q in prepared
            ),
            "claim_content_exact": first is not None and claimed == prepared,
            "repeat_claim_exact": first is not None and second == first,
            "repeat_claim_adds_no_transaction": transactions_after_first is not None
                and len(dynamo.transactions) == transactions_after_first,
            "single_atomic_claim_transaction": len(dynamo.transactions) == 1,
            "no_queue_messages": not queue.messages,
            "input_unchanged": questions == operation["questions"],
            "bank_feedback_contract_unchanged": meta.get("feedbackContract") == original_bank_contract,
        }
        result["passed"] = all(result["checks"].values())
    return result


def check_capture(capture):
    operations = capture.get("operations")
    if not isinstance(operations, list) or not operations:
        raise ValueError("Capture must contain a nonempty operations array.")
    plan = capture.get("plan", {})
    planned = plan.get("operations", [])
    originals = {case["case_id"]: case["payload"]
                 for case in plan.get("origin", {}).get("cases", [])}
    results = []
    for index, operation in enumerate(operations):
        job = planned[index] if index < len(planned) else operation
        request = copy.deepcopy(originals.get(operation.get("case_id"), job.get("request")))
        if not isinstance(request, dict) or not isinstance(request.get("goal"), dict):
            raise ValueError(f"Operation {index} lacks its original goal/request context.")
        if request.get("feedbackContract") != job.get("request", request).get("feedbackContract"):
            raise ValueError(f"Operation {index} changed its original feedback contract.")
        for key in ("targetCount", "minimumDifficulty"):
            request[key] = job.get("request", request).get(key, request.get(key))
            if not isinstance(request[key], int):
                raise ValueError(f"Operation {index} lacks {key}.")
        results.append(check_operation(operation, request, index))
    return {
        "schema_version": 1,
        "source_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True,
        ).strip(),
        "scope": "Offline preparation and atomic claim/replay of each complete returned batch. "
                 "Each operation has its own empty-history, completed finite bank with only its "
                 "prepared questions; bank target equals that inventory (one for empty inventory). "
                 "No refill, provider, cloud, UI rendering, or semantic quality claim. XCTest uses "
                 "the original case goal/sources, requested target/difficulty, and fresh local history.",
        "source_sha256": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                          for path in SOURCE_FILES},
        "operations": results,
        "runtime_returned_count": sum(r["runtime_returned_count"] for r in results),
        "bank_claimable_count": sum(r["bank_claimable_count"] for r in results),
        "client_retained_count": None,
        "passed": all(r["passed"] for r in results),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw = args.capture.read_bytes()
    report = check_capture(json.loads(raw))
    report["capture_sha256"] = hashlib.sha256(raw).hexdigest()
    report["capture_path"] = str(args.capture.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "passed": report["passed"],
                      "runtime_returned_count": report["runtime_returned_count"],
                      "bank_claimable_count": report["bank_claimable_count"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
