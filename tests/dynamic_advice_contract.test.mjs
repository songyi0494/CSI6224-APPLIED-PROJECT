import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
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
 for(const name of ['20260924123254_create_investigations','20260929101702_phase3ca_security_investigations_gate_age_advice','20260929101703_final_result_contract','202610080001_p1_p2_contract_reconciliation','202610090001_p1_bmd_risk_boolean_contract','202610090002_p1_care_frailty_boolean_contract','202610090003_patient_questionnaire_required_contract','202610090004_dynamic_patient_advice_contract','202610090005_adherence_concern_boolean_contract']) await db.exec(migration(name));
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
for(const [a,b] of [[true,false],[false,true],[true,true],[false,false]]) test(`calcium Boolean OR dairy=${a} clinician hypocalcaemia=${b}`,async()=>{
 await dairy(a);await saveInv(50,b);const r=await review();const list=await finalize(r);
 assert.equal(r.calcium.supplementRequired,a||b);assert.equal(list.filter(x=>x==='Take calcium 600 mg once daily.').length,a||b?1:0);
 assert.equal(r.calcium.authoritativeHypocalcaemia,b);assert.equal(r.source.adviceContractVersion,adviceVersion);
});
test('recorded ionised calcium cannot create hypocalcaemia',async()=>{
 for(const ion of [0,0.5,1.08,1.12,1.2,null]) {
  const inv=(await saveInv(50,false,ion,70,0)).rows[0].data;
  const r=(await db.query('select public.review_clinical_case_results($1,$2,1) as data',[id,inv.revision])).rows[0].data;
  assert.equal(r.calcium.authoritativeHypocalcaemia,false);assert.equal(r.calcium.recommendation,null);
  // Reset only the synthetic fixture between values.
  await db.exec('delete from investigations;update clinical_cases set results_review=\'{}\'');
 }
});
for(const [vit,expected,recheck] of [[null,null,false],[50,'maintenance',false],[30,'loading',false],[20,'loading',true],[80,null,false],[40,'maintenance',false],[75,'maintenance',false],[25,'loading',false]]) test(`Vitamin D ${vit} uses the supplied band without invented dose`,async()=>{
 await saveInv(vit);const r=await review();const list=await finalize(r);
 assert.equal(r.vitaminD.recheckBeforeTreatment,recheck);
 assert.equal(r.vitaminD.recommendation,expected===null?null:expected==='maintenance'?'Take cholecalciferol 25 micrograms once daily. Continue treatment.':'Take cholecalciferol 75 micrograms once daily for 6 weeks. Then take 25 micrograms once daily.');
 assert.equal(list.includes('Recheck vitamin D before starting osteoporosis treatment.'),recheck);
});
test('all blank baseline numbers stay null and do not block an explicitly saved P1 pathway',async()=>{
 const inv=(await saveInv(null,false,null,null)).rows[0].data;assert.equal(inv.completed,true);assert.equal(inv.vitaminD.value,null);assert.equal(inv.bodyWeight.value,null);
 await evaluate();const r=await review();assert.equal(r.vitaminD.recommendation,null);assert.equal(r.protein.recommendation,null);
});
test('a missing hypocalcaemia confirmation is never false',async()=>{
 const inv=(await saveInv(50,null,0.5)).rows[0].data;assert.equal(inv.authoritativeHypocalcaemia,null);assert.equal(inv.completed,true);
 await assert.rejects(review(),/Confirm hypocalcaemia/);assert.equal((await db.query('select results_review from clinical_cases')).rows[0].results_review.source,undefined);
});
test('numeric dairy history remains readable but cannot supply the new confirmation',async()=>{
 await saveInv();await answers({postmenopausal:'Yes',dietaryDairyServings:2,smoking:'No',alcohol:'No'});
 await assert.rejects(review(),/current patient-reported dairy threshold/);
 assert.equal((await db.query('select answers from questionnaire_responses')).rows[0].answers.dietaryDairyServings,2);
});
test('wrong dairy types and null fail closed',async()=>{await saveInv();for(const value of [null,2,'Yes','true',{},[]]) {await dairy(value);await assert.rejects(review(),/dairy threshold/);}});
test('submission requires Boolean dairy while preserving profile gender and hidden historical answers',async()=>{
 await db.exec(`select set_config('test.uid','${patient}',false);update questionnaire_responses set status='draft';delete from clinical_cases;`);
 for(const value of [2,'Yes',null]) {await dairy(value);await assert.rejects(db.query('select public.submit_questionnaire_response($1)',[response]),/required questionnaire|Dairy threshold/);}
 await answers({postmenopausal:'No',dairyLessThan3Serves:false,smoking:'No',alcohol:'No',dietaryDairyServings:5,sex:'Male'});
 await db.query('select public.submit_questionnaire_response($1)',[response]);const row=(await db.query('select * from questionnaire_responses')).rows[0];assert.equal(row.status,'submitted');assert.equal(row.answers.dietaryDairyServings,5);assert.equal(row.answers.dairyLessThan3Serves,false);
});
test('hypocalcaemia confirmation preserves numeric and pathway revisions and invalidates only candidate advice',async()=>{
 await saveInv(50,null);await evaluate();const before=(await db.query('select * from clinical_cases')).rows[0];
 const inv=(await confirm(true)).rows[0].data;assert.equal(inv.revision,1);assert.equal(inv.hypocalcaemiaRevision,1);assert.equal(inv.authoritativeHypocalcaemia,true);
 const after=(await db.query('select * from clinical_cases')).rows[0];assert.equal(after.status,'evaluated');assert.deepEqual(after.rule_evaluation,before.rule_evaluation);assert.equal(after.pathway_revision,before.pathway_revision);
 const r=await review();assert.equal(r.calcium.recommendation,'Take calcium 600 mg once daily.');
 await confirm(false,1);await assert.rejects(db.query('select public.get_clinical_case_results_review($1)',[id]),/not available/);
 await assert.rejects(confirm(true,1),/Investigations changed/);
});
for(const path of ['PATHWAY1','PATHWAY2']) test(`${path} approval projects the same vitamin D recheck to the patient`,async()=>{
 await saveInv(20,false);await evaluate(path);const r=await review();const expected=await finalize(r);
 await db.query('select public.review_pathway_evaluation($1,\'approved\',\'Reviewed\',1,1,1,1)',[id]);
 await assert.rejects(confirm(true,1),/approved patient result cannot be changed/);
 await db.exec(`select set_config('test.uid','${patient}',false)`);
 const result=(await db.query('select public.get_patient_approved_results() as data')).rows[0].data;
 assert.equal(result.length,1);assert.deepEqual(result[0].lifestyleRecommendations,expected);assert.equal(result[0].lifestyleRecommendations.filter(x=>x==='Recheck vitamin D before starting osteoporosis treatment.').length,1);
});
test('old advice cannot be reused for current approval, but Withhold remains available',async()=>{
 await saveInv();await evaluate();await review();await db.exec(`update clinical_cases set results_review=results_review #- '{source,adviceContractVersion}'`);
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,\'approved\',\'Reviewed\',1,1,1,1)',[id]),/Current Common Advice/);
 await db.query('select public.review_pathway_evaluation($1,\'withheld\',\'Needs review\',1,1,1)',[id]);assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'withheld');
});
test('approval is bound to the advice revision actually reviewed by the clinician',async()=>{
 await saveInv();await evaluate();await review();await confirm(true,1);await review();
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,\'approved\',\'Reviewed old advice\',1,1,1,1)',[id]),/Advice confirmation changed/);
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,\'approved\',\'Legacy caller\',1,1,1)',[id]),/Advice confirmation changed/);
 assert.equal((await db.query('select count(*)::int as count from clinician_decisions')).rows[0].count,0);
 await db.query('select public.review_pathway_evaluation($1,\'approved\',\'Reviewed current advice\',1,1,1,2)',[id]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'approved');
});
test('a stored Boolean without a confirmation revision does not acquire authority',async()=>{
 await saveInv(50,null);await db.exec('update investigations set authoritative_hypocalcaemia=false');await assert.rejects(review(),/Confirm hypocalcaemia/);
 const inv=(await confirm(false,0)).rows[0].data;assert.equal(inv.hypocalcaemiaRevision,1);await review();
});
test('authorization and source revision checks remain protected',async()=>{
 await saveInv();await db.exec(`select set_config('test.uid','${other}',false)`);await assert.rejects(confirm(true,1),/assigned current case/);await assert.rejects(review(),/assigned clinical case/);
 await db.exec(`select set_config('test.uid','${clinician}',false);select set_config('test.approved','false',false)`);await assert.rejects(confirm(true,1),/Only approved clinicians/);
 await db.exec(`select set_config('test.approved','true',false);update questionnaire_responses set revision=2`);await assert.rejects(review(),/Questionnaire response changed/);
});
test('historical hidden falls answers cannot generate a current referral',async()=>{
 await saveInv();await answers({postmenopausal:'Yes',dairyLessThan3Serves:false,smoking:'No',alcohol:'No',fallsPast12Months:2,fearOfFalling:'Yes',movementRehabilitationInterest:'Yes'});const r=await review();assert.ok(!(await finalize(r)).some(x=>/falls clinic/i.test(x)));
});
test('active SQL contains no lab cutoff, and numeric validation still rejects invalid recorded values',async()=>{
 const sql=(await db.query("select pg_get_functiondef('public.review_clinical_case_results(uuid,integer,integer)'::regprocedure) as sql")).rows[0].sql;assert.ok(!sql.includes('1.12'));assert.ok(!/ionised_calcium\s*</.test(sql));
 for(const value of [-1,'NaN','Infinity']) await assert.rejects(saveInv(value),/finite non-negative/);
});
test('direct authenticated writes cannot bypass the clinician confirmation RPC',async()=>{
 await saveInv();await db.exec('set role authenticated');
 try {await assert.rejects(db.query('update public.investigations set authoritative_hypocalcaemia=true'),/permission denied/);} finally {await db.exec('reset role');}
});
test('representative UI advice fixture is generated by the current SQL contract',async()=>{
 await dairy(true);await saveInv(50,false);await answers({postmenopausal:'Yes',dairyLessThan3Serves:true,smoking:'Yes',alcohol:'No'});const r=await review();r.source.generatedAt='2026-10-09T01:00:00Z';
 const url=new URL('../app/test/fixtures/dynamic_ui_advice.json',import.meta.url);
 if(process.env.SONGYI_UI_GENERATE_FIXTURE==='true') writeFileSync(url,JSON.stringify(r,null,2));
 const fixture=JSON.parse(readFileSync(url));fixture.protein.ageAsOf=r.protein.ageAsOf;assert.deepEqual(fixture,r);
});
