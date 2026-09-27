"""Compare the saved mapped bank baseline with the relative-clause candidate.

This reuses the frozen 40/80 simulator without editing its original evidence
or calling a model, AWS, or a real bank.
"""

import importlib.util
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
BASELINE = HERE.parent / "mapped-bank-diversity-simulation-20260927"
spec = importlib.util.spec_from_file_location("mapped_bank_simulation", BASELINE / "run.py")
assert spec and spec.loader
simulation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulation)

old_family = simulation._english_family
simulation._english_family = lambda scene: (
    "relative" if scene in simulation.agreement.RELATIVE_SCENES else old_family(scene)
)

baseline = json.loads((BASELINE / "summary.json").read_text())
candidate = simulation.simulate()
for old, new in zip(baseline["checkpoints"], candidate["checkpoints"], strict=True):
    print(json.dumps({
        "items": new["items"],
        "baselineUniqueStems": old["uniqueExactStems"],
        "candidateUniqueStems": new["uniqueExactStems"],
        "baselineSameFamilyPairs": old["sameSlotFamilyPairsTotal"],
        "candidateSameFamilyPairs": new["sameSlotFamilyPairsTotal"],
        "candidateSlot3Families": new["slotSpecificFamilyCounts"]["3"],
    }, sort_keys=True))
print(json.dumps({"post80FailureReasons": candidate["post80FailureReasons"],
                  "providerCalls": candidate["providerCalls"]}, sort_keys=True))
