"""Join frozen assessments to exact runtime/client identities, without inference.

This artifact reports assessor agreement, not a model-independent truth oracle.
Run with Python 3.12; the optional argument is a new output filename. Original
packets and assessments are never edited, and output is never overwritten.
"""

import hashlib
import json
import sys
from collections import Counter
from pathlib import Path


BASE = Path(__file__).resolve().parent
INPUT_HASHES = {}


def read(relative):
    path = BASE / relative
    data = path.read_bytes()
    INPUT_HASHES[relative] = hashlib.sha256(data).hexdigest()
    return json.loads(data)


def indexed(rows, expected):
    result = {row["id"]: row for row in rows}
    assert len(rows) == len(result) == len(expected)
    assert set(result) == set(expected)
    return result


def counts(rows, field):
    return dict(sorted(Counter(row[field] for row in rows).items()))


def key_agreement(rows):
    states = [row["key_status"] for row in rows]
    if states == ["supported_unique", "supported_unique"]:
        return "supported_unique"
    if states == ["wrong", "wrong"]:
        return "wrong"
    if states == ["ambiguous", "ambiguous"]:
        return "ambiguous"
    return "disagreement"


def main():
    raw_packet = read("raw-assessment/raw-stems-and-choices.json")
    client_packet = read("client-assessment/client-stems-and-choices.json")
    raw_ids = [row["id"] for row in raw_packet["items"]]
    client_ids = [row["id"] for row in client_packet["items"]]
    raw_subject = indexed(raw_packet["items"], raw_ids)
    client_subject = indexed(client_packet["items"], client_ids)
    raw_mapping = indexed(read("raw-assessment/private-mapping.json")["items"], raw_ids)
    client_mapping = indexed(read("client-assessment/private-mapping.json")["items"], client_ids)
    raw_keys = indexed(read("raw-assessment/authored-key-main.json")["items"], raw_ids)
    client_keys = indexed(read("client-assessment/client-keys.json")["items"], client_ids)
    teaching = indexed(read("client-assessment/client-teaching.json")["items"], client_ids)
    lineage = read("stage-lineage.json")
    raw_lineage = {row["raw_blind_packet_id"]: row for row in lineage["occurrences"]}
    assert set(raw_lineage) == set(raw_ids)
    assert len(lineage["occurrences"]) == len(raw_ids)
    returned = {
        (row["returned"]["operation_index"], row["returned"]["question_index"]): row
        for row in lineage["occurrences"] if row["returned"] is not None
    }
    assert len(returned) == len(client_ids)
    concealed = {row["occurrence_id"]: row for row in lineage["concealed_key_and_feedback"]}
    assert len(concealed) == len(raw_ids)

    phase1 = {"raw": {}, "client": {}}
    phase2 = {"raw": {}, "client": {}}
    for kind, packet, ids in [("raw", raw_packet, raw_ids), ("client", client_packet, client_ids)]:
        freeze = read(f"{kind}-phase-one-freeze.json")
        packet_file = f"{kind}-assessment/{kind}-stems-and-choices.json"
        assert INPUT_HASHES[packet_file] == freeze["packet_byte_sha256"]
        subjects = indexed(packet["items"], ids)
        for assessor in "ab":
            filename = f"{kind}-assessment/assessment-{assessor}-phase1.json"
            assessment = read(filename)
            assert INPUT_HASHES[filename] == freeze["assessments"][assessor]["byte_sha256"]
            assert assessment["packet_sha256"] == freeze["packet_byte_sha256"]
            phase1[kind][assessor] = indexed(assessment["items"], ids)
            for qid, row in phase1[kind][assessor].items():
                assert len(row["per_choice"]) == len(subjects[qid]["choices"]) == 4
                assert sorted(choice["choice_index"] for choice in row["per_choice"]) == list(range(4))
                assert sorted(row["supported_choice_indices"]) == sorted(
                    choice["choice_index"] for choice in row["per_choice"]
                    if choice["judgment"] == "supported"
                )

    for assessor in "ab":
        assessment = read(f"raw-assessment/assessment-{assessor}-phase2.json")
        assert len(assessment["input_sha256"]) == 7
        for filename, sha256 in assessment["input_sha256"].items():
            if filename.startswith(("raw/", "client/")):
                kind, name = filename.split("/", 1)
                filename = f"{kind}-assessment/{name}"
            elif filename.startswith("client-"):
                filename = f"client-assessment/{filename}"
            else:
                filename = f"raw-assessment/{filename}"
            assert INPUT_HASHES[filename] == sha256
        phase2["raw"][assessor] = indexed(assessment["authored_items"], raw_ids)
        phase2["client"][assessor] = indexed(assessment["client_items"], client_ids)
        for kind, ids, keys, subjects in [
            ("raw", raw_ids, raw_keys, raw_subject),
            ("client", client_ids, client_keys, client_subject),
        ]:
            for qid in ids:
                first = phase1[kind][assessor][qid]
                second = phase2[kind][assessor][qid]
                prior_match = (
                    first["status"] == "unique"
                    and len(first["supported_choice_indices"]) == 1
                    and subjects[qid]["choices"][first["supported_choice_indices"][0]] == keys[qid]["expectedAnswer"]
                )
                assert second["key_matches_prior_unique"] == prior_match
                assert (second["key_status"] == "supported_unique") == prior_match

    raw_rows = []
    for qid in raw_ids:
        mapping, line = raw_mapping[qid], raw_lineage[qid]
        assert (mapping["call_index"], mapping["question_index"]) == (
            line["author"]["call_index"], line["author"]["question_index"]
        )
        assert mapping["question"]["prompt"] == line["author"]["subject"]["prompt"] == raw_subject[qid]["prompt"]
        assert mapping["question"]["choices"] == line["author"]["subject"]["choices"] == raw_subject[qid]["choices"]
        assert mapping["question"]["expectedAnswer"] == raw_keys[qid]["expectedAnswer"]
        seconds = [phase2["raw"][a][qid] for a in "ab"]
        raw_rows.append({
            "raw_id": qid,
            "occurrence_id": line["occurrence_id"],
            "case_id": line["case_id"],
            "terminal_outcome": line["terminal_outcome"],
            "client_id": None,
            "key_agreement": key_agreement(seconds),
            "main_support": {a: phase2["raw"][a][qid]["main_support"] for a in "ab"},
            "difficulty": {a: phase1["raw"][a][qid]["difficulty"] for a in "ab"},
            "distinct_choices": {a: phase1["raw"][a][qid]["distinct_choices"] for a in "ab"},
            "plausible_distractors": {a: phase1["raw"][a][qid]["plausible_distractors"] for a in "ab"},
        })
    raw_by_id = {row["raw_id"]: row for row in raw_rows}
    client_rows, display_rows, used_returns = [], [], set()
    for qid in client_ids:
        mapping = client_mapping[qid]
        identity = (mapping["operation_index"], mapping["question_index"])
        assert identity not in used_returns
        used_returns.add(identity)
        line = returned[identity]
        proposed = line["returned"]["subject"]
        question = mapping["question"]
        assert question["prompt"] == client_subject[qid]["prompt"] == proposed["prompt"]
        assert question["displayed_choices"] == client_subject[qid]["choices"]
        assert Counter(question["displayed_choices"]) == Counter(proposed["choices"])
        unchanged = concealed[line["occurrence_id"]]["returned"]
        assert question["expectedAnswer"] == client_keys[qid]["expectedAnswer"] == unchanged["expectedAnswer"]
        assert question["main"] == teaching[qid]["main"] == unchanged["explanation"]
        assert question["feedback_displays"] == teaching[qid]["feedback_displays"]
        firsts = [phase1["client"][a][qid] for a in "ab"]
        seconds = [phase2["client"][a][qid] for a in "ab"]
        for assessor, row in zip("ab", seconds, strict=True):
            assert len(row["choice_feedback"]) == 4
            by_choice = {x["choice_index"]: x for x in row["choice_feedback"]}
            assert sorted(by_choice) == list(range(4))
            for index, choice in enumerate(question["displayed_choices"]):
                assert by_choice[index]["choice"] == choice
                display = question["feedback_displays"][index]
                assert display["choice"] == choice
                assert display["choice_feedback"] == unchanged["choiceExplanations"][choice]
            assert row["all_teaching_supported"] == (
                row["main_support"] == "supported"
                and all(x["display_support"] == "supported" for x in row["choice_feedback"])
            )
        key = key_agreement(seconds)
        whole_content = key == "supported_unique" and all(s["all_teaching_supported"] for s in seconds)
        design = all(s["goal_relevant"] and s["distinct_choices"] and s["plausible_distractors"] for s in firsts)
        difficulty = all(s["difficulty"] >= 3 for s in firsts)
        # Missing quantities can be intentional evidence for a uniquely warranted
        # cannot-determine key. Do not blindly turn premise_status into a veto.
        useful = whole_content and design and difficulty
        row = {
            "client_id": qid,
            "raw_id": line["raw_blind_packet_id"],
            "occurrence_id": line["occurrence_id"],
            "case_id": line["case_id"],
            "operation_index": identity[0],
            "returned_question_index": identity[1],
            "key_agreement": key,
            "whole_content_supported_by_both": whole_content,
            "goal_and_choice_quality_supported_by_both": design,
            "difficulty_at_least_three_by_both": difficulty,
            "useful_by_frozen_criterion": useful,
            "phase1": {a: phase1["client"][a][qid] for a in "ab"},
            "phase2": {a: phase2["client"][a][qid] for a in "ab"},
        }
        client_rows.append(row)
        raw_by_id[row["raw_id"]]["client_id"] = qid
        for index in range(4):
            support = {
                a: next(x for x in phase2["client"][a][qid]["choice_feedback"] if x["choice_index"] == index)["display_support"]
                for a in "ab"
            }
            display_rows.append({
                "client_id": qid, "choice_index": index, "assessment": support,
                "agreement": support["a"] if support["a"] == support["b"] else "disagreement",
            })
    assert used_returns == set(returned)
    operation_counts = []
    for case_id in dict.fromkeys(row["case_id"] for row in lineage["occurrences"]):
        raw = [row for row in raw_rows if row["case_id"] == case_id]
        client = [row for row in client_rows if row["case_id"] == case_id]
        operation_counts.append({
            "case_id": case_id, "requested_slots": 5, "raw_occurrences": len(raw),
            "client_retained": len(client),
            "whole_content_supported_by_both": sum(row["whole_content_supported_by_both"] for row in client),
            "useful_by_frozen_criterion": sum(row["useful_by_frozen_criterion"] for row in client),
        })
    summary = {
        "requested_slots": lineage["coverage"]["requested_slots"],
        "raw_occurrences": len(raw_rows), "client_retained": len(client_rows),
        "raw_key_agreement": counts(raw_rows, "key_agreement"),
        "client_key_agreement": counts(client_rows, "key_agreement"),
        "whole_content_supported_by_both": sum(row["whole_content_supported_by_both"] for row in client_rows),
        "useful_by_frozen_criterion": sum(row["useful_by_frozen_criterion"] for row in client_rows),
        "composed_displays": len(display_rows),
        "display_agreement": counts(display_rows, "agreement"),
        "display_support_by_assessor": {
            a: dict(Counter(row["assessment"][a] for row in display_rows)) for a in "ab"
        },
        "operations": operation_counts,
    }
    result = {
        "method": "Exact occurrence and return-index join, then independent assessor agreement; no adjudication overrides.",
        "limitations": "Assessor judgments are fallible. Disagreements and uncertainty are unresolved, not definitely false. This is one selected three-goal trial, not a population error-rate estimate.",
        "input_byte_sha256": INPUT_HASHES,
        "summary": summary, "raw_items": raw_rows, "client_items": client_rows,
        "composed_display_judgments": display_rows,
    }
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else BASE / "assessment-join.json"
    with output.open("x") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
