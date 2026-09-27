"""Reproduce the refined answer-hidden worksheet from the pinned source.

Run at f48440e with the backend test dependencies on PYTHONPATH. This uses the
closed five-slot fake-author fixture and makes no network or bank calls.
"""

import hashlib
import json
import random
from pathlib import Path

import native_output_contracts as native
from agreement_task_constructor import prepare_mapped_agreement_rows
from test_mapped_quantitative_families import MappedQuantitativeFamilyTests


def main() -> None:
    fixture = MappedQuantitativeFamilyTests()
    fixture.setUp()
    source = fixture.raw()
    contract = fixture.contract()
    adapted = json.loads(native.adapt_native_response(json.dumps(source), contract))
    initial, _, _, failures = prepare_mapped_agreement_rows(adapted, contract)
    assert not failures and len(initial) == 5
    refill, _, _, failures = prepare_mapped_agreement_rows(
        adapted, contract, existing_prompts=tuple(row["prompt"] for row in initial),
    )
    assert not failures and len(refill) == 5

    worksheet = []
    private = []
    randomizer = random.Random(20260928)
    for generation, batch in (("initial", initial), ("refill", refill)):
        for slot, row in enumerate(batch):
            identifier = hashlib.sha256(
                f'{generation}|{slot}|{row["prompt"]}'.encode()
            ).hexdigest()[:10]
            choices = list(row["choices"])
            randomizer.shuffle(choices)
            assert len(choices) == len(set(choices)) == 4
            assert choices.count(row["expectedAnswer"]) == 1
            worksheet.append({
                "id": identifier, "prompt": row["prompt"],
                "choices": {chr(65 + index): choice for index, choice in enumerate(choices)},
            })
            private.append({
                "id": identifier, "generation": generation, "slot": slot,
                "key": chr(65 + choices.index(row["expectedAnswer"])),
                "answer": row["expectedAnswer"],
                "source": source["questions"][str(slot)],
            })
    randomizer.shuffle(worksheet)
    assert len({row["prompt"] for row in worksheet}) == 10
    directory = Path(__file__).resolve().parent
    for filename, rows in (("refined-worksheet.json", worksheet),
                           ("refined-private.json", private)):
        encoded = (json.dumps(rows, indent=2, ensure_ascii=False) + "\n").encode()
        assert (directory / filename).read_bytes() == encoded
        print(filename, hashlib.sha256(encoded).hexdigest())


if __name__ == "__main__":
    main()
