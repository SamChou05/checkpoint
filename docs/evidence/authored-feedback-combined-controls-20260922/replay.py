"""No-network replay of frozen native responses through the actual composition."""
import copy
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('combined_probe_replay', HERE / 'combined_probe.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def replay():
    plan = json.loads(p.PLAN.read_text())
    capture = json.loads(p.CAPTURE.read_text())
    p.require(capture['status'] != 'running', 'Capture must be final.')
    p.require(capture['plan_sha256'] == p.sha(p.PLAN), 'Capture plan binding changed.')
    p.require(plan == {**p.build_plan(), 'plan_state': 'frozen'}, 'Frozen plan/source/config changed.')
    p.verify_pins(plan)
    originals, expected = p.source_cases()
    by_id = {case['case_id']: case for case in originals['cases']}
    reports = []
    provider_calls = 0
    # Any accidental SDK client creation is a hard local failure.
    with patch.dict(p.os.environ, p.ENVIRONMENT), patch.object(p.boto3, 'client', side_effect=AssertionError('Network disabled in replay.')):
        for batch, job in zip(plan['batches'], capture['batches'], strict=False):
            p.require(batch['batch'] == job['batch'], 'Batch order mismatch.')
            cases = [by_id[descriptor['case_id']] for descriptor in batch['controls']]
            p.require(job['case_ids'] == [case['case_id'] for case in cases], 'Control identity mismatch.')
            learners = [copy.deepcopy(case['learner_item']) for case in cases]
            request = {**copy.deepcopy(batch['scope']), 'minimumDifficulty': 1, 'adaptiveSkillPlans': [], 'existingQuestionCoverage': []}
            row_index = 0
            stage_reports = []
            def stage(name, system, prompt, count):
                nonlocal row_index, provider_calls
                p.require(row_index < len(job['calls']), 'Replay requested an unrecorded stage.')
                row = job['calls'][row_index]
                row_index += 1
                provider_calls += 1
                contract = p.native.SolverSlotContract(count) if name == 'solver' else p.native.AuthoredFeedbackReviewContract(count)
                p.require((row['stage'], row['count']) == (name, count), 'Stage count changed.')
                p.require(p.digest(row['request']) == row['request_sha256'], 'Recorded request hash mismatch.')
                p.require(row['contract'] == p.native.contract_metadata(contract), 'Native contract metadata changed.')
                report = {'stage': name, 'count': count, 'source_case_ids': row['source_case_ids'],
                          'actual_request_recreated_exactly': False, 'native_and_local_valid': False,
                          'elapsed_seconds': row.get('elapsed_seconds'), 'usage': row.get('usage'),
                          'stop_reason': row.get('stop_reason'), 'provider_error': row.get('provider_error')}
                stage_reports.append(report)
                def converse(**actual_request):
                    p.require(actual_request == row['request'], 'Actual production request does not match the frozen dispatch.')
                    report['actual_request_recreated_exactly'] = True
                    if 'raw' not in row:
                        # Reproduce unavailable-stage behavior, not invent provider content.
                        raise p.ProviderError('Captured provider attempt has no model response.')
                    return {'output': {'message': {'content': [{'text': row['raw']}]}},
                            'stopReason': row['stop_reason'], **({'usage': row['usage']} if row.get('usage') is not None else {})}
                fake = SimpleNamespace(converse=converse)
                adapted = p.generation._generate_with_bedrock(normalized_request=request, bedrock_client=fake, model_id=p.MODEL,
                            system_prompt=system, user_prompt=prompt, contract=contract)
                report['native_adapter_valid'] = True
                if 'adapted_response' in row:
                    p.require(adapted == row['adapted_response'], 'Adapted stage text differs from captured adaptation.')
                if row.get('stop_reason') != 'end_turn' or row.get('elapsed_seconds', 101) > 100 or row.get('remaining_milliseconds_after', 0) <= 0:
                    raise p.ProviderError('Captured stage failed prospective completion/deadline criteria.')
                if name == 'solver':
                    items = [{'index': i, 'prompt': learner['prompt'], 'choices': learner['choices']} for i, learner in enumerate(learners)]
                    decoded = p.solver.validate_batch(adapted, items, audit_choice_pairs=True, choice_slots=True)
                    p.require(decoded == row['decoded_records'], 'Solver record replay changed.')
                    choices, pairs, mismatches = 0, 0, []
                    for item_index, record in enumerate(decoded):
                        gold = expected[cases[item_index]['case_id']]
                        choice_gold = {value['choice']: value['judgment'] for value in gold['answer_set']['offered_choices']}
                        pair_gold = {frozenset((value['leftChoice'], value['rightChoice'])): value['expected_relation'] for value in gold['all_six_pair_expectations']}
                        for value in record['choices']:
                            target = {'supported': 'supported', 'unsupported': 'refuted', 'uncertain': 'uncertain'}[choice_gold[value['choice']]]
                            choices += value['judgment'] == target
                            if value['judgment'] != target:
                                mismatches.append({'case_id': cases[item_index]['case_id'], 'field': 'choice', 'exact_choice': value['choice'], 'expected': target, 'observed': value['judgment']})
                        for value in record['choicePairs']:
                            target = pair_gold[frozenset((value['leftChoice'], value['rightChoice']))]
                            pairs += value['relation'] == target
                            if value['relation'] != target:
                                mismatches.append({'case_id': cases[item_index]['case_id'], 'field': 'pair', 'exact_choices': [value['leftChoice'], value['rightChoice']], 'expected': target, 'observed': value['relation']})
                    report.update(choice_labels_matching_draft=choices, choice_labels_returned=4 * count,
                                  pair_labels_matching_draft=pairs, pair_labels_returned=6 * count, label_mismatches=mismatches)
                else:
                    try:
                        decoded = p.audit.validate(adapted, count)
                    except ValueError as error:
                        report['local_validation_failure_type'] = type(error).__name__
                        report['raw_native_valid_items_without_batch_credit'] = count
                        raise
                    p.require(decoded == row['decoded_records'], 'Audit record replay changed.')
                    mismatches = []
                    for index, cid in enumerate(row['source_case_ids']):
                        gold, observed = expected[cid], decoded[str(index)]
                        fields = [('task', gold['task']['expected_judgment'], observed['task']['judgment']),
                                  ('answerChoice', gold['answer_set']['expected_answerChoice'], observed['answerChoice'])]
                        fields.extend((f'feedback.{field}', value['expected_judgment'], observed['feedback'][field]['judgment']) for field, value in gold['feedback'].items())
                        for field, target, actual in fields:
                            if target != actual:
                                mismatches.append({'case_id': cid, 'field': field, 'expected': target, 'observed': actual,
                                                   'expectation_uncertain': target == 'uncertain'})
                    report.update(label_mismatches=mismatches, audit_items_assessed=count, short_reasons_returned=6 * count)
                report['native_and_local_valid'] = True
                return adapted
            failure = None
            try:
                result = p.verification.verify_authored_feedback(learners, request,
                    lambda system, prompt, count: stage('solver', system, prompt, count),
                    lambda system, prompt, count: stage('audit', system, prompt, count))
            except (p.ProviderError, p.ServiceConfigurationError, p.SafetyInterventionError, ValueError) as error:
                result, failure = None, type(error).__name__
            p.require(row_index == len(job['calls']), 'Replay did not consume every recorded dispatch.')
            p.require(learners == [case['learner_item'] for case in cases], 'Replay mutated originals.')
            report = {'batch': batch['batch'], 'recorded_status': job['status'], 'stages': stage_reports,
                      'failed_batch_has_no_semantic_credit': job['status'] != 'complete', 'replay_failure_type': failure}
            if job['status'] == 'complete':
                p.require(result is not None, 'A completed batch could not replay.')
                selected = [{field: item[field] for field in p.author.LEARNER_FIELDS} for item in result]
                p.require(selected == job['selected_originals'], 'Actual composition admission changed on replay.')
                hashes = [p.author.learner_content_digest(item) for item in selected]
                p.require(hashes == job['selected_original_hashes'], 'Selected learner hashes changed.')
                decisions = []
                for case in cases:
                    accepted = case['learner_item'] in selected
                    correct = accepted == (case['gold']['required_gate_decision'] == 'accept')
                    decisions.append({'case_id': case['case_id'], 'accepted': accepted,
                                      'expected_accept': case['gold']['required_gate_decision'] == 'accept', 'matches_gold': correct})
                p.require(decisions == job['decisions'], 'Captured decisions differ from original whole gold.')
                report.update(exact_original_selected_hashes=hashes, decisions=decisions)
            reports.append(report)
    return {'plan_sha256': p.sha(p.PLAN), 'capture_sha256': p.sha(p.CAPTURE),
            'replay_source_sha256': p.sha(Path(__file__)), 'network_calls': 0,
            'all_frozen_source_pins_match': True, 'actual_production_requests_and_admission_replayed': True,
            'recorded_provider_calls_replayed': provider_calls, 'batch_reports': reports,
            'original_denominators_unchanged': capture['denominators'], 'original_mechanical_results_unchanged': capture['mechanical_results'],
            'limits': 'Independent short-reason/content audit remains separate. No missing assessment earns credit. This replay neither retries nor rescues failed trials.'}


if __name__ == '__main__':
    result = replay()
    p.save(HERE / 'replay-summary.json', result)
    print(json.dumps({'network_calls': 0, 'replayed_dispatches': result['recorded_provider_calls_replayed'],
                      'summary_sha256': p.sha(HERE / 'replay-summary.json')}))
