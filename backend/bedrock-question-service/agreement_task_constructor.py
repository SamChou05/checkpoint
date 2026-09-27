"""Closed subject–verb agreement tasks for an exact-scope opt-in route.

The model may choose only a scene and clause order; it supplies no learner text,
choices, key, teaching, metadata, or provenance. Provider acceptance and live
quality of the opt-in route require separate qualification.
"""

from dataclasses import dataclass
import hashlib
import json

from native_output_contracts import AuthorSlotContract
from question_bank_common import _normalized_stem_identity, _stem_fingerprint


SUPPORTED_TOPIC = "Standard written English"
SUPPORTED_OBJECTIVE = "Apply subject-verb agreement or unambiguous pronoun reference"
# Preserve the deployed wire kind while closed scene IDs distinguish the
# full-sentence selector from the older two-blank pair constructors.
TASK_KIND = "agreement_pair_v1"
COMPOUND_SCENE = "compound_every"  # Preserve the wire scene ID across prompt revisions.
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
    compound_object: str
    distributive_group: str
    distributive_object: str
    compound_base: str
    compound_third: str
    distributive_base: str
    distributive_third: str


@dataclass(frozen=True)
class _InversionScene:
    singular_subject: str
    plural_attractor: str
    plural_subject: str
    singular_attractor: str
    location: str


@dataclass(frozen=True)
class _NumberScene:
    people: str
    singular_attractor: str
    things: str
    plural_attractor: str
    plural_complement: str
    singular_complement: str


@dataclass(frozen=True)
class _RelativeScene:
    plural_antecedent: str
    relative_object: str
    matrix_object: str
    relative_base: str
    relative_third: str
    matrix_base: str
    matrix_third: str


@dataclass(frozen=True)
class _CorrelativeScene:
    singular_subject: str
    plural_subject: str
    singular_object: str
    plural_object: str
    singular_base: str
    singular_third: str
    plural_base: str
    plural_third: str


@dataclass(frozen=True)
class _GerundFrame:
    activity: str
    activity_object: str
    plural_subject: str
    plural_object: str
    activity_base: str
    activity_third: str
    plural_base: str
    plural_third: str


@dataclass(frozen=True)
class _PartitiveScene:
    mass_subject: str
    mass_object: str
    mass_base: str
    mass_third: str
    count_subject: str
    count_object: str
    count_base: str
    count_third: str


