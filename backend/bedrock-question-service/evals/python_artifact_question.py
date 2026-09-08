"""Eval-only construction from one Python artifact and a native observation.

Nothing here executes source or contacts a provider. The caller must obtain the
service result from the managed execution path, retain its request/lifecycle
record, and confirm cleanup. Correlation hashes are not signatures. A matching
result does not establish determinism, teaching quality, or runtime admission.
"""

import builtins
import copy
import json
import re

from execution_evidence import (
    _json,
    _same_json_value,
    _sha,
    _valid_typed_result,
    parse_execution_observation,
    prepare_execution_job,
)


PROTOCOL = "checkpoint.python-artifact-question.v1"
SCOPE = (
    "Exact artifact/invocation observation and typed key binding only. "
    "Teaching feedback, difficulty, relevance, distractor quality, determinism, "
    "and Python object alias identity are unassessed. No runtime admission."
)


class ArtifactQuestionError(ValueError):
    """The proposed representation is invalid or exceeds an admission limit."""


def _text(value, field, maximum, *, minimum=1):
    if type(value) is not str or len(value.strip()) < minimum or len(value) > maximum:
        raise ArtifactQuestionError(f"invalid_or_overlong:{field}")
    return value


def _runtime(runtime):
    if (
        type(runtime) is not dict
        or set(runtime) != {"implementation", "version"}
        or runtime["implementation"] != "cpython"
        or type(runtime["version"]) is not str
        or re.fullmatch(r"3\.\d+\.\d+", runtime["version"]) is None
    ):
        raise ArtifactQuestionError("explicit_cpython_runtime_required")
    return copy.deepcopy(runtime)


def _literal(value):
    """Python literal for JSON inputs; strings expose exact Unicode code points."""
    if type(value) is list:
        return "[" + ", ".join(_literal(v) for v in value) + "]"
    if type(value) is dict:
        return (
            "{"
            + ", ".join(f"{ascii(k)}: {_literal(v)}" for k, v in value.items())
            + "}"
        )
    return ascii(value)


def _typed_literal(item):
    kind, value = item["type"], item["value"]
    if kind == "none":
        return "None"
    if kind == "int":
        return value
    if kind == "float":
        return repr(float.fromhex(value))
    if kind in ("bool", "str"):
        return ascii(value)
    if kind == "dict":
        return (
            "{"
            + ", ".join(f"{ascii(key)}: {_typed_literal(v)}" for key, v in value)
            + "}"
        )
    values = ", ".join(_typed_literal(v) for v in value)
    if kind == "tuple":
        return "(" + values + ("," if len(value) == 1 else "") + ")"
    return "[" + values + "]"


def _option(option):
    if type(option) is not dict:
        raise ArtifactQuestionError("invalid_option")
    kind = option.get("kind")
    if kind == "return" and set(option) == {"kind", "value", "reason"}:
        if not _valid_typed_result(option["value"]):
            raise ArtifactQuestionError("invalid_typed_option")
        identity = {"kind": kind, "value": option["value"]}
        name = option["value"]["type"]
        if name == "none":
            name = "NoneType"
        label = f"Returns {_typed_literal(option['value'])} ({name})"
    elif kind == "exception" and set(option) == {"kind", "type", "reason"}:
        name = option["type"]
        exception = getattr(builtins, name, None) if type(name) is str else None
        if not isinstance(exception, type) or not issubclass(exception, Exception):
            raise ArtifactQuestionError("invalid_exception_option")
        if exception.__name__ != name:
            raise ArtifactQuestionError("noncanonical_exception_class")
        identity = {"kind": kind, "type": name}
        # Exact class avoids overlapping SyntaxError/IndentationError choices.
        label = f"Raises exactly {name}"
    else:
        raise ArtifactQuestionError("invalid_option_fields")
    _text(option["reason"], "choice_feedback", 280, minimum=12)
    _text(label, "choice", 140)
    return identity, label


