"""Request decoding, normalization, and shared validation helpers."""

import base64
import binascii
import json
import logging
import math
import os
import re
import uuid
from typing import Any

import question_bank
from service_errors import BadRequestError


LOGGER = logging.getLogger("lambda_function")

DEFAULT_MAX_QUESTIONS = 20
DEFAULT_MAX_REQUEST_BODY_BYTES = 128 * 1024
MAX_SOURCE_DOCUMENTS = 5
MAX_SOURCE_DOCUMENT_NAME_CHARS = 160
MAX_SOURCE_DOCUMENT_CHARS = 24_000
MAX_SOURCE_CONTEXT_CHARS = 24_000
MAX_SKILL_MAP_SKILLS = 6
MAX_SKILL_OBJECTIVES = 5
MAX_SKILL_NAME_CHARS = 48
MAX_OBJECTIVE_NAME_CHARS = 80
MAX_SKILL_ALLOCATION_WEIGHT = 100
UNSUPPORTED_SKILL_NAME_SEPARATORS = frozenset(",;")
SKILL_MAP_ID_PREFIX = "checkpoint:skill-map:v1"
SOURCE_TRUNCATION_MARKER = "\n\n[... source truncated ...]\n\n"


def _decode_body(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body")
    if body is None:
        raise BadRequestError("Missing JSON body.")

    try:
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(body, validate=True)
        elif isinstance(body, str):
            raw_body = body.encode("utf-8")
        elif isinstance(body, bytes):
            raw_body = body
        else:
            raise BadRequestError("Body must be JSON text.")
    except (binascii.Error, UnicodeEncodeError, ValueError) as error:
        raise BadRequestError("Body encoding is invalid.") from error

    maximum_body_bytes = _int_env(
        "MAX_REQUEST_BODY_BYTES",
        DEFAULT_MAX_REQUEST_BODY_BYTES,
        maximum=1024 * 1024,
    )
    if len(raw_body) > maximum_body_bytes:
        raise BadRequestError(f"Body exceeds the {maximum_body_bytes}-byte limit.")

    try:
        body_text = raw_body.decode("utf-8")
    except UnicodeDecodeError as error:
        raise BadRequestError("Body must be UTF-8 JSON.") from error

    try:
        payload = json.loads(body_text)
    except json.JSONDecodeError as error:
        raise BadRequestError("Body must be valid JSON.") from error

    if not isinstance(payload, dict):
        raise BadRequestError("Body must be a JSON object.")

    return payload


def _normalize_skill_map_inference_request(payload: dict[str, Any]) -> dict[str, Any]:
    goal = payload.get("goal")
    if not isinstance(goal, dict):
        raise BadRequestError("Missing goal object.")

    title = _validated_text(goal.get("title"), "goal.title", 200)
    learning_target = (
        _validated_text(
            goal.get("learningTarget"),
            "goal.learningTarget",
            240,
        )
        or title
    )
    if not learning_target:
        raise BadRequestError("Missing goal learningTarget.")

    content_topics = goal.get("contentTopics") or []
    if not isinstance(content_topics, list):
        raise BadRequestError("goal.contentTopics must be an array.")
    normalized_topics = _validated_string_list(
        content_topics,
        "goal.contentTopics",
        maximum_items=8,
        maximum_characters=80,
    )

    suggested_value = payload.get("suggestedSkills")
    nested_suggested_value = goal.get("suggestedSkills")
    if suggested_value is not None and nested_suggested_value is not None:
        raise BadRequestError(
            "Supply suggestedSkills either at the top level or inside goal, not both."
        )
    if suggested_value is None:
        suggested_value = nested_suggested_value
    if suggested_value is None:
        suggested_value = []
    if not isinstance(suggested_value, list):
        raise BadRequestError("suggestedSkills must be an array.")
    if len(suggested_value) > MAX_SKILL_MAP_SKILLS:
        raise BadRequestError(
            f"suggestedSkills exceeds the {MAX_SKILL_MAP_SKILLS}-skill limit."
        )
    suggested_skills = _validated_string_list(
        suggested_value,
        "suggestedSkills",
        maximum_items=MAX_SKILL_MAP_SKILLS,
        maximum_characters=MAX_SKILL_NAME_CHARS,
    )
    for index, name in enumerate(suggested_skills):
        if _has_unsupported_skill_name_separator(name):
            raise BadRequestError(
                f"suggestedSkills[{index}] must not contain commas or semicolons."
            )
    suggested_keys = [_canonical(name) for name in suggested_skills]
    if len(set(suggested_keys)) != len(suggested_keys):
        raise BadRequestError("suggestedSkills must contain distinct names.")

    return {
        "goal": {
            "title": title,
            "category": _validated_text(goal.get("category"), "goal.category", 80),
            "focusAreas": _validated_text(
                goal.get("focusAreas"),
                "goal.focusAreas",
                1_000,
            ),
            "currentLevel": _validated_text(
                goal.get("currentLevel"),
                "goal.currentLevel",
                200,
            ),
            "learningTarget": learning_target,
            "contentTopics": normalized_topics,
            "questionDirective": _validated_text(
                goal.get("questionDirective"),
                "goal.questionDirective",
                1_000,
            ),
        },
        "suggestedSkills": suggested_skills,
        "competencies": _normalized_competencies(payload.get("competencies")),
        "sourceDocuments": _normalized_source_documents(payload.get("sourceDocuments")),
    }


def _normalize_request(payload: dict[str, Any]) -> dict[str, Any]:
    goal = payload.get("goal")
    if not isinstance(goal, dict):
        raise BadRequestError("Missing goal object.")

    target_count = _clamped_int(
        payload.get("targetCount"), minimum=1, maximum=_max_questions()
    )
    minimum_difficulty = _clamped_int(
        payload.get("minimumDifficulty"), minimum=1, maximum=5
    )

    title = _validated_text(goal.get("title"), "goal.title", 200)
    learning_target = (
        _validated_text(
            goal.get("learningTarget"),
            "goal.learningTarget",
            240,
        )
        or title
    )
    if not learning_target:
        raise BadRequestError("Missing goal learningTarget.")

    focus_areas = _validated_text(goal.get("focusAreas"), "goal.focusAreas", 1_000)
    skill_map = _normalized_supplied_skill_map(payload.get("skillMap"))
    desired_skill_allocation = _normalized_desired_skill_allocation(
        payload.get("desiredSkillAllocation"),
        skill_map,
    )
    content_topics = goal.get("contentTopics") or []
    if not isinstance(content_topics, list):
        raise BadRequestError("goal.contentTopics must be an array.")

    normalized_topics = _validated_string_list(
        content_topics,
        "goal.contentTopics",
        maximum_items=8,
        maximum_characters=80,
    )
    if skill_map:
        normalized_topics = [skill["name"] for skill in skill_map["skills"]]
    elif not normalized_topics:
        normalized_topics = _topics_from_focus(goal.get("focusAreas"))
    needs_skill_map_value = goal.get("needsSkillMap", False)
    if not isinstance(needs_skill_map_value, bool):
        raise BadRequestError("goal.needsSkillMap must be a boolean.")
    needs_skill_map = not skill_map and (
        needs_skill_map_value
        or _topics_need_inference(normalized_topics, learning_target, title)
    )

    normalized_request = {
        "goal": {
            "title": title,
            "category": _validated_text(goal.get("category"), "goal.category", 80),
            "focusAreas": focus_areas,
            "currentLevel": _validated_text(
                goal.get("currentLevel"),
                "goal.currentLevel",
                200,
            ),
            "learningTarget": learning_target,
            "contentTopics": normalized_topics or [learning_target],
            "questionDirective": _validated_text(
                goal.get("questionDirective"),
                "goal.questionDirective",
                1_000,
            ),
            "needsSkillMap": needs_skill_map,
            "preferredQuestionStyle": "Multiple Choice",
        },
        "competencies": _normalized_competencies(payload.get("competencies")),
        "existingPrompts": _validated_string_list(
            payload.get("existingPrompts"),
            "existingPrompts",
            maximum_items=30,
            maximum_characters=360,
        ),
        "existingQuestionCoverage": _list_of_question_coverage(
            payload.get("existingQuestionCoverage")
        ),
        "reportedPrompts": _validated_string_list(
            payload.get("reportedPrompts"),
            "reportedPrompts",
            maximum_items=30,
            maximum_characters=360,
        ),
        "sourceDocuments": _normalized_source_documents(payload.get("sourceDocuments")),
        "targetCount": target_count,
        "minimumDifficulty": minimum_difficulty,
        "difficultyGuidance": _validated_text(
            payload.get("difficultyGuidance"),
            "difficultyGuidance",
            500,
        )
        or _difficulty_guidance(minimum_difficulty),
    }
    if skill_map:
        normalized_request["skillMap"] = skill_map
        normalized_request["desiredSkillAllocation"] = desired_skill_allocation
        normalized_request["requestedSkillAllocation"] = _apportion_skill_allocation(
            [skill["id"] for skill in skill_map["skills"]],
            desired_skill_allocation,
            target_count,
        )
    return normalized_request


def _normalized_supplied_skill_map(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise BadRequestError("skillMap must be an object.")
    version = value.get("version")
    if (
        isinstance(version, bool)
        or not isinstance(version, int)
        or not 1 <= version <= 1_000_000
    ):
        raise BadRequestError("skillMap.version must be a positive integer.")
    raw_skills = value.get("skills")
    if not isinstance(raw_skills, list):
        raise BadRequestError("skillMap.skills must be an array.")
    if not 1 <= len(raw_skills) <= MAX_SKILL_MAP_SKILLS:
        raise BadRequestError(
            f"skillMap.skills must contain 1 to {MAX_SKILL_MAP_SKILLS} skills."
        )

    skills: list[dict[str, Any]] = []
    seen_skill_ids: set[str] = set()
    seen_skill_names: set[str] = set()
    seen_objective_ids: set[str] = set()
    for skill_index, raw_skill in enumerate(raw_skills):
        if not isinstance(raw_skill, dict):
            raise BadRequestError(f"skillMap.skills[{skill_index}] must be an object.")
        skill_id = _validated_uuid(
            raw_skill.get("id"),
            f"skillMap.skills[{skill_index}].id",
        )
        skill_name_field = f"skillMap.skills[{skill_index}].name"
        name = _validated_text(
            raw_skill.get("name"),
            skill_name_field,
            MAX_SKILL_NAME_CHARS,
        )
        if not name:
            raise BadRequestError(f"{skill_name_field} must not be empty.")
        if _has_unsupported_skill_name_separator(name):
            raise BadRequestError(
                f"{skill_name_field} must not contain commas or semicolons."
            )
        name_key = _canonical(name)
        skill_id_key = _uuid_key(skill_id)
        if skill_id_key in seen_skill_ids or name_key in seen_skill_names:
            raise BadRequestError("skillMap skills must have distinct IDs and names.")

        raw_objectives = raw_skill.get("objectives")
        if not isinstance(raw_objectives, list):
            raise BadRequestError(
                f"skillMap.skills[{skill_index}].objectives must be an array."
            )
        if not 0 <= len(raw_objectives) <= MAX_SKILL_OBJECTIVES:
            raise BadRequestError(
                f"skillMap.skills[{skill_index}].objectives must contain 0 to "
                f"{MAX_SKILL_OBJECTIVES} objectives."
            )

        objectives: list[dict[str, str]] = []
        seen_names_for_skill: set[str] = set()
        for objective_index, raw_objective in enumerate(raw_objectives):
            field = f"skillMap.skills[{skill_index}].objectives[{objective_index}]"
            if not isinstance(raw_objective, dict):
                raise BadRequestError(f"{field} must be an object.")
            objective_id = _validated_uuid(raw_objective.get("id"), f"{field}.id")
            objective_name = _validated_text(
                raw_objective.get("name"),
                f"{field}.name",
                MAX_OBJECTIVE_NAME_CHARS,
            )
            if not objective_name:
                raise BadRequestError(f"{field}.name must not be empty.")
            objective_name_key = _canonical(objective_name)
            objective_id_key = _uuid_key(objective_id)
            if (
                objective_id_key in seen_objective_ids
                or objective_name_key in seen_names_for_skill
            ):
                raise BadRequestError(
                    "skillMap objectives must have distinct IDs and names within each skill."
                )
            seen_objective_ids.add(objective_id_key)
            seen_names_for_skill.add(objective_name_key)
            objectives.append({"id": objective_id, "name": objective_name})

        seen_skill_ids.add(skill_id_key)
        seen_skill_names.add(name_key)
        skills.append({"id": skill_id, "name": name, "objectives": objectives})

    return {"version": version, "skills": skills}


def _normalized_desired_skill_allocation(
    value: Any,
    skill_map: dict[str, Any] | None,
) -> dict[str, int]:
    if value is None:
        return {}
    if not skill_map:
        raise BadRequestError("desiredSkillAllocation requires skillMap.")

    raw_entries: list[tuple[Any, Any, str]] = []
    if isinstance(value, dict):
        raw_entries = [
            (skill_id, count, f"desiredSkillAllocation.{skill_id}")
            for skill_id, count in value.items()
        ]
    elif isinstance(value, list):
        for index, item in enumerate(value):
            if not isinstance(item, dict):
                raise BadRequestError(
                    f"desiredSkillAllocation[{index}] must be an object."
                )
            raw_entries.append(
                (
                    item.get("skillID"),
                    item.get("count"),
                    f"desiredSkillAllocation[{index}]",
                )
            )
    else:
        raise BadRequestError("desiredSkillAllocation must be an array or object.")

    if len(raw_entries) > len(skill_map["skills"]):
        raise BadRequestError("desiredSkillAllocation contains too many entries.")
    valid_skill_ids = {
        _uuid_key(skill["id"]): skill["id"] for skill in skill_map["skills"]
    }
    allocation: dict[str, int] = {}
    for raw_skill_id, raw_count, field in raw_entries:
        skill_id = _validated_uuid(raw_skill_id, f"{field}.skillID")
        skill_id_key = _uuid_key(skill_id)
        if skill_id_key not in valid_skill_ids:
            raise BadRequestError(
                f"{field}.skillID does not belong to the supplied skillMap."
            )
        resolved_skill_id = valid_skill_ids[skill_id_key]
        if resolved_skill_id in allocation:
            raise BadRequestError(
                "desiredSkillAllocation contains a duplicate skillID."
            )
        if (
            isinstance(raw_count, bool)
            or not isinstance(raw_count, int)
            or not 0 <= raw_count <= MAX_SKILL_ALLOCATION_WEIGHT
        ):
            raise BadRequestError(
                f"{field}.count must be an integer from 0 to "
                f"{MAX_SKILL_ALLOCATION_WEIGHT}."
            )
        allocation[resolved_skill_id] = raw_count
    if allocation and not any(allocation.values()):
        raise BadRequestError(
            "desiredSkillAllocation must request at least one question."
        )
    return allocation


def _validated_uuid(value: Any, field_name: str) -> str:
    if not isinstance(value, str):
        raise BadRequestError(f"{field_name} must be a UUID string.")
    try:
        uuid.UUID(value)
    except (ValueError, AttributeError) as error:
        raise BadRequestError(f"{field_name} must be a UUID string.") from error
    return value.strip()


def _uuid_key(value: str) -> str:
    return str(uuid.UUID(value))


def _deterministic_skill_id(name: str) -> str:
    return str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            f"{SKILL_MAP_ID_PREFIX}:skill:{_canonical(name)}",
        )
    )


