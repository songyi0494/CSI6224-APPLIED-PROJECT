import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { evaluateCasePathway, demographicEligibility } from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
import { evaluateDecisionTree } from '../supabase/functions/evaluate_pathway/engine/evaluateDecisionTree.ts';
import { validateFacts } from '../supabase/functions/evaluate_pathway/engine/validateFacts.ts';
import { factSchema } from '../supabase/functions/evaluate_pathway/engine/factSchema.ts';
const rules = new URL('../supabase/functions/evaluate_pathway/rules/', import.meta.url);
const docs = Object.fromEntries([1,2].map(n => [`PATHWAY${n}`, JSON.parse(readFileSync(new URL(`pathway_${n}.json`, rules)))]));
const female = {sex:'female', age:71, postmenopausal:true, questionnaireRevision:1, ageAsOf:'2026-10-08'};
const eligible = {minimalTraumaFracture:'yes', fractureSite:'hip'};
const evaluate = (facts={}, context=female) => evaluateCasePathway(docs, facts, context);

test('Boolean eGFR true continues after eligibility; false selects specialist',()=>{
  const yes=evaluate({...eligible,eGFR:true});
  assert.equal(yes.status,'question'); assert.equal(yes.nodeId,'ON_OSTEOPOROSIS_TREATMENT');
  const no=evaluate({...eligible,eGFR:false});
  assert.equal(no.status,'complete'); assert.equal(no.trace.at(-1).nodeId,'LEAF_RENAL_REFERRAL');
});
test('active schema rejects raw eGFR numbers; historical value requests reconfirmation',()=>{
  for(const raw of [29,30,45,60]) {
    assert.equal(validateFacts({eGFR:raw},factSchema).valid,false);
    const r=evaluate({...eligible,eGFR:raw});
    assert.equal(r.status,'question');assert.equal(r.nodeId,'RENAL_DYSFUNCTION');
  }
  assert.equal(validateFacts({eGFR:true},factSchema).valid,true);
  assert.equal(validateFacts({eGFR:false},factSchema).valid,true);
});
test('P1 starts at demographic eligibility, then structured fracture question',()=>{
  const r=evaluate(); assert.equal(r.nodeId,'MINIMAL_TRAUMA_KNOWN');
  assert.deepEqual(r.requiredFacts,['minimalTraumaFracture']);
  assert.equal(r.trace[0].nodeId,'P1_DEMOGRAPHIC_ELIGIBILITY');
});
test('minimal trauma No is not eligible and cannot complete',()=>{
  const r=evaluate({...eligible,minimalTraumaFracture:'no',eGFR:false});
  assert.equal(r.status,'error');assert.equal(r.error.code,'ELIGIBILITY_NOT_MET');assert.deepEqual(r.actions,[]);
});
test('minimal trauma missing and Not sure never become No',()=>{
  const missing=evaluate({fractureSite:'hip',eGFR:false});
  assert.equal(missing.status,'question');
  const unsure=evaluate({...eligible,minimalTraumaFracture:'not_sure',eGFR:false});
  assert.equal(unsure.status,'error');assert.equal(unsure.error.code,'ELIGIBILITY_INFORMATION_REQUIRED');
});
for(const site of ['hand','foot','face','ankle']) test(`excluded ${site} cannot complete`,()=>{
  const r=evaluate({...eligible,fractureSite:site,eGFR:false});
  assert.equal(r.status,'error');assert.equal(r.error.code,'ELIGIBILITY_NOT_MET');
});
for(const site of ['hip','vertebral','leg']) test(`eligible ${site} reaches eGFR`,()=>{
  const r=evaluate({...eligible,fractureSite:site});assert.equal(r.status,'question');assert.equal(r.nodeId,'RENAL_DYSFUNCTION');
});
test('site missing, uncertain and combined values do not infer eligibility',()=>{
  assert.equal(evaluate({minimalTraumaFracture:'yes'}).nodeId,'FRACTURE_SITE_KNOWN');
  assert.equal(evaluate({...eligible,fractureSite:'not_sure'}).error.code,'ELIGIBILITY_INFORMATION_REQUIRED');
  assert.equal(evaluate({...eligible,fractureSite:'Leg, ankle or foot'}).error.code,'INVALID_FACT_VALUE');
});
for(const [name,ctx,expected] of [
  ['postmenopausal woman',female,'question'],
  ['man aged 51',{...female,sex:'male',age:51,postmenopausal:null},'question'],
  ['man aged 50',{...female,sex:'male',age:50,postmenopausal:null},'error'],
  ['man aged 49',{...female,sex:'male',age:49,postmenopausal:null},'error'],
  ['woman before menopause',{...female,postmenopausal:false},'error'],
]) test(`demographics ${name}`,()=>assert.equal(evaluate(eligible,ctx).status,expected));
test('missing source demographics stop without requesting duplicate clinician facts',()=>{
  for(const ctx of [null,{...female,sex:null},{...female,postmenopausal:null},{...female,sex:'male',age:null}]) {
    const r=evaluate({...eligible,eGFR:false},ctx);assert.equal(r.status,'error');assert.equal(r.error.code,'ELIGIBILITY_INFORMATION_REQUIRED');
  }
  assert.equal(demographicEligibility({...female,sex:'male',age:51,postmenopausal:null}),true);
});
test('clinician-supplied demographic flag cannot override protected sources',()=>{
  const r=evaluate({...eligible,p1DemographicEligible:true},{...female,postmenopausal:false});
  assert.equal(r.status,'error');assert.equal(r.error.code,'ELIGIBILITY_NOT_MET');
});
test('free-text patient mechanism does not create structured confirmation',()=>{
  const r=evaluate({fractureCircumstance:'Fall from standing height',fractureSite:'hip'});
  assert.equal(r.status,'question');assert.deepEqual(r.requiredFacts,['minimalTraumaFracture']);
});
test('exactly 12 months is No; more than 12 months is Yes',()=>{
  // The clinician confirms this strict threshold; raw duration is not a rule input.
  for(const [months,answer,expected] of [[12,false,'complete'],[12.01,true,'question'],[13,true,'question']]) {
    assert.equal(answer,months>12);
    const r=evaluate({...eligible,eGFR:true,osteoporosisTreatmentStatus:true,antiresorptiveTreatmentStatus:true,antiresorptiveTreatmentOver12Months:answer});
    assert.equal(r.status,expected);
    if(answer) assert.equal(r.nodeId,'TREATMENT_ADHERENCE');
    else assert.equal(r.trace.at(-1).nodeId,'LEAF_STANDARD_ANTIRESORPTIVE_OPTIONS');
  }
});
test('old >=12 duration fact requires a new confirmation; no reinterpretation',()=>{
  const r=evaluate({...eligible,eGFR:true,osteoporosisTreatmentStatus:true,antiresorptiveTreatmentStatus:true,antiresorptiveTreatmentDuration:true});
  assert.equal(r.status,'question');assert.deepEqual(r.requiredFacts,['antiresorptiveTreatmentOver12Months']);
  assert.match(r.question,/more than 12 months/);
});
test('P2 duration new fact rejects numeric or uncertain values',()=>{
  for(const value of [12,'yes','not_sure']) assert.equal(validateFacts({antiresorptiveTreatmentOver12Months:value},factSchema).valid,false);
});
test('unapproved remaining numeric contracts are unchanged and explicitly reproducible',()=>{
  for(const key of ['clinicalFrailtyScore','lifeExpectancy','femoralNeckTscore','hipTscore','lumbarSpineTscore','FRAX10YmajorOsteoporoticFractureRiskPercent','FRAX10YmajorHipFractureRiskPercent']) assert.equal(factSchema[key].type,'number');
  const p1=docs.PATHWAY1;
  assert.equal(p1.nodes.RESIDENTIAL_OR_FRAILTY.condition.any[1].value,true);
  assert.equal(p1.nodes.T_SCORE_CHECK.condition.any[0].value,true);
});