@dataclass(frozen=True)
class _SentenceSelectionScene:
    compound: str
    correlative: str
    gerund: str


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
# Avoid collective nouns, possessives, ambiguous pronouns, existential there,
# subjunctives, past tense, and register-dependent agreement.
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
        "Maya and Theo", "lunch", "the guests", "a plate",
        "prepare", "prepares", "receive", "receives",
    ),
    "compound_guides": _CompoundScene(
        "Nora and Eli", "the maps", "the guides", "a badge",
        "fold", "folds", "wear", "wears",
    ),
    "compound_visitors": _CompoundScene(
        "Leah and Omar", "the doors", "the visitors", "a ticket",
        "close", "closes", "hold", "holds",
    ),
    "compound_clerks": _CompoundScene(
        "Ava and Ben", "the forms", "the clerks", "a copy",
        "review", "reviews", "keep", "keeps",
    ),
}
INVERSION_SCENES = {
    "inversion_archive": _InversionScene("the report", "the interns", "the records", "the curator", "the archive"),
    "inversion_studio": _InversionScene("the script", "the actors", "the props", "the director", "the studio"),
    "inversion_library": _InversionScene("the book", "the volunteers", "the returns", "the librarian", "the library"),
    "inversion_lab": _InversionScene("the sample", "the technicians", "the notes", "the scientist", "the lab"),
}
NUMBER_SCENES = {
    "number_volunteers": _NumberScene("volunteers", "the curator", "tickets", "the guides", "waiting", "limited"),
    "number_workers": _NumberScene("workers", "the manager", "reports", "the assistants", "ready", "fixed"),
    "number_readers": _NumberScene("readers", "the author", "copies", "the editors", "present", "known"),
    "number_students": _NumberScene("students", "the tutor", "forms", "the teachers", "available", "clear"),
}
RELATIVE_SCENES = {
    # "Who" refers to the plural antecedent, while "one" is the singular
    # subject of the main clause. The two blanks require different analyses.
    "relative_guides": _RelativeScene("guides", "the maps", "a badge", "fold", "folds", "wear", "wears"),
    "relative_editors": _RelativeScene("editors", "the proofs", "a notebook", "check", "checks", "carry", "carries"),
    "relative_technicians": _RelativeScene("technicians", "the samples", "a log", "label", "labels", "keep", "keeps"),
    "relative_clerks": _RelativeScene("clerks", "the files", "a key", "sort", "sorts", "hold", "holds"),
}
CORRELATIVE_SCENES = {
    # With either/or and neither/nor, the nearer subject controls the verb.
    # Each task contrasts a singular nearer subject with a plural nearer one.
    "or_archive": _CorrelativeScene(
        "the curator", "the assistants", "the catalog", "the records",
        "check", "checks", "sort", "sorts",
    ),
    "or_studio": _CorrelativeScene(
        "the director", "the actors", "the script", "the props",
        "review", "reviews", "move", "moves",
    ),
    "or_library": _CorrelativeScene(
        "the librarian", "the volunteers", "the book", "the returns",
        "examine", "examines", "arrange", "arranges",
    ),
    "or_lab": _CorrelativeScene(
        "the scientist", "the technicians", "the log", "the samples",
        "inspect", "inspects", "label", "labels",
    ),
}
GERUND_SCENES = {
    # Each order uses a different activity and plural subject, rather than
    # turning one sentence into a second bank stem by swapping its clauses.
    "gerund_reports": (
        _GerundFrame("Proofreading the reports", "patience", "the editors", "every heading",
                     "require", "requires", "check", "checks"),
        _GerundFrame("Verifying the totals", "careful work", "the auditors", "each calculation",
                     "demand", "demands", "review", "reviews"),
    ),
    "gerund_books": (
        _GerundFrame("Cataloging the books", "readers", "the librarians", "the shelf labels",
                     "help", "helps", "update", "updates"),
        _GerundFrame("Restoring the manuscripts", "time", "the archivists", "the damaged pages",
                     "take", "takes", "examine", "examines"),
    ),
    "gerund_meals": (
        _GerundFrame("Preparing the meals", "planning", "the cooks", "the ingredients",
                     "require", "requires", "measure", "measures"),
        _GerundFrame("Cleaning the ovens", "patience", "the chefs", "the equipment",
                     "demand", "demands", "inspect", "inspects"),
    ),
    "gerund_maps": (
        _GerundFrame("Drawing the maps", "accuracy", "the cartographers", "the borders",
                     "require", "requires", "trace", "traces"),
        _GerundFrame("Checking the routes", "time", "the surveyors", "the distances",
                     "take", "takes", "record", "records"),
    ),
}
PARTITIVE_SCENES = {
    # The same quantifier can refer to a mass or to plural countable items.
    # Agreement follows the measured noun, not the surface quantifier.
    "partitive_paint": _PartitiveScene(
        "Half of the paint", "the wall", "cover", "covers",
        "Half of the brushes", "on the rack", "rest", "rests",
    ),
    "partitive_rice": _PartitiveScene(
        "Most of the rice", "in the pot", "remain", "remains",
        "Most of the plates", "on the shelf", "sit", "sits",
    ),
    "partitive_water": _PartitiveScene(
        "Some of the water", "through the pipe", "flow", "flows",
        "Some of the bottles", "on the table", "stand", "stands",
    ),
    "partitive_mail": _PartitiveScene(
        "Most of the mail", "by noon", "arrive", "arrives",
        "Most of the letters", "return addresses", "include", "includes",
    ),
}
SENTENCE_SELECTION_SCENES = {
    # Four different subject structures appear as complete sentences. The
    # selected variant has exactly one grammatical sentence, rather than a
    # Cartesian product of two verb blanks like the older English families.
    "select_archive": _SentenceSelectionScene("compound_every", "or_archive", "gerund_reports"),
    "select_library": _SentenceSelectionScene("compound_guides", "or_library", "gerund_books"),
    "select_studio": _SentenceSelectionScene("compound_visitors", "or_studio", "gerund_meals"),
    "select_lab": _SentenceSelectionScene("compound_clerks", "or_lab", "gerund_maps"),
}


