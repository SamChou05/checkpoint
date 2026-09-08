"""Unintegrated HTML MCQs bound to a trusted, isolated Chromium observation.

The binding covers the exact displayed artifact, probe and native answer tuple.
It does not certify model feedback, standards conformance, cross-browser results,
difficulty, distractor plausibility or goal fit. Hashes are not trust signatures.
"""

import copy
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import unicodedata

PROTOCOL = "checkpoint.html_artifact_job.v1"
OBSERVATION_PROTOCOL = "checkpoint.html_artifact_observation.v1"
PROPERTIES = (
    "disabled",
    "matches(':disabled')",
    "required",
    "readOnly",
    "willValidate",
    "validity.valueMissing",
    "validity.valid",
    "checkValidity()",
)
SETTINGS = {
    "offline": True,
    "javaScriptEnabled": False,
    "acceptDownloads": False,
    "serviceWorkers": "block",
    "allRoutesAborted": True,
    "chromiumSandbox": True,
}
OBSERVER = Path(__file__).with_name("observe_html_artifact.js")
TAGS = {
    "form",
    "fieldset",
    "legend",
    "label",
    "input",
    "button",
    "textarea",
    "select",
    "option",
    "optgroup",
    "div",
    "span",
    "p",
    "br",
}
ATTRIBUTES = {
    "id",
    "type",
    "value",
    "name",
    "disabled",
    "required",
    "readonly",
    "checked",
    "multiple",
    "selected",
    "min",
    "max",
    "step",
    "minlength",
    "maxlength",
    "pattern",
    "for",
    "form",
    "placeholder",
    "label",
    "size",
}
SCOPE = "Exact observed Chromium values and selected tuple for this displayed HTML/probe only. Causal feedback, standards and cross-browser truth, goal fit, distractor plausibility and difficulty remain unqualified. Hashes bind records; they are not authenticity signatures."


class HTMLArtifactError(ValueError):
    pass


def _reject(reason):
    raise HTMLArtifactError(reason)


