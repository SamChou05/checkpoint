const fs = require('fs');
const crypto = require('crypto');
const {chromium} = require('/Users/samchou/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const inputPath='/tmp/checkpoint-stem-length-html-blind-20260908.json';
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const raw=fs.readFileSync(inputPath);
if(sha(raw)!=='4f3bdbaad9e1826c4b25a9b6403457b08ac147478a22af8e54792d67011483a9')throw Error('Blind input hash mismatch');
const items=JSON.parse(raw);
const groups=new Map();
for(const item of items){if(!groups.has(item.prompt))groups.set(item.prompt,[]);groups.get(item.prompt).push(item.id);}
(async()=>{
 const browser=await chromium.launch({headless:true,chromiumSandbox:true,timeout:15000});
 const output={schema:'checkpoint.html_blind_native_observations.v1',input_path:inputPath,input_sha256:sha(raw),browser_version:browser.version(),runner_source:fs.readFileSync(__filename,'utf8'),settings:{offline:true,javaScriptEnabled:false,acceptDownloads:false,allRoutesAborted:true,chromiumSandbox:true},observations:[]};
 try{
  for(const [prompt,ids] of groups){
   let html,kind,statement=null,span=null,inputSpan=null;
   if(prompt.includes('<fieldset')){
    const start=prompt.indexOf('<fieldset'),end=prompt.lastIndexOf('</fieldset>')+'</fieldset>'.length;
    html=prompt.slice(start,end);kind='exact_displayed_html_fragment';span={start,end};
    if(prompt.includes("document.getElementById('x').removeAttribute('disabled');"))statement="document.getElementById('x').removeAttribute('disabled');";
   }else{
    const match=/<input[^>]*>/.exec(prompt);if(!match)throw Error('No literal input');
    inputSpan={start:match.index,end:match.index+match[0].length,text:match[0]};
    kind='assistant_realization_of_explicit_prose_ancestry_with_exact_input';
    if(prompt.startsWith("A disabled outer fieldset's first legend"))html='<fieldset disabled id="outer"><legend><fieldset disabled id="inner">'+match[0]+'</fieldset></legend></fieldset>';
    else html='<fieldset disabled>'+match[0]+'</fieldset>';
    if(prompt.includes("b.removeAttribute('disabled')"))statement="b.removeAttribute('disabled')";
   }
   const context=await browser.newContext({offline:true,javaScriptEnabled:false,acceptDownloads:false});
   await context.route('**/*',route=>route.abort());
   const page=await context.newPage();
   const observe=()=>page.evaluate(()=>[...document.querySelectorAll('input')].map(input=>({id:input.id,ownDisabled:input.disabled,effectiveDisabled:input.matches(':disabled'),willValidate:input.willValidate,checkValidity:input.checkValidity(),validityValid:input.validity.valid,typeMismatch:input.validity.typeMismatch,valueMissing:input.validity.valueMissing,value:input.value,outerHTML:input.outerHTML,fieldsetAncestors:[...(()=>{let result=[],p=input.parentElement;while(p){if(p.localName==='fieldset')result.push(p);p=p.parentElement;}return result;})()].map(fs=>({id:fs.id,disabledAttribute:fs.hasAttribute('disabled'),insideFirstLegend:[...fs.children].filter(c=>c.localName==='legend')[0]?.contains(input)??false}))})));
   try{
    await page.setContent(html,{timeout:10000});
    const row={ids,prompt,prompt_sha256:sha(prompt),prompt_code_points:[...prompt].length,observation_kind:kind,html,html_sha256:sha(html),exact_html_span:span,exact_input_span:inputSpan,statement,serializedDOMBefore:await page.locator('body').innerHTML(),before:await observe()};
    if(statement){row.exact_statement_span={start:prompt.indexOf(statement),end:prompt.indexOf(statement)+statement.length};await page.evaluate(statement);row.after=await observe();row.serializedDOMAfter=await page.locator('body').innerHTML();}
    output.observations.push(row);
   }finally{await context.close();}
  }
 }finally{await browser.close();}
 const outputPath='/tmp/checkpoint-stem-length-html-blind-observations-20260908.json';
 fs.writeFileSync(outputPath,JSON.stringify(output,null,2)+'\n');
 console.log(JSON.stringify({path:outputPath,sha256:sha(fs.readFileSync(outputPath)),observations:output.observations.map(r=>({ids:r.ids,chars:r.prompt_code_points,kind:r.observation_kind,before:r.before,after:r.after}))},null,2));
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
