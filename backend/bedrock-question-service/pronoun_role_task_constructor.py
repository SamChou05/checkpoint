"""Offline, closed pronoun-reference task prototype; not wired to authoring.

Only reviewed scene IDs and an order may be supplied. All learner text, role
claims, answer keys, and feedback are constructed from code-owned data.
"""

from dataclasses import dataclass


TASK_KIND = "pronoun_role_v1"
ORDERS = ("forward", "reverse")
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")


class PronounRoleTaskError(ValueError):
    """A task or its compiled learner content violates the closed contract."""


@dataclass(frozen=True)
class _SingleSpeakerScene:
    speaker: str
    addressee: str
    first_verb: str
    addressee_object: str
    second_verb: str
    speaker_object: str


@dataclass(frozen=True)
class _SpeakerShiftScene:
    planner: str
    offerer: str
    action: str
    offerer_object: str
    tool: str
    action_noun: str


# Each frame is reviewed as a coherent plan. Avoid past-tense reports: neither
# the plan nor the offered tool asserts that an action was completed.
SINGLE_SPEAKER_SCENES = {
    "catalog": _SingleSpeakerScene("Mara", "Nia", "catalog", "sketches", "photograph", "model"),
    "repair": _SingleSpeakerScene("Eli", "Ava", "repair", "bicycle", "inspect", "helmet"),
    "translate": _SingleSpeakerScene("Leah", "Theo", "translate", "notes", "review", "draft"),
    "frame": _SingleSpeakerScene("Sana", "Remy", "frame", "drawing", "measure", "canvas"),
}
SPEAKER_SHIFT_SCENES = {
    "deliver": _SpeakerShiftScene("Iris", "Caleb", "deliver", "poster", "cart", "delivery"),
    "move": _SpeakerShiftScene("Nora", "Omar", "move", "boxes", "trolley", "move"),
    "hang": _SpeakerShiftScene("Aya", "Leo", "hang", "painting", "ladder", "job"),
    "copy": _SpeakerShiftScene("Nina", "Eli", "copy", "notes", "printer", "task"),
}

# Tuple positions encode planned actor, first object's owner, second planned
# actor, and second object's owner. These are different semantic claims, not
# superficial rephrasings of one answer.
_SINGLE_ROLE_MAPS = (
    ("speaker", "addressee", "addressee", "speaker"),
    ("addressee", "speaker", "speaker", "addressee"),
    ("speaker", "speaker", "addressee", "addressee"),
    ("addressee", "addressee", "speaker", "speaker"),
)
# Planned actor, planned object's owner, and offered tool's owner.
_SHIFT_ROLE_MAPS = (
    ("planner", "offerer", "offerer"),
    ("offerer", "planner", "planner"),
    ("planner", "planner", "offerer"),
    ("planner", "offerer", "planner"),
)


def task_schema() -> dict:
    """Return a standalone closed schema; production does not import it."""
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "kind": {"type": "string", "const": TASK_KIND},
            "scene": {"type": "string", "enum": [*SINGLE_SPEAKER_SCENES, *SPEAKER_SHIFT_SCENES]},
            "order": {"type": "string", "enum": list(ORDERS)},
        },
        "required": ["kind", "scene", "order"],
    }


def _checked_task(task: object, ordinal: int) -> tuple[str, str]:
    if (type(task) is not dict or set(task) != {"kind", "scene", "order"}
            or type(task["kind"]) is not str or task["kind"] != TASK_KIND
            or type(task["scene"]) is not str
            or task["scene"] not in {*SINGLE_SPEAKER_SCENES, *SPEAKER_SHIFT_SCENES}
            or type(task["order"]) is not str or task["order"] not in ORDERS
            or type(ordinal) is not int or ordinal < 0):
        raise PronounRoleTaskError("Unsupported or model-extended pronoun-role task.")
    return task["scene"], task["order"]


def _ordered_claims(claims: tuple[tuple[str, ...], ...], ordinal: int) -> tuple[tuple[str, ...], ...]:
    offset = ordinal % len(claims)
    return claims[offset:] + claims[:offset]


