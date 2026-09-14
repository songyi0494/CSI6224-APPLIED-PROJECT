import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';
import {evaluateAssessment} from '../supabase/functions/evaluate_pathway_1/engine.ts';
const source=readFileSync(new URL('../supabase/functions/evaluate_pathway_1/index.ts',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'');
function setup({user='patient-a',owner='patient-a',authError=null,revision=1,loadError=null,status='draft',isClinician=false,facts={osteoporosisTreatmentStatus:true},clinician_facts={}}={}){
  let handler;const writes=[];
  const createClient=(_url,key)=>key==='SUPABASE_SERVICE_ROLE_KEY'?{rpc:async(name,args)=>{writes.push({name,args});return {error:null};}}:{
    auth:{getUser:async()=>({data:{user:user?{id:user}:null},error:authError})},
    rpc:async(name)=>name==='has_role'?{data:isClinician,error:null}:{data:{patient_id:owner,revision,status,facts,clinician_facts},error:loadError},
  };
  runInNewContext(stripTypeScriptTypes(source),{createClient,evaluateAssessment,Response,Request,Deno:{env:{get:k=>k},serve:h=>handler=h}});
  return {handler,writes};
}
function request(body={assessment_id:'a',revision:1},headers={Authorization:'Bearer test'}){
  return new Request('https://local.invalid/evaluate',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify(body)});
}
test('edge requires an authenticated request',async()=>{const {handler,writes}=setup();assert.equal((await handler(request({},{}))).status,401);assert.equal(writes.length,0);});
test('edge rejects an invalid token',async()=>{const {handler,writes}=setup({user:null,authError:true});assert.equal((await handler(request())).status,401);assert.equal(writes.length,0);});
test('edge rejects another patient assessment',async()=>{const {handler,writes}=setup({owner:'patient-b'});assert.equal((await handler(request())).status,403);assert.equal(writes.length,0);});
test('edge rejects a stale revision',async()=>{const {handler,writes}=setup({revision:2});assert.equal((await handler(request())).status,409);assert.equal(writes.length,0);});
test('edge evaluates stored input and does not return raw recommendations',async()=>{
  const {handler,writes}=setup();const response=await handler(request({assessment_id:'a',revision:1,facts:{osteoporosisTreatmentStatus:false},pathway:'PATHWAY1',decision:'approved'}));
  assert.equal(response.status,200);assert.deepEqual(await response.json(),{assessment_id:'a'});
  assert.equal(writes[0].args.p_actor,'patient-a');assert.equal(writes[0].args.p_result.pathway,'PATHWAY2');assert.equal(writes[0].args.p_result.decision,'not_integrated');
});
test('edge rejects patient-triggered Pathway 1 evaluation from draft',async()=>{
  const {handler,writes}=setup({facts:{osteoporosisTreatmentStatus:false},status:'draft'});
  assert.equal((await handler(request())).status,403);assert.equal(writes.length,0);
});
test('edge rejects patient-triggered Pathway 1 evaluation from clinician input state',async()=>{
  const {handler,writes}=setup({facts:{osteoporosisTreatmentStatus:false},status:'clinician_input_required'});
  assert.equal((await handler(request())).status,403);assert.equal(writes.length,0);
});
test('edge allows clinician-triggered Pathway 1 evaluation with merged clinician facts',async()=>{
  const {handler,writes}=setup({
    user:'clinician-a',owner:'patient-a',status:'clinician_input_required',isClinician:true,
    facts:{osteoporosisTreatmentStatus:false,age:71,sex:'female',postmenopausal:true,minimalTraumaFracture:true,fractureSite:'vertebral',liveInResidentialCare:false},
    clinician_facts:{eGFR:54,clinicalFrailtyScore:4,lifeExpectancy:10,knownPoorMedicationAdherence:false,cognitiveImpairment:false,dxaImpractical:false,dxaDoneWithinPrevious2Years:true,tScoreValue:-3.5,tScoreSite:'hip',hipVertebralOrMultipleFracturesInLast24M:true,yearsSinceMenopause:20},
  });
  const response=await handler(request());
  assert.equal(response.status,200);assert.equal(writes[0].args.p_actor,'clinician-a');
  assert.equal(writes[0].args.p_result.pathway,'PATHWAY1');assert.equal(writes[0].args.p_result.decision,'action_taken');
});
test('edge rejects pending or rejected clinician-triggered evaluation',async()=>{
  for (const user of ['pending-clinician','rejected-clinician']) {
    const {handler,writes}=setup({
      user,owner:'patient-a',status:'clinician_input_required',isClinician:false,
      facts:{osteoporosisTreatmentStatus:false},
    });
    assert.equal((await handler(request())).status,403);assert.equal(writes.length,0);
  }
});
test('edge rejects unsupported HTTP methods',async()=>{const {handler}=setup();assert.equal((await handler(new Request('https://local.invalid'))).status,405);});
