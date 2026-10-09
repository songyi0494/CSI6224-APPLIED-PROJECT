import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {before, beforeEach, after, test} from 'node:test';
import {evaluateCasePathway,contractVersion} from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
const {PGlite}=await import(process.env.SONGYI_PGLITE_MODULE ?? '@electric-sql/pglite');
const id='00000000-0000-0000-0000-000000000001';
const patient='00000000-0000-0000-0000-000000000002';
const clinician='00000000-0000-0000-0000-000000000003';
const response='00000000-0000-0000-0000-000000000004';
let db;
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql as $$select '${clinician}'::uuid$$;
 create function public.is_approved_clinician() returns boolean language sql as $$select true$$;
 create table profiles(id uuid primary key,date_of_birth date);
 create table questionnaire_responses(id uuid primary key,answers jsonb,revision integer,status text);
 create table clinical_cases(id uuid primary key,patient_id uuid,assigned_clinician_id uuid,questionnaire_response_id uuid,status text,pathway_revision integer,rule_evaluation jsonb,results_review jsonb,updated_at timestamptz);
 create table investigations(case_id uuid primary key,revision integer,vitamin_d_level numeric,ionised_calcium numeric,total_calcium numeric,body_weight_kg numeric);
 create function public.phase3ca_investigations_complete(p uuid) returns boolean language sql as $$select exists(select 1 from public.investigations where case_id=p and revision>0 and vitamin_d_level is not null and ionised_calcium is not null and body_weight_kg is not null)$$;`);
 await db.exec(readFileSync(new URL('../supabase/migrations/20261001001927_fix_review_clinical_case_results.sql',import.meta.url),'utf8'));
 const release=readFileSync(new URL('../supabase/migrations/20260929101703_final_result_contract.sql',import.meta.url),'utf8');
 const start=release.indexOf('create or replace function public.phase3_final_common_advice(');
 await db.exec(release.slice(start,release.indexOf('$$;',start)+3));
});
beforeEach(async()=>{
 await db.exec(`truncate profiles,questionnaire_responses,clinical_cases,investigations;
 insert into profiles values('${patient}',current_date-interval '71 years');
 insert into questionnaire_responses values('${response}','{"smoking":"No","alcohol":"No","dietaryDairyServings":5}',1,'submitted');
 insert into investigations values('${id}',1,50,1.2,null,70);
 insert into clinical_cases values('${id}','${patient}','${clinician}','${response}','evaluated',1,'{"status":"complete","pathwayRevision":1,"investigationRevision":1}',null,now());`);
});
after(async()=>{await db?.close();});
const review=async()=> (await db.query('select public.review_clinical_case_results($1,1,1) as review',[id])).rows[0].review;
async function setAnswers(smoking,alcohol,dairy) {await db.query('update questionnaire_responses set answers=$1::jsonb',[JSON.stringify({smoking,alcohol,dietaryDairyServings:dairy})]);}
test('A authoritative smoking Yes / alcohol No yields only smoking advice',async()=>{await setAnswers('Yes','No',5);const r=await review();assert.ok(r.lifestyleAdvice.includes('Ceasing smoking'));assert.ok(!r.lifestyleAdvice.includes('Reducing alcohol intake'));});
test('B smoking No / alcohol Yes yields only alcohol advice',async()=>{await setAnswers('No','Yes',5);const r=await review();assert.ok(!r.lifestyleAdvice.includes('Ceasing smoking'));assert.ok(r.lifestyleAdvice.includes('Reducing alcohol intake'));});
test('C dairy 2 triggers established calcium advice',async()=>{await setAnswers('No','No',2);const r=await review();assert.equal(r.calcium.supplementRequired,true);assert.equal(r.calcium.recommendation,'Calcium supplement 600 mg daily');});
test('D dairy 5 / server hypocalcaemia false produces no calcium recommendation',async()=>{const r=await review();assert.equal(r.calcium.hypocalcaemia,false);assert.equal(r.calcium.recommendation,null);});
test('E vitamin D 50 produces the existing maintenance advice',async()=>{const r=await review();assert.equal(r.vitaminD.recommendation,'Cholecalciferol 25 microg daily ongoing');assert.equal(r.vitaminD.recheckBeforeTreatment,false);});
test('F vitamin D 35 produces existing loading then maintenance course',async()=>{await db.exec('update investigations set vitamin_d_level=35');const r=await review();assert.equal(r.vitaminD.recommendation,'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily');assert.equal(r.vitaminD.recheckBeforeTreatment,false);});
test('G vitamin D 20 requires explicit recheck before treatment',async()=>{await db.exec('update investigations set vitamin_d_level=20');const r=await review();assert.equal(r.vitaminD.recheckBeforeTreatment,true);assert.equal(r.vitaminD.recommendation,'Cholecalciferol 75 microg/day for 6 weeks, then 25 microg daily');});
test('calcium authority gap is reproducible and remains in backend evidence',async()=>{await db.exec('update investigations set ionised_calcium=1.08');const r=await review();assert.equal(r.calcium.hypocalcaemia,true);assert.equal(r.calcium.supplementRequired,true);/* Evidence of current implementation, not clinical validation of 1.12. */});
test('current source revisions remain protected',async()=>{await db.exec('update questionnaire_responses set revision=2');await assert.rejects(review(),/Questionnaire response changed/);});
test('patient-release recheck contract gap is confirmed without changing release authority',async()=>{
 await db.exec('update investigations set vitamin_d_level=20');const r=await review();assert.equal(r.vitaminD.recheckBeforeTreatment,true);
 const final=(await db.query('select public.phase3_final_common_advice($1::jsonb) as advice',[JSON.stringify(r)])).rows[0].advice;
 assert.ok(!final.some(text=>/recheck/i.test(text))); // Explicit unresolved gap, not desired acceptance behavior.
});
test('P1/P2 UI fixtures match the unchanged authoritative evaluator exactly',()=>{
 const fixtures=JSON.parse(readFileSync(new URL('../app/test/fixtures/final_ui_evaluations.json',import.meta.url)));
 const docs=Object.fromEntries([1,2].map(n=>[`PATHWAY${n}`,JSON.parse(readFileSync(new URL(`../supabase/functions/evaluate_pathway/rules/pathway_${n}.json`,import.meta.url)))]));
 for(const f of Object.values(fixtures)) assert.deepEqual(f.evaluation,{...evaluateCasePathway(docs,f.facts,f.eligibility),contractVersion,pathwayRevision:1,investigationRevision:1});
});
test('UI advice fixture matches the unchanged SQL advice producer',async()=>{
 await setAnswers('Yes','No',2);const r=await review();
 // Normalize only time/actor provenance in the synthetic visual fixture.
 r.source.generatedAt='2026-10-09T01:00:00Z';
 const url=new URL('../app/test/fixtures/final_ui_advice.json',import.meta.url);
 if(process.env.SONGYI_UI_GENERATE_FIXTURE==='true') writeFileSync(url,JSON.stringify(r,null,2));
 const fixture=JSON.parse(readFileSync(url));
 // AgeAsOf is generated from PostgreSQL's current_date; it is not UI authority.
 fixture.protein.ageAsOf=r.protein.ageAsOf;
 assert.deepEqual(fixture,r);
});
