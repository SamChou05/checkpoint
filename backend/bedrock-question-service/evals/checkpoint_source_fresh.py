#!/usr/bin/env python3
"""Frozen fresh qualification across both deployed authors; max 24 calls per suite."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from unittest.mock import patch

from evals.checkpoint_correctness_trace import SERVICE, SETTINGS, run_case, write
from evals.checkpoint_prompt_ablation import use_aws_cli_credentials
import question_generation as generation
from request_contract import _normalize_request

FIXTURES = {
    'source': SERVICE / 'evals/fixtures/source_policy_fresh.json',
    'subject-final': SERVICE / 'evals/fixtures/subject_reference_final.json',
}
MODELS = {'api_nova': 'amazon.nova-lite-v1:0', 'worker_kimi': 'moonshotai.kimi-k2.5'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--aws-cli-credentials', action='store_true')
    parser.add_argument('--suite', choices=FIXTURES, default='source')
    args = parser.parse_args()
    fixture = FIXTURES[args.suite]
    cases = json.loads(fixture.read_text())
    assert len(cases) == 4 and len({c['id'] for c in cases}) == 4
    for case in cases:
        assert _normalize_request(case['payload'])['targetCount'] == 2
    settings = {**SETTINGS, 'GENERATION_ATTEMPTS': '1', 'MAX_PROVIDER_CALLS_PER_REQUEST': '3',
                'BEDROCK_STRUCTURED_OUTPUT_MODE': 'legacy',
                'BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE': 'native'}
    if args.suite == 'subject-final':
        from verification_policy import VERIFICATION_POLICY_REVISION
        assert VERIFICATION_POLICY_REVISION == 8
        template = (SERVICE/'template.yaml').read_text()
        assert 'BedrockVerificationStructuredOutputMode:\n    Type: String\n    Default: native' in template
        assert 'BedrockStructuredOutputMode:\n    Type: String\n    Default: legacy' in template
    plan = {'suite': args.suite, 'cases': cases, 'authors': MODELS, 'settings': settings, 'maximum_calls': 24,
            'scope': 'Four fixed fresh requests, each with API Nova and worker Kimi author. Same final policy and native Sonnet verification; no deployment, queue/HTTP latency claim, bank writes, or runtime semantic override. At most three actual calls per job; no retries after transport failure.'}
    if not args.execute:
        print(json.dumps(plan, indent=2))
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    plan['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SERVICE, text=True).strip()
    plan['source_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SERVICE.glob('*.py')}
    plan['fixture_sha256'] = hashlib.sha256(fixture.read_bytes()).hexdigest()
    write(args.output_dir/'plan.json', plan)
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    for i, case in enumerate(cases):
        arms = list(MODELS) if i % 2 == 0 else list(reversed(MODELS))
        for arm in arms:
            with patch.dict(os.environ, {**settings, 'BEDROCK_MODEL_ID': MODELS[arm]}):
                trace = run_case({**case, 'id': case['id']+'_'+arm}, args.output_dir,
                                 generation._bedrock_client(), maximum_calls=3)
            print(json.dumps({'case': case['id'], 'arm': arm, 'calls': len(trace['calls']),
                              'returned': len(trace['final']), 'seconds': trace['elapsed_seconds'],
                              'error': trace.get('error_type')}), flush=True)


if __name__ == '__main__':
    main()