def canonical(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _object(value, keys):
    if type(value) is not dict or set(value) != set(keys):
        _reject("invalid_object_fields")


def _text(value, maximum, minimum=1):
    if (
        type(value) is not str
        or len(value.strip()) < minimum
        or len(value) > maximum
        or any(
            unicodedata.category(c) in ("Cs", "Cf")
            or (unicodedata.category(c) == "Cc" and c not in "\n\r\t")
            for c in value
        )
    ):
        _reject("invalid_or_oversized_text")


class _PassiveHTML(HTMLParser):
    """A deliberately small balanced form-markup family, not an HTML validator."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.ids, self.elements = [], [], 0

    def handle_starttag(self, tag, attrs):
        if tag not in TAGS or any(name not in ATTRIBUTES for name, _ in attrs):
            _reject("unsupported_tag_or_attribute")
        names = [name for name, _ in attrs]
        if len(names) != len(set(names)):
            _reject("duplicate_attribute")
        self.ids.extend(value for name, value in attrs if name == "id")
        self.elements += 1
        if tag not in ("input", "br"):
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        # HTML ignores the self-closing slash on non-void HTML elements.
        if tag not in ("input", "br"):
            _reject("unsupported_nonvoid_self_closing_tag")
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if not self.stack or self.stack.pop() != tag:
            _reject("unbalanced_html_fragment")

    def handle_decl(self, decl):
        _reject("unsupported_declaration")

    def unknown_decl(self, data):
        _reject("unsupported_declaration")

    def handle_pi(self, data):
        _reject("unsupported_processing_instruction")


def render_prompt(spec):
    return f"In a fresh Chromium document, for #{spec['targetID']}, what are {', '.join(spec['properties'])} (in order)?\n{spec['html']}"


def render_choice(values):
    return json.dumps(values, separators=(", ", ": "))


def prepare_html_artifact(spec):
    _object(
        spec,
        (
            "html",
            "targetID",
            "properties",
            "alternatives",
            "explanation",
            "topic",
            "difficulty",
        ),
    )
    _text(spec["html"], 320)
    if (
        type(spec["targetID"]) is not str
        or re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,23}", spec["targetID"]) is None
    ):
        _reject("invalid_target_id")
    properties = spec["properties"]
    if (
        type(properties) is not list
        or not 2 <= len(properties) <= 4
        or any(type(p) is not str or p not in PROPERTIES for p in properties)
        or len(set(properties)) != len(properties)
    ):
        _reject("invalid_properties")
    alternatives = spec["alternatives"]
    if type(alternatives) is not list or len(alternatives) != 4:
        _reject("four_alternatives_required")
    for alternative in alternatives:
        _object(alternative, ("values", "reason"))
        values = alternative["values"]
        if (
            type(values) is not list
            or len(values) != len(properties)
            or any(type(v) is not bool for v in values)
        ):
            _reject("invalid_boolean_tuple")
        _text(alternative["reason"], 280, minimum=12)
    choices = [render_choice(a["values"]) for a in alternatives]
    if len(set(choices)) != 4 or any(len(c) > 140 for c in choices):
        _reject("duplicate_or_oversized_choice")
    _text(spec["explanation"], 420, minimum=12)
    _text(spec["topic"], 80)
    if type(spec["difficulty"]) is not int or not 1 <= spec["difficulty"] <= 5:
        _reject("invalid_proposed_difficulty")
    prompt = render_prompt(spec)
    if len(prompt) > 320:
        _reject("rendered_prompt_limit_exceeded")
    parser = _PassiveHTML()
    parser.feed(spec["html"])
    parser.close()
    if parser.stack or not parser.elements:
        _reject("unbalanced_or_empty_html_fragment")
    if parser.ids.count(spec["targetID"]) != 1 or len(parser.ids) != len(
        set(parser.ids)
    ):
        _reject("missing_or_duplicate_target_id")
    job = {
        "protocol": PROTOCOL,
        "spec": copy.deepcopy(spec),
        "prompt": prompt,
        "choices": choices,
        "artifact_sha256": digest(spec["html"]),
        "probe_sha256": digest(
            canonical({"targetID": spec["targetID"], "properties": properties})
        ),
        "observer_source_sha256": hashlib.sha256(OBSERVER.read_bytes()).hexdigest(),
    }
    job["job_id"] = digest(canonical(job))
    return job


def bind_html_observation(job, observation):
    if type(job) is not dict or canonical(job) != canonical(
        prepare_html_artifact(job.get("spec"))
    ):
        _reject("job_binding_mismatch")
    _object(
        observation,
        (
            "protocol",
            "job_id",
            "artifact_sha256",
            "probe_sha256",
            "observer_source_sha256",
            "status",
            "reason",
            "browser",
            "settings",
            "values",
            "serialized_dom",
            "serialized_dom_sha256",
            "target_outer_html",
            "cleanup",
        ),
    )
    if observation["protocol"] != OBSERVATION_PROTOCOL or any(
        observation[key] != job[key]
        for key in (
            "job_id",
            "artifact_sha256",
            "probe_sha256",
            "observer_source_sha256",
        )
    ):
        _reject("observation_binding_mismatch")
    if (
        observation["status"] != "observed"
        or observation["reason"] != ""
        or observation["cleanup"] != {"context": "closed", "browser": "closed"}
    ):
        _reject("incomplete_native_observation")
    if canonical(observation["settings"]) != canonical(SETTINGS):
        _reject("unexpected_native_settings")
    _object(observation["browser"], ("name", "version"))
    if observation["browser"]["name"] != "chromium":
        _reject("unexpected_browser")
    _text(observation["browser"]["version"], 80)
    _text(observation["serialized_dom"], 4096)
    _text(observation["target_outer_html"], 4096)
    if digest(observation["serialized_dom"]) != observation["serialized_dom_sha256"]:
        _reject("serialized_dom_binding_mismatch")
    values = observation["values"]
    if (
        type(values) is not list
        or len(values) != len(job["spec"]["properties"])
        or any(type(v) is not bool for v in values)
    ):
        _reject("invalid_native_values")
    expected = render_choice(values)
    if job["choices"].count(expected) != 1:
        _reject("observed_answer_not_uniquely_offered")
    spec = job["spec"]
    question = {
        "prompt": job["prompt"],
        "choices": job["choices"],
        "expectedAnswer": expected,
        "explanation": spec["explanation"],
        "choiceExplanations": {
            choice: a["reason"]
            for choice, a in zip(job["choices"], spec["alternatives"], strict=True)
        },
        "topic": spec["topic"],
        "difficulty": spec["difficulty"],
        "format": "Multiple Choice",
        "feedback_assessment": "unassessed",
    }
    return {
        "job": copy.deepcopy(job),
        "observation": copy.deepcopy(observation),
        "question": copy.deepcopy(question),
        "evidence": {
            "scope": SCOPE,
            "question_sha256": digest(canonical(question)),
            "observation_sha256": digest(canonical(observation)),
            "observed_summary": "; ".join(
                f"{p}={str(v).lower()}"
                for p, v in zip(spec["properties"], values, strict=True)
            ),
            "feedback_assessment": "unassessed",
        },
    }


def validate_bound_question(bundle):
    """Recompute exact bindings, not authenticity or semantic feedback approval."""
    if type(bundle) is not dict or set(bundle) != {
        "job",
        "observation",
        "question",
        "evidence",
    }:
        _reject("invalid_bound_bundle")
    if canonical(bundle) != canonical(
        bind_html_observation(bundle["job"], bundle["observation"])
    ):
        _reject("bound_question_mutated")
    return True
