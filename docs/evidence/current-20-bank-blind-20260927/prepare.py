"""Freeze a keyless 20-item offline sample from current mapped constructors.

No provider, worker, queue, DynamoDB, or AWS operation occurs. The answer map
is written outside the repository and must stay sealed until review locks.
"""

from __future__ import annotations

from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BACKEND = ROOT / "backend" / "bedrock-question-service"
PRIVATE = Path(os.environ["CHECKPOINT_PRIVATE_MAP_DIR"])
SOURCE_FILES = (
    "agreement_task_constructor.py",
    "mapped_quantitative_families.py",
    "native_output_contracts.py",
    "quantitative_authoring.py",
    "question_bank.py",
    "question_bank_common.py",
)
sys.path.insert(0, str(BACKEND))

import agreement_task_constructor as agreement  # noqa: E402
import mapped_quantitative_families as numeric  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
from question_bank_common import _normalized_stem_identity  # noqa: E402


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _render(value: object) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def _check_source(seed: dict) -> None:
    if seed["batchCount"] != 4 or seed["providerCalls"] != 0:
        raise AssertionError("Unexpected frozen sample design")
    subprocess.run(
        ("git", "diff", "--quiet", seed["baseSourceCommit"], "--", *(
            "backend/bedrock-question-service/" + name for name in SOURCE_FILES
        )), cwd=ROOT, check=True,
    )
    if len(numeric.SLOT_FAMILIES) != 3 or any(len(families) != 4 for families in numeric.SLOT_FAMILIES):
        raise AssertionError("The complete current numeric repertoire changed")
    capture = ROOT / seed["sourceEvidence"]
    raw = json.loads(json.loads(capture.read_text())["author_response"]
                     ["output"]["message"]["content"][0]["text"])
    if raw["questions"] != seed["sourceTaskSeed"]:
        raise AssertionError("Seed differs from the accepted native author task object")


def _numeric_inventory() -> dict[int, dict[str, tuple[str, int, int]]]:
    result = {}
    for slot in range(3):
        second = numeric.OPERANDS if slot == 0 else numeric.BOUNDARIES
        metadata = (
            (family, a, b)
            for family in numeric.SLOT_FAMILIES[slot]
            for a in numeric.OPERANDS
            for b in second
        )
        result[slot] = {
            identity: (family, a, b)
            for (family, a, b), (_, _, _, identity, _) in zip(
                metadata, numeric._inventory_rows(slot), strict=True  # noqa: SLF001
            )
        }
    return result


def _english_family(scene: str) -> str:
    for name, scenes in (
        ("proximity", agreement.SCENES),
        ("inversion", agreement.INVERSION_SCENES),
        ("relative", agreement.RELATIVE_SCENES),
        ("compound", agreement.COMPOUND_SCENES),
        ("number", agreement.NUMBER_SCENES),
        ("correlative", agreement.CORRELATIVE_SCENES),
        ("gerund", agreement.GERUND_SCENES),
    ):
        if scene in scenes:
            return name
    raise AssertionError("Selected English scene left the closed inventory")


