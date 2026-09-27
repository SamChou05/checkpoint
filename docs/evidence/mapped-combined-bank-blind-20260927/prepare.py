"""Prepare an answer-hidden synthetic first-three-batch worksheet; no provider calls."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

here = Path(__file__).resolve().parent
root = here.parents[2]
source_commit = '847584de1ea5c2b3b7147f181c52ec8cd83296ba'
assert subprocess.check_output(('git', 'rev-parse', 'HEAD'), cwd=root, text=True).strip() == source_commit
sys.path.insert(0, str(root / 'backend/bedrock-question-service'))
import agreement_task_constructor as agreement  # noqa: E402
import mapped_quantitative_families as numeric  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402

seed = json.loads((root / 'docs/evidence/mapped-bank-diversity-simulation-20260927/seed.json').read_text())
assignments = (
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',numeric.SUPPORTED_TOPIC,numeric.SUPPORTED_OBJECTIVE,3),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',agreement.SUPPORTED_TOPIC,agreement.SUPPORTED_OBJECTIVE,2),
)
contract=native.AuthorSlotContract(5,'constructed_quantitative',assignments,assignments[0][0],2,True,True)
adapted=json.loads(native.adapt_native_response(json.dumps({'questions':seed['sourceTasks']}),contract))
stored=[]
prompts=[]
items=[]
for batch in range(1,4):
 rows, math_proof, english_proof, failures=agreement.prepare_mapped_agreement_rows(
  adapted,contract,existing_prompts=tuple(prompts[-30:]),
  blocked_variant_identities=tuple(question_bank._agreement_variant_history(stored)),
  blocked_quantitative_variant_identities=tuple(question_bank._mapped_quantitative_variant_history(stored)))
 assert not failures and len(rows)==5 and set(math_proof)=={0,1,2} and set(english_proof)=={3,4}
 for slot,row in enumerate(rows):
  (math_proof if slot<3 else english_proof)[slot].content(row)
  assert len(row['choices'])==4 and len(set(row['choices']))==4
  assert row['choices'].count(row['expectedAnswer'])==1
  assert set(row['choiceExplanations'])==set(row['choices'])
  choices=list(row['choices'])
  random.Random(int(hashlib.sha256(row['prompt'].encode()).hexdigest()[:16],16)).shuffle(choices)
  displayed=dict(zip('ABCD',choices,strict=True))
  key=next(label for label,choice in displayed.items() if choice==row['expectedAnswer'])
  items.append({'batch':batch,'slot':slot,'prompt':row['prompt'],'choices':displayed,'key':key,'row':row})
  prompts.append(row['prompt'])
  stored.append({'questionJSON':{'S':json.dumps(row,sort_keys=True)},'state':{'S':'ready'},'createdAt':{'N':str(len(stored))}})
random.Random(17393).shuffle(items)
worksheet={'status':'offline_code_owned_candidates_not_worker_verified',
 'instructions':'Independently choose the one correct displayed answer for each item, or mark ambiguous/none. Judge whether the four choices are meaningfully distinct, self-containment, and difficulty 1-5 for a requested level 2. Identify moderate or strong near-duplicate pairs across all items by the reasoning task, even when operands or scene words differ. Do not inspect any source, private mapping, other reviews, or implementation before locking your review.',
 'items':[{'id':f'B{i:02d}','prompt':item['prompt'],'choices':item['choices']} for i,item in enumerate(items,1)]}
private={'mapping':{f'B{i:02d}':{'batch':item['batch'],'slot':item['slot'],'key':item['key'],'row':item['row']} for i,item in enumerate(items,1)}}
rendered_worksheet = json.dumps(worksheet,indent=2,ensure_ascii=False)+'\n'
rendered_private = json.dumps(private,indent=2,ensure_ascii=False)+'\n'
assert (here/'worksheet.json').read_text() == rendered_worksheet
assert (here/'private.json').read_text() == rendered_private
print('items',len(items),'worksheet_sha256',hashlib.sha256((here/'worksheet.json').read_bytes()).hexdigest())
