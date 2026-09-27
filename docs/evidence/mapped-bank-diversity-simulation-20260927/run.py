"""Reproduce exact-stem and structural-family counts for the closed mapped route.

Run from any directory with the backend's test dependencies installed. No
provider, AWS, filesystem bank, or model call is made.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
BACKEND = HERE.parents[2] / "backend" / "bedrock-question-service"
sys.path.insert(0, str(BACKEND))

import agreement_task_constructor as agreement  # noqa: E402
import mapped_quantitative_families as numeric  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
from question_bank_common import _normalized_stem_identity  # noqa: E402


def _family_by_numeric_identity(slot: int) -> dict[str, str]:
    result: dict[str, str] = {}
    for family, _, _, identity in numeric._inventory(slot):  # noqa: SLF001
        if identity in result and result[identity] != family:
            raise AssertionError("Two numeric families render the same stem")
        result[identity] = family
    return result


def _english_family(scene: str) -> str:
    if scene in agreement.INVERSION_SCENES:
        return "inversion"
    if scene in agreement.NUMBER_SCENES:
        return "number"
    if scene in agreement.COMPOUND_SCENES:
        return "compound"
    if scene in agreement.SCENES:
        return "proximity"
    raise AssertionError("Selected scene left the closed inventory")


def _snapshot(batch_count: int, prompts: list[str], counts: list[Counter[str]]) -> dict:
    families = {
        str(slot): dict(sorted(counts[slot].items())) for slot in range(5)
    }
    pairs_by_slot = {
        str(slot): sum(count * (count - 1) // 2 for count in counts[slot].values())
        for slot in range(5)
    }
    return {
        "batches": batch_count,
        "items": len(prompts),
        "uniqueExactStems": len({_normalized_stem_identity(prompt) for prompt in prompts}),
        "slotSpecificFamilyCounts": families,
        "sameSlotFamilyPairsBySlot": pairs_by_slot,
        "sameSlotFamilyPairsTotal": sum(pairs_by_slot.values()),
    }


def simulate() -> dict:
    seed = json.loads((HERE / "seed.json").read_text())
    if seed["batchSize"] != 5 or seed["checkpoints"] != [8, 16]:
        raise AssertionError("Unexpected frozen batch design")
    assignments = (
        ("11111111-1111-4111-8111-111111111111",
         "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
         numeric.SUPPORTED_TOPIC, numeric.SUPPORTED_OBJECTIVE, 3),
        ("22222222-2222-4222-8222-222222222222",
         "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
         agreement.SUPPORTED_TOPIC, agreement.SUPPORTED_OBJECTIVE, 2),
    )
    contract = native.AuthorSlotContract(5, "constructed_quantitative", assignments,
                                         assignments[0][0], 2, True, True)
    source = {"questions": seed["sourceTasks"]}
    adapted = json.loads(native.adapt_native_response(json.dumps(source), contract))
    numeric_family_maps = [_family_by_numeric_identity(slot) for slot in range(3)]
    stored: list[dict] = []
    prompts: list[str] = []
    counts = [Counter() for _ in range(5)]
    checkpoints = []

    for batch in range(1, max(seed["checkpoints"]) + 1):
        rows, numeric_proof, english_proof, failures = agreement.prepare_mapped_agreement_rows(
            adapted, contract,
            existing_prompts=tuple(prompts[-30:]),
            blocked_variant_identities=tuple(question_bank._agreement_variant_history(stored)),
            blocked_quantitative_variant_identities=tuple(
                question_bank._mapped_quantitative_variant_history(stored)
            ),
        )
        if failures or len(rows) != 5 or set(numeric_proof) != {0, 1, 2} or set(english_proof) != {3, 4}:
            raise AssertionError(f"Batch {batch} did not compile five proven slots: {failures}")
        for slot, row in enumerate(rows):
            if (len(row["choices"]) != 4 or len(set(row["choices"])) != 4
                    or row["choices"].count(row["expectedAnswer"]) != 1
                    or set(row["choiceExplanations"]) != set(row["choices"])):
                raise AssertionError(f"Batch {batch}, slot {slot} lost exact choices/key/feedback")
            identity = _normalized_stem_identity(row["prompt"])
            if identity in {_normalized_stem_identity(prompt) for prompt in prompts}:
                raise AssertionError(f"Batch {batch}, slot {slot} repeated a full-bank stem")
            if slot < 3:
                numeric_proof[slot].content(row)
                family = numeric_family_maps[slot][identity]
            else:
                english_proof[slot].content(row)
                family = _english_family(json.loads(english_proof[slot].task_json)["scene"])
            counts[slot][family] += 1
            prompts.append(row["prompt"])
            stored.append({"questionJSON": {"S": json.dumps(row, sort_keys=True)},
                           "state": {"S": "ready"},
                           "createdAt": {"N": str(len(stored))}})
        if batch in seed["checkpoints"]:
            checkpoints.append(_snapshot(batch, prompts, counts))

    # The next English selection is structurally exhausted even though the
    # numeric operand inventory still has unseen exact stems.
    _, _, _, after_eighty_failures = agreement.prepare_mapped_agreement_rows(
        adapted, contract, existing_prompts=tuple(prompts[-30:]),
        blocked_variant_identities=tuple(question_bank._agreement_variant_history(stored)),
        blocked_quantitative_variant_identities=tuple(
            question_bank._mapped_quantitative_variant_history(stored)
        ),
    )
    return {
        "baselineSourceCommit": seed["baselineSourceCommit"],
        "sourceTaskSeed": seed["sourceTasks"],
        "checkpoints": checkpoints,
        "post80FailureReasons": after_eighty_failures,
        "providerCalls": 0,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="Replace the frozen result")
    args = parser.parse_args()
    rendered = json.dumps(simulate(), sort_keys=True, indent=2) + "\n"
    result_path = HERE / "summary.json"
    if args.write:
        result_path.write_text(rendered)
    elif result_path.read_text() != rendered:
        raise AssertionError("Simulation differs from frozen summary.json")
    print(rendered, end="")


if __name__ == "__main__":
    main()
