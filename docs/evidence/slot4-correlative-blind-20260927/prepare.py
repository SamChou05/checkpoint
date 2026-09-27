import hashlib
import json
import random
import subprocess
import sys
from pathlib import Path
here=Path(__file__).resolve().parent
root=here.parents[2]
assert subprocess.check_output(('git','rev-parse','HEAD'),cwd=root,text=True).strip()=='0d28a099b0aa8bafd1e815222907b8e0e82082cc'
sys.path.insert(0,str(root/'backend/bedrock-question-service'))
from agreement_task_constructor import CORRELATIVE_SCENES,TASK_KIND,compile_question  # noqa: E402
rows=[]
for scene in CORRELATIVE_SCENES:
 for order in ('singular_first','plural_first'):
  row=compile_question({'kind':TASK_KIND,'scene':scene,'order':order},ordinal=4)
  choices=list(row['choices'])
  random.Random(int(hashlib.sha256(row['prompt'].encode()).hexdigest()[:16],16)).shuffle(choices)
  displayed=dict(zip('ABCD',choices,strict=True))
  key=next(label for label,choice in displayed.items() if choice==row['expectedAnswer'])
  rows.append({'scene':scene,'order':order,'row':row,'choices':displayed,'key':key})
random.Random(12078).shuffle(rows)
worksheet={'instructions':'For each learner-facing item, independently select the one correct displayed choice (or mark none/multiple), assess whether the four choices differ meaningfully, and rate naturalness/idiomaticity on a 1-5 scale (1 unusable, 5 natural). Note any ambiguity or awkward mixed singular/plural constructions. Do not inspect source or private mapping until review is locked.','items':[{'id':f'C{i:02d}','prompt':x['row']['prompt'],'choices':x['choices']} for i,x in enumerate(rows,1)]}
private={'mapping':{f'C{i:02d}':{'scene':x['scene'],'order':x['order'],'key':x['key'],'row':x['row']} for i,x in enumerate(rows,1)}}
assert (here/'worksheet.json').read_text()==json.dumps(worksheet,indent=2,ensure_ascii=False)+'\n'
assert (here/'private.json').read_text()==json.dumps(private,indent=2,ensure_ascii=False)+'\n'
print(hashlib.sha256((here/'worksheet.json').read_bytes()).hexdigest())
