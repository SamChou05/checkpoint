"""Offline transport/contract characterization; no provider calls or correctness rate.

Run from any directory with a Python 3.12 environment containing requirements.txt.
This compares the original stale checkout's committed baseline with the current
worktree implementation without modifying either production implementation.
"""

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import types
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SERVICE = ROOT / "backend/bedrock-question-service"
BASELINE = "aa2db49c45153c52a34da051beaf803d5f39577d"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.session import get_session  # noqa: E402
from botocore.validate import validate_parameters  # noqa: E402
import native_output_contracts as contracts  # noqa: E402
import question_generation as current  # noqa: E402
from service_errors import ProviderError, ServiceConfigurationError  # noqa: E402


class RecordingClient:
    def __init__(self):
        self.calls = []

    def converse(self, **request):
        self.calls.append(request)
        return {
            "stopReason": "end_turn",
            "output": {"message": {"content": [{"text": '{"questions":[]}'}]}},
        }


def snapshot_call(module, mode, model):
    client = RecordingClient()
    keywords = {} if module is committed else {"contract": "question_author_v1"}
    with patch.dict(os.environ, {
        "BEDROCK_STRUCTURED_OUTPUT_MODE": mode,
        "BEDROCK_KIMI_THINKING": "disabled",
        "BEDROCK_CLAUDE_THINKING": "disabled",
        "BEDROCK_GUARDRAIL_IDENTIFIER": "",
        "BEDROCK_GUARDRAIL_VERSION": "",
    }):
        try:
            module._generate_with_bedrock(
                {}, client, model, user_prompt="Return an empty question envelope.",
                system_prompt="Return JSON only.", **keywords,
            )
        except ServiceConfigurationError as error:
            return {"calls": len(client.calls), "configuration_error": str(error)}
    request = client.calls[0]
    shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
    validate_parameters(request, shape)
    return {
        "calls": len(client.calls),
        "has_output_config": "outputConfig" in request,
        "has_tool_config": "toolConfig" in request,
        "inference_config": request["inferenceConfig"],
        "sdk_input_shape_valid": True,
    }


def accepted(payload, contract="question_author_v1"):
    try:
        contracts.adapt_native_response(json.dumps(payload), contract)
        return True
    except ProviderError:
        return False


committed_source = subprocess.check_output(
    ["git", "show", f"{BASELINE}:backend/bedrock-question-service/question_generation.py"],
    cwd=ROOT, text=True,
)
committed = types.ModuleType("committed_question_generation")
exec(compile(committed_source, "committed_question_generation", "exec"), committed.__dict__)

question = {
    "prompt": "What is 2 + 2?", "choices": ["4", "3", "5", "6"],
    "expectedAnswer": "4", "explanation": "Adding two and two gives four.",
    "topic": "Arithmetic", "difficulty": 1, "format": "Multiple Choice",
}
cases = {
    "valid": ({"questions": [question]}, True),
    "empty_batch": ({"questions": []}, True),
}
for name, change, expected in [
    ("only_three_choices", {"choices": ["4", "3", "5"]}, True),
    ("five_choices", {"choices": ["4", "3", "5", "6", "7"]}, True),
    ("duplicate_choice_text", {"choices": ["4", "4", "5", "6"]}, True),
    ("answer_not_offered", {"expectedAnswer": "7"}, True),
    ("invalid_difficulty_range", {"difficulty": -99}, True),
    ("empty_prompt", {"prompt": ""}, True),
    ("unknown_property", {"unexpected": True}, False),
    ("wrong_format_enum", {"format": "Essay"}, False),
    ("wrong_choice_type", {"choices": ["4", "3", 5, "6"]}, False),
    ("boolean_not_integer", {"difficulty": True}, False),
]:
    cases[name] = ({"questions": [{**question, **change}]}, expected)
cases["missing_required_answer"] = ({"questions": [
    {key: value for key, value in question.items() if key != "expectedAnswer"}
]}, False)

