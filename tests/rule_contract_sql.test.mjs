import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, beforeEach, after, test} from 'node:test';
// This harness freezes the previously applied care migration. The current
// aggregate migration and release boundary are tested in adherence_contract_sql.
const contractVersion = 'songyi-p1p2-20261009-care';
// Install the test-only PGlite dependency outside the checkout, then provide
// its module URL. This harness never connects to Supabase or a live database.
const {PGlite} = await import(process.env.SONGYI_PGLITE_MODULE ?? '@electric-sql/pglite');
let db;
const id='00000000-0000-0000-0000-000000000001';
const patient='00000000-0000-0000-0000-000000000002';
const clinician='00000000-0000-0000-0000-000000000003';
const response='00000000-0000-0000-0000-000000000004';
before(async()=>{
 db=new PGlite();
 await db.exec(`
 create role anon; create role authenticated;
 create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function public.is_approved_clinician() returns boolean language sql as $$select current_setting('test.approved',true) = 'true'$$;
 create table profiles(id uuid primary key, gender text, date_of_birth date);
 create table questionnaire_responses(id uuid primary key, patient_id uuid, status text, answers jsonb, revision integer);
 create table clinical_cases(id uuid primary key, patient_id uuid, questionnaire_response_id uuid, assigned_clinician_id uuid, status text, clinician_facts jsonb, pathway_answer_order text[], pathway_revision integer, rule_evaluation jsonb, pathway text, routing_reason text, updated_at timestamptz, results_review jsonb default '{}');
 create table clinician_decisions(case_id uuid primary key, clinician_id uuid, decision text, notes text, pathway_revision integer, investigation_revision integer, questionnaire_revision integer, approved_actions_snapshot jsonb, approved_common_advice_snapshot jsonb, released_at timestamptz, updated_at timestamptz default now());
 create function public.phase3_final_common_advice(p_results_review jsonb) returns jsonb language sql as $$select '[]'::jsonb$$;
 create table investigations(case_id uuid primary key, revision integer, completed_at timestamptz);
 create function public.phase3ca_investigations_complete(p_case_id uuid) returns boolean language sql as $$select exists(select 1 from public.investigations where case_id=p_case_id and completed_at is not null)$$;
 `);
 await db.exec(readFileSync(new URL('../supabase/migrations/202610080001_p1_p2_contract_reconciliation.sql',import.meta.url),'utf8'));
 await db.exec(readFileSync(new URL('../supabase/migrations/202610090001_p1_bmd_risk_boolean_contract.sql',import.meta.url),'utf8'));
 await db.exec(readFileSync(new URL('../supabase/migrations/202610090002_p1_care_frailty_boolean_contract.sql',import.meta.url),'utf8'));
});
beforeEach(async()=>{
 await db.exec(`
 truncate public.clinical_cases, public.profiles, public.questionnaire_responses, public.investigations, public.clinician_decisions;
 select set_config('test.uid','${clinician}',false); select set_config('test.approved','true',false);
 insert into profiles values('${patient}','female',current_date - interval '71 years');
 insert into questionnaire_responses values('${response}','${patient}','submitted','{"postmenopausal":"Yes"}',1);
 insert into clinical_cases(id,patient_id,questionnaire_response_id,assigned_clinician_id,status,clinician_facts,pathway_answer_order,pathway_revision,updated_at) values('${id}','${patient}','${response}','${clinician}','in_progress','{}','{}',0,now());
 insert into investigations values('${id}',1,now());
 `);
});
after(async()=>{await db?.close();});
async function answer(key,value){return db.query('select public.save_pathway_answer($1,$2,$3::jsonb) as facts',[id,key,JSON.stringify(value)]);}
async function context(){return (await db.query('select public.get_pathway_case_context($1) as context',[id])).rows[0].context;}
async function eligible(){await answer('minimalTraumaFracture','yes');await answer('fractureSite','hip');await answer('eGFR',false);}
async function save(ctx, extras={}) {
 const evaluation={status:'complete',pathwayId:'PATHWAY1',actions:[],trace:[],contractVersion,eligibilityContext:ctx.eligibility_context,...extras};
 return db.query('select public.save_rule_evaluation($1,$2::jsonb,$3,$4)',[id,JSON.stringify(evaluation),ctx.pathway_revision,ctx.investigation_revision]);
}
test('SQL persists Boolean threshold and rejects numeric eGFR',async()=>{
 for(const value of [29,30,60,'true']) await assert.rejects(answer('eGFR',value),/eGFR must confirm/);
 await answer('eGFR',true);assert.equal((await context()).clinician_facts.eGFR,true);
 await answer('eGFR',false);assert.equal((await context()).clinician_facts.eGFR,false);
});
test('SQL persists Not sure without converting it to No',async()=>{
 await answer('minimalTraumaFracture','not_sure');await answer('fractureSite','not_sure');
 const ctx=await context();assert.equal(ctx.clinician_facts.minimalTraumaFracture,'not_sure');assert.equal(ctx.clinician_facts.fractureSite,'not_sure');
 await assert.rejects(save(ctx),/structured P1 eligibility/);
});
test('SQL allows separately captured excluded sites but rejects completion',async()=>{
 for(const site of ['hand','foot','face','ankle']) {
  await eligible();await answer('fractureSite',site);await answer('eGFR',false);
  assert.equal((await context()).clinician_facts.fractureSite,site);
  await assert.rejects(save(await context()),/structured P1 eligibility/);
 }
 await assert.rejects(answer('fractureSite','Leg, ankle or foot'),/separate fracture site/);
});
test('SQL source context uses profile sex rather than forged questionnaire sex',async()=>{
 await db.exec(`update questionnaire_responses set answers='{"sex":"Male","postmenopausal":"Yes"}';`);
 assert.equal((await context()).eligibility_context.sex,'female');
 await assert.rejects(answer('p1DemographicEligible',true),/patient profile/);
});
test('SQL uncertainty, unavailable and No menopause retain distinct source states',async()=>{
 for(const [answers,expected] of [[{postmenopausal:'Not sure'},null],[{},null],[{postmenopausal:'No'},false],[{postmenopausal:false},false]]) {
  await db.query('update questionnaire_responses set answers=$1::jsonb',[JSON.stringify(answers)]);
  assert.equal((await context()).eligibility_context.postmenopausal,expected);
  await eligible();await assert.rejects(save(await context()),/demographic eligibility/);
 }
});
test('SQL derives age and never fabricates male menopause',async()=>{
 await db.exec(`update profiles set gender='male',date_of_birth=current_date - interval '51 years';`);
 let ctx=await context();assert.equal(ctx.eligibility_context.age,51);assert.equal(ctx.eligibility_context.postmenopausal,null);
 await eligible();await save(await context());
});
test('SQL male age 50 cannot save an eligible result',async()=>{
 await db.exec(`update profiles set gender='male',date_of_birth=current_date - interval '50 years';`);
 await eligible();await assert.rejects(save(await context()),/demographic eligibility/);
});
test('SQL >12-month key rejects legacy meaning and raw months',async()=>{
 await assert.rejects(answer('antiresorptiveTreatmentDuration',true),/current duration question/);
 await assert.rejects(answer('antiresorptiveTreatmentOver12Months',12),/requires Yes or No/);
 await answer('antiresorptiveTreatmentOver12Months',false);
 assert.equal((await context()).clinician_facts.antiresorptiveTreatmentOver12Months,false);
 await answer('antiresorptiveTreatmentOver12Months',true);
 assert.equal((await context()).clinician_facts.antiresorptiveTreatmentOver12Months,true);
});
test('SQL source revision change rejects stale evaluation',async()=>{
 await eligible();const ctx=await context();
 await db.exec('update questionnaire_responses set revision=revision+1');
 await assert.rejects(save(ctx),/Eligibility information changed/);
 assert.equal((await context()).status,'in_progress');
});
test('SQL demographic change rejects stale evaluation',async()=>{
 await eligible();const ctx=await context();
 await db.exec(`update profiles set gender='male',date_of_birth=current_date - interval '50 years';`);
 await assert.rejects(save(ctx),/Eligibility information changed/);
});
test('SQL old evaluator payload cannot save complete results',async()=>{
 await eligible();const ctx=await context();
 await assert.rejects(save(ctx,{contractVersion:'old'}),/old contract/);
 await assert.rejects(save(ctx,{eligibilityContext:null}),/old contract/);
});
test('SQL valid current eligibility persists without rewriting historical cases',async()=>{
 await eligible();const ctx=await context();await save(ctx);
 const row=(await db.query('select status,rule_evaluation from clinical_cases where id=$1',[id])).rows[0];
 assert.equal(row.status,'evaluated');assert.deepEqual(row.rule_evaluation.eligibilityContext,ctx.eligibility_context);
});
test('SQL answer edit preserves existing downstream invalidation',async()=>{
 await eligible();await answer('osteoporosisTreatmentStatus',true);
 await answer('minimalTraumaFracture','not_sure');
 const ctx=await context();assert.deepEqual(ctx.clinician_facts,{minimalTraumaFracture:'not_sure'});
});
test('SQL assignment and approved-clinician checks remain in place',async()=>{
 await db.exec(`select set_config('test.uid','${patient}',false);`);
 await assert.rejects(context(),/assigned clinical case/);
 await assert.rejects(answer('eGFR',true),/assigned clinical case/);
 await db.exec(`select set_config('test.uid','${clinician}',false);select set_config('test.approved','false',false);`);
 await assert.rejects(context(),/approved clinicians/);
});
test('SQL stale eligibility also blocks approval after advice is refreshed',async()=>{
 await eligible();const ctx=await context();await save(ctx,{actions:[{type:'referral',destination:'SPECIALIST'}]});
 await db.exec(`update questionnaire_responses set revision=2; update clinical_cases set results_review='{"source":{"investigationRevision":1,"questionnaireRevision":2}}';`);
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'approved','Reviewed',ctx.pathway_revision,1,2]),/Current P1 eligibility/);
 assert.equal((await db.query('select count(*)::integer as count from clinician_decisions')).rows[0].count,0);
});
test('SQL current eligibility permits existing clinician approval and Withhold',async()=>{
 await eligible();const ctx=await context();await save(ctx,{actions:[{type:'referral',destination:'SPECIALIST'}]});
 await db.exec(`update clinical_cases set results_review='{"source":{"investigationRevision":1,"questionnaireRevision":1}}';`);
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'approved','Reviewed',ctx.pathway_revision,1,1]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'approved');
 await db.exec(`update questionnaire_responses set answers='{"postmenopausal":"No"}', revision=2;`);
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'withheld','Eligibility changed',ctx.pathway_revision,1,2]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'withheld');
});
test('SQL BMD/risk Boolean persistence rejects numbers, strings, null and retired components',async()=>{
 for(const key of ['tScoreAtOrBelowMinus2_5AnySite','veryHighFractureRisk']) {
  for(const value of [-3.1,30,'true','not_sure',null]) await assert.rejects(answer(key,value));
  await answer(key,true);assert.equal((await context()).clinician_facts[key],true);
  await answer(key,false);assert.equal((await context()).clinician_facts[key],false);
 }
 for(const key of ['femoralNeckTscore','hipTscore','lumbarSpineTscore','recentFractureWithin2Y','historyOf2orMoreFractures','clinicalRiskFactors','FRAX10YmajorOsteoporoticFractureRiskPercent','FRAX10YmajorHipFractureRiskPercent']) await assert.rejects(answer(key,true),/historical/);
 await assert.rejects(answer('inventedCriterion',true),/Unsupported active pathway fact/);
});
test('SQL traversed T-score node requires fresh confirmation and never derives raw history',async()=>{
 await eligible();await db.exec(`update clinical_cases set clinician_facts=clinician_facts || '{"femoralNeckTscore":-3.1,"hipTscore":-2.5,"lumbarSpineTscore":-1.0}'::jsonb;`);
 let ctx=await context();
 const trace=[{pathwayId:'PATHWAY1',nodeId:'T_SCORE_CHECK',nodeType:'decision',matched:false}];
 await assert.rejects(save(ctx,{trace}),/Fresh clinician confirmation.*T-score/);
 assert.equal((await context()).clinician_facts.femoralNeckTscore,-3.1);
 await answer('tScoreAtOrBelowMinus2_5AnySite',false);await save(await context(),{trace});
});
test('SQL complete composite requires a separate confirmation even with a low T-score and high FRAX history',async()=>{
 await eligible();await answer('tScoreAtOrBelowMinus2_5AnySite',true);
 await db.exec(`update clinical_cases set clinician_facts=clinician_facts || '{"femoralNeckTscore":-3.1,"FRAX10YmajorOsteoporoticFractureRiskPercent":40}'::jsonb;`);
 const trace=[{pathwayId:'PATHWAY1',nodeId:'T_SCORE_CHECK',nodeType:'decision',matched:true},{pathwayId:'PATHWAY1',nodeId:'HIGH_RISK_CHECK',nodeType:'decision',matched:false}];
 await assert.rejects(save(await context(),{trace}),/complete very-high-fracture-risk/);
 await answer('veryHighFractureRisk',false);await save(await context(),{trace});
 const stored=(await db.query('select clinician_facts from clinical_cases where id=$1',[id])).rows[0].clinician_facts;
 assert.equal(stored.veryHighFractureRisk,false);assert.equal(stored.femoralNeckTscore,-3.1);
});
test('SQL earlier renal leaf does not demand BMD/risk confirmations',async()=>{
 await eligible();await save(await context(),{trace:[{pathwayId:'PATHWAY1',nodeId:'RENAL_DYSFUNCTION',nodeType:'decision',matched:false}]});
});
test('SQL predecessor contract snapshot is not a current BMD evaluation',async()=>{
 await eligible();await assert.rejects(save(await context(),{contractVersion:'songyi-p1p2-20261008',trace:[{pathwayId:'PATHWAY1',nodeId:'T_SCORE_CHECK',nodeType:'decision',matched:false}]}),/old contract/);
});
test('SQL P2 lowBMD remains an independent Boolean field',async()=>{
 await answer('lowBMD',true);await answer('tScoreAtOrBelowMinus2_5AnySite',false);await answer('veryHighFractureRisk',false);
 const facts=(await context()).clinician_facts;
 assert.equal(facts.lowBMD,true);assert.equal(facts.tScoreAtOrBelowMinus2_5AnySite,false);assert.equal(facts.veryHighFractureRisk,false);
});
test('SQL preserves retired numeric history when the first current confirmation is saved',async()=>{
 await db.exec(`update clinical_cases set clinician_facts='{"femoralNeckTscore":-3.1,"FRAX10YmajorOsteoporoticFractureRiskPercent":40}',pathway_answer_order='{}';`);
 await answer('tScoreAtOrBelowMinus2_5AnySite',false);
 const facts=(await context()).clinician_facts;
 assert.equal(facts.femoralNeckTscore,-3.1);assert.equal(facts.FRAX10YmajorOsteoporoticFractureRiskPercent,40);
 assert.equal(facts.tScoreAtOrBelowMinus2_5AnySite,false);assert.equal('veryHighFractureRisk' in facts,false);
});
test('SQL earlier answer edit invalidates new decisions but retains retired evidence',async()=>{
 await eligible();await answer('tScoreAtOrBelowMinus2_5AnySite',true);await answer('veryHighFractureRisk',true);
 await db.exec(`update clinical_cases set clinician_facts=clinician_facts || '{"femoralNeckTscore":-3.1,"FRAX10YmajorHipFractureRiskPercent":5}'::jsonb;`);
 await answer('minimalTraumaFracture','not_sure');
 const facts=(await context()).clinician_facts;
 assert.equal(facts.minimalTraumaFracture,'not_sure');assert.equal(facts.femoralNeckTscore,-3.1);assert.equal(facts.FRAX10YmajorHipFractureRiskPercent,5);
 assert.equal('tScoreAtOrBelowMinus2_5AnySite' in facts,false);assert.equal('veryHighFractureRisk' in facts,false);
});
test('SQL preserves predecessor-only renal decisions that do not rely on the changed BMD contract',async()=>{
 await eligible();const ctx=await context();
 await save(ctx,{contractVersion:'songyi-p1p2-20261008',trace:[{pathwayId:'PATHWAY1',nodeId:'RENAL_DYSFUNCTION',nodeType:'decision',matched:false}],actions:[{type:'referral',destination:'SPECIALIST'}]});
 await db.exec(`update clinical_cases set results_review='{"source":{"investigationRevision":1,"questionnaireRevision":1}}';`);
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'approved','Reviewed',ctx.pathway_revision,1,1]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'approved');
});
test('SQL care confirmation requires Boolean JSON and rejects the three old active fields',async()=>{
 const key='frailtyResidentialOrLimitedLifeExpectancy';
 for(const value of [6,7,5,'true','No','not_sure',null])await assert.rejects(answer(key,value));
 for(const old of ['liveInResidentialCare','clinicalFrailtyScore','lifeExpectancy'])await assert.rejects(answer(old,true),/historical/);
 await answer(key,true);assert.equal((await context()).clinician_facts[key],true);
 await answer(key,false);assert.equal((await context()).clinician_facts[key],false);
});
test('SQL missing care confirmation cannot complete a traversed care decision',async()=>{
 await eligible();
 const trace=[{pathwayId:'PATHWAY1',nodeId:'RESIDENTIAL_OR_FRAILTY',nodeType:'decision',matched:true}];
 await assert.rejects(save(await context(),{trace}),/Fresh clinician confirmation.*care/);
 await answer('frailtyResidentialOrLimitedLifeExpectancy',true);await save(await context(),{trace});
});
test('SQL first current care confirmation retains old component history without deriving it',async()=>{
 await db.exec(`update clinical_cases set clinician_facts='{"liveInResidentialCare":true,"clinicalFrailtyScore":7,"lifeExpectancy":5}',pathway_answer_order='{}';`);
 const old=(await context()).clinician_facts;
 assert.equal('frailtyResidentialOrLimitedLifeExpectancy' in old,false);
 await answer('frailtyResidentialOrLimitedLifeExpectancy',false);
 const facts=(await context()).clinician_facts;
 assert.equal(facts.frailtyResidentialOrLimitedLifeExpectancy,false);
 for(const key of ['liveInResidentialCare','clinicalFrailtyScore','lifeExpectancy'])assert.equal(facts[key],old[key]);
});
test('SQL answer invalidation preserves old care and BMD evidence while clearing current confirmations',async()=>{
 await eligible();await answer('frailtyResidentialOrLimitedLifeExpectancy',false);await answer('tScoreAtOrBelowMinus2_5AnySite',true);await answer('veryHighFractureRisk',true);
 await db.exec(`update clinical_cases set clinician_facts=clinician_facts || '{"liveInResidentialCare":true,"clinicalFrailtyScore":7,"lifeExpectancy":5,"hipTscore":-3.1}'::jsonb;`);
 await answer('minimalTraumaFracture','not_sure');const facts=(await context()).clinician_facts;
 assert.equal(facts.clinicalFrailtyScore,7);assert.equal(facts.lifeExpectancy,5);assert.equal(facts.liveInResidentialCare,true);assert.equal(facts.hipTscore,-3.1);
 for(const key of ['frailtyResidentialOrLimitedLifeExpectancy','tScoreAtOrBelowMinus2_5AnySite','veryHighFractureRisk'])assert.equal(key in facts,false);
});
test('SQL older care traversals need the new contract even with old residential or numeric evidence',async()=>{
 await eligible();await db.exec(`update clinical_cases set clinician_facts=clinician_facts || '{"liveInResidentialCare":true,"clinicalFrailtyScore":7,"lifeExpectancy":5}'::jsonb;`);
 const trace=[{pathwayId:'PATHWAY1',nodeId:'RESIDENTIAL_OR_FRAILTY',nodeType:'decision',matched:true}];
 for(const version of ['songyi-p1p2-20261008','songyi-p1p2-20261009-bmd'])await assert.rejects(save(await context(),{trace,contractVersion:version}),/old contract/);
});
test('SQL approval refuses older care evidence; Withhold remains available',async()=>{
 await eligible();const ctx=await context();await save(ctx,{actions:[{type:'referral',destination:'SPECIALIST'}]});
 await db.exec(`update clinical_cases set rule_evaluation=rule_evaluation || '{"contractVersion":"songyi-p1p2-20261009-bmd","trace":[{"pathwayId":"PATHWAY1","nodeId":"RESIDENTIAL_OR_FRAILTY","nodeType":"decision","matched":true}]}'::jsonb,results_review='{"source":{"investigationRevision":1,"questionnaireRevision":1}}';`);
 await assert.rejects(db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'approved','Reviewed',ctx.pathway_revision,1,1]),/Current P1 eligibility/);
 await db.query('select public.review_pathway_evaluation($1,$2,$3,$4,$5,$6)',[id,'withheld','Fresh care confirmation required',ctx.pathway_revision,1,1]);
 assert.equal((await db.query('select decision from clinician_decisions')).rows[0].decision,'withheld');
});
