"""One-shot Bedrock replay of Trial 04's second reviewer with the new diversity instruction."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import time

from botocore.config import Config

from bounded_bedrock_capture import credential_session, safe_error, safe_response


# Frozen experiment text. The unsuccessful instruction was removed from the
# worker after this diagnostic; keep the probe independently reproducible.
GENERIC_RESERVE_DIVERSITY_AUDIT = """

GENERIC RESERVE BATCH DIVERSITY AUDIT: Compare every supplied item with each
other supplied item and with every existingQuestions descriptor. A later item
is a material repeat when it asks for the same central learner decision or
calculation AND uses the same answer format, even when the objects, wording,
numbers, story, or number of arithmetic steps differ. Set
issueFlags.novelty=true and valid=false on the later supplied item (or on the
supplied item when its counterpart is in existingQuestions). Do not reject
different operations or response formats merely because they share a topic.
This batch-diversity rule is stricter than the general exact/cosmetic-repeat
rule above; use it for this reserve pass.
"""


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / "backend/bedrock-question-service/question_generation.py"
BASELINE = ROOT / "docs/evidence/generic-reserve-seven-probe-v4-20260927/capture.json"
PLAN = HERE / "plan.json"
RESERVATION = HERE / "reservation.json"
CAPTURE = HERE / "capture.json"
BASELINE_SHA256 = "da76d3c3a1dcfb9faebbc4da9345f2b73188c121ca46e2697233d29f948b0e8f"
EXPECTED_ACCOUNT = "239342516379"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    if PLAN.exists() or RESERVATION.exists() or CAPTURE.exists():
        raise FileExistsError("Probe is already prepared or used.")
    if digest(BASELINE) != BASELINE_SHA256:
        raise ValueError("Baseline capture differs from the pinned result.")
    baseline = json.loads(BASELINE.read_text())
    call = baseline["calls"][4]
    if (call["stage"] != "authored_solution_reviewer_v3_n3"
            or call["response"]["stopReason"] != "end_turn"
            or len(call["request"]["system"]) != 1):
        raise ValueError("Unexpected original reviewer request.")
    request = copy.deepcopy(call["request"])
    request["system"][0]["text"] += GENERIC_RESERVE_DIVERSITY_AUDIT
    if request["system"][0]["text"].count("GENERIC RESERVE BATCH DIVERSITY AUDIT") != 1:
        raise ValueError("Missing or repeated diversity audit.")
    plan = {
        "probe_id": "generic-reserve-diversity-review-replay-20260927-01",
        "baseline_capture_sha256": BASELINE_SHA256,
        "source_commit": "8805f44",
        "source_sha256": digest(SOURCE),
        "account": EXPECTED_ACCOUNT,
        "region": "us-east-1",
        "call_limit": 1,
        "sdk_attempt_limit": 1,
        "connect_timeout_seconds": 3,
        "read_timeout_seconds": 120,
        "quality_scope": "diagnostic replay of one reviewer call; not a full worker qualification",
        "request": request,
    }
    with PLAN.open("x") as stream:
        json.dump(plan, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(digest(PLAN))


def execute(plan_sha256):
    if digest(PLAN) != plan_sha256 or RESERVATION.exists() or CAPTURE.exists():
        raise ValueError("Plan differs from reviewed bytes or probe was already used.")
    plan = json.loads(PLAN.read_text())
    if (digest(BASELINE) != plan["baseline_capture_sha256"]
            or digest(SOURCE) != plan["source_sha256"]
            or plan["call_limit"] != 1 or plan["sdk_attempt_limit"] != 1
            or plan["account"] != EXPECTED_ACCOUNT):
        raise ValueError("Frozen inputs or limits differ.")
    session, secrets = credential_session()
    config = Config(retries={"mode": "standard", "total_max_attempts": 1},
                    connect_timeout=3, read_timeout=120)
    identity = session.client("sts", region_name=plan["region"], config=config).get_caller_identity()
    if identity["Account"] != EXPECTED_ACCOUNT:
        raise ValueError("AWS account differs from frozen plan.")
    with RESERVATION.open("x") as stream:
        json.dump({"plan_sha256": plan_sha256, "status": "reserved",
                   "account": EXPECTED_ACCOUNT}, stream, indent=2)
        stream.write("\n")
    bedrock = session.client("bedrock-runtime", region_name=plan["region"], config=config)
    start = time.monotonic()
    try:
        response = bedrock.converse(**plan["request"])
        retained, omitted_reasoning_blocks = safe_response(response, secrets)
        result = {"status": "completed", "response": retained,
                  "reasoning_blocks_omitted": omitted_reasoning_blocks}
    except Exception as error:  # Record a terminal one-shot error without retrying.
        result = {"status": "failed", "error": safe_error(error, secrets)}
    result.update({"probe_id": plan["probe_id"], "plan_sha256": plan_sha256,
                   "elapsed_seconds": round(time.monotonic() - start, 6)})
    with CAPTURE.open("x") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(json.dumps({"status": result["status"], "capture_sha256": digest(CAPTURE),
                      "elapsed_seconds": result["elapsed_seconds"]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "execute"))
    parser.add_argument("--plan-sha256")
    args = parser.parse_args()
    if args.mode == "prepare":
        prepare()
    elif args.plan_sha256:
        execute(args.plan_sha256)
    else:
        parser.error("execute requires --plan-sha256")


if __name__ == "__main__":
    main()
