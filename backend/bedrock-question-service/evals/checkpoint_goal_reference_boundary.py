#!/usr/bin/env python3
"""Compare source-only and full subject-reference solving; at most three calls."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
from unittest.mock import patch

import complete_question_solution as solution
import question_generation as generation
import question_verification as verification
from evals.checkpoint_correctness_trace import SERVICE, SETTINGS, TraceClient, write
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials
from request_contract import _normalize_request

REFERENCE_SYSTEM = solution.SOURCE_SOLUTION_SYSTEM_PROMPT.replace(
    'supplied study-source facts', 'supplied subject-reference facts')


def reference_prompt(items, request, **_):
    _, prompt = solution.build_solver_prompt(items, request, context="source")
    data = json.loads(prompt.split('\n', 1)[1].rsplit('\n', 1)[0])
    data.update(solution._subject_context(request))
    return REFERENCE_SYSTEM, '<question_solution_json>\n'+json.dumps(data, ensure_ascii=False)+'\n</question_solution_json>'


def plan():
    cases = json.loads((SERVICE/'evals/fixtures/source_recall_boundary.json').read_text())
    references = '\n\n'.join(c['payload']['sourceDocuments'][0]['text'] for c in cases)
    assert len(references) <= 1000
    payload = {'goal': {'title': 'Learn the fictional subjects described in my goal',
                       'focusAreas': references,
                       'contentTopics': ['Reference knowledge and application']},
               'targetCount': 8, 'minimumDifficulty': 1, 'sourceDocuments': []}
    request = _normalize_request(payload)
    assert request['goal']['focusAreas'] == references
    questions = [copy.deepcopy(c['items'][i]['question']) for c in cases for i in (0, 2)]
    return {'payload': payload, 'request': request, 'questions': questions,
            'classification': ['valid_learned_recall', 'missing_case']*4,
            'candidate_system': REFERENCE_SYSTEM, 'maximum_calls': 3,
            'settings': {**SETTINGS, 'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native'},
            'scope': 'Same eight fixed items and request in both arms. The four existing study references are now supplied verbatim in goal.focusAreas, not an attachment. Two matched solver calls, then at most one existing final-review call for candidate survivors. No author inference, retries, deployment or bank writes. Experimental provenance is historical, not a new production claim.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--aws-cli-credentials', action='store_true')
    args = parser.parse_args()
    frozen = plan()
    if not args.execute:
        print(json.dumps(frozen, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    frozen['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SERVICE, text=True).strip()
    frozen['source_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob('*.py')}
    write(args.output_dir/'plan.json', frozen)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    trace = {'calls': [], 'arms': {}}
    def save():
        write(args.output_dir/'trace.json', trace)
    with patch.dict(os.environ, frozen['settings']):
        capture = TraceClient(generation._bedrock_client(), trace, save, cap=3)
        budget = generation.ProviderCallBudget(3)
        def infer(system, prompt, contract):
            return generation._generate_with_bedrock(frozen['request'], capture,
                generation._verification_model_id(), system_prompt=system, user_prompt=prompt,
                contract=contract, call_budget=budget)
        items = [{'index': i, **{k: q[k] for k in ('prompt', 'choices', 'topic')}} for i, q in enumerate(frozen['questions'])]
        try:
            for arm in ('source_only', 'references'):
                system, prompt = (solution.build_solver_prompt(items, frozen['request'], context="source")
                                  if arm == 'source_only' else reference_prompt(items, frozen['request']))
                raw = infer(system, prompt, 'complete_choice_solver_v1')
                records = solution.validate_batch(raw, items)
                trace['arms'][arm] = {'adapted_response': json.loads(raw),
                    'rejections': [solution.rejection_reason(r, q) for r, q in zip(records, frozen['questions'], strict=True)]}
                save()
            metrics = {}
            with patch.object(verification, 'build_solver_prompt', reference_prompt):
                trace['candidate_final'] = verification.verify_questions(
                    copy.deepcopy(frozen['questions']), frozen['request'],
                    lambda system, prompt: infer(system, prompt, 'default_reviewer_v1'),
                    solve=lambda *_: json.dumps(trace['arms']['references']['adapted_response']),
                    solver_contract='complete_choices', solver_context='reference',
                    preserve_reviewed_text=True, request_metrics=metrics)
            trace['metrics'] = metrics
        except Exception as error:
            trace['error_type'] = type(error).__name__
        save()
    print(json.dumps({'calls': len(trace['calls']), 'arms': {a: t['rejections'] for a,t in trace['arms'].items()},
                      'returned': len(trace.get('candidate_final', [])), 'error': trace.get('error_type')}))


if __name__ == '__main__':
    main()
