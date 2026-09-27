"""Closed subject–verb agreement tasks for an exact-scope opt-in route.

The model may choose only a scene and clause order; it supplies no learner text,
choices, key, teaching, metadata, or provenance. Provider acceptance and live
quality of the opt-in route require separate qualification.
"""

from dataclasses import dataclass
import json

from native_output_contracts import AuthorSlotContract
from question_bank_common import _normalized_stem_identity, _stem_fingerprint


SUPPORTED_TOPIC = "Standard written English"
SUPPORTED_OBJECTIVE = "Apply subject-verb agreement or unambiguous pronoun reference"
TASK_KIND = "agreement_pair_v1"
COMPOUND_SCENE = "compound_every"
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


@dataclass(frozen=True)
class _CompoundScene:
    compound_subject: str
    singular_attractor: str
    compound_object: str
    distributive_subject: str
    plural_attractor: str
    distributive_object: str
    compound_base: str
    compound_third: str
    distributive_base: str
    distributive_third: str


@dataclass(frozen=True)
class _Clause:
    text: str
    base: str
    third: str
    correct_third: bool
    subject: str
    attractor: str | None = None
    rule: str = "near"


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
COMPOUND_SCENES = {
    COMPOUND_SCENE: _CompoundScene(
        "Maya and Theo", "the cook", "lunch", "Every guest", "the servers", "a plate",
        "prepare", "prepares", "receive", "receives",
    ),
    "compound_guides": _CompoundScene(
        "Nora and Eli", "the guide", "the maps", "Every guide", "the hikers", "a badge",
        "fold", "folds", "wear", "wears",
    ),
    "compound_visitors": _CompoundScene(
        "Leah and Omar", "the visitor", "the doors", "Every visitor", "the guides", "a ticket",
        "close", "closes", "hold", "holds",
    ),
    "compound_clerks": _CompoundScene(
        "Ava and Ben", "the clerk", "the forms", "Every clerk", "the visitors", "a copy",
        "review", "reviews", "keep", "keeps",
    ),
}


class AgreementTaskError(ValueError):
    """The closed grammar task cannot be compiled under this pilot's rules."""


def task_schema() -> dict:
    """Small provider-facing shape for one task, not a qualified Bedrock schema."""
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "enum": [TASK_KIND]},
            "scene": {"type": "string", "enum": sorted((*SCENES, *COMPOUND_SCENES))},
            "order": {"type": "string", "enum": ["singular_first", "plural_first"]},
        },
        "required": ["kind", "scene", "order"],
    }


