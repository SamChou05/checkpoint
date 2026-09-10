"""Offline historical-prefix/native-review policy audit; never storage or inference."""
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

SERVICE = Path('/tmp/checkpoint-native-qualification-20260909/backend/bedrock-question-service')
sys.path.insert(0, str(SERVICE))
from evals import checkpoint_native_stage_probe as probe
from complete_question_solution import validate_batch, rejection_reason
from generation_diagnostics import quality_summary
from question_quality import _extract_json_object
from question_verification import verify_questions
import question_generation as generation

NATIVE = Path('/tmp/checkpoint-native-stage-live-20260909/capture.json')
ORIGINAL = probe.ORIGIN
OUTPUT = Path('/tmp/checkpoint-native-review-policy-20260909.json')


def binding(path, value):
    return {'path': str(path), 'byte_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'canonical_sha256': probe._hash(value)}


def subject(request, role):
    return probe._subject(request, role)


class ReviewReached(BaseException):
    pass


def reconstruct(original, review_index):
    target = original['calls'][review_index]
    operation_index = target['operation_index']
    operation = original['plan']['operations'][operation_index]
    indexes = [i for i, call in enumerate(original['calls'])
               if call['operation_index'] == operation_index and i <= review_index]
    cursor, active, recovered, matches = 0, {}, {}, []
    metrics = {'ProviderCalls': 0, 'BedrockInputTokens': 0, 'BedrockOutputTokens': 0}

    def capture_verification(candidates, request, reviewer, *args, **kwargs):
        active.clear()
        active.update(candidates=copy.deepcopy(candidates), request=copy.deepcopy(request))
        return verify_questions(candidates, request, reviewer, *args, **kwargs)

    class Client:
        def converse(self, **request):
            nonlocal cursor
            assert cursor < len(indexes), 'Unexpected replay request'
            index = indexes[cursor]
            archived = original['calls'][index]
            assert probe._same(request, archived['request']), f'Archive request mismatch {index}'
            matches.append({'archived_call_index': index,
                            'request_sha256': probe._hash(request), 'exact_request_match': True})
            cursor += 1
            if index == review_index:
                recovered.update(copy.deepcopy(active))
                raise ReviewReached()
            assert probe.runtime._usable_observation(archived['observation'])
            return probe.runtime._provider_response(archived['observation'])

    with patch.dict(os.environ, {**operation['settings'], 'BEDROCK_STRUCTURED_OUTPUT_MODE': 'legacy'}), patch.object(
        generation, 'verify_questions', side_effect=capture_verification,
    ):
        try:
            generation._generate_sanitized_questions(
                copy.deepcopy(operation['request']), Client(),
                call_budget=generation.ProviderCallBudget(operation['maximum_calls']), request_metrics=metrics,
            )
        except ReviewReached:
            pass
    assert recovered and cursor == len(indexes), 'Exact target reviewer was not reached'
    solver_index = next(i for i in reversed(indexes[:-1]) if original['calls'][i]['role'] == 'solver')
    author_index = next(i for i in reversed(indexes[:-1]) if original['calls'][i]['role'] == 'author')
    author_rows = _extract_json_object(original['calls'][author_index]['observation']['response']['text'])['questions']
    solver_call = original['calls'][solver_index]
    solutions = validate_batch(solver_call['observation']['response']['text'], subject(solver_call['request'], 'solver')['items'])
    candidates = []
    for index, candidate in enumerate(recovered['candidates']):
        matches_author = [(i, row) for i, row in enumerate(author_rows)
                          if row['prompt'] == candidate['prompt'] and row['choices'] == candidate['choices']]
        assert len(matches_author) == 1, 'Candidate must match exact raw authored prompt and choices'
        raw_index, raw = matches_author[0]
        assert raw['expectedAnswer'] == candidate['expectedAnswer'], 'Authored key changed'
        if operation['arm'] == 'authored_solution':
            assert raw['explanation'] == candidate['explanation'], 'Immutable author teaching changed'
        candidates.append({'candidate_index': index, 'candidate': candidate,
                           'author_call_index': author_index, 'author_response_item_index': raw_index,
                           'raw_authored_question': raw, 'exact_prompt_choices_and_key_match': True,
                           'exact_authored_explanation_match': raw['explanation'] == candidate['explanation'],
                           'original_solver_record': solutions[index],
                           'original_solver_gate_rejection': rejection_reason(solutions[index], candidate)})
    return {**recovered, 'candidate_provenance': candidates, 'historical_prefix_request_matches': matches,
            'historical_prefix_metrics_before_target_response': quality_summary(metrics),
            'original_solver_call_index': solver_index, 'original_reviewer_call_index': review_index,
            'operation_index': operation_index, 'feedback_contract': operation['arm']}


def replay_native_review(native, original, position, reconstruction):
    job, call = native['plan']['jobs'][position], native['calls'][position]
    assert job['position'] == call['position'] == position
    assert probe.runtime._usable_observation(call['observation'])
    assert probe._hash(job['request']) == call['request_sha256']
    archive_review = original['calls'][reconstruction['original_reviewer_call_index']]
    archive_solver = original['calls'][reconstruction['original_solver_call_index']]
    callback_matches = []
    metrics = {}

    def solver(system, user):
        assert system == archive_solver['request']['system'][0]['text']
        assert user == archive_solver['request']['messages'][0]['content'][0]['text']
        callback_matches.append({'stage': 'solver', 'exact_system_and_subject_bytes': True})
        return archive_solver['observation']['response']['text']

    def reviewer(system, user):
        assert system == archive_review['request']['system'][0]['text']
        assert user == archive_review['request']['messages'][0]['content'][0]['text']
        callback_matches.append({'stage': 'reviewer', 'exact_system_and_subject_bytes': True})

        class NativeRecordedClient:
            def converse(self, **request):
                assert probe._same(request, job['request']), 'Native request binding mismatch'
                callback_matches.append({'stage': 'native_transport', 'exact_native_request_match': True})
                return probe.runtime._provider_response(call['observation'])

        return generation._generate_with_bedrock(
            copy.deepcopy(reconstruction['request']), NativeRecordedClient(), job['request']['modelId'],
            user_prompt=user, system_prompt=system, contract=job['contract'],
        )

    with patch.dict(os.environ, probe.SETTINGS):
        accepted = verify_questions(
            copy.deepcopy(reconstruction['candidates']), copy.deepcopy(reconstruction['request']), reviewer,
            request_metrics=metrics, solve=solver, solver_contract='complete_choices',
            feedback_contract=reconstruction['feedback_contract'], preserve_reviewed_text=True,
        )
    assert len(callback_matches) == 3, 'All exact callbacks must execute once'
    raw_reviews = json.loads(call['observation']['response']['text'])['reviews']
    by_index = {review['index']: review for review in raw_reviews}
    reviewed_items = []
    for item in job['subject']['items']:
        matches = [c for c in reconstruction['candidate_provenance']
                   if c['candidate']['prompt'] == item['prompt'] and set(c['candidate']['choices']) == set(item['choices'])]
        assert len(matches) == 1
        candidate = matches[0]
        returned = [q for q in accepted if q['prompt'] == item['prompt']]
        assert len(returned) <= 1
        reviewed_items.append({'review_index': item['index'], 'exact_reviewed_item': item,
                               'candidate_index': candidate['candidate_index'],
                               'authored_expected_answer': candidate['candidate']['expectedAnswer'],
                               'native_review': by_index[item['index']],
                               'actual_policy_outcome': 'would_return' if returned else 'would_reject',
                               'local_simulated_returned_question': returned[0] if returned else None})
    return {'native_position': position, 'original_reviewer_call_index': job['archived_call_index'],
            'feedback_contract': reconstruction['feedback_contract'], 'callback_matches': callback_matches,
            'candidate_count_before_solver': len(reconstruction['candidates']),
            'reviewed_item_count': len(reviewed_items), 'local_simulated_return_count': len(accepted),
            'actual_policy_metrics': quality_summary(metrics), 'all_reviewed_items': reviewed_items,
            'native_response_text_sha256': hashlib.sha256(call['observation']['response']['text'].encode()).hexdigest()}


def main():
    native, original = json.loads(NATIVE.read_text()), json.loads(ORIGINAL.read_text())
    assert hashlib.sha256(ORIGINAL.read_bytes()).hexdigest() == probe.ORIGIN_SHA256
    assert native['status'] == 'completed'
    assert native['plan_sha256'] == probe._hash(native['plan'])
    assert native['plan']['origin']['capture_canonical_sha256'] == probe._hash(original)
    snapshot = probe._source_snapshot(native['plan']['source_revision'])
    assert all(snapshot[key] == native['plan'][key] for key in ('source_sha256', 'dependencies'))
    with patch.object(probe.shared, 'new_client', side_effect=AssertionError('Provider calls forbidden')), patch.object(
        probe.caller, 'observe_request', side_effect=AssertionError('Workers forbidden'),
    ), patch.object(generation, '_bedrock_client', side_effect=AssertionError('Provider calls forbidden')):
        reconstructed = {index: reconstruct(original, index) for index in (5, 28)}
        runs = [replay_native_review(native, original, position, reconstructed[5 if position < 8 else 28])
                for position in (6, 7, 8, 9)]
    report = {'scope': 'Offline actual production-policy replay. Original historical author/solver outputs and exact replayed operation prefixes, followed by fresh native reviewer records. Not a fresh full native pipeline or production delivery. All returned questions and verification fields are local simulated audit outputs only; no storage or model calls.',
              'source': snapshot, 'helper_path': str(Path(__file__)),
              'helper_byte_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'native_capture': binding(NATIVE, native), 'original_capture': binding(ORIGINAL, original),
              'reconstructions': reconstructed, 'runs': runs,
              'provider_calls': 0, 'production_storage_writes': 0, 'local_audit_report_writes': 1, 'semantic_assessment': 'owned by separate content review'}
    probe.shared.write_json(OUTPUT, report)
    print(json.dumps({'report': str(OUTPUT), 'runs': [
        {'position': run['native_position'], 'reviewed': run['reviewed_item_count'],
         'would_return': run['local_simulated_return_count'], 'metrics': run['actual_policy_metrics']}
        for run in runs]}))


if __name__ == '__main__':
    main()
