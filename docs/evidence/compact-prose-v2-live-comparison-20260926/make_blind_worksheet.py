"""Project a finalized paired capture into a separate keyless reviewer directory."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))
import question_quality as quality  # noqa: E402
from quantitative_authoring import prepare_mixed_rows  # noqa: E402
import author_pair_probe as probe  # noqa: E402


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write_new(path, value, mode):
    data = (json.dumps(value, ensure_ascii=False, allow_nan=False, indent=2) + "\n").encode()
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    return sha(data)


def project(expected_capture_sha, expected_plan_sha, reviewer_dir):
    capture_path, plan_path = HERE / "capture.json", HERE / "plan.json"
    if sha(capture_path.read_bytes()) != expected_capture_sha or sha(plan_path.read_bytes()) != expected_plan_sha:
        raise ValueError("Capture or plan hash mismatch.")
    capture, plan = json.loads(capture_path.read_text()), json.loads(plan_path.read_text())
    if (capture.get("state") != "complete" or capture.get("plan_sha256") != expected_plan_sha
            or len(capture.get("calls", [])) != 2 or set(capture.get("slots", {})) != {"v1", "v2"}
            or any(capture["slots"][arm] != "native_adapted" for arm in ("v1", "v2"))):
        raise ValueError("Paired capture is incomplete.")
    if [call.get("arm") for call in capture["calls"]] != plan["arm_order"]:
        raise ValueError("Captured arm order changed.")
    if reviewer_dir.exists():
        raise ValueError("Reviewer directory already exists.")
    private_path = HERE / "blind-private-map.json"
    if private_path.exists():
        raise ValueError("Private mapping already exists.")
    original_request = probe.baseline()[0]
    if probe.sha(probe.canonical(original_request)) != plan["request_sha256"]:
        raise ValueError("Frozen original request changed.")
    worksheet, private = [], {}
    diagnostics = {}
    for call in capture["calls"]:
        arm = call["arm"]
        payload = call["adapted"]
        if type(payload) is not dict or type(payload.get("questions")) is not list or len(payload["questions"]) != 5:
            raise ValueError("Adapted author slots changed.")
        prepared, compiled, failures = prepare_mixed_rows(payload, construct_choices=True)
        if len(prepared) != 5:
            raise ValueError("Compiler lost an original slot.")
        metrics, compiled_output = {}, {}
        events = []
        original_record = quality.record_quality

        def observe(metric, stage, reason, count=1):
            original_record(metric, stage, reason, count)
            if stage == "sanitize" and reason != "surplus":
                if count != 1:
                    raise ValueError("Unexpected per-row sanitizer count.")
                events.append(reason)

        order = quality._compiled_first_within_assignment(prepared, original_request, compiled)
        with patch.object(quality, "record_quality", observe):
            accepted = quality._sanitize_questions(
                prepared, original_request, metrics,
                preserve_authored_explanation=True, compiled_candidates=compiled,
                compiled_output=compiled_output, prefer_compiled_within_assignment=True)
        if len(events) != 5 or len(order) != 5:
            raise ValueError("Sanitizer did not classify every original slot.")
        source_reasons = dict(zip(order, events, strict=True))
        accepted_by_source = {}
        accepted_iter = iter(accepted)
        for source_ordinal in order:
            if source_reasons[source_ordinal] == "accepted":
                accepted_by_source[source_ordinal] = next(accepted_iter)
        if next(accepted_iter, None) is not None:
            raise ValueError("Accepted sanitizer rows do not match events.")
        diagnostics[arm] = {"compiler_rejections": failures,
                            "sanitizer_reasons_by_original_slot":
                            [source_reasons[index] for index in range(5)],
                            "sanitizer_counts": metrics.get("QuestionQuality", {}).get("sanitize", {})}
        for source_ordinal in range(5):
            opaque = secrets.token_hex(12)
            while opaque in private:
                opaque = secrets.token_hex(12)
            item = {"id": opaque}
            reason = source_reasons[source_ordinal]
            if reason == "accepted":
                question = accepted_by_source[source_ordinal]
                choices = question["choices"]
                if not (type(question["prompt"]) is str and type(choices) is list
                        and len(choices) == 4 and all(type(choice) is str and choice for choice in choices)
                        and question["expectedAnswer"] in choices):
                    raise ValueError("Sanitized row cannot be projected.")
                indices = list(range(4))
                secrets.SystemRandom().shuffle(indices)
                item.update(stem=question["prompt"],
                            choices={label: choices[index]
                                     for label, index in zip("ABCD", indices, strict=True)})
                key = next(label for label in "ABCD" if item["choices"][label] == question["expectedAnswer"])
                private[opaque] = {"arm": arm, "original_slot": source_ordinal,
                                   "status": reason, "display_to_source_index": indices,
                                   "correct_display_label": key}
            else:
                item["unavailable"] = True
                private[opaque] = {"arm": arm, "original_slot": source_ordinal, "status": reason}
            worksheet.append(item)
    secrets.SystemRandom().shuffle(worksheet)
    if sha(capture_path.read_bytes()) != expected_capture_sha or sha(plan_path.read_bytes()) != expected_plan_sha:
        raise ValueError("Capture or plan changed during projection.")
    reviewer_dir.mkdir(parents=True, exist_ok=False)
    worksheet_path = reviewer_dir / "worksheet.json"
    rubric_path = reviewer_dir / "RUBRIC.md"
    worksheet_sha = write_new(worksheet_path, {"version": 1, "requested_items": 10,
                                               "items": worksheet}, 0o644)
    rubric = """# Blind multiple-choice audit

This worksheet contains two unlabeled batches of five attempted items. IDs are
random; order and displayed choices are independently shuffled. No keys,
explanations, model arms, or original slot positions are supplied. Do not inspect
the trial branch, raw capture, plan, or private map until your review is locked.

For each readable item, choose the single best display letter from A-D or mark
ambiguous/unsupported. Judge whether the stem supplies all necessary facts and
whether all six unordered choice pairs differ in meaning. Note any near-duplicate
choices, factual or grammatical uncertainty, and suspected repeated mechanisms.
For unavailable items, record unavailable. Do not infer a key from answer style.
Commit your independent review before asking for the private mapping or teaching.
"""
    with rubric_path.open("x") as stream:
        stream.write(rubric)
        stream.flush()
        os.fsync(stream.fileno())
    rubric_sha = sha(rubric_path.read_bytes())
    private_sha = write_new(private_path, {"version": 1,
        "capture_sha256": expected_capture_sha, "plan_sha256": expected_plan_sha,
        "worksheet_sha256": worksheet_sha, "mapping": private,
        "diagnostics": diagnostics}, 0o600)
    return {"worksheet": str(worksheet_path), "worksheet_sha256": worksheet_sha,
            "rubric": str(rubric_path), "rubric_sha256": rubric_sha,
            "private_map": str(private_path), "private_map_sha256": private_sha,
            "requested_items": len(worksheet),
            "readable_items": sum("stem" in item for item in worksheet),
            "unavailable_items": sum("unavailable" in item for item in worksheet)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-sha256", required=True)
    parser.add_argument("--plan-sha256", required=True)
    parser.add_argument("--reviewer-dir", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(project(args.capture_sha256, args.plan_sha256, args.reviewer_dir), indent=2))