class AgreementTaskError(ValueError):
    """The closed grammar task cannot be compiled under this pilot's rules."""


def task_schema() -> dict:
    """Small provider-facing shape for one task, not a qualified Bedrock schema."""
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "enum": [TASK_KIND]},
            "scene": {"type": "string", "enum": sorted((*SCENES, *COMPOUND_SCENES,
                                                       *INVERSION_SCENES, *NUMBER_SCENES,
                                                       *RELATIVE_SCENES, *CORRELATIVE_SCENES,
                                                       *GERUND_SCENES, *PARTITIVE_SCENES,
                                                       *SENTENCE_SELECTION_SCENES))},
            "order": {"type": "string", "enum": ["singular_first", "plural_first"]},
        },
        "required": ["kind", "scene", "order"],
    }


def _checked_task(task: object) -> tuple[str, str]:
    if (type(task) is not dict or set(task) != {"kind", "scene", "order"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["scene"]) is not str or task["scene"] not in {
                *SCENES, *COMPOUND_SCENES, *INVERSION_SCENES, *NUMBER_SCENES,
                *RELATIVE_SCENES, *CORRELATIVE_SCENES, *GERUND_SCENES,
                *PARTITIVE_SCENES, *SENTENCE_SELECTION_SCENES,
            }
            or type(task["order"]) is not str
            or task["order"] not in {"singular_first", "plural_first"}):
        raise AgreementTaskError("Unsupported or model-extended agreement task.")
    return task["scene"], task["order"]


def _clause(subject: str, attractor: str, obj: str) -> str:
    return f"{subject[0].upper()}{subject[1:]} near {attractor} ___ {obj}"


def _compile_relative_question(scene: _RelativeScene, order: str, ordinal: int) -> dict:
    """Prove agreement separately in a relative clause and its main clause."""
    matrix = f"One of the {scene.plural_antecedent} ___ {scene.matrix_object}."
    relative = (f"The {scene.plural_antecedent} who ___ {scene.relative_object} "
                "are here.")
    clauses = ((matrix, relative) if order == "singular_first" else
               (relative, matrix))
    prompt = ("Fill both blanks with present-tense forms in standard written American English. "
              f"{' '.join(clauses)} Which ordered pair fills the blanks?")
    positions = (("matrix", "relative") if order == "singular_first" else
                 ("relative", "matrix"))
    pairs = [(False, False), (False, True), (True, False), (True, True)]
    pairs = pairs[ordinal % 4:] + pairs[:ordinal % 4]
    forms = {
        "relative": (scene.relative_base, scene.relative_third),
        "matrix": (scene.matrix_base, scene.matrix_third),
    }
    choices = ["; ".join(forms[position][int(flag)]
                         for position, flag in zip(positions, flags, strict=True))
               for flags in pairs]
    correct_flags = tuple(position == "matrix" for position in positions)
    answer = "; ".join(forms[position][int(flag)]
                       for position, flag in zip(positions, correct_flags, strict=True))
    relative_rule = (f'The relative pronoun "who" refers to plural "{scene.plural_antecedent}"; '
                     f'the relative-clause verb is "{scene.relative_base}".')
    matrix_rule = ('The main-clause subject is singular "One"; '
                   f'the main-clause verb is "{scene.matrix_third}".')
    rules = {"relative": relative_rule, "matrix": matrix_rule}
    explanation = (" ".join(rules[position] for position in positions)
                   + f" Therefore the ordered pair is {answer}.")

    def feedback(flags: tuple[bool, bool]) -> str:
        reasons = []
        for position, flag in zip(positions, flags, strict=True):
            if flag == (position == "matrix"):
                reasons.append(rules[position])
            elif position == "relative":
                reasons.append(f'"{scene.relative_third}" does not agree with plural '
                               f'"{scene.plural_antecedent}"; use "{scene.relative_base}".')
            else:
                reasons.append(f'"{scene.matrix_base}" does not agree with singular "One"; '
                               f'use "{scene.matrix_third}".')
        return " ".join(reasons)

    result = {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
              "explanation": explanation,
              "choiceExplanations": {choice: feedback(flags)
                                     for choice, flags in zip(choices, pairs, strict=True)}}
    if (len(set(choices)) != 4 or choices.count(answer) != 1
            or len(prompt) > 320 or len(explanation) > 420
            or any(len(text) > 280 for text in result["choiceExplanations"].values())):
        raise AgreementTaskError("Relative-clause agreement exceeded closed answer limits.")
    return result