def prepare() -> tuple[dict, dict, dict]:
    seed = json.loads((HERE / "seed.json").read_text())
    _check_source(seed)
    assignments = (
        ("11111111-1111-4111-8111-111111111111",
         "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
         numeric.SUPPORTED_TOPIC, numeric.SUPPORTED_OBJECTIVE, 3),
        ("22222222-2222-4222-8222-222222222222",
         "bbbbbbbb-bbbb-4bbb-8bb8-bbbbbbbbbbbb",
         agreement.SUPPORTED_TOPIC, agreement.SUPPORTED_OBJECTIVE, 2),
    )
    contract = native.AuthorSlotContract(5, "constructed_quantitative", assignments,
                                         assignments[0][0], 2, True, True)
    adapted = json.loads(native.adapt_native_response(
        json.dumps({"questions": seed["sourceTaskSeed"]}), contract
    ))
    inventory = _numeric_inventory()
    prompts: list[str] = []
    stored: list[dict] = []
    items: list[dict] = []
    family_counts = [Counter() for _ in range(5)]
    operand_counts = [Counter() for _ in range(3)]
    pair_counts = Counter()
    checkpoints = []

    for batch in range(1, seed["batchCount"] + 1):
        rows, numeric_proof, english_proof, failures = agreement.prepare_mapped_agreement_rows(
            adapted, contract, existing_prompts=tuple(prompts[-30:]),
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
                raise AssertionError(f"Batch {batch}, slot {slot} lost its proof or one key")
            identity = _normalized_stem_identity(row["prompt"])
            if identity in {_normalized_stem_identity(prompt) for prompt in prompts}:
                raise AssertionError("Full-bank history repeated a stem")
            if slot < 3:
                numeric_proof[slot].content(row)
                family, a, b = inventory[slot][identity]
                operand_counts[slot][(a, b)] += 1
                pair_counts[(a, b)] += 1
                task = {"family": family, "a": a, "b": b}
            else:
                english_proof[slot].content(row)
                task = json.loads(english_proof[slot].task_json)
                family = _english_family(task["scene"])
            family_counts[slot][family] += 1
            choices = list(row["choices"])
            choice_rng = random.Random(int(hashlib.sha256(
                f'{seed["choiceSeed"]}:{row["prompt"]}'.encode()
            ).hexdigest()[:16], 16))
            choice_rng.shuffle(choices)
            displayed = dict(zip("ABCD", choices, strict=True))
            key = next(label for label, choice in displayed.items()
                       if choice == row["expectedAnswer"])
            items.append({"batch": batch, "slot": slot, "family": family,
                          "task": task, "row": row, "choices": displayed, "key": key})
            prompts.append(row["prompt"])
            stored.append({"questionJSON": {"S": json.dumps(row, sort_keys=True)},
                           "state": {"S": "ready"},
                           "createdAt": {"N": str(len(stored))}})
        if batch in (3, 4):
            checkpoints.append({
                "items": 5 * batch,
                "sameSlotFamilyPairs": sum(sum(n * (n - 1) // 2 for n in counts.values())
                                           for counts in family_counts),
                "familyCountsBySlot": {str(slot): dict(sorted(counts.items()))
                                       for slot, counts in enumerate(family_counts)},
                "sameSlotOperandPairs": sum(sum(n * (n - 1) // 2 for n in counts.values())
                                            for counts in operand_counts),
                "numericOperandPairReuseAcrossSlots": sum(n * (n - 1) // 2
                                                           for n in pair_counts.values()),
                "uniqueNumericOperandPairsAcrossSlots": len(pair_counts),
            })

    random.Random(seed["itemOrderSeed"]).shuffle(items)
    worksheet = {
        "status": "offline_code_owned_candidates_not_worker_verified",
        "targetDifficulty": seed["targetDifficulty"],
        "items": [
            {"id": f"Q{i:02d}", "prompt": item["row"]["prompt"],
             "choices": item["choices"]}
            for i, item in enumerate(items, 1)
        ],
    }
    private = {
        "worksheetSha256": hashlib.sha256(_render(worksheet).encode()).hexdigest(),
        "mapping": {
            f"Q{i:02d}": {key: item[key] for key in ("batch", "slot", "family", "task", "row", "key")}
            for i, item in enumerate(items, 1)
        },
    }
    summary = {
        "baseSourceCommit": seed["baseSourceCommit"],
        "seedSha256": _sha(HERE / "seed.json"),
        "sourceCaptureSha256": _sha(ROOT / seed["sourceEvidence"]),
        "sourceFileSha256": {name: _sha(BACKEND / name) for name in SOURCE_FILES},
        "worksheetSha256": private["worksheetSha256"],
        "items": len(items), "batches": seed["batchCount"],
        "uniqueExactStems": len({_normalized_stem_identity(prompt) for prompt in prompts}),
        "numericFamilyOptionsBySlot": {str(slot): list(families)
                                       for slot, families in enumerate(numeric.SLOT_FAMILIES)},
        "checkpoints": checkpoints,
        "providerCalls": 0,
    }
    return worksheet, private, summary


def _check_or_write(path: Path, rendered: str) -> None:
    if path.exists():
        if path.read_text() != rendered:
            raise AssertionError(f"Frozen output changed: {path}")
    else:
        path.write_text(rendered)


def main() -> None:
    worksheet, private, summary = prepare()
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    _check_or_write(HERE / "worksheet.json", _render(worksheet))
    _check_or_write(PRIVATE / "answer-map.json", _render(private))
    (PRIVATE / "answer-map.json").chmod(0o600)
    _check_or_write(HERE / "summary.json", _render(summary))
    print(json.dumps({"worksheet": str(HERE / "worksheet.json"),
                      "worksheetSha256": summary["worksheetSha256"],
                      "items": summary["items"], "providerCalls": 0}))


if __name__ == "__main__":
    main()
