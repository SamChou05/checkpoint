"""Offline prototype: compile a closed subject–verb agreement task.

This module is deliberately not connected to the provider or question-bank
pipeline. A future route must qualify the provider grammar and propagate the
private ordinal sidecar through the existing sanitizer and final audit. The
model may choose only a scene and clause order; it supplies no learner text,
choices, key, teaching, metadata, or provenance.
"""

from dataclasses import dataclass
import json

from native_output_contracts import AuthorSlotContract


SUPPORTED_TOPIC = "Standard written English"
SUPPORTED_OBJECTIVE = "Apply subject-verb agreement or unambiguous pronoun reference"
TASK_KIND = "agreement_pair_v1"
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")


@dataclass(frozen=True)
class _Scene:
    singular_subject: str
    plural_attractor: str
    singular_object: str
    plural_subject: str
    singular_attractor: str
    plural_object: str
    first_base: str
    first_third: str
    second_base: str
    second_third: str


# Whole clause frames and inflections are reviewed code data, never model text.
# Avoid collective nouns, possessives, relative clauses, ambiguous pronouns,
# existential there, subjunctives, past tense, and register-dependent agreement.
SCENES = {
    "coach": _Scene("the coach", "the players", "the schedule",
                    "the players", "the coach", "the drills",
                    "check", "checks", "practice", "practices"),
    "librarian": _Scene("the librarian", "the volunteers", "the books",
                        "the volunteers", "the librarian", "the returns",
                        "organize", "organizes", "sort", "sorts"),
    "chef": _Scene("the chef", "the cooks", "the menu",
                   "the cooks", "the chef", "the meals",
                   "plan", "plans", "prepare", "prepares"),
    "curator": _Scene("the curator", "the assistants", "the exhibit",
                      "the assistants", "the curator", "the records",
                      "label", "labels", "catalog", "catalogs"),
}


class AgreementTaskError(ValueError):
    """The closed grammar task cannot be compiled under this pilot's rules."""


def task_schema() -> dict:
    """Small provider-facing shape for one task, not a qualified Bedrock schema."""
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "enum": [TASK_KIND]},
            "scene": {"type": "string", "enum": sorted(SCENES)},
            "order": {"type": "string", "enum": ["singular_first", "plural_first"]},
        },
        "required": ["kind", "scene", "order"],
    }


def _checked_task(task: object) -> tuple[str, str]:
    if (type(task) is not dict or set(task) != {"kind", "scene", "order"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["scene"]) is not str or task["scene"] not in SCENES
            or type(task["order"]) is not str
            or task["order"] not in {"singular_first", "plural_first"}):
        raise AgreementTaskError("Unsupported or model-extended agreement task.")
    return task["scene"], task["order"]


def _clause(subject: str, attractor: str, obj: str) -> str:
    return f"{subject[0].upper()}{subject[1:]} near {attractor} ___ {obj}"


