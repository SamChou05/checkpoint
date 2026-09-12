#!/usr/bin/env python3
"""Fixed-input matched follow-up to the September 12 broad pass; dry by default.

Each job supplies a frozen author result, so its only real provider calls are
the existing solver/reviewer (at most two). No author, replacement or bank write.
The stimulus-preservation arm changes only the sanitizer's suffix transformation;
the source-visibility arm changes only the supplied reference context. Native
versus legacy changes the existing structured-output setting, not model/effort.
"""

import argparse
import copy
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

SERVICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE))

import question_generation as generation  # noqa: E402
import question_quality as quality  # noqa: E402
from evals.checkpoint_correctness_trace import SETTINGS, digest, run_case, write  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402
from request_contract import _clean_subject_text  # noqa: E402

EVIDENCE = SERVICE.parents[1] / "docs/evidence/correctness-audit-20260912"


def question(prompt, choices, answer, topic):
    return {"prompt": prompt, "choices": choices, "expectedAnswer": answer,
            "explanation": "The result follows from the stated facts and the requested operation.",
            "topic": topic, "difficulty": 1, "format": "Multiple Choice"}


def source_controls():
    records = [
        ("math", "In the fictional Luma game, a blue token scores 3 points.",
         "A Luma player earns 4 blue tokens. How many points does the player earn?",
         "In a game each blue token scores 3 points. A player earns 5 blue tokens. How many points are earned?",
         ["12", "4", "7", "0"], "12", ["15", "5", "8", "0"], "15"),
        ("programming", "The fictional Rho language defines x @ y as 2*x + y.",
         "What does the expression 4 @ 3 evaluate to in Rho?",
         "A language defines x @ y as 2*x + y. What does 5 @ 3 evaluate to?",
         ["11", "7", "12", "1"], "11", ["13", "8", "15", "2"], "13"),
        ("language", "The fictional Zali word 'naro' means 'river'.",
         "Which English word translates the Zali word 'naro'?",
         "In Zali, 'pali' means 'forest'. Which English word translates 'pali'?",
         ["river", "hill", "forest", "cloud"], "river", ["river", "hill", "forest", "cloud"], "forest"),
        ("factual", "The fictional Vale museum opens only on Tuesday.",
         "On which day of the week does the Vale museum open?",
         "The fictional Fern museum opens only on Friday. On which day does it open?",
         ["Tuesday", "Monday", "Friday", "Sunday"], "Tuesday",
         ["Tuesday", "Monday", "Friday", "Sunday"], "Friday"),
    ]
    questions, sources = [], []
    for topic, source, missing, complete, choices, answer, valid_choices, valid_answer in records:
        sources.append({"name": topic + " rules", "text": source, "truncated": False})
        questions.extend([question(missing, choices, answer, topic),
                          question(complete, valid_choices, valid_answer, topic)])
    return questions, sources


def jobs(group):
    if group == "stimulus":
        probes = json.loads((EVIDENCE / "stimulus-transformation-probes.json").read_text())
        payload = copy.deepcopy(probes[0]["request"])
        payload["targetCount"] = len(probes)
        return [(arm, payload, [p["author_output"] for p in probes])
                for arm in ("current", "preserve")]
    if group == "source":
        questions, sources = source_controls()
        payload = {"goal": {"title": "Interpret synthetic rules and passages",
                            "contentTopics": ["Rules and passages"]},
                   "minimumDifficulty": 1, "targetCount": len(questions)}
        return [(arm, {**payload, "sourceDocuments": sources if arm == "full" else []}, questions)
                for arm in ("full", "visible_only")]
    if group in {"native", "algebra"}:
        names = ["math_algebra"] if group == "algebra" else ["math_probability", "code_sql", "language_articles"]
        result = []
        for index, name in enumerate(names):
            trace = json.loads((EVIDENCE / "baseline" / (name + ".json")).read_text())
            # First authored batch. Do not select candidates based on later survival.
            authored = next(s["output"]["questions"] for s in trace["stages"]
                            if s["stage"] == "author_parse" and "output" in s)
            for arm in (("legacy", "native") if index % 2 == 0 else ("native", "legacy")):
                result.append((name + "_" + arm, trace["original_request"], authored))
        return result
    raise ValueError("Unknown controlled group.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=["stimulus", "source", "native", "algebra"], required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args()
    plan = {"group": args.group, "jobs": jobs(args.group), "settings": SETTINGS}
    plan["max_provider_calls"] = 2 * len(plan["jobs"])
    if not args.execute:
        print(json.dumps({"group": args.group, "max_provider_calls": plan["max_provider_calls"],
                          "sha256": digest(plan)}, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    write(args.output_dir / "plan.json", plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    for arm, payload, questions in plan["jobs"]:
        settings = {**SETTINGS, "GENERATION_ATTEMPTS": "1"}
        if arm.endswith("_native"):
            settings["BEDROCK_STRUCTURED_OUTPUT_MODE"] = "native"
        original_cleaner = quality._prompt_without_trailing_choice_echo
        cleaner = (lambda prompt, choices: _clean_subject_text(prompt)) if arm == "preserve" else original_cleaner
        with (patch.dict(os.environ, settings),
              patch.object(generation, "_generate_provider_payload", return_value={"questions": questions}),
              patch.object(quality, "_prompt_without_trailing_choice_echo", cleaner)):
            trace = run_case({"id": arm, "payload": payload}, args.output_dir, generation._bedrock_client())
        trace["fixed_author_control"] = True
        trace["settings"] = settings
        write(args.output_dir / (arm + ".json"), trace)
        print(json.dumps({"arm": arm, "calls": len(trace["calls"]), "returned": len(trace["final"]),
                          "seconds": trace["elapsed_seconds"], "quality": trace["metrics"].get("QuestionQuality"),
                          "error": trace.get("error_type")}), flush=True)


if __name__ == "__main__":
    main()
