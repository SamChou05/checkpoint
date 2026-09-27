"""Reproduce the captured schema/compiler mismatch without any AWS call."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
CAPTURE_SHA256 = "5d4212bbc7dbc852645c99d7f737311957250239dded3aee9f785ae4a74405e3"
PLAN_SHA256 = "36f7a318314a7abccd822f23bfe3d06c729cee656e97218d1585f35c97316775"


def replay():
    capture_path, plan_path = HERE / "capture.json", HERE / "plan.json"

    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    if sha(capture_path) != CAPTURE_SHA256 or sha(plan_path) != PLAN_SHA256:
        raise ValueError("Frozen capture or plan changed")
    capture, plan = json.loads(capture_path.read_text()), json.loads(plan_path.read_text())
    if capture["plan"] != plan or capture["summary"]["returned_questions"] != 0:
        raise ValueError("This is not the captured zero-return trial")
    raw = capture["calls"][0]["raw_author_object"]
    if set(raw["questions"]) != {str(index) for index in range(5)}:
        raise ValueError("Author did not return all five typed slots")
    spec = importlib.util.spec_from_file_location("frozen_worker_probe", HERE / "full_worker_probe.py")
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)
    request = plan["jobs"][0]["request"]
    schema = json.loads(plan["initial_author_wire"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    slot4_allowed = schema["properties"]["questions"]["properties"]["4"]["properties"]["scene"]["enum"]
    scene = raw["questions"]["4"]["scene"]
    with patch.dict(os.environ, harness.ENVIRONMENT, clear=True):
        contract = harness.mapped_contract(request)
        adapted = json.loads(harness.native.adapt_native_response(json.dumps(raw), contract))
        try:
            harness.runtime.prepare_mapped_agreement_rows(adapted, contract)
        except Exception as error:
            if (type(error).__name__ != "AgreementTaskError"
                    or str(error) != "Original English slots require their closed agreement families."):
                raise
        else:
            raise ValueError("Captured author output no longer reproduces the compiler rejection")
    from agreement_task_constructor import GERUND_SCENES
    if scene != "gerund_meals" or scene not in slot4_allowed or scene not in GERUND_SCENES:
        raise ValueError("Gerund scene was not both schema- and constructor-supported")
    return {"capture_sha256": CAPTURE_SHA256, "plan_sha256": PLAN_SHA256,
            "original_slots": 5, "returned_original_slots": [],
            "bedrock_converse_calls": 1, "raw_author_typed_slots": 5,
            "native_adapter_accepted": True, "slot4_scene": scene,
            "slot4_scene_allowed_by_native_schema": True,
            "failure_stage": "compile_mapped_english_slots_before_sanitization",
            "exception_type": "AgreementTaskError",
            "exception_message": "Original English slots require their closed agreement families.",
            "cause": "slot4 compiler allowlist omits GERUND_SCENES while schema includes it",
            "provider_retry_or_topup": False}


if __name__ == "__main__":
    result = replay()
    with (HERE / "offline-replay.json").open("x") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(result, indent=2))
