import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, beforeEach, after, test} from 'node:test';

// Local PostgreSQL only. No Supabase access or deployment.
const {PGlite} = await import(process.env.SONGYI_PGLITE_MODULE ?? '@electric-sql/pglite');
const patient='00000000-0000-0000-0000-000000000001';
const other='00000000-0000-0000-0000-000000000002';
const clinician='00000000-0000-0000-0000-000000000003';
const response='00000000-0000-0000-0000-000000000004';
const migration=name=>readFileSync(new URL(`../supabase/migrations/${name}.sql`,import.meta.url),'utf8');
const complete={sex:'Female',postmenopausal:'No',smoking:'No',alcohol:'No',dairyLessThan3Serves:true};
let db;
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table profiles(id uuid primary key,gender text,role text,full_name text);
 create function public.current_user_role() returns text language sql as $$select role from public.profiles where id=auth.uid()$$;
 create function public.is_approved_clinician() returns boolean language sql as $$select public.current_user_role()='clinician'$$;
 create function public.is_admin() returns boolean language sql as $$select public.current_user_role()='admin'$$;
 grant select on profiles to authenticated;
 grant usage on schema auth to authenticated;`);
 // Apply actual table/trigger/RLS migrations, not recreated submission logic.
 for(const name of ['20260919144034_create_clinical_cases','20260924004151_create_questionnaire_questions','20260924130400_create_questionnaire_responses','20260924131533_link_questionnaire_response_to_clinical_case']) await db.exec(migration(name));
 await db.exec(`alter table clinical_cases add column pathway_revision integer default 0, add column rule_evaluation jsonb;
 create table clinician_decisions(case_id uuid, clinician_id uuid,decision text,notes text,pathway_revision integer,investigation_revision integer,questionnaire_revision integer,released_at timestamptz);
 create table investigations(case_id uuid,revision integer);`);
 await db.exec(migration('20260930171552_clinician_decisions_for_completed_queue'));
 const current=migration('202610090004_dynamic_patient_advice_contract');
 const start=current.indexOf('create or replace function public.submit_questionnaire_response(');
 await db.exec(current.slice(start,current.indexOf('$$;',start)+3));
 await db.exec('grant select on clinical_cases to authenticated');
});
beforeEach(async()=>{
 await db.exec(`truncate profiles,questionnaire_responses,clinical_cases,clinician_decisions,investigations cascade;
 delete from questionnaire_questions where field_key is null;
 select set_config('test.uid','${patient}',false);
 insert into profiles values('${patient}','female','patient','Synthetic patient'),('${other}','male','patient','Other'),('${clinician}','male','clinician','Clinician');`);
 await db.query(`insert into questionnaire_responses(id,patient_id,answers) values($1,$2,$3::jsonb)`,[response,patient,JSON.stringify(complete)]);
});
after(async()=>{await db?.close();});
const submit=()=>db.query('select public.submit_questionnaire_response($1) as case_id',[response]);
const answers=value=>db.query('update questionnaire_responses set answers=$1::jsonb where id=$2',[JSON.stringify(value),response]);
const row=async()=> (await db.query('select * from questionnaire_responses where id=$1',[response])).rows[0];
const count=async()=> (await db.query('select count(*)::int as count from clinical_cases')).rows[0].count;
async function fails(pattern=/required questionnaire/){const before=await row();await assert.rejects(submit(),pattern);assert.equal((await row()).status,'draft');assert.deepEqual((await row()).answers,before.answers);assert.equal(await count(),0);}

test('A female completes only visible fields; profile supplies sex authority',async()=>{
 const value={...complete};delete value.sex;await answers(value);await submit();assert.equal((await row()).status,'submitted');assert.ok((await row()).submitted_at);
});
test('B male requires no menopause and ignores forged client sex',async()=>{
 await db.exec(`update profiles set gender='male' where id='${patient}'`);
 const value={...complete};delete value.postmenopausal;await answers(value);await submit();assert.equal(await count(),1);
});
for(const [name,key] of [['C','postmenopausal'],['D','smoking'],['E','alcohol'],['F','dairyLessThan3Serves']]) test(`${name} missing ${key} fails and preserves draft answers`,async()=>{const value={...complete};delete value[key];await answers(value);await fails();});
test('G hidden required historical and custom rows do not block or get rewritten',async()=>{
 const keys=['adultFractureHistory','fractureSite','fractureTiming','fractureCircumstance','osteoporosisMedicineHistory','osteoporosisMedicineName','osteoporosisMedicineTiming','medicineAdherenceDifficulty','fallsPast12Months','fearOfFalling','movementRehabilitationInterest','physicalActivity','myocardialInfarctionHistory','strokeHistory'];
 for(const key of keys) await db.query(`insert into questionnaire_questions(question_text,question_type,is_required,display_order,field_key) values('Historical','text',true,100,$1)`,[key]);
 await db.exec(`insert into questionnaire_questions(question_text,question_type,is_required,display_order) values('Custom','text',true,101);`);
 const before=(await db.query('select * from questionnaire_questions order by id')).rows;
 await submit();assert.equal(await count(),1);assert.deepEqual((await db.query('select * from questionnaire_questions order by id')).rows,before);
});
test('H successful submission creates one unassigned case visible through actual clinician queue RPC',async()=>{
 const id=(await submit()).rows[0].case_id;
 const c=(await db.query('select * from clinical_cases where id=$1',[id])).rows[0];
 assert.equal(c.patient_id,patient);assert.equal(c.questionnaire_response_id,response);assert.equal(c.status,'clinician_input_required');assert.equal(c.assigned_clinician_id,null);assert.ok(c.submitted_at);
 await db.exec(`select set_config('test.uid','${clinician}',false)`);
 const queue=(await db.query('select public.get_clinician_case_list() as queue')).rows[0].queue;
 assert.equal(queue.length,1);assert.equal(queue[0].id,id);
});
test('I repeat submission fails without duplicate case or timestamp/answer change',async()=>{
 await submit();const before=await row();await assert.rejects(submit(),/already been submitted/);assert.equal(await count(),1);assert.deepEqual(await row(),before);
});
test('J another patient cannot submit response',async()=>{
 await db.exec(`select set_config('test.uid','${other}',false)`);await fails(/only submit your own/);
});
test('authentication and patient role checks preserved',async()=>{
 await db.exec(`select set_config('test.uid','',false)`);await fails(/Authentication required/);
 await db.exec(`select set_config('test.uid','${clinician}',false)`);await fails(/Only patients/);
});
test('unknown response fails without case creation',async()=>{await assert.rejects(db.query('select public.submit_questionnaire_response($1)',[other]),/not found/);assert.equal(await count(),0);});
test('female cannot bypass menopause through forged male answer',async()=>{await answers({sex:'Male',smoking:'No',alcohol:'No',dairyLessThan3Serves:true});await fails();});
test('invalid or unavailable profile gender fails closed',async()=>{
 for(const gender of [null,'','not supplied']) {await db.query('update profiles set gender=$1 where id=$2',[gender,patient]);await fails(/Sex recorded at birth is unavailable/);}
});
test('recognized nonfemale profiles need no menopause',async()=>{
 for(const gender of ['another term','another_term','other']) {
  await db.query('update profiles set gender=$1 where id=$2',[gender,patient]);
  await answers({smoking:'No',alcohol:'No',dairyLessThan3Serves:false});await submit();
  // Fixture reset only; implementation never resets submitted history.
  await db.exec(`delete from clinical_cases;update questionnaire_responses set status='draft',submitted_at=null`);
 }
});
test('null and malformed visible answers fail closed without defaulting',async()=>{
 for(const key of ['smoking','alcohol','postmenopausal','dairyLessThan3Serves']) {
  await answers({...complete,[key]:null});await fails();
 }
 for(const key of ['smoking','alcohol','postmenopausal']) for(const value of ['',true,0,'Not sure',{},[]]) {
  await answers({...complete,[key]:value});await fails(/choices must be Yes or No/);
 }
 for(const value of [2,'2','',{},[]]) {await answers({...complete,dairyLessThan3Serves:value});await fails(/Dairy threshold/);}
});
test('failed validation can retry same draft after correction',async()=>{
 await answers({...complete,smoking:null});await fails();await answers(complete);await submit();assert.equal(await count(),1);
});
test('historical response answers remain untouched by submission',async()=>{
 const value={...complete,adultFractureHistory:'Yes',fractureTiming:'Historical text'};await answers(value);const before=await row();await submit();assert.deepEqual((await row()).answers,value);assert.equal((await row()).revision,before.revision);
});
test('actual response RLS permits only own draft answer updates',async()=>{
 await db.exec('set role authenticated');
 assert.equal((await db.query('select id from questionnaire_responses')).rows.length,1);
 await db.exec(`select set_config('test.uid','${other}',false)`);
 assert.equal((await db.query('select id from questionnaire_responses')).rows.length,0);
 assert.equal((await db.query(`update questionnaire_responses set answers='{}' returning id`)).rows.length,0);
 await db.exec('reset role');
 await db.exec(`select set_config('test.uid','${patient}',false)`);await submit();
 await db.exec('set role authenticated');
 assert.equal((await db.query(`update questionnaire_responses set answers='{}' returning id`)).rows.length,0);
 await db.exec('reset role');
});
test('old validator reproduces hidden required-row failure on same valid payload',async()=>{
 await db.exec(migration('20260930144357_fix_questionnaire_menopause_validation'));
 try {
  await db.exec(`insert into questionnaire_questions(question_text,question_type,is_required,display_order) values('Hidden','text',true,101)`);
  await fails(/All required questionnaire/);
 } finally {const current=migration('202610090004_dynamic_patient_advice_contract');const start=current.indexOf('create or replace function public.submit_questionnaire_response(');await db.exec(current.slice(start,current.indexOf('$$;',start)+3));}
 await submit();assert.equal(await count(),1);
});
