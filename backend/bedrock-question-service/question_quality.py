"""Question-response parsing, sanitization, and quality checks."""

import json
import re
from typing import Any

from generation_diagnostics import record_quality

from question_bank_common import _normalized_stem_identity, _stem_fingerprint
from request_contract import (
    MAX_OBJECTIVE_NAME_CHARS,
    _canonical,
    _choice_uniqueness_key,
    _has_unambiguous_choices,
    _clamped_int,
    _clean_text,
    _clean_subject_text,
    _clip,
    _deterministic_objective_id,
    _strip_choice_label,
    _semantic_signal_key,
    _uuid_key,
)
from service_errors import ProviderError


MAX_PROVIDER_PROMPT_CHARS = 320

GENERIC_META_EXPECTED_ANSWER_SIGNALS = (
    "The answer that follows from the stated facts and respects the topic's constraints.",
    "The answer that follows from the stimulus.",
    "The choice that fits all stated constraints without adding new assumptions.",
    "The statement that can be checked against the specific facts or rules of the topic.",
    "Stay close to what the passage or problem facts actually establish.",
    "Use the facts in the prompt to eliminate choices that do not directly follow.",
)
GENERIC_META_CHOICE_SIGNALS = (
    "The answer that changes the topic to study planning.",
    "The answer that ignores qualifiers in the prompt.",
    "The answer that sounds familiar but adds unsupported assumptions.",
    "The broadest statement, even if it ignores details.",
    "The choice that is more dramatic.",
    "The choice that ignores exceptions.",
)
GENERIC_META_EXPLANATION_SIGNALS = (
    "Checkpoint should test the subject matter by rewarding constraint-aware reasoning, not broad study advice.",
    "Good knowledge checks reward constraint-aware reasoning inside the target domain.",
    "Checkpoint questions should test knowledge that can be verified, not vague intent.",
)
GENERIC_META_SCENARIOS = (
    "boundary condition",
    "competing constraints",
    "counterexample analysis",
    "real world transfer",
    "failure diagnosis",
    "scaling decision",
    "evidence interpretation",
)


def _extract_json_object(text: str) -> dict[str, Any]:
    trimmed = text.strip()
    if trimmed.startswith("```"):
        trimmed = re.sub(r"^```(?:json)?\s*", "", trimmed)
        trimmed = re.sub(r"\s*```$", "", trimmed)

    candidates = [trimmed]
    start = trimmed.find("{")
    end = trimmed.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidates.append(trimmed[start : end + 1])

    for candidate in candidates:
        parsed = _parse_provider_json(candidate)
        if parsed is not None:
            return parsed

    array_start = trimmed.find("[")
    array_end = trimmed.rfind("]")
    if array_start != -1 and array_end != -1 and array_end > array_start:
        parsed = _parse_provider_json(trimmed[array_start : array_end + 1])
        if parsed is not None:
            return parsed

    raise ProviderError("Provider response was not valid JSON.")


def _parse_provider_json(candidate: str) -> dict[str, Any] | None:
    try:
        parsed = json.loads(candidate, object_pairs_hook=_unique_json_object)
    except ValueError:
        return None

    if isinstance(parsed, dict):
        return parsed

    if isinstance(parsed, list):
        return {"questions": parsed}

    return None


def _unique_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property.")
        result[key] = value
    return result


