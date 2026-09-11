#!/usr/bin/env python3
"""Export blinded complete-teaching packets without calls or quality selection.

Adapted from the archived native-workflow assessment exporter. Every recoverable
author-array occurrence gets an ID, including malformed subjects and teaching.
Phase one exposes only readable subject fields; phase two preserves the entire
raw question value and every choiceFeedback row without native adaptation. Client
mode uses the actual Swift order/displays, never Python replacement compositions.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import random
import sys

SERVICE = Path(__file__).resolve().parents[1]
ROOT = SERVICE.parents[1]
sys.path.insert(0, str(SERVICE))

from evals import checkpoint_runtime_qualification as runtime  # noqa: E402
from question_quality import _extract_json_object, _strict_json_object  # noqa: E402
from service_errors import ProviderError  # noqa: E402

EXPERIMENT = "native-complete-teaching-workflow-v1"
SHUFFLE_SEED = "complete-teaching-20260910"
OPERATION_STATUSES = {"completed", "coverage_failure", "operational_failure", "unattempted"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def load(path):
    raw = Path(path).read_bytes()
    return _strict_json_object(raw.decode("utf-8")), digest(raw)


def capture_input(path):
    capture, byte_hash = load(path)
    require(capture.get("status") in {"completed", "operational_failure"}, "Capture must be terminal.")
    plan = capture.get("plan")
    require(type(plan) is dict and plan.get("experiment") == EXPERIMENT, "Wrong experiment.")
    require(capture.get("plan_sha256") == runtime._hash(plan), "Capture plan hash mismatch.")
    cases, jobs, operations = plan["fixture"]["cases"], plan["operations"], capture["operations"]
    require(all(type(rows) is list and len(rows) == 3 for rows in (cases, jobs, operations)), "All three operations required.")
    require(type(capture.get("calls")) is list, "Call inventory missing.")
    require(plan.get("maximum_calls") == 18 and len(capture["calls"]) <= 18, "Call allowance changed.")
    require(plan.get("fixture_sha256") == runtime._hash(plan["fixture"]), "Fixture hash mismatch.")
    require(plan["fixture"].get("experiment") == EXPERIMENT, "Wrong fixture experiment.")
    require(len({case["case_id"] for case in cases}) == 3, "Case identities must be distinct.")
    for index, (case, job, operation) in enumerate(zip(cases, jobs, operations, strict=True)):
        require(case["case_id"] == job["case_id"] == operation["case_id"], f"Operation {index} identity mismatch.")
        require(case["payload"]["targetCount"] == job["request"]["targetCount"] == 5, "Requested slots changed.")
        require(case["payload"].get("feedbackContract") == job["request"].get("feedbackContract") == "authored_complete",
                "Explicit complete-teaching selector missing or changed.")
        require(case["payload"].get("minimumDifficulty") == job["request"].get("minimumDifficulty") == 3,
                "Prospective difficulty floor changed.")
        require(job.get("kind") == operation.get("kind") == "fresh" and job.get("maximum_calls") == 6
                and operation.get("maximum_calls") == 6, "Fresh operation allowance changed.")
        require(operation.get("status") in OPERATION_STATUSES, "Unknown operation status.")
        require(type(operation.get("questions")) is list, "Runtime occurrence inventory missing.")
        require(len(operation["questions"]) <= 5, "Runtime exceeds requested slots.")
        if operation["status"] == "unattempted":
            require(not operation["questions"], "Unattempted operation returned questions.")
    call_counts = Counter()
    for call in capture["calls"]:
        index = call.get("operation_index")
        require(type(index) is int and 0 <= index < 3, "Call operation binding missing.")
        require(operations[index]["status"] != "unattempted", "Unattempted operation has calls.")
        require(type(call.get("operation_call_index")) is int
                and call["operation_call_index"] == call_counts[index], "Call occurrence order changed.")
        require(call.get("request_sha256") == runtime._hash(call["request"]), "Call request hash mismatch.")
        call_counts[index] += 1
        require(call_counts[index] <= 6, "Operation call allowance exceeded.")
    parser_hash = digest((SERVICE / "question_quality.py").read_bytes())
    require(plan["source_sha256"].get("question_quality.py") == parser_hash, "Extraction parser differs from frozen runtime.")
    binding = {"capture_byte_sha256": byte_hash, "capture_canonical_sha256": runtime._hash(capture),
               "plan_sha256": capture["plan_sha256"], "source_revision": plan["source_revision"]}
    return capture, binding


def denominators(capture):
    return [{"operation_index": index, "case_id": operation["case_id"], "requested_slots": 5,
             "runtime_status": operation["status"], "runtime_returned_count": len(operation["questions"]),
             "generation_shortfall": 5 - len(operation["questions"]),
             "result_category": operation.get("result_category"),
             "observed_call_count": sum(call["operation_index"] == index for call in capture["calls"])}
            for index, operation in enumerate(capture["operations"])]


def subject_fields(question, *, choices_key="choices"):
    return (type(question) is dict and type(question.get("prompt")) is str
            and type(question.get(choices_key)) is list
            and all(type(choice) is str for choice in question[choices_key]))


def opaque_rows(rows, phase):
    """One prospectively seeded permutation, without mutating the inventory."""
    shuffled = list(rows)
    seed = int.from_bytes(hashlib.sha256(f"{SHUFFLE_SEED}:{phase}".encode("utf-8")).digest(), "big")
    random.Random(seed).shuffle(shuffled)
    return [(f"q{index:03d}", row) for index, row in enumerate(shuffled, 1)]


def masked_subject(item_id, question, context, *, choices_key="choices"):
    value = question if type(question) is dict else {}
    prompt = value.get("prompt")
    choices = value.get(choices_key)
    # A malformed nested object might itself contain an answer/explanation. Do
    # not leak it in phase one or silently extract a repaired subset of choices.
    return {"id": item_id, "goal": copy.deepcopy(context["goal"]),
            "sourceDocuments": copy.deepcopy(context.get("sourceDocuments", [])),
            "prompt": prompt if type(prompt) is str else None,
            "choices": copy.deepcopy(choices) if type(choices) is list
                       and all(type(choice) is str for choice in choices) else None,
            "subject_status": "readable" if subject_fields(question, choices_key=choices_key) else "malformed"}


def teaching_structure(question):
    """Describe raw shape without admission, repairing rows or judging truth."""
    if type(question) is not dict:
        return {"question_type": type(question).__name__, "issues": ["question_not_object"]}
    choices, rows = question.get("choices"), question.get("choiceFeedback")
    readable_choices = type(choices) is list and all(type(choice) is str for choice in choices)
    matches = Counter()
    malformed, unmatched, wrong_fields, blank_explanations, explanation_lengths = [], [], [], [], []
    if type(rows) is list:
        for index, row in enumerate(rows):
            if type(row) is not dict:
                malformed.append(index)
                continue
            if set(row) != {"choice", "explanation"}:
                wrong_fields.append(index)
            if type(row.get("choice")) is not str or type(row.get("explanation")) is not str:
                malformed.append(index)
            if type(row.get("explanation")) is str:
                explanation_lengths.append({"row_index": index, "code_points": len(row["explanation"])})
                if not row["explanation"].strip():
                    blank_explanations.append(index)
            if readable_choices and type(row.get("choice")) is str and row["choice"] in choices:
                matches[row["choice"]] += 1
            else:
                unmatched.append(index)
    missing = [index for index, choice in enumerate(choices) if matches[choice] == 0] if readable_choices else None
    duplicates = [index for index, choice in enumerate(choices) if matches[choice] > 1] if readable_choices else None
    return {
        "question_type": "dict", "present_fields": sorted(question),
        "field_types": {key: type(question[key]).__name__ if key in question else "missing"
                        for key in ("prompt", "choices", "expectedAnswer", "explanation", "choiceFeedback", "choiceExplanations")},
        "empty_string_fields": [key for key in ("prompt", "expectedAnswer", "explanation")
                                if type(question.get(key)) is str and not question[key].strip()],
        "choice_feedback_row_count": len(rows) if type(rows) is list else None,
        "missing_choice_indices": missing, "duplicate_choice_indices": duplicates,
        "unmatched_row_indices": unmatched, "malformed_row_indices": malformed,
        "wrong_row_fields_indices": wrong_fields, "blank_explanation_indices": blank_explanations,
        "explanation_lengths": explanation_lengths,
        "four_exact_feedback_rows": readable_choices and len(choices) == 4 and len(set(choices)) == 4
            and type(rows) is list and len(rows) == 4
            and not any((missing, duplicates, unmatched, malformed, wrong_fields, blank_explanations)),
    }


def require_binding(capture, binding):
    require(binding.get("capture_canonical_sha256") == runtime._hash(capture)
            and binding.get("plan_sha256") == capture.get("plan_sha256"), "Capture changed after input binding.")


def finish(output, files, binding, counts, selection):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for name, value in files.items():
        with (output / name).open("x", encoding="utf-8") as stream:
            json.dump({**binding, **value}, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
    manifest = {**binding, **counts, "requested_slots": 15, "selection": selection,
                "shuffle": {"seed": SHUFFLE_SEED, "phase": counts["phase"],
                            "algorithm": "Python random.Random(int.from_bytes(SHA256(UTF8(seed + ':' + phase)), 'big')).shuffle once over occurrence order"},
                "builder_byte_sha256": digest(Path(__file__).read_bytes()),
                "parser_byte_sha256": digest((SERVICE / "question_quality.py").read_bytes()),
                "files": {name: digest((output / name).read_bytes()) for name in files}}
    (output / "packet-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return manifest


def raw_packets(capture, binding, output):
    require_binding(capture, binding)
    rows, calls, malformed = [], [], []
    per_operation = denominators(capture)
    for entry in per_operation:
        entry.update(author_calls=0, parsed_question_occurrences=0, masked_subject_occurrences=0, readable_subject_occurrences=0,
                     malformed_question_occurrences=0, unreadable_author_calls=0)
    for call_index, call in enumerate(capture["calls"]):
        if call.get("role") not in {"author", "author_json_repair"}:
            continue
        operation_index = call.get("operation_index")
        require(type(operation_index) is int and 0 <= operation_index < 3, "Author operation binding missing.")
        require(call.get("request_sha256") == runtime._hash(call["request"]), "Author request hash mismatch.")
        context = capture["plan"]["operations"][operation_index]["request"]
        tally = per_operation[operation_index]
        tally["author_calls"] += 1
        raw = ((call.get("observation") or {}).get("response") or {}).get("text")
        observation = {"call_index": call_index, "operation_index": operation_index,
                       "operation_call_index": call.get("operation_call_index"), "role": call["role"],
                       "lifecycle": call.get("lifecycle"), "response_text_sha256": digest(raw.encode()) if type(raw) is str else None}
        try:
            require(type(raw) is str, "No observed author text.")
            try:
                parsed = _strict_json_object(raw)
                observation["parser"] = "whole_object_or_sole_fence"
            except ProviderError:
                parsed = _extract_json_object(raw)
                observation["parser"] = "existing_author_recovery"
            # The existing recovery helper tries a brace-delimited object
            # before a prose-wrapped root array. Recover that outer array too,
            # without mistaking an object's nested choices array for questions.
            if (type(parsed.get("questions")) is not list and 0 <= raw.find("[") < raw.find("{")):
                parsed = _extract_json_object(raw[raw.find("["):raw.rfind("]") + 1])
                observation["parser"] = "existing_author_recovery_root_array"
            require(type(parsed.get("questions")) is list, "No questions array in recoverable author output.")
        except (ProviderError, ValueError) as error:
            observation.update(status="unreadable", error_type=type(error).__name__, reason=str(error))
            malformed.append({**observation, "raw_text": raw})
            tally["unreadable_author_calls"] += 1
            calls.append(observation)
            continue
        observation.update(status="parsed", question_occurrences=len(parsed["questions"]))
        tally["parsed_question_occurrences"] += len(parsed["questions"])
        for question_index, question in enumerate(parsed["questions"]):
            entry = {"call_index": call_index, "operation_index": operation_index,
                     "operation_call_index": call.get("operation_call_index"), "question_index": question_index,
                     "role": call["role"], "case_id": context.get("case_id", tally["case_id"]),
                     "request_sha256": call["request_sha256"], "response_text_sha256": observation["response_text_sha256"],
                     "question": copy.deepcopy(question), "context": context}
            rows.append(entry)
            tally["masked_subject_occurrences"] += 1
            if subject_fields(question):
                tally["readable_subject_occurrences"] += 1
            else:
                malformed.append({**entry, "status": "malformed_question_fields"})
                tally["malformed_question_occurrences"] += 1
        calls.append(observation)
    first, teaching, mapping = [], [], []
    for item_id, entry in opaque_rows(rows, "raw_author"):
        question, context = entry["question"], entry["context"]
        first.append(masked_subject(item_id, question, context))
        teaching.append({"id": item_id, "authored": copy.deepcopy(question), "structure": teaching_structure(question)})
        mapping.append({"id": item_id, **{key: value for key, value in entry.items() if key != "context"}})
    return finish(output, {
        "raw-stems-and-choices.json": {"items": first},
        "authored-key-teaching.json": {"items": teaching},
        "private-mapping.json": {"items": mapping, "author_calls": calls},
        "private-malformed-occurrences.json": {"occurrences": malformed},
    }, binding, {"phase": "raw_author", "operations": per_operation,
                 "author_call_count": len(calls), "masked_subject_count": len(first),
                 "readable_subject_count": sum(r["readable_subject_occurrences"] for r in per_operation),
                 "parsed_question_occurrence_count": sum(r["parsed_question_occurrences"] for r in per_operation),
                 "malformed_question_occurrence_count": sum(r["malformed_question_occurrences"] for r in per_operation),
                 "unreadable_author_call_count": sum(r["unreadable_author_calls"] for r in per_operation)},
        "Every author/repair/topoff call and every recoverable questions-array occurrence is inventoried. Every array row gets a phase-one ID; non-string subjects or non-string-list choices are null placeholders, not silently repaired. Phase two preserves each entire raw value including every choiceFeedback row and malformed or incomplete teaching. Unreadable calls remain private with unknown item counts. There is no native adaptation, length, correctness, difficulty or survival filtering. Raw questions are extra opportunities, not additional requested slots.")


def client_packets(capture, binding, bank_path, client_path, output):
    require_binding(capture, binding)
    bank, bank_hash = load(bank_path)
    client, client_hash = load(client_path)
    plan = capture["plan"]
    native = bank.get("native_capture_binding")
    require(type(native) is dict and native.get("experiment") == EXPERIMENT and native.get("exact_runtime_replay") is True,
            "Bank report lacks exact native replay binding.")
    require(bank.get("capture_sha256") == binding["capture_byte_sha256"], "Bank capture bytes mismatch.")
    require(native.get("capture_canonical_sha256") == binding["capture_canonical_sha256"], "Bank capture content mismatch.")
    for key in ("plan_sha256", "source_revision"):
        require(native.get(key) == binding[key], f"Bank {key} mismatch.")
    for key in ("source_sha256", "delivery_source_sha256", "dependencies"):
        require(native.get(key) == plan[key], f"Bank frozen {key} mismatch.")
    require(bank.get("source_sha256") == plan["delivery_source_sha256"], "Bank delivery-source mismatch.")
    require(client.get("delivery_fixture_sha256") == bank_hash, "Swift attachment refers to different bank-report bytes.")
    require(client.get("source_sha256") == bank["source_sha256"], "Swift attachment source binding mismatch.")
    require(bank.get("requested_count") == 15, "Bank requested-slot denominator changed.")
    require(all(type(value.get("operations")) is list and len(value["operations"]) == 3 for value in (bank, client)),
            "Both delivery reports must retain all three operations.")
    per_operation, rows = denominators(capture), []
    for index, (bank_operation, observed) in enumerate(zip(bank["operations"], client["operations"], strict=True)):
        require(bank_operation.get("operation_index") == observed.get("operation_index") == index, "Delivery operation order changed.")
        require(bank_operation.get("case_id") == per_operation[index]["case_id"], "Bank case binding mismatch.")
        require(bank_operation.get("bank_feedback_contract") == "authored_complete", "Bank complete-teaching selector changed.")
        claim_request = bank_operation.get("claim_request", {})
        require(claim_request.get("minimumVerificationVersion") == 1
                and claim_request.get("minimumVerificationPolicyRevision") == 4, "Bank verification floor changed.")
        client_request_provenance = (observed.get("case_id") == per_operation[index]["case_id"]
                                    and observed.get("request_feedback_contract") == "authored_complete"
                                    and observed.get("minimum_verification_policy_revision") == 4)
        if "error" not in observed:
            require(client_request_provenance, "Swift request selector, case or verification floor changed.")
        require(runtime._same(bank_operation.get("runtime_questions"), capture["operations"][index]["questions"]),
                "Bank runtime occurrence inventory changed.")
        original = copy.deepcopy(plan["fixture"]["cases"][index]["payload"])
        for field in ("targetCount", "minimumDifficulty"):
            original[field] = plan["operations"][index]["request"][field]
        require(runtime._same(bank_operation.get("request"), original), "Swift input context differs from original case.")
        claimed = (bank_operation.get("claim_response") or {}).get("questions", [])
        require(type(claimed) is list, "Claim occurrence array missing.")
        by_remote = {q["remoteID"]: q for q in claimed}
        require(len(by_remote) == len(claimed), "Ambiguous claim remote-ID binding.")
        retained = observed.get("retained_questions", [])
        require(type(retained) is list and ("retained_questions" in observed or "error" in observed), "Swift retained inventory missing.")
        require("error" not in observed or not retained, "Failed Swift operation unexpectedly retained unbound questions.")
        require(observed.get("client_retained_count") == len(retained), "Swift retained denominator mismatch.")
        for value in (bank_operation, observed):
            require(value.get("runtime_returned_count") == per_operation[index]["runtime_returned_count"], "Runtime denominator mismatch.")
            require(value.get("bank_claimable_count") == len(claimed), "Claim denominator mismatch.")
        ids = [question.get("remoteID") for question in retained]
        require(all(type(remote) is str and remote in by_remote for remote in ids), "Retained ID absent from the exact claim.")
        require(len(set(ids)) == len(ids), "Ambiguous retained occurrence ID.")
        dropped = [q["remoteID"] for q in claimed if q["remoteID"] not in ids]
        require("client_dropped_remote_ids" in observed or "error" in observed, "Swift dropped-ID inventory missing.")
        if "client_dropped_remote_ids" in observed:
            require(observed["client_dropped_remote_ids"] == dropped, "Swift dropped-ID inventory mismatch.")
        per_operation[index].update(
            prepared_count=bank_operation.get("prepared_count"), bank_claimable_count=len(claimed),
            bank_shortfall=per_operation[index]["runtime_returned_count"] - len(claimed),
            client_retained_count=len(retained), client_shortfall=len(claimed) - len(retained),
            client_dropped_remote_ids=dropped, client_error=observed.get("error"),
            client_request_provenance_observed=client_request_provenance,
            client_drop_inventory_observed="client_dropped_remote_ids" in observed,
        )
        for question_index, question in enumerate(retained):
            require(subject_fields(question, choices_key="displayed_choices"), "Swift retained subject fields are unreadable.")
            require(len(question["displayed_choices"]) == 4 and type(question.get("feedback_displays")) is list
                    and len(question["feedback_displays"]) == 4, "All four actual Swift feedback displays required.")
            require(all(type(row) is dict and type(row.get("choice")) is str and type(row.get("display")) is str
                        and "choice_feedback" in row for row in question["feedback_displays"]),
                    "Actual Swift feedback fields missing.")
            prior = by_remote[question["remoteID"]]
            rows.append({"operation_index": index, "question_index": question_index,
                         "case_id": per_operation[index]["case_id"], "context": original,
                         "question": copy.deepcopy(question), "claimed_question": copy.deepcopy(prior),
                         "claim_client_checks": {
                             "prompt_exact": question["prompt"] == prior.get("prompt"),
                             "key_exact": question.get("expectedAnswer") == prior.get("expectedAnswer"),
                             "main_exact": question.get("main") == prior.get("explanation"),
                             "choices_same_multiset": Counter(question["displayed_choices"]) == Counter(prior.get("choices", [])),
                             "feedback_order_matches_choices": [row.get("choice") for row in question["feedback_displays"]] == question["displayed_choices"],
                             "choice_feedback_exact": type(prior.get("choiceExplanations")) is dict and all(
                                 row["choice"] in prior["choiceExplanations"]
                                 and row["choice_feedback"] == prior["choiceExplanations"][row["choice"]]
                                 for row in question["feedback_displays"]),
                             "complete_provenance": type(question.get("verificationVersion")) is int
                                 and question["verificationVersion"] == prior.get("verificationVersion") == 1
                                 and type(question.get("verificationPolicyRevision")) is int
                                 and question["verificationPolicyRevision"] == prior.get("verificationPolicyRevision") == 4,
                         }})
    for key in ("runtime_returned_count", "bank_claimable_count", "client_retained_count"):
        require(client.get(key) == sum(operation[key] for operation in per_operation), f"Client aggregate {key} mismatch.")
    for key in ("runtime_returned_count", "bank_claimable_count"):
        require(bank.get(key) == sum(operation[key] for operation in per_operation), f"Bank aggregate {key} mismatch.")
    first, keys, teaching, mapping = [], [], [], []
    for item_id, entry in opaque_rows(rows, "actual_swift_client"):
        question, context = entry["question"], entry["context"]
        first.append(masked_subject(item_id, question, context, choices_key="displayed_choices"))
        keys.append({"id": item_id, "expectedAnswer": question.get("expectedAnswer")})
        teaching.append({"id": item_id, "main": question.get("main"),
                         "feedback_displays": copy.deepcopy(question["feedback_displays"])})
        mapping.append({"id": item_id, **{key: value for key, value in entry.items() if key != "context"}})
    return finish(output, {
        "client-stems-and-choices.json": {"items": first}, "client-keys.json": {"items": keys},
        "client-teaching.json": {"items": teaching}, "private-mapping.json": {"items": mapping},
    }, {**binding, "bank_delivery_byte_sha256": bank_hash, "swift_attachment_byte_sha256": client_hash},
        {"phase": "actual_swift_client", "operations": per_operation, "masked_subject_count": len(first),
         "client_retained_count": client["client_retained_count"], "bank_claimable_count": bank["bank_claimable_count"],
         "runtime_returned_count": bank["runtime_returned_count"],
         "claim_client_mismatch_count": sum(not all(row["claim_client_checks"].values()) for row in rows),
         "complete_provenance_mismatch_count": sum(not row["claim_client_checks"]["complete_provenance"] for row in rows)},
        "Every actual Swift-retained occurrence, in its actual displayed choice order, with all observed feedback displays separately concealed. No factual or presentation-quality filter. All three operations,15 requested slots, runtime shortfalls, bank losses, client drops and operation errors remain in denominators. Content differences are recorded privately rather than replaced by Python reconstructions.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("raw", "client"))
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bank-delivery", type=Path)
    parser.add_argument("--client-attachment", type=Path)
    args = parser.parse_args(argv)
    if args.phase == "client" and (args.bank_delivery is None or args.client_attachment is None):
        parser.error("Client phase requires exact bank delivery and actual Swift attachment files.")
    if args.phase == "raw" and (args.bank_delivery is not None or args.client_attachment is not None):
        parser.error("Raw phase accepts no client delivery input.")
    capture, binding = capture_input(args.capture)
    manifest = raw_packets(capture, binding, args.output) if args.phase == "raw" else client_packets(
        capture, binding, args.bank_delivery, args.client_attachment, args.output,
    )
    print(json.dumps({"phase": manifest["phase"], "items": manifest["masked_subject_count"],
                      "requested_slots": manifest["requested_slots"], "output": str(args.output)}))


if __name__ == "__main__":
    main()