def compile_question(task: dict, *, ordinal: int) -> dict:
    """Return exactly five code-owned learner fields for original slot 3 or 4."""
    scene_id, order = _checked_task(task)
    if type(ordinal) is not int or ordinal not in {3, 4}:
        raise AgreementTaskError("Agreement pilot supports original slots 3 and 4 only.")
    scene = SCENES[scene_id]
    singular = (_clause(scene.singular_subject, scene.plural_attractor, scene.singular_object),
                scene.first_base, scene.first_third, scene.singular_subject,
                scene.plural_attractor)
    plural = (_clause(scene.plural_subject, scene.singular_attractor, scene.plural_object),
              scene.second_base, scene.second_third, scene.plural_subject,
              scene.singular_attractor)
    clauses = (singular, plural) if order == "singular_first" else (plural, singular)
    prompt = ("Fill both blanks with the present-tense verb forms that agree with "
              "the subjects in standard written American English. "
              f"{clauses[0][0]}, while {clauses[1][0].lower()}. "
              "Which ordered pair fills the blanks?")
    # False/True indexes choose the bare or third-person singular form for each
    # clause. The Cartesian product has four different ordered commitments.
    pairs = [(False, False), (False, True), (True, False), (True, True)]
    pairs = pairs[ordinal % 4:] + pairs[:ordinal % 4]

    def form(clause: tuple, third_person: bool) -> str:
        return clause[2] if third_person else clause[1]

    choices = [f"{form(clauses[0], first)}; {form(clauses[1], second)}"
               for first, second in pairs]
    correct_flags = tuple(clause is singular for clause in clauses)
    correct_index = pairs.index(correct_flags)
    answer = choices[correct_index]

    def reason(clause: tuple, selected_third: bool, position: str) -> str:
        should_be_third = clause is singular
        head, attractor = clause[3], clause[4]
        correct_form = form(clause, should_be_third)
        selected_form = form(clause, selected_third)
        number = "singular" if should_be_third else "plural"
        judgment = (f'The form "{selected_form}" agrees.'
                    if selected_third == should_be_third else
                    f'"{selected_form}" does not agree; use "{correct_form}".')
        return (f'The {position} head subject "{head}" is {number}; '
                f'"near {attractor}" does not change that. {judgment}')

    explanation = (reason(clauses[0], correct_flags[0], "first") + " "
                   + reason(clauses[1], correct_flags[1], "second")
                   + f" Therefore the ordered pair is {answer}.")
    feedback = {
        choice: (reason(clauses[0], flags[0], "first") + " "
                 + reason(clauses[1], flags[1], "second"))
        for choice, flags in zip(choices, pairs, strict=True)
    }
    if len(set(choices)) != 4 or list(feedback) != choices:
        raise AgreementTaskError("Agreement choices are not exactly distinct.")
    if len(prompt) > 320 or len(explanation) > 420 or any(len(text) > 280 for text in feedback.values()):
        raise AgreementTaskError("Compiled agreement teaching exceeds learner text limits.")
    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": explanation, "choiceExplanations": feedback}


@dataclass(frozen=True)
class CompiledAgreementCandidate:
    """Original slot and trusted assignment survive independently of raw text."""

    ordinal: int
    task_json: str
    assignment: tuple[str, str, str, str, int]
    learner_json: str

    def content(self, question: dict | None = None) -> dict:
        rendered = compile_question(json.loads(self.task_json), ordinal=self.ordinal)
        if rendered != json.loads(self.learner_json):
            raise AgreementTaskError("Agreement provenance changed.")
        metadata = {"topic": self.assignment[2], "skillID": self.assignment[0],
                    "objectiveID": self.assignment[1], "objective": self.assignment[3],
                    "difficulty": 2, "format": "Multiple Choice"}
        result = {**rendered, **metadata}
        if (question is not None
                and (type(question) is not dict or set(question) != set(result)
                     or any(question[key] != value for key, value in result.items()))):
            raise AgreementTaskError("Compiled agreement content or assignment changed.")
        return result


def compile_mapped_english_slots(tasks_by_slot: dict, contract: AuthorSlotContract) -> dict[int, CompiledAgreementCandidate]:
    """Bind complete original English slots of this exact 3:2 pilot, no top-ups."""
    if (type(contract) is not AuthorSlotContract or contract.count != 5
            or contract.mode != "constructed_quantitative"
            or contract.mapped_assignments is None
            or [assignment[4] for assignment in contract.mapped_assignments] != [3, 2]
            or contract.mapped_quantitative_difficulty != 2
            or contract.mapped_assignments[1][2] != SUPPORTED_TOPIC
            or contract.mapped_assignments[1][3] != SUPPORTED_OBJECTIVE):
        raise AgreementTaskError("Trusted mapped assignment is outside the agreement pilot.")
    if type(tasks_by_slot) is not dict or set(tasks_by_slot) != {"3", "4"}:
        raise AgreementTaskError("Both original English slots must be present.")
    scenes = [_checked_task(tasks_by_slot[str(slot)])[0] for slot in (3, 4)]
    if len(set(scenes)) != 2:
        raise AgreementTaskError("The two English slots must use different scenes.")
    assignment = contract.mapped_assignments[1]
    candidates = {}
    for slot in (3, 4):
        task = tasks_by_slot[str(slot)]
        learner = compile_question(task, ordinal=slot)
        candidate = CompiledAgreementCandidate(
            slot, json.dumps(task, sort_keys=True, separators=(",", ":")), assignment,
            json.dumps(learner, sort_keys=True, separators=(",", ":")),
        )
        candidate.content()
        candidates[slot] = candidate
    return candidates
