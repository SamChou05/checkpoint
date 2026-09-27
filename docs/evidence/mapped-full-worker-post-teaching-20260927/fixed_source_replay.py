"""Replay the failed author payload through the exact patched local source."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
SOURCE_COMMIT = "c12d554"
PLAN_SHA256 = "36f7a318314a7abccd822f23bfe3d06c729cee656e97218d1585f35c97316775"
CAPTURE_SHA256 = "5d4212bbc7dbc852645c99d7f737311957250239dded3aee9f785ae4a74405e3"


def replay() -> dict:
    plan_path, capture_path = HERE / "plan.json", HERE / "capture.json"
    if (hashlib.sha256(plan_path.read_bytes()).hexdigest() != PLAN_SHA256
            or hashlib.sha256(capture_path.read_bytes()).hexdigest() != CAPTURE_SHA256):
        raise ValueError("Frozen plan or author capture changed")
    if subprocess.run(
        ["git", "diff", "--quiet", SOURCE_COMMIT, "--", "backend/bedrock-question-service"],
        cwd=ROOT, check=False,
    ).returncode != 0:
        raise ValueError("Backend source differs from the exact patched revision")
    sys.path.insert(0, str(SERVICE))
    from agreement_task_constructor import prepare_mapped_agreement_rows
    from native_output_contracts import AuthorSlotContract, adapt_native_response
    from question_quality import _sanitize_questions

    plan, capture = json.loads(plan_path.read_text()), json.loads(capture_path.read_text())
    assignment = plan["mapped_assignment"]
    contract = AuthorSlotContract(
        5, "constructed_quantitative",
        tuple(tuple(row) for row in assignment["assignments"]),
        assignment["quantitative_skill_id"], assignment["quantitative_difficulty"],
        True, True,
    )
    raw = capture["calls"][0]["raw_author_object"]
    adapted = json.loads(adapt_native_response(json.dumps(raw), contract))
    rows, numeric, english, failures = prepare_mapped_agreement_rows(adapted, contract)
    metrics: dict = {}
    accepted = _sanitize_questions(
        rows, plan["jobs"][0]["request"], metrics,
        preserve_authored_explanation=True, compiled_candidates=numeric,
        compiled_output={}, agreement_candidates=english, agreement_output={},
    )
    counts = (len(raw["questions"]), len(adapted["questions"]), len(rows),
              len(numeric), len(english), len(failures), len(accepted))
    if counts != (5, 5, 5, 3, 2, 0, 5) or metrics["QuestionQuality"]["sanitize"] != {"accepted": 5}:
        raise ValueError(f"Patched replay failed its five-slot gate: {counts}")
    return {
        "source_commit": SOURCE_COMMIT,
        "plan_sha256": PLAN_SHA256,
        "capture_sha256": CAPTURE_SHA256,
        "captured_bedrock_calls": 1,
        "captured_original_slots_returned": 0,
        "captured_slot4_scene": raw["questions"]["4"]["scene"],
        "native_slots": 5,
        "prepared_original_slots": 5,
        "compiled_numeric": 3,
        "compiled_english": 2,
        "compiler_failures": 0,
        "sanitized_candidates": 5,
        "downstream_model_review_exercised": False,
    }


if __name__ == "__main__":
    print(json.dumps(replay(), indent=2, sort_keys=True))