def _deterministic_objective_id(skill_id: str, name: str) -> str:
    return str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            (
                f"{SKILL_MAP_ID_PREFIX}:objective:"
                f"{_uuid_key(skill_id)}:{_canonical(name)}"
            ),
        )
    )


def _apportion_skill_allocation(
    skill_ids: list[str],
    desired_allocation: dict[str, int],
    total_count: int,
) -> dict[str, int]:
    counts = question_bank._apportion_skill_counts(
        skill_ids,
        desired_allocation,
        total_count,
    )
    return {skill_id: count for skill_id, count in counts.items() if count > 0}


def _normalized_source_documents(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise BadRequestError("sourceDocuments must be an array.")
    if len(value) > MAX_SOURCE_DOCUMENTS:
        raise BadRequestError(
            f"sourceDocuments exceeds the {MAX_SOURCE_DOCUMENTS}-document limit."
        )

    documents: list[dict[str, str]] = []
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise BadRequestError(f"sourceDocuments[{index}] must be an object.")

        name = (
            _validated_text(
                item.get("name"),
                f"sourceDocuments[{index}].name",
                MAX_SOURCE_DOCUMENT_NAME_CHARS,
            )
            or f"Source {index + 1}"
        )
        raw_text = item.get("text")
        if not isinstance(raw_text, str):
            raise BadRequestError(f"sourceDocuments[{index}].text must be text.")
        cleaned_text = _clean_source_text(raw_text)
        if not cleaned_text:
            raise BadRequestError(f"sourceDocuments[{index}].text must not be empty.")

        documents.append({"name": name, "text": cleaned_text})

    character_limits = _source_context_character_limits(documents)
    normalized: list[dict[str, Any]] = []
    for document, character_limit in zip(documents, character_limits, strict=True):
        text = _truncate_source_text(document["text"], character_limit)
        normalized.append(
            {
                "name": document["name"],
                "text": text,
                "truncated": len(text) < len(document["text"]),
            }
        )

    return normalized


def _source_context_character_limits(documents: list[dict[str, str]]) -> list[int]:
    capacities = [
        min(len(document["text"]), MAX_SOURCE_DOCUMENT_CHARS) for document in documents
    ]
    allocations = [0] * len(documents)
    remaining_characters = MAX_SOURCE_CONTEXT_CHARS
    unallocated_indexes = list(range(len(documents)))

    while unallocated_indexes and remaining_characters > 0:
        fair_share = remaining_characters // len(unallocated_indexes)
        constrained_indexes = [
            index for index in unallocated_indexes if capacities[index] <= fair_share
        ]
        if constrained_indexes:
            for index in constrained_indexes:
                allocations[index] = capacities[index]
                remaining_characters -= capacities[index]
            constrained = set(constrained_indexes)
            unallocated_indexes = [
                index for index in unallocated_indexes if index not in constrained
            ]
            continue

        for index in unallocated_indexes:
            allocations[index] = fair_share
            remaining_characters -= fair_share
        for index in unallocated_indexes:
            if remaining_characters <= 0:
                break
            if allocations[index] < capacities[index]:
                allocations[index] += 1
                remaining_characters -= 1
        break

    return allocations


def _clean_source_text(value: str) -> str:
    normalized_newlines = value.replace("\r\n", "\n").replace("\r", "\n")
    printable_text = "".join(
        character if character == "\n" or character.isprintable() else " "
        for character in normalized_newlines
    )

    lines: list[str] = []
    for raw_line in printable_text.split("\n"):
        line = " ".join(raw_line.split()).strip()
        if line:
            lines.append(line)
        elif lines and lines[-1] != "":
            lines.append("")

    return "\n".join(lines).strip()


def _truncate_source_text(value: str, maximum_characters: int) -> str:
    if len(value) <= maximum_characters:
        return value
    if maximum_characters <= (2 * len(SOURCE_TRUNCATION_MARKER)) + 3:
        return _clip(value, maximum_characters)

    available_characters = maximum_characters - (2 * len(SOURCE_TRUNCATION_MARKER))
    leading_characters = math.ceil(available_characters / 3)
    middle_characters = math.ceil((available_characters - leading_characters) / 2)
    trailing_characters = available_characters - leading_characters - middle_characters
    middle_start = max(0, (len(value) - middle_characters) // 2)
    leading_text = value[:leading_characters].rstrip()
    middle_text = value[middle_start : middle_start + middle_characters].strip()
    trailing_text = value[-trailing_characters:].lstrip()
    return (
        f"{leading_text}{SOURCE_TRUNCATION_MARKER}"
        f"{middle_text}{SOURCE_TRUNCATION_MARKER}{trailing_text}"
    )


def _topics_need_inference(topics: list[str], learning_target: str, title: str) -> bool:
    if not topics:
        return True
    if len(topics) != 1:
        return False

    topic_key = _canonical(topics[0])
    return topic_key in {_canonical(learning_target), _canonical(title)}


def _topics_from_focus(value: Any) -> list[str]:
    if not isinstance(value, str):
        return []

    topics = []
    seen = set()
    for part in re.split(r"[,;\n]+", value):
        topic = _clip(_clean_text(part), 80)
        key = _canonical(topic)
        if key and key not in seen:
            seen.add(key)
            topics.append(topic)
        if len(topics) >= 8:
            break
    return topics


def _difficulty_guidance(level: int) -> str:
    if level <= 1:
        return "Foundations: direct recognition, definitions, single-step facts, and gentle distractors."
    if level == 2:
        return "Easy application: one concept in a familiar context with light reasoning and clear distractors."
    if level == 3:
        return "Medium application: apply concepts to a short scenario with qualifiers and plausible distractors."
    if level == 4:
        return "Hard reasoning: use multi-step logic, edge cases, constraints, counterexamples, or nuanced distractors."
    return "Expert synthesis: combine multiple concepts in a dense exam-style scenario with subtle traps."


def _normalized_competencies(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise BadRequestError("competencies must be an array.")

    competencies = []
    for index, item in enumerate(value[:20]):
        if not isinstance(item, dict):
            raise BadRequestError(f"competencies[{index}] must be an object.")
        competency: dict[str, Any] = {
            "topic": _validated_text(
                item.get("topic"), f"competencies[{index}].topic", 80
            ),
        }
        for key, minimum, maximum in [
            ("estimatedLevel", 0, 5),
            ("masteryPercent", 0, 100),
            ("attempts", 0, 1_000_000),
            ("correct", 0, 1_000_000),
            ("partial", 0, 1_000_000),
            ("incorrect", 0, 1_000_000),
        ]:
            raw_value = item.get(key)
            if isinstance(raw_value, (int, float)) and not isinstance(raw_value, bool):
                competency[key] = max(minimum, min(maximum, raw_value))
        competencies.append(competency)
    return competencies


def _list_of_question_coverage(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise BadRequestError("existingQuestionCoverage must be an array.")

    coverage: list[dict[str, Any]] = []
    for index, item in enumerate(value[:30]):
        if not isinstance(item, dict):
            raise BadRequestError(
                f"existingQuestionCoverage[{index}] must be an object."
            )
        prompt = _validated_text(
            item.get("prompt"),
            f"existingQuestionCoverage[{index}].prompt",
            360,
        )
        expected_answer = _validated_text(
            item.get("expectedAnswer"),
            f"existingQuestionCoverage[{index}].expectedAnswer",
            280,
        )
        topic = _validated_text(
            item.get("topic"),
            f"existingQuestionCoverage[{index}].topic",
            80,
        )
        choices = _validated_string_list(
            item.get("choices"),
            f"existingQuestionCoverage[{index}].choices",
            maximum_items=4,
            maximum_characters=140,
        )
        difficulty = _clamped_int(item.get("difficulty"), minimum=1, maximum=5)

        if prompt or expected_answer or topic:
            normalized_item = {
                "topic": topic,
                "prompt": prompt,
                "expectedAnswer": expected_answer,
                "choices": choices,
                "difficulty": difficulty,
            }
            for key in ("skillID", "objectiveID"):
                raw_identifier = item.get(key)
                if raw_identifier is not None:
                    normalized_item[key] = _validated_uuid(
                        raw_identifier,
                        f"existingQuestionCoverage[{index}].{key}",
                    )
            objective = _validated_text(
                item.get("objective", item.get("objectiveName")),
                f"existingQuestionCoverage[{index}].objective",
                MAX_OBJECTIVE_NAME_CHARS,
            )
            if objective:
                normalized_item["objective"] = objective
            coverage.append(normalized_item)

    return coverage


def _validated_text(value: Any, field_name: str, maximum_characters: int) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise BadRequestError(f"{field_name} must be text.")
    cleaned = _clean_text(value)
    if len(cleaned) > maximum_characters:
        raise BadRequestError(
            f"{field_name} exceeds the {maximum_characters}-character limit."
        )
    return cleaned


def _validated_string_list(
    value: Any,
    field_name: str,
    maximum_items: int,
    maximum_characters: int,
) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise BadRequestError(f"{field_name} must be an array.")

    strings = []
    for index, item in enumerate(value[:maximum_items]):
        cleaned = _validated_text(
            item,
            f"{field_name}[{index}]",
            maximum_characters,
        )
        if cleaned:
            strings.append(cleaned)
    return strings


def _clean_text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).split()).strip()


def _canonical(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def _has_unsupported_skill_name_separator(value: str) -> bool:
    return any(separator in value for separator in UNSUPPORTED_SKILL_NAME_SEPARATORS)


def _duplicate_prompt_key(prompt: str) -> str:
    quoted_parts = [
        part
        for match in re.findall(r"'([^']+)'|\"([^\"]+)\"", prompt)
        for part in match
        if len(_canonical(part)) >= 16
    ]
    if quoted_parts:
        quoted = max(quoted_parts, key=lambda part: len(_canonical(part)))
        return f"quoted:{_canonical(quoted)}"

    normalized = _clean_text(prompt).lower()
    normalized = re.sub(
        r"^(?:choose|select|which|what|identify|pick)\b.*?\b(?:sentence|question|example|option)\b[: ]+",
        "",
        normalized,
    )
    return _canonical(normalized)


def _choice_uniqueness_key(value: str) -> str:
    normalized = _strip_answer_prefix(_clean_text(value).lower())
    normalized = _strip_choice_label(normalized)
    return _canonical(normalized)


def _strip_answer_prefix(value: str) -> str:
    for prefix in [
        "correct answer",
        "correct choice",
        "correct option",
        "answer",
        "choice",
        "option",
    ]:
        if value.startswith(prefix):
            remainder = value[len(prefix) :].strip(" \t\n:-.")
            if remainder:
                return remainder
    return value


def _strip_choice_label(value: str) -> str:
    return re.sub(
        r"^\s*(?:[\[(]?[abcd1234][\]).:]|\b[abcd1234][\).:])\s*", "", value, count=1
    )


def _clip(value: str, limit: int) -> str:
    return value[:limit].strip()


def _clamped_int(value: Any, minimum: int, maximum: int) -> int:
    try:
        integer = int(value)
    except (TypeError, ValueError):
        integer = minimum
    return max(minimum, min(maximum, integer))


def _max_questions() -> int:
    raw_value = os.getenv("MAX_QUESTIONS_PER_BATCH")
    if not raw_value:
        return DEFAULT_MAX_QUESTIONS
    return _clamped_int(raw_value, minimum=1, maximum=40)


def _int_env(key: str, default: int, maximum: int = 20000) -> int:
    return (
        _clamped_int(os.getenv(key), minimum=1, maximum=maximum)
        if os.getenv(key)
        else default
    )


def _float_env(key: str, default: float) -> float:
    try:
        return float(os.getenv(key, ""))
    except ValueError:
        return default


def _bounded_float_env(
    key: str,
    default: float,
    minimum: float,
    maximum: float,
) -> float:
    return max(minimum, min(maximum, _float_env(key, default)))


def _bool_env(key: str, default: bool) -> bool:
    raw_value = os.getenv(key)
    if raw_value is None:
        return default

    return raw_value.strip().lower() in {"1", "true", "yes", "y", "on"}


def _nonnegative_int(value: Any) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0


def _deployment_environment() -> str:
    return os.getenv("DEPLOYMENT_ENVIRONMENT", "development").strip().lower()


def _is_development_environment() -> bool:
    return _deployment_environment() in {"development", "dev", "local", "test"}


def _is_production_environment() -> bool:
    return _deployment_environment() in {"production", "prod"}


def _rate_limiting_required() -> bool:
    return _is_production_environment() or _bool_env("REQUIRE_RATE_LIMITING", False)


def _service_mode() -> str:
    mode = os.getenv("SERVICE_MODE", "enabled").strip().lower()
    if mode in {"enabled", "drain", "disabled"}:
        return mode
    LOGGER.error("Invalid SERVICE_MODE; failing closed")
    return "disabled"
