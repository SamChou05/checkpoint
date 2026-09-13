#!/usr/bin/env python3
"""Source-recall boundary comparison. Dry by default; at most 16 calls."""
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
import complete_question_solution as solution  # noqa: E402
import question_generation as generation  # noqa: E402
import question_verification as verification  # noqa: E402
from evals.checkpoint_correctness_trace import SETTINGS, run_case, write  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402

SOURCE_SOLUTION_SYSTEM_PROMPT = solution.COMPLETE_SOLUTION_SYSTEM_PROMPT.replace(
    'Use the goal to establish scope,\nthe supplied sources or fictional rules when relevant, and established subject\nknowledge.',
    "Use established subject knowledge and supplied study-source facts as evidence "
    "about their named subject. A recall question may test a source fact without "
    "repeating that fact in its stem. Distinguish general reference rules from "
    "example-specific data: do not transplant an example's conditions into an "
    "unspecified case. The item must establish the case-specific facts needed "
    "to select an answer. Assess each item independently; do not borrow case "
    "facts from another item or infer an omitted condition from a lesson's intent.",
)


def build_source_prompt(items, request, **_):
    _, prompt = solution.build_solver_prompt(items, request, context="displayed")
    data = json.loads(prompt.split('\n', 1)[1].rsplit('\n', 1)[0])
    data['sourceDocuments'] = solution._subject_context(
        {'sourceDocuments': request.get('sourceDocuments', [])})['sourceDocuments']
    return SOURCE_SOLUTION_SYSTEM_PROMPT, '<question_solution_json>\n' + json.dumps(data, ensure_ascii=False) + '\n</question_solution_json>'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--aws-cli-credentials', action='store_true')
    args = parser.parse_args()
    cases = json.loads((SERVICE / 'evals/fixtures/source_recall_boundary.json').read_text())
    plan = {'cases': cases, 'arms': ['displayed', 'source'], 'maximum_calls': 16,
            'candidate_system': SOURCE_SOLUTION_SYSTEM_PROMPT,
            'settings': {**SETTINGS, 'GENERATION_ATTEMPTS': '1', 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native'},
            'scope': 'Fixed synthetic author results; native solver/reviewer; no regeneration or bank writes. Source arm uses historical reference provenance, not a proposed current policy stamp.'}
    if not args.execute:
        print(json.dumps(plan, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    plan['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SERVICE, text=True).strip()
    plan['source_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob('*.py')}
    write(args.output_dir / 'plan.json', plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    for i, case in enumerate(cases):
        for arm in (['displayed', 'source'] if i % 2 == 0 else ['source', 'displayed']):
            questions = [copy.deepcopy(item['question']) for item in case['items']]
            verifier = generation.verify_questions
            def verify(*values, **kwargs):
                kwargs['solver_context'] = 'reference' if arm == 'source' else 'displayed'
                return verifier(*values, **kwargs)
            builder = build_source_prompt if arm == 'source' else solution.build_solver_prompt
            with (patch.dict(os.environ, plan['settings']),
                  patch.object(generation, '_generate_provider_payload', return_value={'questions': questions}),
                  patch.object(generation, 'verify_questions', verify),
                  patch.object(verification, 'build_solver_prompt', builder)):
                trace = run_case({'id': case['id']+'_'+arm, 'payload': case['payload']}, args.output_dir,
                                 generation._bedrock_client(), maximum_calls=2)
            print(json.dumps({'case': case['id'], 'arm': arm, 'calls': len(trace['calls']),
                              'returned': len(trace['final']), 'seconds': trace['elapsed_seconds'],
                              'quality': trace['metrics'].get('QuestionQuality'), 'error': trace.get('error_type')}), flush=True)


if __name__ == '__main__':
    main()