def _compile_sentence_selection_question(scene_id: str, order: str) -> dict:
    """Select the only correct full sentence across four nontrivial rules."""
    scene = SENTENCE_SELECTION_SCENES[scene_id]
    compound = COMPOUND_SCENES[scene.compound]
    correlative = CORRELATIVE_SCENES[scene.correlative]
    gerund = GERUND_SCENES[scene.gerund][order == "plural_first"]
    scene_index = tuple(SENTENCE_SELECTION_SCENES).index(scene_id)
    correct_rule = (scene_index + 2 * (order == "plural_first")) % 4
    compound_forms = (compound.compound_base, compound.compound_third)
    each_forms = (compound.distributive_base, compound.distributive_third)
    correlative_forms = (correlative.plural_base, correlative.plural_third)
    gerund_forms = (gerund.activity_base, gerund.activity_third)
    # Each pair is (wrong, right). Every distractor violates a different
    # subject/verb relation; all choices are whole, otherwise parallel sentences.
    sentences = (
        (f"{compound.compound_subject} each {compound_forms[1]} {compound.compound_object}.",
         f"{compound.compound_subject} each {compound_forms[0]} {compound.compound_object}."),
        (f"Each of {compound.distributive_group} {each_forms[0]} {compound.distributive_object}.",
         f"Each of {compound.distributive_group} {each_forms[1]} {compound.distributive_object}."),
        (f"Neither {correlative.singular_subject} nor {correlative.plural_subject} "
         f"{correlative_forms[1]} {correlative.plural_object}.",
         f"Neither {correlative.singular_subject} nor {correlative.plural_subject} "
         f"{correlative_forms[0]} {correlative.plural_object}."),
        (f"{gerund.activity} {gerund_forms[0]} {gerund.activity_object}.",
         f"{gerund.activity} {gerund_forms[1]} {gerund.activity_object}."),
    )
    reasons = (
        (f'"{compound.compound_subject}" is a plural joined subject; the following "each" '
         f'does not make it singular, so use "{compound_forms[0]}".'),
        (f'"Each" is the singular head of "Each of {compound.distributive_group}"; '
         f'the plural noun after "of" does not control the verb, so use "{each_forms[1]}".'),
        (f'With "neither...nor," the nearer subject "{correlative.plural_subject}" is '
         f'plural, so use "{correlative_forms[0]}".'),
        (f'The whole -ing activity "{gerund.activity}" is one singular subject, '
         f'even though it contains a plural noun, so use "{gerund_forms[1]}".'),
    )
    raw = [sentences[index][index == correct_rule] for index in range(4)]
    desired_position = (scene_index + (order == "plural_first")) % 4
    rotation = (correct_rule - desired_position) % 4
    indices = list(range(4))[rotation:] + list(range(4))[:rotation]
    choices = [raw[index] for index in indices]
    answer = sentences[correct_rule][1]
    raw_feedback = {
        raw[index]: ("This sentence agrees. " if index == correct_rule else
                     "This sentence does not agree. ") + reasons[index]
        for index in range(4)
    }
    feedback = {choice: raw_feedback[choice] for choice in choices}
    prompt = (f"An editor compares sentences about {compound.compound_subject}, "
              f"{correlative.plural_subject}, and {gerund.activity.lower()}. "
              "Which sentence uses present-tense subject-verb agreement correctly "
              "in standard written American English?")
    # The final immutable-main reviewer does not see choice-specific teaching.
    # Prove why all four sentences do or do not agree in the main explanation.
    brief_reasons = (
        f'"{compound.compound_subject}" is plural; following "each" does not change that, '
        f'so use "{compound_forms[0]}".',
        f'"Each of {compound.distributive_group}" has singular "Each" and needs "{each_forms[1]}".',
        f'After "neither...nor," nearer "{correlative.plural_subject}" is plural and needs "{correlative_forms[0]}".',
        f'"{gerund.activity}" is one singular activity and needs "{gerund_forms[1]}".',
    )
    explanation = f'Only "{answer}" agrees. ' + " ".join(brief_reasons)
    if (len(set(choices)) != 4 or choices.count(answer) != 1
            or len(prompt) > 320 or len(explanation) > 420
            or any(len(value) > 280 for value in feedback.values())):
        raise AgreementTaskError("Sentence-selection agreement exceeded closed answer limits.")
    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": explanation, "choiceExplanations": feedback}


