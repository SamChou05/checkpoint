"""Replay the current closed 3:2 constructor against full-bank history offline.

The public worksheet omits answers and source-task identities. Its private map
is written only to CHECKPOINT_PRIVATE_MAP_DIR for a later blind review.
"""

from __future__ import annotations

from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BACKEND = ROOT / "backend/bedrock-question-service"
sys.path[:0] = [str(BACKEND), str(BACKEND / "tests")]

import agreement_task_constructor as agreement  # noqa: E402
import mapped_bank_capacity_harness as capacity  # noqa: E402
import mapped_quantitative_families as numeric  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
from question_bank_common import _normalized_stem_identity  # noqa: E402


SIGNATURE_SOURCE = ROOT / "docs/evidence/solve-signature-gate-20260927/probe.py"
spec = importlib.util.spec_from_file_location("closed_solve_signature", SIGNATURE_SOURCE)
assert spec and spec.loader
signature_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signature_module)

SOURCE_COMMIT = "1dc91bf50d85c644488c9eda96de513954f5d969"
SOURCE_SEED = ROOT / "docs/evidence/current-20-bank-blind-20260927/seed.json"
SOURCE_CAPTURE = ROOT / "docs/evidence/native-v9-author-acceptance-20260927/capture.json"
CAPTURE_SHA256 = "17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa"
ITEM_ORDER_SEED = 2026092702
CHOICE_SEED = 2026092703
SAMPLE_FAMILIES = {
    0: ("fraction_evaluation", "fraction_product_complement",
        "fraction_quotient", "fraction_reciprocal_sum"),
    1: ("bounded_quadratic_equation", "bounded_rational_equation",
        "bounded_two_root_minimum", "bounded_quadratic_exclusion_count"),
    2: ("bounded_ratio_threshold", "bounded_linear_budget_maximum",
        "bounded_solution_count", "bounded_centered_square_count"),
    3: ("inversion", "partitive", "proximity", "relative"),
    4: ("compound", "correlative", "gerund", "sentence_selection"),
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _render(value: object) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def _freeze(path: Path, value: object) -> None:
    rendered = _render(value)
    if path.exists():
        if path.read_text() != rendered:
            raise AssertionError(f"Frozen output changed: {path}")
    else:
        path.write_text(rendered)


def _source_tasks() -> dict:
    changed = subprocess.run(
        ("git", "diff", "--quiet", SOURCE_COMMIT, "--", "backend/bedrock-question-service"),
        cwd=ROOT, check=False,
    )
    if changed.returncode:
        raise AssertionError("Backend source changed after pinned source commit")
    if _sha(SOURCE_CAPTURE.read_bytes()) != CAPTURE_SHA256:
        raise AssertionError("Accepted native author capture changed")
    seed = json.loads(SOURCE_SEED.read_text())
    source = json.loads(json.loads(SOURCE_CAPTURE.read_text())["author_response"]
                        ["output"]["message"]["content"][0]["text"])["questions"]
    if source != seed["sourceTaskSeed"]:
        raise AssertionError("Source tasks differ from accepted capture")
    return source


def _snapshot(items: list[dict]) -> dict:
    families = [Counter() for _ in range(5)]
    scenes = [Counter() for _ in range(5)]
    formats = [Counter() for _ in range(5)]
    signatures = [Counter() for _ in range(3)]
    cross_family_signatures = [dict() for _ in range(3)]
    signature_family_uses = [dict() for _ in range(3)]
    for item in items:
        slot = item["slot"]
        families[slot][item["family"]] += 1
        formats[slot][item["format"]] += 1
        if slot < 3:
            signatures[slot][item["solveSignature"]] += 1
            cross_family_signatures[slot].setdefault(item["solveSignature"], set()).add(
                item["family"])
            signature_family_uses[slot].setdefault(item["solveSignature"], Counter())[
                item["family"]] += 1
        else:
            scenes[slot][item["scene"]] += 1
    def pair_count(counter: Counter) -> int:
        return sum(n * (n - 1) // 2 for n in counter.values())

    return {
        "items": len(items),
        "uniqueExactStems": len({_normalized_stem_identity(item["row"]["prompt"])
                                 for item in items}),
        "uniqueKeysAndFourLiteralDistinctChoices": sum(
            len(item["row"]["choices"]) == len(set(item["row"]["choices"])) == 4
            and item["row"]["choices"].count(item["row"]["expectedAnswer"]) == 1
            for item in items),
        "familyUsesBySlot": {str(s): dict(sorted(families[s].items())) for s in range(5)},
        "sceneUsesByEnglishSlot": {str(s): dict(sorted(scenes[s].items())) for s in (3, 4)},
        "promptFormatUsesBySlot": {str(s): dict(sorted(formats[s].items())) for s in range(5)},
        "sameFamilyPairsBySlot": {str(s): pair_count(families[s]) for s in range(5)},
        "samePromptFormatPairsBySlot": {str(s): pair_count(formats[s]) for s in range(5)},
        "numericSolveSignatureUsesBySlot": {
            str(s): dict(sorted(signatures[s].items())) for s in range(3)},
        "sameNumericSolveSignaturePairsBySlot": {
            str(s): pair_count(signatures[s]) for s in range(3)},
        "sameNumericSolveSignaturePairsAcrossNumericSlots": pair_count(Counter(
            item["solveSignature"] for item in items if item["slot"] < 3)),
        "crossFamilySameNumericSolveSignaturePairsBySlot": {
            str(s): sum(
                pair_count(Counter({signature: sum(counts.values())})) - pair_count(counts)
                for signature, counts in signature_family_uses[s].items()
            ) for s in range(3)},
        "numericSignaturesSpanningFamiliesBySlot": {
            str(s): {signature: sorted(names) for signature, names in
                     sorted(cross_family_signatures[s].items()) if len(names) > 1}
            for s in range(3)},
    }


def simulate() -> tuple[dict, dict, dict]:
    source = _source_tasks()
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
    catalog = capacity._catalog()  # noqa: SLF001
    numeric_catalog = {}
    for slot in range(3):
        numeric_catalog[slot] = {
            identity: (family, task)
            for family, task, _, identity in numeric._inventory(slot)  # noqa: SLF001
        }
    stored: list[dict] = []
    prompts: list[str] = []
    items: list[dict] = []
    snapshots = []

    for batch in range(1, 17):
        rows, numeric_proof, english_proof, failures = agreement.prepare_mapped_agreement_rows(
            adapted, contract, existing_prompts=tuple(prompts[-30:]),
            blocked_variant_identities=tuple(question_bank._agreement_variant_history(stored)),
            blocked_quantitative_variant_identities=tuple(
                question_bank._mapped_quantitative_variant_history(stored)),
        )
        if failures or len(rows) != 5 or set(numeric_proof) != {0, 1, 2} or set(english_proof) != {3, 4}:
            raise AssertionError(f"Batch {batch} failed: {failures}")
        for slot, row in enumerate(rows):
            identity = _normalized_stem_identity(row["prompt"])
            if identity in {_normalized_stem_identity(prompt) for prompt in prompts}:
                raise AssertionError(f"Batch {batch}, slot {slot} repeated an exact stem")
            if identity not in catalog[slot]:
                raise AssertionError(f"Batch {batch}, slot {slot} left the closed inventory")
            if (len(row["choices"]) != 4 or len(set(row["choices"])) != 4
                    or row["choices"].count(row["expectedAnswer"]) != 1
                    or set(row["choiceExplanations"]) != set(row["choices"])):
                raise AssertionError(f"Batch {batch}, slot {slot} lost key or feedback")
            (numeric_proof if slot < 3 else english_proof)[slot].content(row)
            family = catalog[slot][identity]
            if slot < 3:
                numeric_family, task = numeric_catalog[slot][identity]
                if family != numeric_family:
                    raise AssertionError("Numeric inventory classification changed")
                scene = None
                solve_signature = signature_module.numeric_signature(task)
                prompt_format = "exact_rational_expression" if slot == 0 else "bounded_condition"
            else:
                task = json.loads(english_proof[slot].task_json)
                scene = task["scene"]
                solve_signature = None
                prompt_format = ("full_sentence_selection" if scene in agreement.SENTENCE_SELECTION_SCENES
                                 else "two_blank_agreement")
            items.append({"batch": batch, "slot": slot, "family": family,
                          "scene": scene, "format": prompt_format,
                          "solveSignature": solve_signature, "task": task, "row": row})
            prompts.append(row["prompt"])
            stored.append({"questionJSON": {"S": json.dumps(row, sort_keys=True)},
                           "state": {"S": "ready"},
                           "createdAt": {"N": str(len(stored))}})
        if batch in (4, 8, 16):
            snapshots.append(_snapshot(items))

    # The first chronological 20 do not yet contain the newly added
    # sentence-selection, quadratic-exclusion, or linear-budget mechanisms.
    # Stratify the blind worksheet over the first 40 replayed items so the
    # sample actually tests those additions and cross-family solve overlap.
    selected = [next(item for item in items[:40]
                     if item["slot"] == slot and item["family"] == family)
                for slot, families in SAMPLE_FAMILIES.items() for family in families]
    if len(selected) != 20 or len({id(item) for item in selected}) != 20:
        raise AssertionError("Stratified worksheet did not select 20 distinct items")
    order = list(range(20))
    random.Random(ITEM_ORDER_SEED).shuffle(order)
    worksheet_items = []
    private_map = {}
    for index, source_index in enumerate(order, 1):
        item = selected[source_index]
        row = item["row"]
        choices = list(row["choices"])
        random.Random(int(_sha(f'{CHOICE_SEED}:{row["prompt"]}'.encode())[:16], 16)).shuffle(
            choices)
        displayed = dict(zip("ABCD", choices, strict=True))
        key = next(label for label, choice in displayed.items()
                   if choice == row["expectedAnswer"])
        question_id = f"Q{index:02d}"
        worksheet_items.append({"id": question_id, "prompt": row["prompt"],
                                "choices": displayed})
        private_map[question_id] = {**item, "key": key}
    worksheet = {"status": "offline_code_owned_candidates_not_worker_verified",
                 "targetDifficulty": "2–3", "items": worksheet_items}
    private = {"worksheetSha256": _sha(_render(worksheet).encode()),
               "mapping": private_map}
    summary = {"sourceCommit": SOURCE_COMMIT, "sourceCaptureSha256": CAPTURE_SHA256,
               "sourceTaskSeedSha256": _sha(_render(source).encode()),
               "worksheetSha256": private["worksheetSha256"],
               "worksheetSampling": "one earliest occurrence per named family from first 40 items",
               "worksheetFamilyRoster": {str(slot): list(families)
                                         for slot, families in SAMPLE_FAMILIES.items()},
               "snapshots": snapshots, "providerCalls": 0,
               "workerCalls": 0, "bankWrites": 0}
    return summary, worksheet, private


def main() -> None:
    private_dir = Path(os.environ["CHECKPOINT_PRIVATE_MAP_DIR"])
    summary, worksheet, private = simulate()
    _freeze(HERE / "summary.json", summary)
    _freeze(HERE / "worksheet.json", worksheet)
    private_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_file = private_dir / "answer-map.json"
    _freeze(private_file, private)
    private_file.chmod(0o600)
    print(_render({"items": [snapshot["items"] for snapshot in summary["snapshots"]],
                   "worksheetSha256": summary["worksheetSha256"],
                   "privateMap": str(private_file), "providerCalls": 0}))


if __name__ == "__main__":
    main()
