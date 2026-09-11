#!/usr/bin/env python3
"""Join already frozen blind assessments to arms; offline, no model calls."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path


def all_status(values):
    assert all(type(value) is bool or value is None for value in values)
    return False if False in values else None if None in values else True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.directory
    hashes = {}

    def read(name):
        raw = (root / name).read_bytes()
        hashes[name] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)

    rows = read("mapping.json")
    rationales, consistency = {}, {}
    for letter in "ab":
        packet = read(f"rationale-packet-{letter}.json")
        judgments = read(f"judgments-{letter}.json")
        assessed = read(f"rationale-assessment-{letter}.json")
        compared = read(f"consistency-assessment-{letter}.json")
        ids = {value["id"] for value in packet}
        assert len(ids) == len(packet)
        for values in (judgments, assessed, compared):
            assert len(values) == len(ids) and {value["id"] for value in values} == ids
        assert not set(rationales) & ids
        rationales.update({value["id"]: value for value in assessed})
        consistency.update({value["id"]: value for value in compared})
    assert set(rationales) == {value["id"] for value in rows if value["available"]}
    grouped = {arm: {group: Counter() for group in ("all", "historical", "fresh")}
               for arm in ("judgment_first", "reason_first")}
    paired, distinct = defaultdict(dict), defaultdict(list)
    joined, disagreements, ambiguous = [], [], []
    names = {"unique": "unique", "multiple_supported": "multiple", "zero_supported": "none", "ambiguous": "ambiguous"}
    for row in rows:
        result = {key: row[key] for key in ("id", "position", "batch_id", "index", "kind", "repeat", "arm", "scorable", "available")}
        if row["available"]:
            ra, co = rationales[row["id"]], consistency[row["id"]]
            choices = row["observed"]["record"]["choices"]
            assert [value["choice"] for value in choices] == [value["choice"] for value in ra["choices"]] == [value["choice"] for value in co["choices"]]
            assert all_status([value["rationale_correct"] for value in ra["choices"]]) is ra["all_rationales_correct"]
            assert all_status([value["consistent"] for value in co["choices"]]) is co["all_consistent"]
            result.update(exact_judgments=row["observed"]["matches_frozen_judgments"],
                          all_rationales_correct=ra["all_rationales_correct"], all_consistent=co["all_consistent"],
                          gate_eligible=row["observed"]["rejection_reason"] is None)
            result["jointly_correct"] = (
                result["exact_judgments"] is True and result["all_rationales_correct"] is True and result["all_consistent"] is True
            ) if row["scorable"] else None
            if names[row["premise_verdict"]] != ra["question_status"]:
                disagreements.append({"id": row["id"], "frozen_status": row["premise_verdict"],
                                      "assessor_status": ra["question_status"], "caveat": ra["caveat"]})
        joined.append(result)
        if not row["scorable"]:
            ambiguous.append(result)
            continue
        paired[(row["batch_id"], row["index"], row["repeat"])][row["arm"]] = result
        distinct[(row["batch_id"], row["index"], row["arm"])].append(result)
        for group in ("all", row["kind"]):
            metric = grouped[row["arm"]][group]
            metric["planned"] += 1
            metric["available"] += result["available"]
            if not result["available"]:
                continue
            for field in ("exact_judgments", "all_rationales_correct", "all_consistent", "jointly_correct"):
                metric[field + "_" + str(result[field]).lower()] += 1
            metric["rationale_choice_rows_correct"] += sum(value["rationale_correct"] is True for value in ra["choices"])
            metric["consistent_choice_rows"] += sum(value["consistent"] is True for value in co["choices"])
    pair_counts = Counter()
    for pair in paired.values():
        left, right = pair["judgment_first"], pair["reason_first"]
        if not left["available"] or not right["available"]:
            pair_counts["unavailable"] += 1
            continue
        a, b = left["jointly_correct"], right["jointly_correct"]
        pair_counts["both_correct" if a and b else "reason_first_only" if b else "judgment_first_only" if a else "neither_correct"] += 1
    repeated = {arm: Counter() for arm in grouped}
    for (_, _, arm), values in distinct.items():
        assert len(values) == 2
        repeated[arm]["planned_distinct_scorable_subjects"] += 1
        repeated[arm]["both_repetitions_available"] += all(value["available"] for value in values)
        repeated[arm]["both_repetitions_exact_judgments"] += all(value.get("exact_judgments") is True for value in values)
        repeated[arm]["both_repetitions_jointly_correct"] += all(value.get("jointly_correct") is True for value in values)
    report = {"input_byte_sha256": hashes, "assessment_scope": "Independent assistant assessments, not expert ground truth. Reasons assessed before declared verdicts; arm/repeat/keys hidden until this join.",
              "by_arm": grouped, "paired_joint_correctness": pair_counts, "distinct_subject_repetition_results": repeated,
              "subject_reading_disagreements": disagreements, "ambiguous_unscored": ambiguous, "responses": joined}
    with args.output.open("x") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps({key: report[key] for key in ("by_arm", "paired_joint_correctness", "distinct_subject_repetition_results")}, indent=2))


if __name__ == "__main__":
    main()
