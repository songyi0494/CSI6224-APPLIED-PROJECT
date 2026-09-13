import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { evaluateAssessment } from '../supabase/functions/evaluate_pathway_1/engine.ts';
const { PGlite }=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const patient='10000000-0000-4000-8000-000000000001',other='10000000-0000-4000-8000-000000000002';
const clinician='20000000-0000-4000-8000-000000000001',pending='20000000-0000-4000-8000-000000000002';
const rejected='20000000-0000-4000-8000-000000000003',unassigned='20000000-0000-4000-8000-000000000004';
const admin='30000000-0000-4000-8000-000000000001',id='40000000-0000-4000-8000-000000000001';
const input={osteoporosisTreatmentStatus:false,age:71,sex:'female',postmenopausal:true,yearSincePostmenopausal:20,minimalTraumaFracture:true,fractureSite:'vertebral',eGFR:54,liveInResidentialCare:false,clinicalFrailtyScore:4,lifeExpectancy:10,knownPoorMedicationAdherence:false,cognitiveImpairment:false,testAvailable:true,testWithinLast2Years:true,'T-score':-3.5,hipVertebralOrMultipleFracturesInLast24M:true,highRisk:true};
let db;
async function as(user,role='authenticated') { await db.exec(`reset role; select set_config('request.jwt.claim.sub','${user}',false); set role ${role};`); }
async function value(sql,params=[]) {return (await db.query(sql,params)).rows[0]?.result;}
async function save(caseId=id,rev=0,facts=input) {return value('select public.save_assessment($1,$2,$3) as result',[caseId,rev,JSON.stringify(facts)]);}
async function get(caseId=id) {return value('select public.get_assessment($1) as result',[caseId]);}
async function complete(caseId=id,rev=1,facts=input) {await as(patient,'service_role');await db.query('select public.complete_evaluation($1,$2,$3,$4)',[patient,caseId,rev,JSON.stringify(evaluateAssessment(facts))]);}
async function decide(a,action,notes='Reviewed the assessment.') {return db.query('select public.record_decision($1,$2,$3,$4,$5,$6)',[a.id,a.revision,a.updated_at,a.evaluation_id,action,notes]);}