def _answer_identity(identity):
    """Collapse signed zero only for detecting equivalent offered answers.

    The task does not ask for a float's sign bit. Equal signed-zero alternatives
    (including inside structural values) must not acquire apparent uniqueness
    from the observation protocol's finer representation. Native result matching
    remains exact; this function never changes the artifact, choice or evidence.
    """

    def normalized(item):
        kind, value = item["type"], item["value"]
        if kind == "float" and float.fromhex(value) == 0:
            value = "0x0.0p+0"
        elif kind in ("list", "tuple"):
            value = [normalized(child) for child in value]
        elif kind == "dict":
            value = [[key, normalized(child)] for key, child in value]
        return {"type": kind, "value": value}

    if identity["kind"] == "return":
        return {"kind": "return", "value": normalized(identity["value"])}
    return identity


def prepare_python_artifact_question(spec, *, case_id, runtime, limits=None):
    """Render an unkeyed draft and build the existing managed execution job.

    spec = {artifact: {source, mode, inputs}, options: [four typed options],
            explanation, topic, difficulty}. exec requires explicit entrypoint,
    args and kwargs; eval requires inputs=None. No authored stem/key is accepted.
    The execution protocol canonicalizes JSON dictionary order. Rendering uses
    that same canonical object so the actual Python argument order is visible.
    """
    if type(spec) is not dict or set(spec) != {
        "artifact",
        "options",
        "explanation",
        "topic",
        "difficulty",
    }:
        raise ArtifactQuestionError("invalid_spec_fields")
    try:
        canonical = json.loads(_json(spec))
        if not _same_json_value(spec, canonical):
            raise ValueError("not exact JSON")
    except (TypeError, ValueError, RecursionError) as error:
        raise ArtifactQuestionError("exact_json_spec_required") from error
    spec = canonical
    runtime = _runtime(runtime)
    artifact = spec["artifact"]
    if (
        type(artifact) is not dict
        or set(artifact) != {"source", "mode", "inputs"}
        or type(artifact["source"]) is not str
        or not artifact["source"].strip()
        or artifact["mode"] not in ("exec", "eval")
        or (artifact["mode"] == "exec" and artifact["inputs"] is None)
        or (artifact["mode"] == "eval" and artifact["inputs"] is not None)
    ):
        raise ArtifactQuestionError("explicit_artifact_and_invocation_required")
    if type(spec["options"]) is not list or len(spec["options"]) != 4:
        raise ArtifactQuestionError("four_options_required")
    if type(spec["difficulty"]) is not int or not 1 <= spec["difficulty"] <= 5:
        raise ArtifactQuestionError("invalid_difficulty")
    _text(spec["topic"], "topic", 80)
    _text(spec["explanation"], "main_feedback", 420, minimum=12)
    identities, labels = zip(*(_option(option) for option in spec["options"]))
    if (
        len({_json(_answer_identity(v)) for v in identities}) != 4
        or len(set(labels)) != 4
    ):
        raise ArtifactQuestionError("duplicate_options")
    try:
        job = prepare_execution_job(case_id, **artifact, limits=limits)
    except ValueError as error:
        raise ArtifactQuestionError("invalid_execution_artifact") from error
    prefix = f"CPython {runtime['version']}: "
    if artifact["mode"] == "exec":
        inputs = artifact["inputs"]
        invocation = (
            inputs["entrypoint"]
            + "(*"
            + _literal(inputs["args"])
            + ", **"
            + _literal(inputs["kwargs"])
            + ")"
        )
        intro = (
            prefix
            + "run source, then call. What returns/raises (exact types/value/order)?\n\n"
        )
        prompt = intro + artifact["source"] + "\n\nCall:\n" + invocation
    else:
        invocation = None
        intro = (
            prefix
            + "what does this expression return or raise (exact types/order)?\n\n"
        )
        prompt = intro + artifact["source"]
    _text(prompt, "prompt", 320)
    draft = {
        "prompt": prompt,
        "choices": list(labels),
        "explanation": spec["explanation"],
        "choiceExplanations": {
            label: option["reason"]
            for label, option in zip(labels, spec["options"], strict=True)
        },
        "topic": spec["topic"],
        "difficulty": spec["difficulty"],
        "format": "Multiple Choice",
    }
    return {
        "protocol": PROTOCOL,
        "spec": spec,
        "runtime": runtime,
        "job": job,
        "draft": draft,
        "option_identities": list(identities),
        "source_span": [len(intro), len(intro) + len(artifact["source"])],
        "invocation": invocation,
        "spec_sha256": _sha(_json(spec)),
        "draft_sha256": _sha(_json(draft)),
        "feedback_assessment": "unassessed",
        "scope": SCOPE,
    }