schema_results = []
for name, (payload, expectation) in cases.items():
    actual = accepted(payload)
    assert actual is expectation, name
    schema_results.append({"case": name, "accepted_by_transport_schema": actual})

# A shape-only alternative that uses only the same provider-supported object,
# required, string and enum primitives. This does NOT prove content correctness,
# and it has not been live-qualified on Bedrock.
slot_schema = {
    "type": "object", "additionalProperties": False,
    "properties": {
        "choices": {
            "type": "object", "additionalProperties": False,
            "properties": {key: {"type": "string"} for key in "ABCD"},
            "required": list("ABCD"),
        },
        "answerChoice": {"type": "string", "enum": list("ABCD")},
    },
    "required": ["choices", "answerChoice"],
}
slot_value = {"choices": dict(zip("ABCD", question["choices"], strict=True)), "answerChoice": "A"}
slot_cases = {"valid": (slot_value, True)}
missing = copy.deepcopy(slot_value)
del missing["choices"]["D"]
slot_cases["missing_fourth_slot"] = (missing, False)
extra = copy.deepcopy(slot_value)
extra["choices"]["E"] = "7"
slot_cases["extra_fifth_slot"] = (extra, False)
slot_cases["nonexistent_answer_slot"] = ({**slot_value, "answerChoice": "E"}, False)
duplicate = copy.deepcopy(slot_value)
duplicate["choices"]["B"] = "4"
slot_cases["duplicate_text_still_needs_application_validation"] = (duplicate, True)
slot_results = []
for name, (payload, expectation) in slot_cases.items():
    try:
        contracts._validate_schema_value(payload, slot_schema)
        actual = True
    except ValueError:
        actual = False
    assert actual is expectation, name
    slot_results.append({"case": name, "accepted_by_transport_schema": actual})

snapshots = {}
for label, module, mode, model in [
    ("committed_kimi", committed, "legacy", "moonshotai.kimi-k2.5"),
    ("working_legacy_kimi", current, "legacy", "moonshotai.kimi-k2.5"),
    ("working_native_kimi", current, "native", "moonshotai.kimi-k2.5"),
    ("working_native_sonnet", current, "native", "us.anthropic.claude-sonnet-4-6"),
    ("working_native_nova", current, "native", "amazon.nova-lite-v1:0"),
]:
    snapshots[label] = snapshot_call(module, mode, model)
assert not snapshots["committed_kimi"]["has_output_config"]
assert not snapshots["working_legacy_kimi"]["has_output_config"]
assert snapshots["working_native_kimi"]["has_output_config"]
assert snapshots["working_native_sonnet"]["has_output_config"]
assert snapshots["working_native_nova"]["calls"] == 0

report = {
    "kind": "Offline deterministic transport and schema characterization",
    "live_provider_calls": 0,
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "baseline": BASELINE,
    "runtime": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
    "source_sha256": {
        "committed_question_generation": hashlib.sha256(committed_source.encode()).hexdigest(),
        **{name: hashlib.sha256((SERVICE / name).read_bytes()).hexdigest()
           for name in ["native_output_contracts.py", "question_generation.py"]},
    },
    "request_snapshots": snapshots,
    "author_schema_cases": schema_results,
    "fixed_slot_alternative_cases": slot_results,
    "limitations": [
        "A transport-schema acceptance is not acceptance into the question bank.",
        "Current sanitization, independent solving and final review add further gates.",
        "No fresh provider behavior, deployment configuration, or semantic error rate was measured.",
        "Alternative fixed slots remove cardinality and answer-reference freedom, not factual ambiguity or duplicate text.",
    ],
}
destination = Path(__file__).with_name("provider-contract-probe.json")
destination.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"output": str(destination), "schema_cases": len(schema_results), "slot_cases": len(slot_results), "transport_cases": len(snapshots)}))
