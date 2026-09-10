#!/usr/bin/env python3
"""Six frozen author-only calls comparing absent versus checked demonstrations.

Dry by default. Reuses the main-capacity request compiler and unfiltered capture
runner. Both arms retain the actual 320-character main-explanation instruction.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_main_capacity_trial as capacity  # noqa: E402

shared, caller = capacity.shared, capacity.caller
_hash = capacity._hash
EXPERIMENT = "fresh-author-checked-examples-v1"
ARMS = ("no_examples", "checked_examples")
EXAMPLE_FIELDS = {"id", "subject_context", "question"}
QUESTION_FIELDS = {"prompt", "choices", "expectedAnswer", "explanation", "topic", "difficulty", "format"}
EXAMPLE_INSTRUCTION = """

The following checked examples illustrate complete premises, one correct answer,
three plausible distinct mistakes, and concise worked teaching. Transfer these
design standards to the current goal; do not reuse their subject matter or
wording. Each subject_context applies only to its example. Generate only the
requested new questions.
"""


def _nonempty_string(value):
    return type(value) is str and bool(value.strip())


def _demonstrations(packet):
    examples = packet.get("demonstrations") if type(packet) is dict else None
    if (type(packet) is not dict or packet.get("experiment") != EXPERIMENT
            or type(examples) is not list or len(examples) != 3):
        raise ValueError("Exactly three checked demonstrations are required.")
    projected, identifiers = [], set()
    for example in examples:
        if (type(example) is not dict or set(example) != EXAMPLE_FIELDS
                or not _nonempty_string(example["id"]) or example["id"] in identifiers
                or not _nonempty_string(example["subject_context"])):
            raise ValueError("Each demonstration has only a distinct ID, subject context and question.")
        identifiers.add(example["id"])
        question = example["question"]
        if type(question) is not dict or set(question) != QUESTION_FIELDS:
            raise ValueError("Demonstration question fields must match the author contract.")
        choices = question["choices"]
        if (type(choices) is not list or len(choices) != 4
                or not all(_nonempty_string(c) and len(c) <= 140 for c in choices)
                or len({c.strip().casefold() for c in choices}) != 4
                or not _nonempty_string(question["expectedAnswer"])
                or question["expectedAnswer"] not in choices
                or not _nonempty_string(question["prompt"]) or len(question["prompt"]) > 320
                or not _nonempty_string(question["explanation"]) or len(question["explanation"]) > 320
                or not _nonempty_string(question["topic"])
                or type(question["difficulty"]) is not int or question["difficulty"] not in (3, 4, 5)
                or question["format"] != "Multiple Choice"):
            raise ValueError("Demonstrations require four distinct bounded choices, an exact key and bounded teaching.")
        projected.append({"subject_context": example["subject_context"],
                          "question": copy.deepcopy(question)})
    return projected


def make_plan(packet, *, source_revision=None):
    examples = _demonstrations(packet)
    compiler_packet = copy.deepcopy(packet)
    compiler_packet["experiment"] = capacity.EXPERIMENT
    plan = capacity.make_plan(compiler_packet, source_revision=source_revision)
    suffix = (EXAMPLE_INSTRUCTION + "<checked_author_examples_json>\n"
              + shared.canonical(examples) + "\n</checked_author_examples_json>")
    baselines = [j for j in plan["jobs"] if j["arm"] == "main_320"]
    jobs = []
    for baseline in baselines:
        index = baseline["case_index"]
        for arm in ARMS if index % 2 == 0 else ARMS[::-1]:
            job = copy.deepcopy(baseline)
            job["arm"] = arm
            if arm == "checked_examples":
                job["request"]["system"][0]["text"] += suffix
            job["request_sha256"] = _hash(job["request"])
            job["input_utf8_bytes"] = capacity._input_bytes(job["request"])
            jobs.append(job)
    plan.update(
        experiment=EXPERIMENT, fixture=copy.deepcopy(packet), fixture_sha256=_hash(packet),
        jobs=jobs, planned_input_utf8_bytes=sum(j["input_utf8_bytes"] for j in jobs),
        scope="Author-only paired absent versus three checked demonstrations. Both arms retain stem320/choice140/main320 instructions; all raw items require independent post-run assessment. No parsing, semantic validation, production admission, source acquisition or deployment in this runner.",
    )
    plan["source_sha256"]["evals/checkpoint_author_examples_trial.py"] = hashlib.sha256(
        Path(__file__).read_bytes()
    ).hexdigest()
    return plan


def load_plan(path, approved_hash):
    return capacity.load_plan(path, approved_hash, plan_builder=make_plan)


def run(plan, directory, *, cli_credentials=False, transport=caller.observe_request):
    return capacity.run(plan, directory, cli_credentials=cli_credentials,
                        transport=transport, plan_builder=make_plan)


def replay_capture(report):
    return capacity.replay_capture(report, plan_builder=make_plan)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--execute", metavar="CANONICAL_PLAN_SHA256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.fixture is not None or args.output is None:
            parser.error("Execute needs an existing frozen plan and fresh output directory.")
        report = run(load_plan(args.plan, args.execute), args.output,
                     cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.fixture is None or args.output is not None or args.aws_cli_credentials:
        parser.error("Dry preparation needs only fixture and new plan path.")
    if args.plan.exists():
        parser.error("Plan path already exists.")
    plan = make_plan(json.loads(args.fixture.read_text()))
    shared.write_json(args.plan, plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": capacity.MAX_CALLS, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
