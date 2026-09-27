"""Offline capacity gate for the closed mapped 3:2 question-bank route.

This deliberately uses the current compilers and full-bank history projection,
not model output or a lexical-only stem counter. Family names are a structural
proxy and must be reviewed when a new constructor mechanism is added.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys


BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND.parents[1]
SEED = ROOT / "docs/evidence/mapped-bank-diversity-simulation-20260927/seed.json"
sys.path.insert(0, str(BACKEND))

import agreement_task_constructor as agreement  # noqa: E402
import mapped_quantitative_families as numeric  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
from question_bank_common import _normalized_stem_identity  # noqa: E402


class CapacityError(ValueError):
    """The simulation cannot classify or prove a bank row."""


def _catalog() -> dict[int, dict[str, str]]:
    """Map each exact compiled variant to its code-owned reasoning family."""
    catalog: dict[int, dict[str, str]] = {}
    for slot in range(3):
        variants: dict[str, str] = {}
        for family, _, _, identity in numeric._inventory(slot):  # noqa: SLF001
            if identity in variants and variants[identity] != family:
                raise CapacityError(f"slot {slot}: numeric families collide on a stem")
            variants[identity] = family
        catalog[slot] = variants

    named_families = (
        ("proximity", agreement.SCENES),
        ("inversion", agreement.INVERSION_SCENES),
        ("relative", agreement.RELATIVE_SCENES),
        ("partitive", agreement.PARTITIVE_SCENES),
        ("compound", agreement.COMPOUND_SCENES),
        ("number", agreement.NUMBER_SCENES),
        ("correlative", agreement.CORRELATIVE_SCENES),
        ("gerund", agreement.GERUND_SCENES),
    )
    schema_scenes = set(agreement.task_schema()["properties"]["scene"]["enum"])
    catalog_scenes = [scene for _, scenes in named_families for scene in scenes]
    if len(catalog_scenes) != len(set(catalog_scenes)) or set(catalog_scenes) != schema_scenes:
        raise CapacityError("Agreement schema scenes need an explicit family classification")
    for slot, permitted in ((3, {"proximity", "inversion", "relative", "partitive"}),
                            (4, {"compound", "number", "correlative", "gerund"})):
        variants = {}
        for family, scenes in named_families:
            if family not in permitted:
                continue
            for scene in scenes:
                for order in ("singular_first", "plural_first"):
                    task = {"kind": agreement.TASK_KIND, "scene": scene, "order": order}
                    identity = _normalized_stem_identity(
                        agreement.compile_question(task, ordinal=slot)["prompt"])
                    if identity in variants:
                        raise CapacityError(f"slot {slot}: English variants share a stem")
                    variants[identity] = family
        catalog[slot] = variants
    return catalog


def _snapshot(stored: list[dict], catalog: dict[int, dict[str, str]],
              uses: list[Counter[str]]) -> dict:
    slots = {}
    for slot in range(5):
        counts = uses[slot]
        used = sum(counts.values())
        pairs = sum(count * (count - 1) // 2 for count in counts.values())
        slots[str(slot)] = {
            "items": used,
            "substantiveFamilyCapacity": len(set(catalog[slot].values())),
            "exactStemCapacity": len(catalog[slot]),
            "remainingExactStems": len(catalog[slot]) - used,
            "familyUses": dict(sorted(counts.items())),
            "sameFamilyPairs": pairs,
        }
    exact_stems = [json.loads(item["questionJSON"]["S"])["prompt"] for item in stored]
    return {
        "items": len(stored),
        "uniqueExactStems": len({_normalized_stem_identity(stem) for stem in exact_stems}),
        "sameSlotFamilyPairs": sum(row["sameFamilyPairs"] for row in slots.values()),
        "slots": slots,
    }


def simulate(targets: tuple[int, ...] = (40, 80)) -> dict:
    """Refill the frozen source through current compilers and durable-history logic."""
    if not targets or any(type(n) is not int or n <= 0 or n % 5 for n in targets):
        raise ValueError("Targets must be positive multiples of five")
    targets = tuple(sorted(set(targets)))
    source = json.loads(SEED.read_text())["sourceTasks"]
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
    adapted = json.loads(native.adapt_native_response(
        json.dumps({"questions": source}), contract))
    catalog = _catalog()
    uses = [Counter() for _ in range(5)]
    stored: list[dict] = []
    prompts: list[str] = []
    snapshots = []
    exhaustion = None

    def prepare() -> tuple:
        return agreement.prepare_mapped_agreement_rows(
            adapted, contract,
            existing_prompts=tuple(prompts[-30:]),
            blocked_variant_identities=tuple(question_bank._agreement_variant_history(stored)),
            blocked_quantitative_variant_identities=tuple(
                question_bank._mapped_quantitative_variant_history(stored)),
        )

    for batch in range(1, max(targets) // 5 + 1):
        rows, numeric_proof, english_proof, failures = prepare()
        if failures or len(rows) != 5 or set(numeric_proof) != {0, 1, 2} or set(english_proof) != {3, 4}:
            exhaustion = {"atItems": (batch - 1) * 5,
                          "failureReasons": failures or ["incomplete_or_unproven_batch"]}
            break
        new_rows = []
        for slot, row in enumerate(rows):
            identity = _normalized_stem_identity(row["prompt"])
            if identity not in catalog[slot]:
                raise CapacityError(f"batch {batch}, slot {slot}: stem absent from family catalog")
            if identity in {_normalized_stem_identity(prompt) for prompt in prompts}:
                raise CapacityError(f"batch {batch}, slot {slot}: full-bank stem repeated")
            if (len(row["choices"]) != 4 or len(set(row["choices"])) != 4
                    or row["choices"].count(row["expectedAnswer"]) != 1
                    or set(row["choiceExplanations"]) != set(row["choices"])):
                raise CapacityError(f"batch {batch}, slot {slot}: key or choice proof failed")
            (numeric_proof if slot < 3 else english_proof)[slot].content(row)
            new_rows.append((slot, row, identity))
        for slot, row, identity in new_rows:
            uses[slot][catalog[slot][identity]] += 1
            prompts.append(row["prompt"])
            stored.append({"questionJSON": {"S": json.dumps(row, sort_keys=True)},
                           "state": {"S": "ready"},
                           "createdAt": {"N": str(len(stored))}})
        if batch * 5 in targets:
            snapshots.append(_snapshot(stored, catalog, uses))
    next_batch_failures = None
    if exhaustion is None:
        _, _, _, next_batch_failures = prepare()
    return {"targets": targets, "snapshots": snapshots, "exhaustion": exhaustion,
            "nextBatchFailureReasons": next_batch_failures, "providerCalls": 0}


def qualification_failures(report: dict, *, max_family_uses: int = 1,
                           reserve_exact_stems: int = 1) -> list[str]:
    """Reject structural reuse and depleted inventories at each requested size."""
    if max_family_uses < 1 or reserve_exact_stems < 0:
        raise ValueError("Family-use limit must be positive; stem reserve cannot be negative")
    failures = []
    for target in report["targets"]:
        snapshot = next((row for row in report["snapshots"] if row["items"] == target), None)
        if snapshot is None:
            reason = report["exhaustion"] or {"failureReasons": ["unknown"]}
            failures.append(f"{target} items unavailable: {reason['failureReasons']}")
            continue
        if snapshot["uniqueExactStems"] != target:
            failures.append(f"{target} items: exact stems repeat")
        for slot, row in snapshot["slots"].items():
            needed = (row["items"] + max_family_uses - 1) // max_family_uses
            if row["substantiveFamilyCapacity"] < needed:
                failures.append(
                    f"{target} items, slot {slot}: only {row['substantiveFamilyCapacity']} "
                    f"substantive families for {row['items']} items; need {needed} "
                    f"at <= {max_family_uses} uses/family")
            for family, uses in row["familyUses"].items():
                if uses > max_family_uses:
                    failures.append(
                        f"{target} items, slot {slot}: {family} used {uses} times; "
                        f"limit is {max_family_uses}")
            if row["remainingExactStems"] < reserve_exact_stems:
                failures.append(
                    f"{target} items, slot {slot}: only {row['remainingExactStems']} "
                    f"unused exact stems; reserve requires {reserve_exact_stems}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--items", nargs="+", type=int, default=[40, 80])
    parser.add_argument("--max-family-uses", type=int, default=1)
    parser.add_argument("--reserve-exact-stems", type=int, default=1)
    args = parser.parse_args()
    report = simulate(tuple(args.items))
    failures = qualification_failures(report, max_family_uses=args.max_family_uses,
                                      reserve_exact_stems=args.reserve_exact_stems)
    print(json.dumps({**report, "qualificationFailures": failures}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
