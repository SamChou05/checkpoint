#!/usr/bin/env python3
"""Read frozen captures, inventory existing responses; no model calls or gate execution."""
import argparse, collections, hashlib, json, re, subprocess
from pathlib import Path

def sha(b): return hashlib.sha256(b).hexdigest()
def canonical(x): return json.dumps(x,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()
def parse_final(text):
    text=text.strip()
    if text.startswith('```'):
        text=re.sub(r'^```(?:json)?\s*','',text)
        text=re.sub(r'\s*```$','',text)
    return json.loads(text)
def request_payload(call):
    text=call['request']['messages'][0]['content'][0]['text']
    return json.loads(text.split('<question_solution_json>',1)[1].split('</question_solution_json>',1)[0])
def solution_record(path,locator,call,solution,question,identity,quality):
    raw=''.join(call['response']['text']); i=solution['index']; limit=solution['limitations'].strip()
    return {'capture_path':path,'raw_solution_locator':locator+f'/response/text#concat_then_json/solutions/{i}',
      'call_locator':locator,'provider_response_text_sha256':sha(raw.encode()),'solution_sha256':sha(canonical(solution)),
      'identity':identity,'prompt':question['prompt'],'solver':solution,'archived_assessment':quality,
      'call_provenance':{'kind':'actual_recorded_model_response','modelId':call['request']['modelId'],'status':call['status'],'stopReason':call['response']['stopReason'],'usage':call['response']['usage']},
      'counterfactual_new_item_veto_all_outcomes':bool(limit),'counterfactual_new_item_veto_resolved_only':solution['outcome']=='resolved' and bool(limit)}

def main():
    p=argparse.ArgumentParser();p.add_argument('--repo',default='/Users/samchou/Documents/Checkpoint');p.add_argument('--output',default='/tmp/checkpoint-limitations-impact-audit-20260906.json');a=p.parse_args();repo=Path(a.repo)
    paths=['docs/evidence/source-authoring-feasibility-20260906.json','docs/evidence/source-authoring-adjudication-20260906.json','docs/evidence/solver-outcome-smoke-20260906.json','docs/evidence/evidence-review-feasibility-20260906.json','docs/evidence/four-domain-feasibility-20260906.json','docs/evidence/four-domain-adjudication-20260906.json']
    data={s:json.loads((repo/s).read_text()) for s in paths}
    src=data[paths[0]];srcadj=data[paths[1]];smoke=data[paths[2]];evidence=data[paths[3]];four=data[paths[4]];fouradj=data[paths[5]]
    rows=[];source_adjudication={r['display_id']:r for r in srcadj['candidate_rows']}
    for ci,call in enumerate(src['calls']):
        if call['stage']!='solver':continue
        j=call['job_index'];result=src['results'][j];payload=request_payload(call);parsed=parse_final(''.join(call['response']['text']))
        assert parsed==result['stage_outputs']['solver']
        for solution in parsed['solutions']:
            i=solution['index'];occ=result['sanitized_occurrences'][i];identity={'experiment':'source_authoring','job_index':j,'case_id':result['case_id'],'arm':result['arm'],'item_index':i,'display_id':occ['blinded']['id']}
            assert payload['items'][i]['prompt']==occ['question']['prompt']
            q=source_adjudication[identity['display_id']]
            rows.append(solution_record(paths[0],f'/calls/{ci}',call,solution,occ['question'],{'record_id':f'source-{j}-{i}',**identity},{'path':paths[1],'locator':f"/candidate_rows/{srcadj['candidate_rows'].index(q)}",'returned':q['returned'],'complete_reviewed_content':q['complete_reviewed_content'],'independent_difficulty':q['independent_difficulty']}))
    for ci,call in enumerate(smoke['capture']['calls']):
        text=call['request']['messages'][0]['content'][0]['text']
        if not text.startswith('<question_solution_json>'):continue
        ri=next(i for i,r in enumerate(smoke['capture']['results']) if r['case_id']==call['case_id']);result=smoke['capture']['results'][ri]
        parsed=parse_final(''.join(call['response']['text']));assert parsed==result['stage_outputs']['solver']
        assert len(parsed['solutions'])==1
        rows.append(solution_record(paths[2],f'/capture/calls/{ci}',call,parsed['solutions'][0],request_payload(call)['items'][0],{'record_id':'outcome-'+call['case_id'],'experiment':'solver_outcome_smoke','case_id':call['case_id']},{'path':paths[2],'locator':f'/adjudication/{ri}','returned':result['accepted'],'adjudication':smoke['adjudication'][ri]}))
    assert len(rows)==16
    assert all(r['call_provenance']['stopReason']=='end_turn' for r in rows)
    assert all(r['solver']['assumptionsRequired']==[] for r in rows)
    older=[]
    for ri,classification in [(1,'meaningful_missing_conditions_or_unjustified_optimum'),(4,'decisive_output_size_limitation')]:
        result=evidence['results'][ri];raw=result['reviews'][0];solution=parse_final(raw)['solutions'][0];case=next(c for c in evidence['fixture']['cases'] if c['case_id']==result['case_id'])
        assert 'outcome' not in solution
        older.append({'capture_path':paths[3],'raw_solution_locator':f'/results/{ri}/reviews/0#json/solutions/0','kind':'actual_old_schema_model_response','schema_note':'outcome absent; do not relabel as resolved under the current contract.','case_id':result['case_id'],'arm':result['arm'],'repeat':result['repeat'],'question':case['question'],'solver':solution,'solution_sha256':sha(canonical(solution)),'accepted_then':result['accepted'],'classification':classification,'new_schema_gate_rate_not_computable':True})
    artifact=four['executed_artifact_files'][7];assert artifact['name']=='photography_exposure.calls.json';assert sha(artifact['exact_utf8_text'].encode())==artifact['sha256']
    call=json.loads(artifact['exact_utf8_text'])[1];solution=parse_final(''.join(call['response']['text']))['solutions'][1];adjudication=fouradj['rows'][14]
    assert solution==adjudication['solver_record_as_supplied_to_reviewer'];assert 'outcome' not in solution
    older.append({'capture_path':paths[4],'raw_solution_locator':'/executed_artifact_files/7/exact_utf8_text#json/1/response/text/0#json/solutions/1','kind':'actual_old_schema_model_response','schema_note':'outcome absent; do not relabel as resolved under the current contract.','case_id':'photography_exposure','content_id':adjudication['id'],'question':adjudication['author_question'],'solver':solution,'solution_sha256':sha(canonical(solution)),'accepted_then':adjudication['retained'],'classification':'useful_exposure_caveat_separate_from_key_and_feedback','frozen_assessment_locator':paths[5]+'#/rows/14','key_status':adjudication['frozen_blind_review']['answer_status'],'qualification':adjudication['frozen_blind_review']['required_qualification'],'reviewer_main_status':adjudication['reviewer_main_explanation_assessment']['status'],'new_schema_gate_rate_not_computable':True})
    valid_old_controls=[]
    for ri in [0,2,3,6]:
        result=evidence['results'][ri];sol=parse_final(result['reviews'][0])['solutions'][0]
        valid_old_controls.append({'locator':paths[3]+f'#/results/{ri}/reviews/0#json/solutions/0','case_id':result['case_id'],'arm':result['arm'],'outcome_present':'outcome' in sol,'limitations_nonempty':bool(sol['limitations'].strip())})
    revision='eb5543316ce639082016f3329107b29d213b1717'
    schema_bytes=subprocess.check_output(['git','show',revision+':backend/bedrock-question-service/question_verification.py'],cwd=repo)
    flagged=[r['identity']['record_id'] for r in rows if r['counterfactual_new_item_veto_resolved_only']]
    assert flagged==['source-0-0']
    report={'schema_version':1,'purpose':'Bounded retrospective item-eligibility audit of a proposed nonempty solver limitations veto. Not a production accuracy estimate or new generation experiment.','created_date':'2026-09-06','runner':{'path':str(Path(__file__).resolve()),'sha256':sha(Path(__file__).read_bytes()),'invocation':'python3 /tmp/checkpoint-limitations-impact-audit-20260906.py --repo /Users/samchou/Documents/Checkpoint'},'source_artifacts':[{'path':s,'sha256':sha((repo/s).read_bytes())} for s in paths],
      'committed_schema_reference':{'revision':revision,'path':'backend/bedrock-question-service/question_verification.py','sha256':sha(schema_bytes),'inspection_note':'Frozen parent of gate commit 26feed4: resolved + empty assumptions was eligible even with limitations; exceptional outcomes required canonical app-owned choices. This runner inventories captures and does not execute either gate.','subsequent_gate_commit':'26feed4fab44763eb0ea3b6451fe09a8a6d76a36'},
      'method':['Exactly 16 explicit-outcome solution records are parsed from eight canonical actual solver responses: four three-item source-authoring calls and four single-item outcome-smoke calls.','Parsed responses are exact-joined to archived stage_outputs and presented stems. Repeated stage_outputs, adjudication embeddings, and pre-fix mock/replay archives are not additional model calls.','A JSON-pointer-like locator uses #json to parse an embedded string and #concat_then_json to concatenate the response text list before parsing.','Veto simulation only checks trimmed limitations text, once for all outcomes and once only for explicit resolved. It does not rerun generation, reindex batches, or predict changed reviewer responses.','Three older actual responses illustrate mechanisms only; their schema lacks outcome. Four nearby old valid control metadata records are checked separately for empty limitations.','No malformed responses, mocks, unit fixtures, author responses, reviewer responses, or native grounding probes are counted as current solver outcomes.'],
      'current_summary':{'actual_solver_calls':8,'actual_solution_records':16,'outcome_counts':dict(collections.Counter(r['solver']['outcome'] for r in rows)),'nonempty_limitations_records':len(flagged),'resolved_only_veto_records':flagged,'all_outcome_veto_records':[r['identity']['record_id'] for r in rows if r['counterfactual_new_item_veto_all_outcomes']],'assumptions_nonempty_records':0,'newly_vetoed_previously_returned_records':sum(r['counterfactual_new_item_veto_resolved_only'] and r['archived_assessment']['returned'] for r in rows)},
      'current_records':rows,'older_examples':older,'older_nearby_valid_controls':valid_old_controls,
      'impact_findings':[
       {'finding':'The sole current veto is a choice-blinding caveat, not an admission that the complete MCQ has no correct answer.','record_id':'source-0-0','exact_limitation':rows[0]['solver']['limitations'],'key_assessment':'Frozen independent review supported the best-listed key. Relevant descriptions live in the choices, so the authored stem does not meet a stronger requirement to be fully answerable before seeing choices.','returned_content_assessment':'Returned main explanation was supported, but one distractor explanation overstated the effect of leaflessness; complete reviewed content was false. Rejecting this item is not demonstrated as either a clean factual catch or a clean complete-content false rejection.','assessment_locator':paths[1]+'#/original_documents/plants-feedback-review/original_utf8_text#json/rows/0'},
       {'finding':'The most consequential latest failures bypass this proposed field check because limitations is empty.','records':['source-2-1','source-2-2','source-1-1','outcome-all_pairs_output_bound','outcome-raw_highlight_recovery_unsupported_sequence'],'details':'The DOB-label item preserves a missing-condition clause in answer instead of limitations; the span item invents absent associations, the plant item invents light amplification, and the outcome smoke repeats unsupported linear-time and mandatory RAW sequence claims. All have resolved, limitations empty, and assumptionsRequired empty.'},
       {'finding':'All four outcome-smoke records survive either proposed limitations check.','details':'This includes both known invalid questions, the supported canonical no_solution key/main explanation, and the fully supported Mira conditional control. The no_solution record happened to have empty limitations; this archive does not empirically test legitimate nonempty exceptional-outcome explanations.'},
       {'finding':'Older limitations range from decisive objections to useful caveats.','details':'The RAW caveat preserves missing recoverability and nonmandatory-order qualifications; the all-pairs evidence caveat explicitly flags output-sensitive work. The DoF exposure caveat does not invalidate the best-listed key, although the solver overpromises exact sharpness and returned feedback had independent errors. These old records cannot supply a current resolved-only rejection rate.'},
       {'finding':'No fully sound returned current item is observed to be newly vetoed in this bounded inventory.','details':'This is not evidence that nonempty limitations never accompany fully sound questions. It describes one nonempty current record and three selected older examples; empty limitations is not proof of correctness.'}],
      'validation_cases_for_root':['Resolved with nonempty prose containing an actual unmet precondition: intended veto.','Resolved with a choice-hidden caveat: fail the declared choice-independent author contract without labeling the complete MCQ factually wrong.','Resolved with an innocuous valid caveat: document the deliberate abstention/coverage cost if all nonempty text is vetoed.','Resolved with the missing condition only in answer and empty limitations: preserve as known uncovered case.','Canonical no_solution/underdetermined/inconsistent_premises with nonempty evidence limitations: preserve if the rule is resolved-only; do not confuse proof qualifications with a required positive-answer assumption.','Whitespace-only limitations and strings containing only a denial such as None: decide using the explicit contract, without unsupported semantic string heuristics.'],
      'limits':['Frozen outputs only; no new model behavior, production rates, broad false-rejection estimates, or call-saving estimates are established.','A stricter gate can enforce an output-field contract while missing identical problems expressed elsewhere or not admitted by the model.','The audit reuses prior independent subject adjudications; it is not a fresh blinded regrade.','Source-authoring occurrence counts remain 12 actual questions, not raw/display duplicate identities.']}
    out=Path(a.output);out.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'path':str(out),'sha256':sha(out.read_bytes()),'summary':report['current_summary']},indent=2))
if __name__=='__main__':main()
