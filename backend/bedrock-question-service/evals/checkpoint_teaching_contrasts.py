#!/usr/bin/env python3
"""Replay four actual review inputs with matched teaching instructions; max 8 calls."""
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
import question_generation as generation  # noqa: E402
import question_verification as verification  # noqa: E402
from evals.checkpoint_correctness_trace import SETTINGS, TraceClient, write  # noqa: E402
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials  # noqa: E402

EVIDENCE = SERVICE.parents[1] / 'docs/evidence/correctness-audit-20260912'
CURRENT = verification.COMPLETE_REVIEW_SYSTEM_PROMPT
CONTRAST = CURRENT.replace(
    "Explain the underlying rule and each choice's actual error, without answer letters\nor personal diagnoses.",
    "Explain the governing rule or evidence and contrast each offered choice with "
    "the correct result or relevant condition. For a wrong choice, identify the "
    "stated fact, requirement or computed result it fails. Do not invent a "
    "learner's thought process, an alternative calculation or a changed scenario "
    "to explain how a distractor arose. Keep factual claims within what the "
    "question and references establish; do not use answer letters.",
)
assert CONTRAST != CURRENT
FILES = [
    'baseline/math_arithmetic.json',
    'context-final/displayed_native.json',
    'final-recheck/fresh_sql_native_recheck_native.json',
    'fresh-paired/fresh_facts_legacy.json',
]


def jobs():
    result = []
    for i, path in enumerate(FILES):
        trace = json.loads((EVIDENCE / path).read_text())
        call = [c for c in trace['calls'] if '<question_review_json>' in c['request']['messages'][0]['content'][0]['text']][-1]
        prompt = call['request']['messages'][0]['content'][0]['text']
        data = json.loads(prompt.split('\n', 1)[1].rsplit('\n', 1)[0])
        questions = []
        for item, solution in zip(data['items'], data['independentSolutions'], strict=True):
            keys = [c['choice'] for c in solution['choices'] if c['judgment'] == 'supported']
            if len(keys) != 1:
                raise ValueError('Expected a previously admitted solver judgment.')
            questions.append({**item, 'expectedAnswer': keys[0], 'explanation': 'Placeholder; never sent to the reviewer.',
                              'difficulty': 3, 'format': 'Multiple Choice'})
        result.append({'id': f'review_{i}', 'origin': path, 'origin_call': call['call'], 'prompt': prompt,
                       'request': trace['normalized_request'], 'questions': questions})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--aws-cli-credentials', action='store_true')
    args = parser.parse_args()
    settings = {**SETTINGS, 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'native', 'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native'}
    plan = {'jobs': jobs(), 'systems': {'current': CURRENT, 'contrast': CONTRAST}, 'settings': settings,
            'maximum_calls': 8, 'scope': 'Actual prior review prompts reused exactly. No author/solver inference or bank writes. Review contract validation is not new independent-verification provenance.'}
    if not args.execute:
        print(json.dumps(plan, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    plan['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SERVICE, text=True).strip()
    plan['source_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob('*.py')}
    write(args.output_dir/'plan.json', plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    for i, job in enumerate(plan['jobs']):
        for arm in (['current', 'contrast'] if i % 2 == 0 else ['contrast', 'current']):
            trace = {'job': job, 'arm': arm, 'calls': [], 'metrics': {}}
            def save():
                write(args.output_dir/(job['id']+'_'+arm+'.json'), trace)
            with patch.dict(os.environ, settings):
                client = TraceClient(generation._bedrock_client(), trace, save, cap=1)
                try:
                    raw = generation._generate_with_bedrock(job['request'], client, generation._verification_model_id(),
                        user_prompt=job['prompt'], system_prompt=plan['systems'][arm],
                        contract='default_reviewer_v1', call_budget=generation.ProviderCallBudget(1))
                    trace['adapted_response'] = json.loads(raw)
                    trace['accepted_by_review_contract'] = verification.verify_questions(
                        copy.deepcopy(job['questions']), job['request'], lambda *_: raw,
                        request_metrics=trace['metrics'], solver_contract='complete_choices', preserve_reviewed_text=True)
                except Exception as error:
                    trace['error_type'] = type(error).__name__
            save()
            print(json.dumps({'job': job['id'], 'arm': arm, 'calls': len(trace['calls']),
                              'contract_accepted': len(trace.get('accepted_by_review_contract', [])),
                              'error': trace.get('error_type')}), flush=True)


if __name__ == '__main__':
    main()