def _checked_task(task: object) -> tuple[str, str]:
    if (type(task) is not dict or set(task) != {"kind", "scene", "order"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["scene"]) is not str or task["scene"] not in {*SCENES, *COMPOUND_SCENES}
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
    if scene_id in COMPOUND_SCENES:
        scene = COMPOUND_SCENES[scene_id]
        first = _Clause(
            _clause(scene.compound_subject, scene.singular_attractor, scene.compound_object),
            scene.compound_base, scene.compound_third, False,
            scene.compound_subject, scene.singular_attractor, rule="compound",
        )
        second = _Clause(
            _clause(scene.distributive_subject, scene.plural_attractor, scene.distributive_object),
            scene.distributive_base, scene.distributive_third, True,
            scene.distributive_subject, scene.plural_attractor, rule="every",
        )
    else:
        scene = SCENES[scene_id]
        first = _Clause(
            _clause(scene.singular_subject, scene.plural_attractor, scene.singular_object),
            scene.first_base, scene.first_third, True,
            scene.singular_subject, scene.plural_attractor,
        )
        second = _Clause(
            _clause(scene.plural_subject, scene.singular_attractor, scene.plural_object),
            scene.second_base, scene.second_third, False,
            scene.plural_subject, scene.singular_attractor,
        )
    clauses = (first, second) if order == "singular_first" else (second, first)
    following = clauses[1].text
    if following.startswith(("The ", "Every ")):
        following = following[0].lower() + following[1:]
    prompt = ("Fill both blanks with the present-tense verb forms that agree with "
              "the subjects in standard written American English. "
              f"{clauses[0].text}, while {following}. "
              "Which ordered pair fills the blanks?")
    # False/True indexes choose the bare or third-person singular form for each
    # clause. The Cartesian product has four different ordered commitments.
    pairs = [(False, False), (False, True), (True, False), (True, True)]
    pairs = pairs[ordinal % 4:] + pairs[:ordinal % 4]

    def form(clause: _Clause, third_person: bool) -> str:
        return clause.third if third_person else clause.base

    choices = [f"{form(clauses[0], first)}; {form(clauses[1], second)}"
               for first, second in pairs]
    correct_flags = tuple(clause.correct_third for clause in clauses)
    correct_index = pairs.index(correct_flags)
    answer = choices[correct_index]

    def reason(clause: _Clause, selected_third: bool, position: str) -> str:
        should_be_third = clause.correct_third
        correct_form = form(clause, should_be_third)
        selected_form = form(clause, selected_third)
        number = "singular" if should_be_third else "plural"
        if clause.rule == "near":
            support = (f'The {position} head subject "{clause.subject}" is {number}; '
                       f'"near {clause.attractor}" does not change that.')
        elif clause.rule == "compound":
            support = (f'{position.capitalize()}, the subject "{clause.subject}" is plural '
                       f'("and" joins two); "near {clause.attractor}" does not change it.')
        else:
            support = (f'{position.capitalize()}, the subject "{clause.subject}" is singular; '
                       f'"near {clause.attractor}" does not change it.')
        judgment = (f'The form "{selected_form}" agrees.'
                    if selected_third == should_be_third else
                    f'"{selected_form}" does not agree; use "{correct_form}".')
        return f"{support} {judgment}"

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
    source_task_json: str
    novelty_prompts: tuple[str, ...]
    blocked_variant_identities: tuple[str, ...]
    novelty_exhausted: bool
    assignment: tuple[str, str, str, str, int]
    learner_json: str

    def content(self, question: dict | None = None) -> dict:
        selected, exhausted = _select_novel_task(
            json.loads(self.source_task_json), self.ordinal, self.novelty_prompts,
            self.blocked_variant_identities,
        )
        if selected != json.loads(self.task_json) or exhausted != self.novelty_exhausted:
            raise AgreementTaskError("Agreement task selection provenance changed.")
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


def canonical_variant_identities() -> frozenset[str]:
    """The complete, bounded bank-history vocabulary for the closed pilot."""
    return frozenset(
        _normalized_stem_identity(compile_question(
            {"kind": TASK_KIND, "scene": scene, "order": order}, ordinal=slot,
        )["prompt"])
        for slot, scenes in ((3, SCENES), (4, COMPOUND_SCENES))
        for scene in scenes
        for order in ("singular_first", "plural_first")
    )


def blocked_fingerprint_variant_identities(
    fingerprints: list[str], version: int,
) -> frozenset[str]:
    """Resolve local fingerprint blocks without exposing prompts to the provider."""
    return frozenset(
        identity for identity in canonical_variant_identities()
        if _stem_fingerprint(identity, version=version) in fingerprints
    )


def _select_novel_task(
    task: dict, ordinal: int, existing_prompts: tuple[str, ...],
    blocked_variant_identities: tuple[str, ...] = (),
) -> tuple[dict, bool]:
    """Keep a fresh authored task, otherwise choose a fresh code-owned variant.

    Prefer a new scene over swapping the clauses in an already seen scene. If
    the finite inventory is exhausted, retain the authored task so the normal
    per-item duplicate filter can reject it without discarding the batch.
    """
    scene, _ = _checked_task(task)
    if ordinal not in (3, 4):
        raise AgreementTaskError("Agreement pilot supports original slots 3 and 4 only.")
    allowed = SCENES if ordinal == 3 else COMPOUND_SCENES
    if scene not in allowed:
        raise AgreementTaskError("Agreement task is outside its mapped slot.")
    blocked = {_normalized_stem_identity(prompt) for prompt in existing_prompts}
    blocked.update(blocked_variant_identities)
    variants = [
        {"kind": TASK_KIND, "scene": candidate_scene, "order": order}
        for candidate_scene in sorted(allowed)
        for order in ("singular_first", "plural_first")
    ]
    by_scene = {
        candidate_scene: any(
            _normalized_stem_identity(compile_question(candidate, ordinal=ordinal)["prompt"]) in blocked
            for candidate in variants if candidate["scene"] == candidate_scene
        )
        for candidate_scene in allowed
    }
    fresh = [
        candidate for candidate in variants
        if _normalized_stem_identity(compile_question(candidate, ordinal=ordinal)["prompt"]) not in blocked
    ]
    if not fresh:
        return task, True
    selected = min(fresh, key=lambda candidate: (
        by_scene[candidate["scene"]], candidate != task,
        candidate["scene"], candidate["order"],
    ))
    return selected, False


def compile_mapped_english_slots(
    tasks_by_slot: dict, contract: AuthorSlotContract, *, existing_prompts: tuple[str, ...] = (),
    blocked_variant_identities: tuple[str, ...] = (),
) -> dict[int, CompiledAgreementCandidate]:
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
    if scenes[0] not in SCENES or scenes[1] not in COMPOUND_SCENES:
        raise AgreementTaskError("Original slot 3 requires proximity and slot 4 requires compound agreement.")
    if type(existing_prompts) is not tuple or any(type(prompt) is not str for prompt in existing_prompts):
        raise AgreementTaskError("Agreement novelty history must contain exact prompt strings.")
    if (type(blocked_variant_identities) is not tuple
            or any(type(identity) is not str for identity in blocked_variant_identities)
            or not set(blocked_variant_identities) <= canonical_variant_identities()):
        raise AgreementTaskError("Agreement blocked identities must be canonical variants.")
    assignment = contract.mapped_assignments[1]
    candidates = {}
    for slot in (3, 4):
        source_task = tasks_by_slot[str(slot)]
        task, exhausted = _select_novel_task(
            source_task, slot, existing_prompts, blocked_variant_identities,
        )
        learner = compile_question(task, ordinal=slot)
        candidate = CompiledAgreementCandidate(
            slot, json.dumps(task, sort_keys=True, separators=(",", ":")),
            json.dumps(source_task, sort_keys=True, separators=(",", ":")),
            existing_prompts, blocked_variant_identities, exhausted, assignment,
            json.dumps(learner, sort_keys=True, separators=(",", ":")),
        )
        candidate.content()
        candidates[slot] = candidate
    return candidates


def prepare_mapped_agreement_rows(
    payload: dict, contract: AuthorSlotContract, *, existing_prompts: tuple[str, ...] = (),
    blocked_variant_identities: tuple[str, ...] = (),
    blocked_stem_fingerprints: tuple[str, ...] = (), stem_fingerprint_version: int = 1,
):
    """Compile a complete 3:2 native batch without relabeling source ordinals.

    Quantitative failures retain their original None position; malformed or
    repeated English tasks reject the entire batch before sanitization.
    """
    from quantitative_authoring import QuantitativeAuthoringError, prepare_mixed_rows

    if (type(payload) is not dict or set(payload) != {"questions"}
            or type(payload["questions"]) is not list or len(payload["questions"]) != 5
            or type(contract) is not AuthorSlotContract or not contract.mapped_agreement_tasks):
        raise AgreementTaskError("Agreement route requires one complete trusted five-slot batch.")
    rows = payload["questions"]
    first_assignment, english_assignment = contract.mapped_assignments
    for ordinal, row in enumerate(rows):
        if type(row) is not dict or row.get("kind") != ("quantitative" if ordinal < 3 else "agreement"):
            raise AgreementTaskError("Mapped row changed its original task kind.")
        assignment = first_assignment if ordinal < 3 else english_assignment
        if any(row.get(field) != value for field, value in zip(
            ("skillID", "objectiveID", "topic", "objective"), assignment[:4], strict=True
        )):
            raise AgreementTaskError("Mapped row changed its trusted assignment.")
        if ordinal >= 3 and set(row) != {
            "kind", "task", "topic", "skillID", "objectiveID", "objective"
        }:
            raise AgreementTaskError("Agreement row contains model-authored learner fields.")
    quantitative_sources = rows[:3]
    if contract.mapped_quantitative_families:
        from mapped_quantitative_families import (
            MappedQuantitativeFamilyError,
            select_novel_task,
        )
        try:
            quantitative_sources = [
                {**row, "task": select_novel_task(
                    ordinal, row["task"], existing_prompts=existing_prompts,
                    blocked_fingerprints=blocked_stem_fingerprints,
                    fingerprint_version=stem_fingerprint_version,
                )}
                for ordinal, row in enumerate(quantitative_sources)
            ]
        except MappedQuantitativeFamilyError as error:
            raise AgreementTaskError(str(error)) from error
    try:
        quantitative_rows, quantitative_proof, failures = prepare_mixed_rows(
            {"questions": quantitative_sources}, construct_choices=True,
        )
    except QuantitativeAuthoringError as error:
        raise AgreementTaskError("Quantitative mapped rows violated their closed contract.") from error
    agreement_proof = compile_mapped_english_slots(
        {str(index): rows[index]["task"] for index in (3, 4)}, contract,
        existing_prompts=existing_prompts,
        blocked_variant_identities=blocked_variant_identities,
    )
    failures.extend(
        "agreement_novelty_exhausted" for candidate in agreement_proof.values()
        if candidate.novelty_exhausted
    )
    return (quantitative_rows + [agreement_proof[index].content() for index in (3, 4)],
            quantitative_proof, agreement_proof, failures)


def checked_agreement_provenance(mapping, count: int, *, original_ordinals: bool = False):
    """Accept only private exact-type sidecars; raw JSON cannot impersonate one."""
    if mapping is None:
        return {}
    if (type(mapping) is not dict or type(count) is not int
            or any(type(index) is not int or not 0 <= index < count
                   or type(value) is not CompiledAgreementCandidate
                   or value.ordinal not in (3, 4)
                   or original_ordinals and value.ordinal != index
                   for index, value in mapping.items())):
        raise AgreementTaskError("Agreement provenance must be a trusted ordinal sidecar.")
    return dict(mapping)