def _sanitize_questions(
    raw_questions: Any,
    request: dict[str, Any],
    request_metrics: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    if not isinstance(raw_questions, list):
        record_quality(request_metrics, "sanitize", "invalid_envelope")
        return []

    requested_objective_allocation = _requested_objective_allocation_limits(request)
    if requested_objective_allocation is None:
        record_quality(
            request_metrics, "sanitize", "invalid_allocation", len(raw_questions)
        )
        return []

    minimum_difficulty = request["minimumDifficulty"]
    blocked_prompts = set()
    for prompt in request["existingPrompts"] + request["reportedPrompts"]:
        blocked_prompts.add(_normalized_stem_identity(prompt))
    for coverage in request["existingQuestionCoverage"]:
        prompt = coverage.get("prompt", "")
        if prompt:
            blocked_prompts.add(_normalized_stem_identity(prompt))
    seen_prompts = set(blocked_prompts)
    blocked_stem_fingerprints = set(request.get("blockedStemFingerprints", []))
    seen_coverage = set()
    seen_choice_sets = set()
    accepted_skill_counts: dict[str, int] = {}
    accepted_objective_counts: dict[tuple[str, str], int] = {}
    objective_scoped_skill_ids = {
        skill_id for skill_id, _ in requested_objective_allocation
    }
    for coverage in request["existingQuestionCoverage"]:
        seen_coverage.update(
            _question_coverage_keys(
                coverage.get("expectedAnswer", ""),
                coverage.get("topic", ""),
            )
        )
        coverage_choice_key = _choice_set_key(coverage.get("choices", []))
        if coverage_choice_key:
            seen_choice_sets.add(coverage_choice_key)
    sanitized: list[dict[str, Any]] = []

    for candidate_index, raw_question in enumerate(raw_questions):
        if not isinstance(raw_question, dict):
            record_quality(request_metrics, "sanitize", "invalid_item")
            continue

        skill_tag = _normalized_question_skill_tag(raw_question, request)
        if request.get("skillMap") and skill_tag is None:
            record_quality(request_metrics, "sanitize", "invalid_skill")
            continue
        if skill_tag:
            skill_id = skill_tag["skillID"]
            allowed_count = request.get("requestedSkillAllocation", {}).get(skill_id, 0)
            if accepted_skill_counts.get(skill_id, 0) >= allowed_count:
                record_quality(request_metrics, "sanitize", "skill_quota")
                continue
            if skill_id in objective_scoped_skill_ids:
                objective_pair = (skill_id, skill_tag["objectiveID"])
                objective_limit = requested_objective_allocation.get(objective_pair, 0)
                if accepted_objective_counts.get(objective_pair, 0) >= objective_limit:
                    record_quality(request_metrics, "sanitize", "objective_quota")
                    continue

        raw_prompt = _prompt_without_trailing_choice_echo(
            raw_question.get("prompt"),
            raw_question.get("choices"),
        )
        if len(raw_prompt) > MAX_PROVIDER_PROMPT_CHARS:
            record_quality(request_metrics, "sanitize", "prompt_length")
            continue

        prompt = raw_prompt
        expected_answer = _choice_uniqueness_key(
            str(raw_question.get("expectedAnswer") or "")
        )
        explanation = _clip(_clean_text(raw_question.get("explanation")), 420)
        topic = (
            skill_tag["topic"]
            if skill_tag
            else _clip(
                _clean_text(raw_question.get("topic")),
                48,
            )
        )
        if not topic:
            topic = request["goal"]["contentTopics"][0]

        prompt_keys = {_normalized_stem_identity(prompt)}
        stem_fingerprint = _stem_fingerprint(
            prompt, version=request.get("stemFingerprintVersion", 1)
        )
        coverage_keys = _question_coverage_keys(expected_answer, topic)
        if (
            len(prompt) < 12
            or not expected_answer
            or not explanation
            or _explanation_admits_bad_answer(explanation)
            or _looks_like_study_strategy(prompt, request["goal"])
            or _prompt_contains_embedded_options(prompt)
            or _prompt_contains_latex_markup(prompt)
        ):
            record_quality(request_metrics, "sanitize", "invalid_content")
            continue
        if (
            any(key in seen_prompts for key in prompt_keys)
            or stem_fingerprint in blocked_stem_fingerprints
        ):
            record_quality(request_metrics, "sanitize", "duplicate_stem")
            continue
        if not seen_coverage.isdisjoint(coverage_keys):
            record_quality(request_metrics, "sanitize", "duplicate_answer")
            continue

        choices = _normalized_choices(raw_question.get("choices"), expected_answer)
        if len(choices) != 4:
            record_quality(request_metrics, "sanitize", "invalid_choices")
            continue
        choice_set_key = _choice_set_key(choices)
        if not choice_set_key or choice_set_key in seen_choice_sets:
            record_quality(request_metrics, "sanitize", "duplicate_choices")
            continue
        if _looks_like_generic_meta_question(
            prompt, expected_answer, choices, explanation
        ):
            record_quality(request_metrics, "sanitize", "generic_content")
            continue
        if _explanation_supports_different_choice(
            expected_answer, choices, explanation
        ):
            record_quality(request_metrics, "sanitize", "contradictory_explanation")
            continue

        difficulty = _clamped_int(raw_question.get("difficulty"), minimum=1, maximum=5)
        if difficulty < minimum_difficulty:
            record_quality(request_metrics, "sanitize", "difficulty_floor")
            continue
        skill_plan = next(
            (
                plan
                for plan in request.get("adaptiveSkillPlans", [])
                if skill_tag and plan["skillID"] == skill_tag["skillID"]
            ),
            None,
        )
        if skill_plan and difficulty != skill_plan["targetDifficulty"]:
            record_quality(request_metrics, "sanitize", "difficulty_target")
            continue

        seen_prompts.update(prompt_keys)
        seen_coverage.update(coverage_keys)
        seen_choice_sets.add(choice_set_key)
        question = {
            "prompt": prompt,
            "expectedAnswer": expected_answer,
            "choices": choices,
            "explanation": explanation,
            "topic": topic,
            "difficulty": difficulty,
            "format": "Multiple Choice",
        }
        if skill_tag:
            question.update(skill_tag)
            accepted_skill_counts[skill_tag["skillID"]] = (
                accepted_skill_counts.get(skill_tag["skillID"], 0) + 1
            )
            objective_pair = (skill_tag["skillID"], skill_tag["objectiveID"])
            if objective_pair in requested_objective_allocation:
                accepted_objective_counts[objective_pair] = (
                    accepted_objective_counts.get(objective_pair, 0) + 1
                )
        sanitized.append(question)
        record_quality(request_metrics, "sanitize", "accepted")

        if len(sanitized) >= request["targetCount"]:
            record_quality(
                request_metrics,
                "sanitize",
                "surplus",
                len(raw_questions) - candidate_index - 1,
            )
            break

    return sanitized


def _normalized_question_skill_tag(
    raw_question: dict[str, Any],
    request: dict[str, Any],
) -> dict[str, str] | None:
    skill_map = request.get("skillMap")
    if not skill_map:
        return None

    raw_topic = _clean_text(raw_question.get("topic"))
    skill = _matching_skill_map_entry(
        skill_map.get("skills", []),
        _clean_text(raw_question.get("skillID")),
        raw_topic,
    )
    if not skill:
        return None

    objectives = skill.get("objectives", [])
    raw_objective_name = _clean_text(
        raw_question.get("objective", raw_question.get("objectiveName"))
    )
    raw_objective_id = _clean_text(raw_question.get("objectiveID"))
    if objectives:
        objective = _matching_skill_map_entry(
            objectives,
            raw_objective_id,
            raw_objective_name,
        )
        if not objective:
            return None
        objective_id = objective["id"]
        objective_name = objective["name"]
    else:
        if not raw_objective_name or len(raw_objective_name) > MAX_OBJECTIVE_NAME_CHARS:
            return None
        if not _canonical(raw_objective_name):
            return None
        objective_id = _deterministic_objective_id(skill["id"], raw_objective_name)
        if raw_objective_id:
            try:
                if _uuid_key(raw_objective_id) != _uuid_key(objective_id):
                    return None
            except (ValueError, AttributeError):
                return None
        objective_name = raw_objective_name

    return {
        "skillID": skill["id"],
        "objectiveID": objective_id,
        "objective": objective_name,
        "topic": skill["name"],
    }


def _matching_skill_map_entry(
    entries: list[dict[str, Any]],
    raw_id: str,
    raw_name: str,
) -> dict[str, Any] | None:
    """Resolve an optional ID/name pair, rejecting unknown or conflicting tags."""
    entries_by_id = {_uuid_key(entry["id"]): entry for entry in entries}
    entries_by_name = {_canonical(entry["name"]): entry for entry in entries}

    entry_from_id = None
    if raw_id:
        try:
            entry_from_id = entries_by_id.get(_uuid_key(raw_id))
        except (ValueError, AttributeError, TypeError):
            return None
        if not entry_from_id:
            return None

    entry_from_name = entries_by_name.get(_canonical(raw_name)) if raw_name else None
    if raw_name and not entry_from_name:
        return None
    if entry_from_id and entry_from_name and entry_from_id is not entry_from_name:
        return None
    return entry_from_id or entry_from_name


def _remaining_requested_skill_allocation(
    request: dict[str, Any],
    accepted_questions: list[dict[str, Any]],
) -> dict[str, int]:
    remaining = dict(request.get("requestedSkillAllocation", {}))
    for question in accepted_questions:
        skill_id = question.get("skillID")
        if skill_id in remaining:
            remaining[skill_id] = max(0, remaining[skill_id] - 1)
    return {skill_id: count for skill_id, count in remaining.items() if count > 0}


def _remaining_requested_objective_allocation(
    request: dict[str, Any],
    accepted_questions: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    accepted_counts: dict[tuple[str, str], int] = {}
    for question in accepted_questions:
        pair = (question.get("skillID", ""), question.get("objectiveID", ""))
        accepted_counts[pair] = accepted_counts.get(pair, 0) + 1

    remaining: list[dict[str, Any]] = []
    for entry in request.get("requestedObjectiveAllocation", []):
        pair = (entry["skillID"], entry["objectiveID"])
        count = max(0, entry["count"] - accepted_counts.get(pair, 0))
        if count > 0:
            remaining.append({**entry, "count": count})
    return remaining


def _requested_objective_allocation_limits(
    request: dict[str, Any],
) -> dict[tuple[str, str], int] | None:
    """Validate the bounded server-internal objective quota representation."""
    if "requestedObjectiveAllocation" not in request:
        return {}
    raw_allocation = request.get("requestedObjectiveAllocation")
    if not isinstance(raw_allocation, list) or len(raw_allocation) > 30:
        return None

    target_count = request.get("targetCount")
    if isinstance(target_count, bool) or not isinstance(target_count, int):
        return None

    skills_by_id: dict[str, dict[str, Any]] = {}
    objectives_by_skill_id: dict[str, dict[str, str]] = {}
    for skill in request.get("skillMap", {}).get("skills", []):
        try:
            skill_key = _uuid_key(skill.get("id", ""))
        except (ValueError, AttributeError, TypeError):
            return None
        skills_by_id[skill_key] = skill
        objective_ids: dict[str, str] = {}
        for objective in skill.get("objectives", []):
            try:
                objective_key = _uuid_key(objective.get("id", ""))
            except (ValueError, AttributeError, TypeError):
                return None
            objective_ids[objective_key] = objective["id"]
        objectives_by_skill_id[skill_key] = objective_ids

    limits: dict[tuple[str, str], int] = {}
    totals_by_skill_id: dict[str, int] = {}
    for entry in raw_allocation:
        if not isinstance(entry, dict):
            return None
        count = entry.get("count")
        if (
            isinstance(count, bool)
            or not isinstance(count, int)
            or not 1 <= count <= max(1, target_count)
        ):
            return None
        try:
            skill_key = _uuid_key(entry.get("skillID", ""))
            objective_key = _uuid_key(entry.get("objectiveID", ""))
        except (ValueError, AttributeError, TypeError):
            return None
        skill = skills_by_id.get(skill_key)
        objective_id = objectives_by_skill_id.get(skill_key, {}).get(objective_key)
        if not skill or not objective_id:
            return None
        pair = (skill["id"], objective_id)
        if pair in limits:
            return None
        limits[pair] = count
        totals_by_skill_id[skill["id"]] = totals_by_skill_id.get(skill["id"], 0) + count

    requested_skills = request.get("requestedSkillAllocation", {})
    if not isinstance(requested_skills, dict):
        return None
    for skill in skills_by_id.values():
        requested_count = requested_skills.get(skill["id"], 0)
        if isinstance(requested_count, bool) or not isinstance(requested_count, int):
            return None
        objective_count = len(skill.get("objectives", []))
        allocated_count = totals_by_skill_id.get(skill["id"], 0)
        if objective_count > 0 and requested_count > 0:
            if allocated_count != requested_count:
                return None
        elif allocated_count != 0:
            return None

    if sum(limits.values()) > target_count:
        return None
    return limits


def _question_coverage_payload(question: dict[str, Any]) -> dict[str, Any]:
    coverage = {
        "topic": _clean_text(question.get("topic")),
        "prompt": _clean_subject_text(str(question.get("prompt") or "")),
        "expectedAnswer": _choice_uniqueness_key(
            str(question.get("expectedAnswer") or "")
        ),
        "choices": [
            _choice_uniqueness_key(choice) for choice in question.get("choices", [])
        ],
        "difficulty": _clamped_int(question.get("difficulty"), minimum=1, maximum=5),
    }
    for key in ("skillID", "objectiveID", "objective"):
        value = _clean_text(question.get(key))
        if value:
            coverage[key] = value
    return coverage


def _choice_set_key(choices: Any) -> str:
    if not isinstance(choices, list) or len(choices) != 4:
        return ""
    if not all(isinstance(choice, str) for choice in choices):
        return ""
    choice_keys = sorted(_choice_uniqueness_key(choice) for choice in choices)
    if any(not key for key in choice_keys):
        return ""
    return "".join(f"{len(key.encode('utf-8'))}:{key}" for key in choice_keys)


def _question_coverage_keys(expected_answer: str, topic: str) -> set[str]:
    keys: set[str] = set()
    topic_key = _choice_uniqueness_key(topic)
    answer_key = _choice_uniqueness_key(expected_answer)

    if len(topic_key) >= 3 and len(answer_key) >= 16:
        keys.add(
            f"topic-answer:{len(topic_key.encode('utf-8'))}:{topic_key}{answer_key}"
        )

    return keys


def _looks_like_generic_meta_question(
    prompt: str,
    expected_answer: str,
    choices: list[str],
    explanation: str,
) -> bool:
    if _matches_semantic_signal(expected_answer, GENERIC_META_EXPECTED_ANSWER_SIGNALS):
        return True

    generic_choice_count = sum(
        1
        for choice in choices
        if _matches_semantic_signal(
            choice,
            GENERIC_META_EXPECTED_ANSWER_SIGNALS + GENERIC_META_CHOICE_SIGNALS,
        )
    )
    if generic_choice_count >= 2:
        return True

    if _matches_semantic_signal(explanation, GENERIC_META_EXPLANATION_SIGNALS):
        return True

    normalized_prompt = _clean_text(prompt).casefold()
    has_hollow_scenario = any(
        scenario in normalized_prompt for scenario in GENERIC_META_SCENARIOS
    )
    asks_inference_from_unnamed_evidence = (
        re.search(
            r"which inference is best supported by the .+ evidence in [^?]+\?",
            normalized_prompt,
        )
        is not None
    )
    return has_hollow_scenario and asks_inference_from_unnamed_evidence


def _matches_semantic_signal(value: str, signals: tuple[str, ...]) -> bool:
    value_key = _semantic_signal_key(value)
    if not value_key:
        return False
    return any(_semantic_signal_key(signal) in value_key for signal in signals)


def _normalized_choices(raw_choices: Any, expected_answer: str) -> list[str]:
    if not isinstance(raw_choices, list):
        raw_choices = []

    if not all(isinstance(choice, str) for choice in raw_choices):
        return []
    choices = [_choice_uniqueness_key(choice) for choice in raw_choices]
    if any(not choice or len(choice) > 140 for choice in choices):
        return []
    if not expected_answer or len(expected_answer) > 140:
        return []

    if len(choices) != 4 or not _has_unambiguous_choices(choices):
        return []
    if expected_answer not in choices:
        return []
    return [expected_answer] + [
        choice for choice in choices if choice != expected_answer
    ]


def _looks_like_study_strategy(prompt: str, goal: dict[str, Any]) -> bool:
    target = " ".join(
        str(goal.get(field, "")) for field in ("title", "learningTarget", "focusAreas")
    ).lower()
    if any(
        signal in target
        for signal in (
            "study skill",
            "productivity",
            "time management",
            "focus habit",
            "habit building",
            "learning how to learn",
        )
    ):
        return False

    # Recognize explicit coaching requests, not subject-independent words such
    # as "next step", "motivation", "distraction" or "finish line". The model
    # reviewer handles less explicit relevance judgments in the goal context.
    return any(
        re.search(pattern, prompt, re.IGNORECASE)
        for pattern in (
            r"\bhow (?:should|can|could) (?:you|i|we) study\b",
            r"\b(?:your|my|our) (?:study|practice) (?:plan|schedule|strategy|routine)\b",
            r"\b(?:study|practice) (?:rep|reps|plan|schedule|strategy)\b.{0,100}\b(?:your|you|my|me|progress|prepare)\b",
            r"\bafter (?:missing|failing)\b.{0,80}\b(?:question|quiz|item|test)\b.{0,80}\b(?:study|practice|review|next)\b",
        )
    )


def _explanation_admits_bad_answer(explanation: str) -> bool:
    normalized = explanation.lower()
    blocked_phrases = [
        "answer is wrong",
        "answer is not",
        "choices do not include",
        "correct answer is not",
        "error in the prompt",
        "error in the provided choices",
        "appears to be an error",
        "closest answer",
        "not in the choices",
        "provided choices",
        "however, the correct answer",
    ]
    return any(phrase in normalized for phrase in blocked_phrases)


def _looks_like_answer_label(value: str) -> bool:
    return bool(
        re.fullmatch(
            r"(?:answer|choice|option)?\s*[\[(]?[a-dA-D][\]).:]?",
            _clean_text(value),
        )
    )


def _prompt_without_trailing_choice_echo(prompt: Any, raw_choices: Any) -> str:
    """Remove only a redundant final copy of choices; retain the stem's layout."""
    if not isinstance(prompt, str):
        return ""
    cleaned_prompt = _clean_subject_text(prompt)
    if not isinstance(raw_choices, list) or not all(
        isinstance(choice, str) for choice in raw_choices
    ):
        return cleaned_prompt
    choices = [_choice_uniqueness_key(choice) for choice in raw_choices]
    if len(choices) != 4 or any(not choice for choice in choices):
        return cleaned_prompt

    lines = cleaned_prompt.split("\n")
    nonempty_lines = [
        (index, line.strip()) for index, line in enumerate(lines) if line.strip()
    ]
    if len(nonempty_lines) <= len(choices):
        return cleaned_prompt
    trailing_lines = nonempty_lines[-len(choices) :]
    for index, ((_, line), choice) in enumerate(
        zip(trailing_lines, choices, strict=True)
    ):
        # A label must be the matching ordinal followed by whitespace. Decimal
        # literals and subject text such as C. elegans are not arbitrary labels.
        label = rf"(?:[{chr(65 + index)}{index + 1}][).:]|\([{chr(65 + index)}{index + 1}]\)|\[[{chr(65 + index)}{index + 1}]\])\s+"
        without_label = re.sub("^" + label, "", line, count=1)
        if (
            _choice_uniqueness_key(line) != choice
            and _choice_uniqueness_key(without_label) != choice
        ):
            return cleaned_prompt
    return (
        _clean_subject_text("\n".join(lines[: trailing_lines[0][0]])) or cleaned_prompt
    )


def _prompt_contains_embedded_options(prompt: str) -> bool:
    # Empty parentheses can be calls or tuple literals. Only explicit choice
    # structure is evidence here; matching trailing choice echoes are removed
    # separately using the actual offered choices.
    normalized = prompt.lower()
    return bool(
        "options:" in normalized
        or re.search(r"\b(?:option|choice)\s+[a-d1-4][\).:]", normalized)
        or re.search(r"(?:^|\s)1[\).]\s+.+\s+2[\).]\s+", prompt)
        or re.search(r"(?:^|\s)A[\).]\s+.+\s+B[\).]\s+", prompt)
    )


def _prompt_contains_latex_markup(prompt: str) -> bool:
    return "\\(" in prompt or "\\)" in prompt or "\\frac" in prompt


def _explanation_supports_different_choice(
    expected_answer: str,
    choices: list[str],
    explanation: str,
) -> bool:
    supported_choice = _explanation_supported_choice(explanation, choices)
    if not supported_choice:
        return False
    return _choice_uniqueness_key(supported_choice) != _choice_uniqueness_key(
        expected_answer
    )


def _explanation_supported_choice(explanation: str, choices: list[str]) -> str | None:
    normalized_explanation = explanation.lower()
    supported_choices: list[str] = []
    short_output_choices = {
        "positive",
        "negative",
        "zero",
        "undefined",
        "true",
        "false",
    }

    for choice in choices:
        normalized_choice = _strip_choice_label(_clean_text(choice).lower())
        if normalized_choice in short_output_choices and re.search(
            rf"\b(?:which|that|it|this|result|sign|value)\s+(?:is|are|equals?)\s+{re.escape(normalized_choice)}\b",
            normalized_explanation,
        ):
            supported_choices.append(choice)

    if any(
        cue in normalized_explanation
        for cue in ["correct", "best answer", "right answer"]
    ):
        explanation_key = _choice_uniqueness_key(explanation)
        for choice in choices:
            choice_key = _choice_uniqueness_key(choice)
            if len(choice_key) >= 12 and choice_key in explanation_key:
                supported_choices.append(choice)

    supported_keys = {_choice_uniqueness_key(choice) for choice in supported_choices}
    if len(supported_keys) != 1:
        return None

    return supported_choices[0]