def _matches_runtime(observed, expected):
    return (
        type(observed) is dict
        and observed.get("implementation") == expected["implementation"]
        and type(observed.get("version")) is str
        and observed["version"].split(maxsplit=1)[:1] == [expected["version"]]
    )


def bind_python_artifact_question(prepared, service_result, *, cleanup_confirmed):
    """Derive a key from trusted-transport native evidence, never authored text.

    Cleanup is an application-owned lifecycle observation, not a model field.
    Any unsuccessful or unsupported observation yields no question/key. A bound
    question is still awaiting independent teaching and ambiguity assessment.
    """
    if type(prepared) is not dict:
        raise ArtifactQuestionError("invalid_prepared_question")
    try:
        rebuilt = prepare_python_artifact_question(
            prepared["spec"],
            case_id=prepared["job"]["case_id"],
            runtime=prepared["runtime"],
            limits=prepared["job"]["limits"],
        )
        if not _same_json_value(rebuilt, prepared):
            raise ArtifactQuestionError("prepared_question_changed")
    except (KeyError, TypeError) as error:
        raise ArtifactQuestionError("invalid_prepared_question") from error

    def decline(status, reason, observation=None):
        return {
            "status": status,
            "reason": reason,
            "question": None,
            "observation": observation,
            "feedback_assessment": "unassessed",
            "scope": SCOPE,
        }

    if cleanup_confirmed is not True:
        return decline("inconclusive", "cleanup_not_confirmed")
    observation = parse_execution_observation(rebuilt["job"], service_result)
    if not observation.get("envelope_valid") or observation.get("status") != "observed":
        return decline(observation["status"], observation.get("reason"), observation)
    if observation.get("operational_failure"):
        return decline("inconclusive", "execution_operational_failure", observation)
    child = observation.get("child")
    if not _matches_runtime(observation.get("runtime"), rebuilt["runtime"]) or (
        child is not None
        and not _matches_runtime(child.get("runtime"), rebuilt["runtime"])
    ):
        return decline("unsupported", "runtime_mismatch", observation)
    if not observation["compile"]["valid"]:
        identity = {"kind": "exception", "type": observation["compile"]["exception"]}
    elif child["exception"] is not None:
        identity = {"kind": "exception", "type": child["exception"]["type"]}
    else:
        identity = {"kind": "return", "value": child["return_value"]}
    matches = [
        i
        for i, option in enumerate(rebuilt["option_identities"])
        if _same_json_value(identity, option)
    ]
    if len(matches) != 1:
        return decline("unmatched", "observed_result_not_uniquely_offered", observation)
    question = copy.deepcopy(rebuilt["draft"])
    question["expectedAnswer"] = question["choices"][matches[0]]
    return {
        "status": "bound",
        "question": question,
        "observation": observation,
        "binding": {
            "protocol": PROTOCOL,
            "job_id": rebuilt["job"]["job_id"],
            "artifact_sha256": rebuilt["job"]["artifact_sha256"],
            "input_sha256": rebuilt["job"]["input_sha256"],
            "harness_sha256": rebuilt["job"]["harness_sha256"],
            "spec_sha256": rebuilt["spec_sha256"],
            "question_sha256": _sha(_json(question)),
            "observation_sha256": _sha(_json(observation)),
            "observed_identity": identity,
            "matched_option_index": matches[0],
            "runtime": rebuilt["runtime"],
        },
        "feedback_assessment": "unassessed",
        "scope": SCOPE,
    }
