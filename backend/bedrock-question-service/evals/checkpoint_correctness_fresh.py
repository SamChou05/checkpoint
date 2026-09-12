#!/usr/bin/env python3
"""Frozen fresh correctness sample. Dry by default; eight jobs, at most 24 calls."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

SERVICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE))

from evals.checkpoint_correctness_trace import SETTINGS, run_case, write  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402
import question_generation as gen  # noqa: E402

cases = []
def add(id,title,focus,level,source=''):
 cases.append({'id':id,'payload':{'goal':{'title':title,'learningTarget':title,'contentTopics':[focus],'currentLevel':{3:'intermediate',4:'advanced'}[level]},'sourceDocuments':[{'name':'Synthetic reference notes','text':source,'truncated':False}] if source else [],'targetCount':2,'minimumDifficulty':level}})
add('fresh_math','Analyze real equations with parameters','Count distinct real solutions while retaining domain restrictions',4)
add('fresh_sql','Trace SQLite outer joins and filters','Compare predicates in ON versus WHERE with duplicate rows',3,'SQLite LEFT JOIN retains unmatched left rows by extending the right columns with NULL. ON determines matches. WHERE filters the joined result and does not retain unknown comparisons. COUNT(*) counts rows; COUNT(expression) counts non-NULL values. All tables needed by a question must be shown.')
add('fresh_language','Preserve English reference and intended meaning','Use determiners to distinguish a particular referent from a general statement',3)
add('fresh_facts','Infer daylight and seasons from stated locations and dates','June and December solstices and opposite hemispheres',3,'At the June solstice the Northern Hemisphere is tilted most toward the Sun, and the Southern Hemisphere away; the relation reverses in December. The June solstice gives the longest daylight of the year at ordinary northern midlatitudes and the shortest at southern midlatitudes. Seasons arise primarily from axial tilt, not Earth-Sun distance.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args()
    settings = {**SETTINGS, "GENERATION_ATTEMPTS": "1", "MAX_PROVIDER_CALLS_PER_REQUEST": "3"}
    plan = {"cases": cases, "settings": settings, "arms": ["legacy", "native"],
            "max_calls": 24, "jobs": 8,
            "scope": "Fresh authored pairs, alternating transport order, one generation pass per arm. Not a causal comparison with earlier different requests."}
    if not args.execute:
        print(json.dumps(plan, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    plan["source_revision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=SERVICE, text=True).strip()
    plan["source_sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob("*.py")}
    write(args.output_dir / "plan.json", plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    for i, case in enumerate(cases):
        for arm in (["legacy", "native"] if i % 2 == 0 else ["native", "legacy"]):
            job = copy.deepcopy(case)
            job["id"] += "_" + arm
            with patch.dict(os.environ, {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": arm}):
                trace = run_case(job, args.output_dir, gen._bedrock_client(), maximum_calls=3)
            print(json.dumps({"case": job["id"], "calls": len(trace["calls"]), "returned": len(trace["final"]),
                              "seconds": trace["elapsed_seconds"], "quality": trace["metrics"].get("QuestionQuality"),
                              "error": trace.get("error_type")}), flush=True)


if __name__ == "__main__":
    main()
