import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {before,beforeEach,after,test} from 'node:test';
import {evaluateCasePathway,contractVersion} from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
const {PGlite}=await import(process.env.SONGYI_PGLITE_MODULE ?? '@electric-sql/pglite');
const id='00000000-0000-0000-0000-000000000001',patient='00000000-0000-0000-0000-000000000002',clinician='00000000-0000-0000-0000-000000000003',response='00000000-0000-0000-0000-000000000004',other='00000000-0000-0000-0000-000000000005';
const adviceVersion='songyi-advice-20261009';
const migration=name=>readFileSync(new URL(`../supabase/migrations/${name}.sql`,import.meta.url),'utf8');
const docs=Object.fromEntries([1,2].map(n=>[`PATHWAY${n}`,JSON.parse(readFileSync(new URL(`../supabase/functions/evaluate_pathway/rules/pathway_${n}.json`,import.meta.url)))]));
let db;
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table profiles(id uuid primary key,gender text,date_of_birth date,full_name text,role text);
 create function public.current_user_role() returns text language sql as $$select role from public.profiles where id=auth.uid()$$;
 create function public.is_approved_clinician() returns boolean language sql as $$select public.current_user_role()='clinician' and current_setting('test.approved',true)='true'$$;
 create function public.is_admin() returns boolean language sql as $$select public.current_user_role()='admin'$$;
 create table questionnaire_responses(id uuid primary key,patient_id uuid,status text,answers jsonb,revision integer,submitted_at timestamptz);
 create table questionnaire_questions(id uuid primary key default gen_random_uuid(),field_key text unique,question_text text,question_type text,is_required boolean,display_order integer,options jsonb);
 create table clinical_cases(id uuid primary key default gen_random_uuid(),patient_id uuid,questionnaire_response_id uuid,assigned_clinician_id uuid,status text,patient_facts jsonb default '{}',clinician_facts jsonb default '{}',pathway_answer_order text[] default '{}',pathway_revision integer default 0,rule_evaluation jsonb,pathway text,routing_reason text,updated_at timestamptz default now(),submitted_at timestamptz,claimed_at timestamptz,results_review jsonb default '{}');
 create table clinician_decisions(case_id uuid primary key,clinician_id uuid,decision text,notes text,pathway_revision integer,updated_at timestamptz default now());
 -- Obsolete signatures required only so the historical migration can revoke them.
 create function public.save_rule_evaluation(uuid,jsonb) returns void language plpgsql as $$begin return;end;$$;
 create function public.review_clinical_case_results(uuid) returns jsonb language sql as $$select '{}'::jsonb$$;
 create function public.review_pathway_evaluation(uuid,text,text) returns void language plpgsql as $$begin return;end;$$;
 `);
 for(const name of ['20260924123254_create_investigations','20260929101702_phase3ca_security_investigations_gate_age_advice','20260929101703_final_result_contract','202610080001_p1_p2_contract_reconciliation','202610090001_p1_bmd_risk_boolean_contract','202610090002_p1_care_frailty_boolean_contract','202610090003_patient_questionnaire_required_contract','202610090004_dynamic_patient_advice_contract']) await db.exec(migration(name));
 const forward=new URL('../supabase/migrations/202610090005_adherence_concern_boolean_contract.sql',import.meta.url);
 if(existsSync(forward)) await db.exec(readFileSync(forward,'utf8'));
});
beforeEach(async()=>{
 await db.exec(`truncate clinical_cases,questionnaire_responses,investigations,clinician_decisions;delete from profiles;
 select set_config('test.uid','${clinician}',false);select set_config('test.approved','true',false);
 insert into profiles values('${patient}','female',current_date-interval '71 years','Synthetic patient','patient'),('${clinician}','male',current_date-interval '51 years','Clinician','clinician'),('${other}','male',current_date-interval '55 years','Other clinician','clinician');
 insert into questionnaire_responses values('${response}','${patient}','submitted','{"postmenopausal":"Yes","dairyLessThan3Serves":false,"smoking":"No","alcohol":"No"}',1,now());
 insert into clinical_cases(id,patient_id,questionnaire_response_id,assigned_clinician_id,status,pathway_revision,clinician_facts) values('${id}','${patient}','${response}','${clinician}','in_progress',1,'{"minimalTraumaFracture":"yes","fractureSite":"hip","eGFR":false}');`);
});
after(async()=>{await db?.close();});
const saveInv=(vit=50,hypo=false,ion=1.2,weight=70,revision=0)=>db.query('select public.save_case_investigations($1,$2,$3,$4,$5,$6) as data',[id,vit,ion,weight,revision,hypo]);
const review=async()=> (await db.query('select public.review_clinical_case_results($1,1,1) as data',[id])).rows[0].data;
const confirm=(value,revision=0)=>db.query('select public.confirm_case_hypocalcaemia($1,$2,$3) as data',[id,value,revision]);
const answers=value=>db.query('update questionnaire_responses set answers=$1::jsonb',[JSON.stringify(value)]);
async function dairy(value){await answers({postmenopausal:'Yes',dairyLessThan3Serves:value,smoking:'No',alcohol:'No'});}
async function finalize(r){return (await db.query('select public.phase3_final_common_advice($1::jsonb) as data',[JSON.stringify(r)])).rows[0].data;}
async function evaluate(path='PATHWAY1') {
 if(path==='PATHWAY2') await db.exec(`update clinical_cases set clinician_facts='{"minimalTraumaFracture":"yes","fractureSite":"hip","eGFR":true,"osteoporosisTreatmentStatus":true,"antiresorptiveTreatmentStatus":true,"antiresorptiveTreatmentOver12Months":false}'`);
 const c=(await db.query('select public.get_pathway_case_context($1) as data',[id])).rows[0].data;
 const r={...evaluateCasePathway(docs,c.clinician_facts,c.eligibility_context),contractVersion,eligibilityContext:c.eligibility_context};
 assert.equal(r.status,'complete');assert.equal(r.pathwayId,path);
 await db.query('select public.save_rule_evaluation($1,$2::jsonb,$3,$4)',[id,JSON.stringify(r),c.pathway_revision,c.investigation_revision]);
}
const answer=(key,value)=>db.query('select public.save_pathway_answer($1,$2,$3::jsonb) as facts',[id,key,JSON.stringify(value)]);
const context=async()=>(await db.query('select public.get_pathway_case_context($1) as data',[id])).rows[0].data;
async function setFacts(facts) { await db.query('update clinical_cases set clinician_facts=$1::jsonb,pathway_answer_order=$2',[JSON.stringify(facts),Object.keys(facts)]); }
async function saveEvaluation(evaluation) {
 const c=await context();return db.query('select public.save_rule_evaluation($1,$2::jsonb,$3,$4)',[id,JSON.stringify({...evaluation,eligibilityContext:c.eligibility_context}),c.pathway_revision,c.investigation_revision]);
}
const eligibleFacts={minimalTraumaFracture:'yes',fractureSite:'hip',eGFR:true,osteoporosisTreatmentStatus:false,frailtyResidentialOrLimitedLifeExpectancy:false};
test('SQL aggregate persists literal Yes and No and rejects retired active writes',async()=>{
 await saveInv();
 for(const value of [true,false]) { await answer('adherenceConcern',value);assert.equal((await context()).clinician_facts.adherenceConcern,value); }
 for(const key of ['knownPoorMedicationAdherence','cognitiveImpairment']) await assert.rejects(answer(key,true),/historical/i);
 for(const value of [null,'true',1,{},[]]) await assert.rejects(answer('adherenceConcern',value));
});
test('SQL aggregate cannot bypass assigned-clinician, approval or progress gates',async()=>{
 await saveInv();
 await db.exec(`select set_config('test.uid','${other}',false)`);await assert.rejects(answer('adherenceConcern',true),/assigned/);
 await db.exec(`select set_config('test.uid','${clinician}',false);select set_config('test.approved','false',false)`);await assert.rejects(answer('adherenceConcern',true),/approved/);
 await db.exec(`select set_config('test.approved','true',false);update clinical_cases set status='evaluated'`);await assert.rejects(answer('adherenceConcern',true),/in-progress/);
});
test('SQL first confirmation and upstream edits retain historical components without deriving an aggregate',async()=>{
 await saveInv();
 await setFacts({knownPoorMedicationAdherence:true,cognitiveImpairment:false});
 await db.exec("update clinical_cases set pathway_answer_order='{}'");
 await answer('adherenceConcern',false);
 let f=(await context()).clinician_facts;assert.equal(f.knownPoorMedicationAdherence,true);assert.equal(f.cognitiveImpairment,false);assert.equal(f.adherenceConcern,false);
 await setFacts({...eligibleFacts,knownPoorMedicationAdherence:true,cognitiveImpairment:false,adherenceConcern:false,testAvailability:true});
 await answer('eGFR',false);f=(await context()).clinician_facts;
 assert.equal(f.knownPoorMedicationAdherence,true);assert.equal(f.cognitiveImpairment,false);assert.ok(!('adherenceConcern' in f));assert.ok(!('testAvailability' in f));
});
test('SQL rejects old adherence traversal versions and requires current Boolean confirmation',async()=>{
 await saveInv();await setFacts({...eligibleFacts,knownPoorMedicationAdherence:true,cognitiveImpairment:false});
 const trace=[{pathwayId:'PATHWAY1',nodeId:'ADHERENCE_CONCERN',nodeType:'decision',matched:true}];
 const e={status:'complete',pathwayId:'PATHWAY1',actions:[{type:'referral',destination:'SPECIALIST'}],trace,contractVersion};
 await assert.rejects(saveEvaluation(e),/adherence/i);
 await answer('adherenceConcern',true);
 for(const v of ['songyi-p1p2-20261009-care','songyi-p1p2-20261009-bmd','songyi-p1p2-20261008']) await assert.rejects(saveEvaluation({...e,contractVersion:v}),/old contract|adherence/i);
 await saveEvaluation(e);
});
test('SQL approve refuses an old adherence snapshot; Withhold remains available',async()=>{
 await saveInv();await setFacts({...eligibleFacts,adherenceConcern:true});
 const c=await context();
 await db.query('update clinical_cases set status=$1,rule_evaluation=$2::jsonb',['evaluated',JSON.stringify({status:'complete',pathwayId:'PATHWAY1',actions:[{type:'referral',destination:'SPECIALIST'}],trace:[{pathwayId:'PATHWAY1',nodeId:'ADHERENCE_CONCERN',nodeType:'decision',matched:true}],contractVersion:'songyi-p1p2-20261009-care',eligibilityContext:c.eligibility_context,pathwayRevision:c.pathway_revision,investigationRevision:1})]);
 await review();
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,$2,$3,$4,1,1,1)',[id,'approved','Test',c.pathway_revision]),/adherence|Re-evaluate/i);
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,1,1,1)',[id,'withheld','Fresh adherence confirmation required',c.pathway_revision]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'withheld');
});
test('SQL aggregate release preserves advice and patient approved-result access',async()=>{
 await saveInv();await setFacts({...eligibleFacts,adherenceConcern:true});
 const c=await context();const e={...evaluateCasePathway(docs,c.clinician_facts,c.eligibility_context),contractVersion};assert.equal(e.status,'complete');
 await saveEvaluation(e);await review();
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,1,1,1)',[id,'approved','Test approved message',c.pathway_revision]);
 await db.exec(`select set_config('test.uid','${patient}',false)`);
 const result=(await db.query('select public.get_patient_approved_results() as data')).rows[0].data;
 assert.equal(result.length,1);assert.equal(result[0].clinicianMessage,'Test approved message');assert.deepEqual(result[0].careRecommendation,e.actions);
});
test('forward migration leaves historical rows and actor grants unchanged',async()=>{
 await setFacts({knownPoorMedicationAdherence:true,cognitiveImpairment:false});
 await db.exec("update clinical_cases set status='approved',rule_evaluation='{\"contractVersion\":\"songyi-p1p2-20261009-care\"}'");
 const snapshot=async()=>(await db.query('select to_jsonb(c) as row from clinical_cases c')).rows;
 const before=await snapshot();await db.exec(migration('202610090005_adherence_concern_boolean_contract'));assert.deepEqual(await snapshot(),before);
 for(const signature of ['save_pathway_answer(uuid,text,jsonb)','save_rule_evaluation(uuid,jsonb,integer,integer)','review_pathway_evaluation(uuid,text,text,integer,integer,integer,integer)','review_pathway_evaluation(uuid,text,text,integer,integer,integer)']){
  const r=(await db.query('select has_function_privilege(\'anon\',$1,\'EXECUTE\') as anon,has_function_privilege(\'authenticated\',$1,\'EXECUTE\') as authenticated',[`public.${signature}`])).rows[0];assert.equal(r.anon,false);assert.equal(r.authenticated,true);
 }
});