def _single_speaker_question(scene: _SingleSpeakerScene, order: str, ordinal: int) -> dict:
    speaker, addressee = scene.speaker, scene.addressee
    plan = f"I will {scene.first_verb} your {scene.addressee_object}"
    condition = f"you {scene.second_verb} my {scene.speaker_object}"
    quote = (f"{plan} after {condition}" if order == "forward"
             else f"Before {condition}, {plan}")
    prompt = (f'{speaker} told {addressee}, "{quote}." '
              "Which account matches the two proposed actions and object owners?")
    names = {"speaker": speaker, "addressee": addressee}
    claims = _ordered_claims(_SINGLE_ROLE_MAPS, ordinal)

    def render(claim: tuple[str, ...]) -> str:
        actor1, owner1, actor2, owner2 = (names[role] for role in claim)
        return (f"{actor1} would {scene.first_verb} {owner1}'s {scene.addressee_object}; "
                f"{actor2} would {scene.second_verb} {owner2}'s {scene.speaker_object}.")

    choices = [render(claim) for claim in claims]
    answer = render(_SINGLE_ROLE_MAPS[0])
    errors = {
        _SINGLE_ROLE_MAPS[1]: "reverses both actors and both owners",
        _SINGLE_ROLE_MAPS[2]: "reverses both object owners",
        _SINGLE_ROLE_MAPS[3]: "reverses both actors",
    }
    wrong_notes = ("One alternative reverses both actors and both owners; "
                   "another reverses both object owners; a third reverses both actors.")
    explanation = (f'In {speaker}\'s words, "I/my" mean {speaker} and "you/your" mean '
                   f"{addressee}. Thus {answer} {wrong_notes}")

    def feedback(claim: tuple[str, ...]) -> str:
        if claim == _SINGLE_ROLE_MAPS[0]:
            return (f'Correct. "I/my" refer to {speaker}; "you/your" refer to {addressee}. '
                    "Both actors and owners match.")
        return (f'Incorrect: this {errors[claim]}. In {speaker}\'s words, "I/my" '
                f'mean {speaker} and "you/your" mean {addressee}.')

    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": explanation,
            "choiceExplanations": {choice: feedback(claim)
                                   for choice, claim in zip(choices, claims, strict=True)}}


def _speaker_shift_question(scene: _SpeakerShiftScene, order: str, ordinal: int) -> dict:
    planner, offerer = scene.planner, scene.offerer
    plan = f'{planner}: "I will {scene.action} your {scene.offerer_object}."'
    offer = f'{offerer}: "Use my {scene.tool} for that {scene.action_noun}."'
    early_offer = (f'{offerer}: "Use my {scene.tool} when you {scene.action} '
                   f'the {scene.offerer_object}."')
    dialogue = (f"{plan} {offer}" if order == "forward"
                else f"{early_offer} {plan}")
    prompt = f"{dialogue} Which account matches the plan and offer in this exchange?"
    names = {"planner": planner, "offerer": offerer}
    claims = _ordered_claims(_SHIFT_ROLE_MAPS, ordinal)

    def render(claim: tuple[str, ...]) -> str:
        actor, object_owner, tool_owner = (names[role] for role in claim)
        return (f"{actor} plans to {scene.action} {object_owner}'s {scene.offerer_object}; "
                f"{offerer} offers {tool_owner}'s {scene.tool}.")

    choices = [render(claim) for claim in claims]
    answer = render(_SHIFT_ROLE_MAPS[0])
    errors = {
        _SHIFT_ROLE_MAPS[1]: "reverses the planned actor and both owners",
        _SHIFT_ROLE_MAPS[2]: f"assigns the {scene.offerer_object} to {planner} instead of {offerer}",
        _SHIFT_ROLE_MAPS[3]: f"assigns the {scene.tool} to {planner} instead of {offerer}",
    }
    wrong_notes = (f"One alternative reverses the planned actor and both owners; "
                   f"another assigns the {scene.offerer_object} to {planner} instead of {offerer}; "
                   f"a third assigns the {scene.tool} to {planner} instead of {offerer}.")
    explanation = (f'In {planner}\'s turn, "I" means {planner} and "your" means {offerer}. '
                   f'In {offerer}\'s turn, "my" means {offerer}. Thus {answer} '
                   f"{wrong_notes}")

    def feedback(claim: tuple[str, ...]) -> str:
        if claim == _SHIFT_ROLE_MAPS[0]:
            return (f'Correct. {planner} proposes the action on {offerer}\'s '
                    f'{scene.offerer_object}, and {offerer} offers {offerer}\'s {scene.tool}.')
        return (f'Incorrect: this {errors[claim]}. The speaker changes: '
                f'"I/your" in {planner}\'s turn refer to {planner}/{offerer}; '
                f'"my" in {offerer}\'s turn refers to {offerer}.')

    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": explanation,
            "choiceExplanations": {choice: feedback(claim)
                                   for choice, claim in zip(choices, claims, strict=True)}}


def compile_question(task: object, *, ordinal: int = 0) -> dict:
    """Compile one fully code-owned question from a strict scene/order task."""
    scene_id, order = _checked_task(task, ordinal)
    result = (_single_speaker_question(SINGLE_SPEAKER_SCENES[scene_id], order, ordinal)
              if scene_id in SINGLE_SPEAKER_SCENES else
              _speaker_shift_question(SPEAKER_SHIFT_SCENES[scene_id], order, ordinal))
    choices = result["choices"]
    if (set(result) != set(LEARNER_FIELDS) or len(choices) != 4
            or len(set(choices)) != 4 or choices.count(result["expectedAnswer"]) != 1
            or list(result["choiceExplanations"]) != choices
            or not 12 <= len(result["prompt"]) <= 320
            or any(not 1 <= len(choice) <= 140 or choice[:3] in {"A. ", "B. ", "C. ", "D. "}
                   for choice in choices)
            or not 12 <= len(result["explanation"]) <= 420
            or any(not 1 <= len(text) <= 280
                   for text in result["choiceExplanations"].values())):
        raise PronounRoleTaskError("Pronoun-role content exceeded closed answer limits.")
    return result
