"""Shared cognitive challenge requirements for question authors and reviewers."""

DIFFICULTY_GUIDANCE = (
    "Recognize or recall a fact or concept.",
    "Apply one familiar rule directly.",
    "Interpret evidence or a representation to distinguish plausible conclusions; "
    "scenario details must affect the answer.",
    "Connect multiple reasoning steps or resolve interacting constraints.",
    "Integrate multiple concepts to analyze a novel problem or tradeoff.",
)

DIFFICULTY_RUBRIC = "\n".join(
    f"{level}: {guidance}" for level, guidance in enumerate(DIFFICULTY_GUIDANCE, 1)
)


def _difficulty_guidance(level: int) -> str:
    return DIFFICULTY_GUIDANCE[min(5, max(1, level)) - 1]
