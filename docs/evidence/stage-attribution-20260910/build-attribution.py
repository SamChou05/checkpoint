"""Join frozen assessments to observed occurrences, never by question text."""

import collections
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def read(name):
    return json.loads((ROOT / name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    trace = read("trace.json")
    capture_path = ROOT.parent / "delivery-feedback-20260909/capture.json"
    capture = json.loads(capture_path.read_text())
    assert trace["exact_replay"] is True
    assert trace["capture_byte_sha256"] == sha(capture_path)
    assert trace["plan_sha256"] == capture["plan_sha256"]
    private = read("private-mapping.json")
    assessments, packets = {}, {}
    for group in ("a", "b"):
        freeze = read(f"freeze-{group}.json")
        for name, expected in freeze["files"].items():
            assert sha(ROOT / name) == expected, name
        packet = read(f"stems-{group}.json")
        assert packet["capture_byte_sha256"] == sha(capture_path)
        records = read(f"assessment-{group}.json")["items"]
        ids = [row["id"] for row in records]
        assert len(set(ids)) == len(ids)
        assert set(ids) == {row["id"] for row in packet["items"]}
        for row in records:
            assert row["id"] not in assessments
            assessments[row["id"]] = {"assessor": group, **row}
        packets.update({row["id"]: row for row in packet["items"]})
    assert set(private) == set(assessments) == set(packets)

    authored = {p["call_index"]: p for p in trace["author_payloads"] if p["parsed_payload"] is not None}
    rows, by_occurrence = {}, {}
    for opaque, origin in private.items():
        operation, call, ordinal = (origin[k] for k in ("operation_index", "call_index", "raw_index"))
        occurrence = f"{trace['capture_canonical_sha256']}:{operation}:{call}:{ordinal}"
        expected_id = "s" + hashlib.sha256(f"{sha(capture_path)}:{call}:{ordinal}".encode()).hexdigest()[:12]
        assert opaque == expected_id and occurrence not in by_occurrence
        assert capture["calls"][call]["operation_index"] == operation
        assert authored[call]["parsed_payload"]["questions"][ordinal] == origin["raw"]
        for field in ("goal", "sourceDocuments"):
            assert packets[opaque][field] == authored[call]["request"][field]
        for field in ("prompt", "choices"):
            assert packets[opaque][field] == origin["raw"][field]
        assessment = assessments[opaque]
        assert set(assessment["supported_choices"]) <= set(origin["raw"]["choices"])
        relation = assessment["status"]
        if relation == "unique":
            assert len(assessment["supported_choices"]) == 1
            relation = ("unique_authored_key" if assessment["supported_choices"] ==
                        [origin["raw"]["expectedAnswer"]] else "unique_other_key")
        rows[opaque] = {"id": opaque, "occurrence": occurrence, "origin": origin,
                        "assessment": assessment, "assessment_relation": relation,
                        "sanitizer": None, "sanitized_question": None,
                        "solver_decision": None, "provider_inputs": [], "review_events": [],
                        "verification_batch": None, "returned_question": None}
        by_occurrence[occurrence] = rows[opaque]

    for batch in trace["sanitizer_batches"]:
        for event in batch["events"]:
            if event["scope"] == "candidate":
                row = by_occurrence[event["occurrence"]]
                assert row["sanitizer"] is None
                assert row["origin"]["raw"] == batch["raw_questions"][event["raw_ordinal"]]
                row["sanitizer"] = event
        for accepted in batch["admitted"]:
            by_occurrence[accepted["occurrence"]]["sanitized_question"] = accepted["question"]
    batch_diagnostics = []
    for index, verification in enumerate(trace["verifications"]):
        for candidate in verification["candidates"]:
            row = by_occurrence[candidate["occurrence"]]
            assert row["sanitized_question"] == candidate["question"]
            row["verification_batch"] = index
        for provider in verification["provider_batches"]:
            for link in provider["links"]:
                item = provider["payload"]["items"][link["index"]]
                row = by_occurrence[link["occurrence"]]
                assert item["prompt"] == row["sanitized_question"]["prompt"]
                assert sorted(item["choices"]) == sorted(row["sanitized_question"]["choices"])
                row["provider_inputs"].append({"call_index": provider["call_index"],
                                               "role": provider["role"], "item": item})
        for decision in verification["solver_decisions"]:
            by_occurrence[decision["occurrence"]]["solver_decision"] = decision
        for event in verification["events"]:
            if event["scope"] == "candidate":
                by_occurrence[event["occurrence"]]["review_events"].append(event)
            else:
                # A cohort counter is not a rejection reason for every member.
                batch_diagnostics.append({"verification_batch": index, **event})
    for operation in trace["operations"]:
        expected = capture["operations"][operation["operation_index"]]["questions"]
        assert [row["question"] for row in operation["returned"]] == expected
        for accepted in operation["returned"]:
            row = by_occurrence[accepted["occurrence"]]
            assert row["returned_question"] is None
            row["returned_question"] = accepted["question"]

    values = sorted(rows.values(), key=lambda row: row["id"])
    assert len(values) == sum(len(b["raw_questions"]) for b in trace["sanitizer_batches"])
    assert all(row["sanitizer"] is not None for row in values)
    def counts(selected):
        return dict(sorted(collections.Counter(r["assessment_relation"] for r in selected).items()))
    admitted = [r for r in values if r["sanitized_question"] is not None]
    returned = [r for r in values if r["returned_question"] is not None]
    changes = []
    for row in admitted:
        raw, normalized = row["origin"]["raw"], row["sanitized_question"]
        fields = {key: {"before": raw.get(key), "after": normalized.get(key)}
                  for key in ("prompt", "expectedAnswer", "choices", "explanation")
                  if raw.get(key) != normalized.get(key)}
        if fields:
            changes.append({"id": row["id"], "fields": fields})
    return {"scope": "Retrospective, one independent assistant assessor per raw occurrence; not expert ground truth, fresh inference, current-source accuracy or a replacement for earlier returned-item assessments.",
            "trace_byte_sha256": sha(ROOT / "trace.json"), "capture_byte_sha256": sha(capture_path),
            "counts": {"raw_occurrences": len(values), "sanitizer_admissions": len(admitted),
                       "returned": len(returned), "raw_assessment_relations": counts(values),
                       "admitted_assessment_relations": counts(admitted),
                       "returned_assessment_relations": counts(returned)},
            "sanitizer_changes": changes, "batch_diagnostics": batch_diagnostics, "items": values}


if __name__ == "__main__":
    output = build()
    (ROOT / "attribution.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(output["counts"], sort_keys=True))
