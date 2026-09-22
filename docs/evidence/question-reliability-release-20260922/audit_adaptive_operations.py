"""Read-only accounting/deadline audit; does not invoke models or modify captures."""
from collections import Counter
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def audit():
    path = HERE / 'pipeline-adaptive-capture.json'
    capture = json.loads(path.read_text())
    plan_path = HERE / 'pipeline-adaptive-plan.json'
    plan = json.loads(plan_path.read_text())
    assert capture['plan_sha256'] == hashlib.sha256(plan_path.read_bytes()).hexdigest()
    calls = capture['calls']
    assert len(calls) <= plan['limits']['maximum_calls']
    rows = []
    for job in capture['jobs']:
        index = job['index']
        job_calls = [call for call in calls if call['job'] == index]
        assert len(job_calls) <= plan['limits']['maximum_calls_per_job']
        for call in job_calls:
            assert call['sdk_total_max_attempts'] == 1
            assert call['remaining_before_dispatch_ms'] >= call['minimum_required_ms']
            assert call['connect_timeout_seconds'] == 3
            assert 2 <= call['read_timeout_seconds'] <= 75
            assert not call.get('reasoning_text_retained', False)
            content = call.get('response', {}).get('output', {}).get('message', {}).get('content', [])
            assert not any('reasoningContent' in block for block in content)
        if 'accepted' not in job:
            rows.append({'index': index, 'status': 'in_progress_or_job_failed', 'dispatches': len(job_calls),
                         'error_type': job.get('error_type')})
            continue
        assert job['metrics']['ProviderCalls'] == len(job_calls) == job['provider_budget_calls']
        for name, usage_key in [('BedrockInputTokens', 'inputTokens'), ('BedrockOutputTokens', 'outputTokens')]:
            assert job['metrics'][name] == sum(call.get('response', {}).get('usage', {}).get(usage_key, 0) for call in job_calls)
        for question in job['accepted']:
            assert question['verificationVersion'] == 1 and question['verificationPolicyRevision'] == 4
            assert len(question['choices']) == 4 and question['expectedAnswer'] in question['choices']
            assert set(question['choiceExplanations']) == set(question['choices'])
        rows.append({
            'index': index, 'title': plan['jobs'][index]['request']['goal']['title'],
            'accepted': len(job['accepted']), 'dispatches': len(job_calls),
            'elapsed_seconds': job['elapsed_seconds'], 'within_240_seconds': job['elapsed_seconds'] <= 240,
            'provider_tokens': {key: job['metrics'][key] for key in ('BedrockInputTokens', 'BedrockOutputTokens')},
            'min_observed_read_timeout_seconds': min(call['read_timeout_seconds'] for call in job_calls),
            'native_transport_failures': sum(call.get('native_transport_valid') is False for call in job_calls),
            'non_end_turn_responses': sum('response' in call and call['response'].get('stopReason') != 'end_turn' for call in job_calls),
            'transport_errors': sum(call.get('outcome') == 'transport_error' for call in job_calls),
            'calls_without_usage_metadata': sum('usage' not in call.get('response', {}) for call in job_calls),
            'quality_dispositions': job['metrics'].get('QuestionQuality', {}),
        })
    return {
        'capture_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'plan_sha256': capture['plan_sha256'], 'capture_status': capture['status'],
        'planned_jobs': len(plan['jobs']), 'planned_requested_questions': 30,
        'unattempted_job_indexes': [job['index'] for job in plan['jobs'] if job['index'] not in {row['index'] for row in capture['jobs']}],
        'provider_dispatches': len(calls),
        'stage_dispatches': dict(Counter(call['request']['outputConfig']['textFormat']['structure']['jsonSchema']['name'] for call in calls)),
        'client_admission_failures': capture.get('client_admission_failures', []), 'jobs': rows,
        'interpretation': 'Accounting and exact response bindings only. Semantic qualification requires the separate independent item audits. A completed capture is not itself a passing result.',
    }


if __name__ == '__main__':
    print(json.dumps(audit(), indent=2, ensure_ascii=False))
