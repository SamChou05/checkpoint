"""Offline replay of original author provenance and independent rational answers."""
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import sys

import jsonschema

HERE = Path(__file__).resolve().parent
PLAN = json.loads((HERE / 'plan.json').read_text())
sys.path.insert(0, PLAN['source_root'])
from quantitative_authoring import LEARNER_FIELDS, flat_task_spec  # noqa: E402
from quantitative_task_compiler import compile_question  # noqa: E402


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def evaluate(node, value=None):
    if 'value' in node:
        return Fraction(node['value'])
    if 'variable' in node:
        return value
    left, right = evaluate(node['left'], value), evaluate(node['right'], value)
    operation = node['op']
    return {'add': lambda: left + right, 'sub': lambda: left - right,
            'mul': lambda: left * right, 'div': lambda: left / right}[operation]()


def independently_correct(spec):
    choices = [Fraction(value) for value in spec['choices']]
    assert len(choices) == len(set(choices)) == 4
    if spec['kind'] == 'exact_value':
        answer = evaluate(spec['expression'])
    else:
        domain = spec['domain']
        values = choices if domain['kind'] == 'offered' else [Fraction(value) for value in range(domain['lower'], domain['upper'] + 1)]
        condition = spec['condition']
        def satisfies(value):
            left, right = evaluate(condition['left'], value), evaluate(condition['right'], value)
            return {'lt': left < right, 'le': left <= right, 'gt': left > right,
                    'ge': left >= right, 'eq': left == right, 'ne': left != right}[condition['relation']]
        valid = [value for value in values if satisfies(value)]
        selection = spec['selection']
        if selection == 'any_satisfying':
            offered = [value for value in choices if value in valid]
            assert len(offered) == 1
            answer = offered[0]
        else:
            answer = min(valid) if selection == 'minimum' else max(valid)
    assert choices.count(answer) == 1
    return str(answer)


def review():
    capture = json.loads((HERE / 'capture.json').read_text())
    assert capture['status'] == 'completed_pending_review'
    assert capture['plan_sha256'] == file_hash(HERE / 'plan.json')
    assert capture['plan'] == PLAN
    for path, expected in PLAN['source_hashes'].items():
        assert file_hash(path) == expected, path
    schema_checks = []
    for call in capture['calls']:
        assert call['response']['stopReason'] == 'end_turn'
        raw = '\n'.join(block['text'] for block in call['response']['output']['message']['content'])
        schema = json.loads(call['request']['outputConfig']['textFormat']['structure']['jsonSchema']['schema'])
        jsonschema.Draft202012Validator(schema).validate(json.loads(raw))
        schema_checks.append({'job': call['job'], 'stage': call['stage'], 'valid': True})
    rows = []
    for job in capture['jobs']:
        assert job['within_deadline'] and job['provider_calls'] <= 6
        for ordinal, (question, provenance) in enumerate(zip(job['returned'], job['returned_provenance'], strict=True)):
            if question['verificationPolicyRevision'] != 6:
                assert provenance is None and question['verificationPolicyRevision'] == 4
                continue
            source_job, source_pass, source_index = provenance['source']
            assert source_job == job['id']
            original = job['passes'][source_pass]['author_payload']['questions'][source_index]
            assert original['kind'] == 'quantitative'
            spec = flat_task_spec(original['task'])
            assert spec == provenance['spec']
            regenerated = compile_question(spec)
            assert regenerated == provenance['learner'] == {key: question[key] for key in LEARNER_FIELDS}
            correct = independently_correct(spec)
            assert Fraction(correct) == Fraction(question['expectedAnswer'])
            rows.append({'job': job['id'], 'return_index': ordinal, 'original_source': provenance['source'],
                         'spec_reconstructed_from_original_author': True, 'all_five_fields_exact': True,
                         'independent_unique_answer': correct, 'four_numerically_distinct_choices': True})
    return {'plan_sha256': file_hash(HERE / 'plan.json'), 'capture_sha256': file_hash(HERE / 'capture.json'),
            'script_sha256': file_hash(__file__), 'pinned_sources_unchanged': True,
            'raw_schema_checks': schema_checks, 'compiled_returns': rows,
            'claim_limit': 'Exact bounded arithmetic/provenance only; independent plausibility, scope, difficulty and prose review remain separate.'}


if __name__ == '__main__':
    result = review()
    with (HERE / 'provenance-review.json').open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'raw_schemas_valid': len(result['raw_schema_checks']), 'compiled_returns_verified': len(result['compiled_returns'])}))