test('PostgreSQL migration, RLS, revisions and persistent publication',async t=>{
  const directory=mkdtempSync(join(tmpdir(),'osteocare-db-'));
  db=new PGlite(directory);
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      grant usage on schema public,auth to anon,authenticated,service_role; grant execute on function auth.uid() to public;`);
    await db.exec(readFileSync(new URL('../supabase/migrations/202609130001_core_workflow.sql',import.meta.url),'utf8'));
    for(const [uid,role,email] of [[patient,'patient','a@test.local'],[other,'patient','b@test.local'],[clinician,'clinician','c@test.local'],[pending,'clinician','p@test.local'],[rejected,'clinician','r@test.local'],[unassigned,'clinician','u@test.local'],[admin,'patient','admin@test.local']]){
      await db.query('insert into auth.users values($1,$2,$3)',[uid,email,JSON.stringify({full_name:uid,role,approval_status:'approved'})]);
    }
    await db.query("update public.profiles set role='admin' where id=$1",[admin]);
    await t.test('signup metadata cannot approve a clinician or create an admin',async()=>{
      assert.equal((await db.query('select approval_status from public.profiles where id=$1',[pending])).rows[0].approval_status,'pending');
      await assert.rejects(db.query('insert into auth.users values($1,$2,$3)',['99999999-0000-4000-8000-000000000001','x@test.local',JSON.stringify({full_name:'X',role:'admin'})]));
    });
    await t.test('only admin can approve or reject clinicians',async()=>{
      await as(patient);await assert.rejects(db.query("select public.review_clinician($1,'approved')",[pending]));
      await as(pending);await assert.rejects(db.query("select public.review_clinician($1,'approved')",[pending]));
      await as(admin);await db.query("select public.review_clinician($1,'approved')",[clinician]);await db.query("select public.review_clinician($1,'approved')",[unassigned]);await db.query("select public.review_clinician($1,'rejected')",[rejected]);
      await as(clinician);await assert.rejects(db.query("select public.review_clinician($1,'approved')",[pending]));
    });
    await t.test('patient cannot alter profile role or approval',async()=>{
      await as(patient);await assert.rejects(db.query("update public.profiles set role='admin' where id=$1",[patient]));
      await as(pending);await assert.rejects(db.query("update public.profiles set approval_status='approved' where id=$1",[pending]));
    });
    await t.test('owned draft and retry use the same assessment/revision',async()=>{
      await as(patient);await assert.rejects(save(id,null));const a=await save();assert.equal(a.patient_id,patient);assert.equal(a.revision,1);assert.equal((await save()).revision,1);
      assert.equal((await db.query('select * from public.assessments')).rows.length,1);
    });
    await t.test('other patient cannot read or modify the assessment',async()=>{
      await as(other);assert.equal((await db.query('select * from public.assessments')).rows.length,0);await assert.rejects(get());await assert.rejects(save(id,1));
    });
    await t.test('patient cannot fabricate an evaluation or clinician decision',async()=>{
      await as(patient);await assert.rejects(db.query('select public.complete_evaluation($1,$2,1,$3)',[patient,id,JSON.stringify(evaluateAssessment(input))]));
      await assert.rejects(db.query("insert into public.evaluations(assessment_id,revision,result,rule_version) values($1,1,'{}','fake')",[id]));
      await assert.rejects(db.query('select public.record_decision($1,1,now(),$2,$3,$4)',[id,id,'approved','fake']));
    });
    await t.test('trusted engine result persists; raw evaluation remains hidden from patient',async()=>{
      await complete();await complete();await as(patient);const a=await get();assert.equal(a.status,'awaiting_review');assert.equal(a.evaluation,undefined);assert.equal(a.approved_actions,undefined);assert.equal((await db.query('select * from public.evaluations')).rows.length,0);
    });
    await t.test('pending and rejected clinicians cannot read the review queue',async()=>{
      for(const u of [pending,rejected]){await as(u);assert.equal((await db.query('select * from public.assessments')).rows.length,0);assert.deepEqual(await value('select public.list_assessments() as result'),[]);await assert.rejects(get());}
    });
    await t.test('approved clinician sees the stored input and matched trace',async()=>{
      await as(clinician);const a=await get();assert.equal(a.pathway,'PATHWAY1');assert.equal(a.evaluation.trace.at(-1).rule_id,'RECENT_MAJOR_FRACTURES');assert.equal(a.facts['T-score'],-3.5);
      await decide(a,'needs_more_information','Please confirm the bone density result.');
    });
    await t.test('request notes reach patient; resubmission revises the same assessment',async()=>{
      await as(patient);const a=await get();assert.equal(a.decision_notes,'Please confirm the bone density result.');const revised=await save(id,1,{...input,'T-score':-3.4});assert.equal(revised.id,id);assert.equal(revised.revision,2);assert.equal(revised.status,'draft');
      await complete(id,2,{...input,'T-score':-3.4});
    });
    await t.test('assignment restricts unrelated approved clinicians',async()=>{await as(unassigned);await assert.rejects(get());});
    let approved;
    await t.test('approval is revision-bound and rejects stale/repeated decisions',async()=>{
      await as(clinician);approved=await get();await assert.rejects(db.query('select public.record_decision($1,$2,null,$3,$4,$5)',[approved.id,approved.revision,approved.evaluation_id,'approved','Missing version token']));
      await decide(approved,'approved');await assert.rejects(decide(approved,'withheld'));
      await as(patient);const a=await get();assert.equal(a.status,'approved');assert.ok(a.approved_actions.length);assert.equal(a.evaluation,undefined);await assert.rejects(save(id,2,{...input,eGFR:55}));
    });
    await t.test('approval survives closing/reopening the database',async()=>{
      await db.close();db=new PGlite(directory);await as(patient);assert.equal((await get()).status,'approved');assert.ok((await get()).approved_actions.length);
      await as(other);await assert.rejects(get());
    });
    await t.test('Pathway 2 is retained for manual review and cannot be approved',async()=>{
      const caseId='40000000-0000-4000-8000-000000000002';await as(patient);await save(caseId,0,{...input,osteoporosisTreatmentStatus:true});await complete(caseId,1,{...input,osteoporosisTreatmentStatus:true});await as(clinician);const a=await get(caseId);assert.equal(a.status,'manual_review');assert.equal(a.pathway,'PATHWAY2');await assert.rejects(decide(a,'approved'));await decide(a,'follow_up_required','Arrange a treatment history review.');await as(patient);assert.equal((await get(caseId)).decision_notes,'Arrange a treatment history review.');
    });
    await t.test('withhold retains notes and does not publish a result',async()=>{
      const caseId='40000000-0000-4000-8000-000000000003';await as(patient);await save(caseId);await complete(caseId);await as(clinician);await decide(await get(caseId),'withheld','Further clinician assessment is needed.');await as(patient);const a=await get(caseId);assert.equal(a.status,'withheld');assert.equal(a.approved_actions,undefined);assert.equal(a.decision_notes,'Further clinician assessment is needed.');
    });
    await t.test('anonymous callers cannot read profiles or invoke workflow functions',async()=>{await as('','anon');await assert.rejects(db.query('select * from public.profiles'));await assert.rejects(get());});
  } finally {await db.close();rmSync(directory,{recursive:true,force:true});}
});