def compile_question(task: dict, *, ordinal: int) -> dict:
    """Return exactly five code-owned learner fields for original slot 3 or 4."""
    scene_id, order = _checked_task(task)
    if type(ordinal) is not int or ordinal not in {3, 4}:
        raise AgreementTaskError("Agreement pilot supports original slots 3 and 4 only.")
    if scene_id in SENTENCE_SELECTION_SCENES:
        if ordinal != 4:
            raise AgreementTaskError("Sentence selection is available only in slot 4.")
        return _compile_sentence_selection_question(scene_id, order)
    if scene_id in RELATIVE_SCENES:
        return _compile_relative_question(RELATIVE_SCENES[scene_id], order, ordinal)
    if scene_id in PARTITIVE_SCENES:
        scene = PARTITIVE_SCENES[scene_id]
        first = _Clause(
            f"{scene.mass_subject} ___ {scene.mass_object}",
            scene.mass_base, scene.mass_third, True, scene.mass_subject,
            rule="partitive_mass",
        )
        second = _Clause(
            f"{scene.count_subject} ___ {scene.count_object}",
            scene.count_base, scene.count_third, False, scene.count_subject,
            rule="partitive_count",
        )
    elif scene_id in COMPOUND_SCENES:
        scene = COMPOUND_SCENES[scene_id]
        first = _Clause(
            f"{scene.compound_subject} each ___ {scene.compound_object}",
            scene.compound_base, scene.compound_third, False,
            scene.compound_subject, rule="compound",
        )
        second = _Clause(
            f"Each of {scene.distributive_group} ___ {scene.distributive_object}",
            scene.distributive_base, scene.distributive_third, True,
            f"Each of {scene.distributive_group}", scene.distributive_group,
            rule="each_of",
        )
    elif scene_id in INVERSION_SCENES:
        scene = INVERSION_SCENES[scene_id]
        first = _Clause(
            f"Near {scene.plural_attractor} ___ {scene.singular_subject} from {scene.location}",
            "are", "is", True, scene.singular_subject, scene.plural_attractor,
            rule="inversion",
        )
        second = _Clause(
            f"Near {scene.singular_attractor} ___ {scene.plural_subject} from {scene.location}",
            "are", "is", False, scene.plural_subject, scene.singular_attractor,
            rule="inversion",
        )
    elif scene_id in NUMBER_SCENES:
        scene = NUMBER_SCENES[scene_id]
        first = _Clause(
            f"A number of {scene.people} near {scene.singular_attractor} ___ {scene.plural_complement}",
            "are", "is", False, f"A number of {scene.people}", scene.singular_attractor,
            rule="number_plural",
        )
        second = _Clause(
            f"The number of {scene.things} near {scene.plural_attractor} ___ {scene.singular_complement}",
            "are", "is", True, f"The number of {scene.things}", scene.plural_attractor,
            rule="number_singular",
        )
    elif scene_id in CORRELATIVE_SCENES:
        scene = CORRELATIVE_SCENES[scene_id]
        first = _Clause(
            f"Either {scene.plural_subject} or {scene.singular_subject} ___ {scene.singular_object}",
            scene.singular_base, scene.singular_third, True,
            scene.singular_subject, scene.plural_subject, rule="correlative",
        )
        second = _Clause(
            f"Neither {scene.singular_subject} nor {scene.plural_subject} ___ {scene.plural_object}",
            scene.plural_base, scene.plural_third, False,
            scene.plural_subject, scene.singular_subject, rule="correlative",
        )
    elif scene_id in GERUND_SCENES:
        frame = GERUND_SCENES[scene_id][order == "plural_first"]
        first = _Clause(
            f"{frame.activity} ___ {frame.activity_object}",
            frame.activity_base, frame.activity_third, True,
            frame.activity, rule="gerund",
        )
        second = _Clause(
            f"{frame.plural_subject[0].upper()}{frame.plural_subject[1:]} ___ {frame.plural_object}",
            frame.plural_base, frame.plural_third, False,
            frame.plural_subject, rule="plural_noun",
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
    if (clauses[1].rule == "gerund"
            or following.startswith(("The ", "Every ", "Each ", "Near ", "A ", "Either ", "Neither ",
                                     "Half ", "Most ", "Some "))):
        following = following[0].lower() + following[1:]
    connector = "and" if scene_id in GERUND_SCENES else "while"
    prompt = ("Fill both blanks with the present-tense verb forms that agree with "
              "the subjects in standard written American English. "
              f"{clauses[0].text}, {connector} {following}. "
              "Which ordered pair fills the blanks?")
    # False/True indexes choose the bare or third-person singular form for each
    # clause. The Cartesian product has four different ordered commitments.
    pairs = [(False, False), (False, True), (True, False), (True, True)]
    # A fixed original slot ordinal would put every gerund answer in B or C.
    # Rotate its eight closed variants evenly across all four positions.
    rotation = (tuple(GERUND_SCENES).index(scene_id) +
                (order == "plural_first")) % 4 if scene_id in GERUND_SCENES else ordinal % 4
    pairs = pairs[rotation:] + pairs[:rotation]

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
            support = (f'{position.capitalize()}, "{clause.subject}" is a plural joined subject; '
                       'the following "each" does not replace it.')
        elif clause.rule == "each_of":
            support = (f'{position.capitalize()}, "{clause.subject}" has singular "Each"; '
                       f'"{clause.attractor}" follows "of".')
        elif clause.rule == "inversion":
            support = (f'{position.capitalize()}, the {number} subject "{clause.subject}" '
                       f'follows the blank; "near {clause.attractor}" is not the subject.')
        elif clause.rule == "number_plural":
            support = (f'{position.capitalize()}, "{clause.subject}" means several and takes '
                       f'a plural verb; "near {clause.attractor}" does not change it.')
        elif clause.rule == "correlative":
            support = (f'{position.capitalize()}, the nearer subject "{clause.subject}" '
                       f'is {number}; "{clause.attractor}" is farther away.')
        elif clause.rule == "gerund":
            support = (f'{position.capitalize()}, the activity "{clause.subject}" is one '
                       'singular subject, even though it contains a plural object.')
        elif clause.rule == "plural_noun":
            support = (f'{position.capitalize()}, the subject "{clause.subject}" is plural.')
        elif clause.rule == "partitive_mass":
            support = (f'{position.capitalize()}, "{clause.subject}" refers to an amount of '
                       'uncountable material, so it takes a singular verb.')
        elif clause.rule == "partitive_count":
            support = (f'{position.capitalize()}, "{clause.subject}" refers to multiple '
                       'countable items, so it takes a plural verb.')
        else:
            support = (f'{position.capitalize()}, "{clause.subject}" has the singular head '
                       f'"number"; "near {clause.attractor}" does not change it.')
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
    source_task_sha256: str
    novelty_prompts: tuple[str, ...]
    blocked_variant_identities: tuple[str, ...]
    novelty_exhausted: bool
    assignment: tuple[str, str, str, str, int]
    learner_json: str

    def content(self, question: dict | None = None) -> dict:
        if hashlib.sha256(self.source_task_json.encode()).hexdigest() != self.source_task_sha256:
            raise AgreementTaskError("Agreement source task provenance changed.")
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
        for slot, scenes in ((3, (*SCENES, *INVERSION_SCENES, *RELATIVE_SCENES,
                                   *PARTITIVE_SCENES)),
                             (4, (*COMPOUND_SCENES, *NUMBER_SCENES, *CORRELATIVE_SCENES,
                                  *GERUND_SCENES, *SENTENCE_SELECTION_SCENES)))
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
    """Choose a fresh code-owned variant and retain its authored source.

    Slot 3 prefers the least-used solve mechanism. Slot 4 introduces its
    scarce full-sentence scenes in the first batch and then spaces them among
    two-blank families. A never-used scene takes priority over a second
    variant of any scene. If the finite inventory is exhausted, retain the
    authored task for the normal per-item duplicate filter.
    """
    scene, _ = _checked_task(task)
    if ordinal not in (3, 4):
        raise AgreementTaskError("Agreement pilot supports original slots 3 and 4 only.")
    allowed = ({**SCENES, **INVERSION_SCENES, **RELATIVE_SCENES,
                **PARTITIVE_SCENES} if ordinal == 3
               else {**COMPOUND_SCENES, **NUMBER_SCENES, **CORRELATIVE_SCENES,
                     **GERUND_SCENES, **SENTENCE_SELECTION_SCENES})
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
    family_by_scene = {
        candidate_scene: ("partitive" if candidate_scene in PARTITIVE_SCENES else
                          "relative" if candidate_scene in RELATIVE_SCENES else
                          "inversion" if candidate_scene in INVERSION_SCENES else
                          "correlative" if candidate_scene in CORRELATIVE_SCENES else
                          "gerund" if candidate_scene in GERUND_SCENES else
                          "sentence_selection" if candidate_scene in SENTENCE_SELECTION_SCENES else
                          "number" if candidate_scene in NUMBER_SCENES else
                          "compound" if candidate_scene in COMPOUND_SCENES else "proximity")
        for candidate_scene in allowed
    }
    family_counts = {
        family: sum(
            _normalized_stem_identity(compile_question(candidate, ordinal=ordinal)["prompt"]) in blocked
            for candidate in variants if family_by_scene[candidate["scene"]] == family
        )
        for family in set(family_by_scene.values())
    }
    used_slot4 = sum(family_counts.values()) if ordinal == 4 else 0
    sentence_uses = family_counts.get("sentence_selection", 0)
    # Four distinct full-sentence scenes can appear at slot-4 positions
    # 1, 4, 8, and 12 without clustering all four in the first four batches.
    sentence_due = (ordinal == 4 and sentence_uses < min(
        len(SENTENCE_SELECTION_SCENES), (used_slot4 + 5) // 4,
    ))

    def priority(candidate: dict) -> tuple:
        candidate_scene = candidate["scene"]
        family_use = family_counts[family_by_scene[candidate_scene]]
        if ordinal == 4:
            return (by_scene[candidate_scene],
                    (candidate_scene in SENTENCE_SELECTION_SCENES) != sentence_due,
                    family_use,
                    # In the level-2 pilot, the first selected full-sentence
                    # variant should use the order independently rated 2/2.
                    # Keep an authored selection unchanged when it is fresh.
                    (scene not in SENTENCE_SELECTION_SCENES
                     and candidate_scene in SENTENCE_SELECTION_SCENES
                     and candidate["order"] != "singular_first"),
                    candidate != task,
                    candidate_scene, candidate["order"])
        return (family_use, by_scene[candidate_scene], candidate != task,
                candidate_scene, candidate["order"])

    selected = min(fresh, key=priority)
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
    if scenes[0] not in {*SCENES, *INVERSION_SCENES, *RELATIVE_SCENES,
                         *PARTITIVE_SCENES} or scenes[1] not in {
        *COMPOUND_SCENES, *NUMBER_SCENES, *CORRELATIVE_SCENES, *GERUND_SCENES,
        *SENTENCE_SELECTION_SCENES,
    }:
        raise AgreementTaskError("Original English slots require their closed agreement families.")
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
        source_json = json.dumps(source_task, sort_keys=True, separators=(",", ":"))
        candidate = CompiledAgreementCandidate(
            slot, json.dumps(task, sort_keys=True, separators=(",", ":")),
            source_json, hashlib.sha256(source_json.encode()).hexdigest(),
            existing_prompts, blocked_variant_identities, exhausted, assignment,
            json.dumps(learner, sort_keys=True, separators=(",", ":")),
        )
        candidate.content()
        candidates[slot] = candidate
    return candidates


def prepare_mapped_agreement_rows(
    payload: dict, contract: AuthorSlotContract, *, existing_prompts: tuple[str, ...] = (),
    blocked_variant_identities: tuple[str, ...] = (),
    blocked_quantitative_variant_identities: tuple[str, ...] = (),
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
                    blocked_variant_identities=blocked_quantitative_variant_identities,
                )}
                for ordinal, row in enumerate(quantitative_sources)
            ]
        except MappedQuantitativeFamilyError as error:
            raise AgreementTaskError(str(error)) from error
    try:
        quantitative_rows, quantitative_proof, failures = prepare_mixed_rows(
            {"questions": quantitative_sources}, construct_choices=True,
            allow_count_satisfying=contract.mapped_quantitative_families,
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
