import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { evaluateAssessment, RULE_VERSION } from '../supabase/functions/evaluate_pathway_1/engine.ts';
export const sample={osteoporosisTreatmentStatus:false,age:71,sex:'female',postmenopausal:true,
  yearSincePostmenopausal:20,minimalTraumaFracture:true,fractureSite:'vertebral',eGFR:54,
  liveInResidentialCare:false,clinicalFrailtyScore:4,lifeExpectancy:10,
  knownPoorMedicationAdherence:false,cognitiveImpairment:false,testAvailable:true,
  testWithinLast2Years:true,'T-score':-3.5,vitaminDLevel:65,
  hipVertebralOrMultipleFracturesInLast24M:true,highRisk:true,historyOfMiOrStroke:false};
test('synthetic case matching existing fields reaches the existing recent-fracture rule deterministically',()=>{
  const a=evaluateAssessment(sample),b=evaluateAssessment({...sample});
  assert.deepEqual(a,b);assert.equal(a.rule_version,RULE_VERSION);assert.equal(a.pathway,'PATHWAY1');
  assert.equal(a.decision,'action_taken');assert.equal(a.trace.find(x=>x.rule_id==='RENAL_DYSFUNCTION').matched,false);
  assert.equal(a.trace.at(-1).rule_id,'RECENT_MAJOR_FRACTURES');assert.equal(a.trace.at(-1).matched,true);
  const doc=JSON.parse(readFileSync(new URL('../supabase/functions/evaluate_pathway_1/pathway_1.json',import.meta.url)));
  assert.deepEqual(a.actions,doc.rules.find(x=>x.id==='RECENT_MAJOR_FRACTURES').then);
});
test('previous treatment never invokes Pathway 1',()=>{
  const r=evaluateAssessment({...sample,osteoporosisTreatmentStatus:true});
  assert.equal(r.pathway,'PATHWAY2');assert.equal(r.decision,'not_integrated');assert.deepEqual(r.actions,[]);assert.deepEqual(r.trace,[]);
});
test('unknown treatment stays unknown',()=>{const r=evaluateAssessment({});assert.equal(r.pathway,null);assert.equal(r.decision,'needs_more_information');});
test('missing renal data does not bypass the safety condition',()=>{
  const r=evaluateAssessment({...sample,eGFR:null});assert.equal(r.decision,'needs_more_information');assert.deepEqual(r.missing_inputs,['eGFR']);assert.deepEqual(r.actions,[]);
});
test('missing exclusion input does not pass notIn',()=>{
  const r=evaluateAssessment({...sample,fractureSite:null});assert.equal(r.decision,'needs_more_information');assert.ok(r.missing_inputs.includes('fractureSite'));
});
test('matched stopping rule ends evaluation',()=>{const r=evaluateAssessment({...sample,eGFR:20});assert.equal(r.trace.at(-1).rule_id,'RENAL_DYSFUNCTION');assert.equal(r.actions[0].type,'referral');});
test('wrong boolean types require clarification',()=>{assert.equal(evaluateAssessment({...sample,postmenopausal:'true'}).decision,'needs_more_information');});
test('all rule ids are unique',()=>{
  const doc=JSON.parse(readFileSync(new URL('../supabase/functions/evaluate_pathway_1/pathway_1.json',import.meta.url)));assert.equal(new Set(doc.rules.map(x=>x.id)).size,doc.rules.length);
});
test('patient input cannot supply an evaluation or override the route',()=>{const r=evaluateAssessment({...sample,osteoporosisTreatmentStatus:true,pathway:'PATHWAY1',decision:'approved'});assert.equal(r.pathway,'PATHWAY2');assert.equal(r.decision,'not_integrated');});
test('t-score no branch does not require very high risk confirmation',()=>{
  const r=evaluateAssessment({...sample,'T-score':-2.4,hipVertebralOrMultipleFracturesInLast24M:false,highRisk:undefined});
  assert.equal(r.decision,'action_taken');assert.equal(r.trace.at(-1).rule_id,'T_SCORE');
  assert.equal(r.trace.at(-1).matched,true);assert.deepEqual(r.missing_inputs,[]);
});
test('recent major fracture branch does not require very high risk confirmation',()=>{
  const r=evaluateAssessment({...sample,'T-score':-3.5,hipVertebralOrMultipleFracturesInLast24M:true,highRisk:undefined});
  assert.equal(r.decision,'action_taken');assert.equal(r.trace.at(-1).rule_id,'RECENT_MAJOR_FRACTURES');
  assert.equal(r.trace.at(-1).matched,true);assert.deepEqual(r.missing_inputs,[]);
});
test('clinician-confirmed very high risk reaches specialist branch',()=>{
  const r=evaluateAssessment({...sample,'T-score':-3.5,hipVertebralOrMultipleFracturesInLast24M:false,highRisk:true});
  assert.equal(r.decision,'action_taken');assert.equal(r.trace.at(-1).rule_id,'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE');
  assert.equal(r.trace.at(-1).matched,true);assert.equal(r.actions[0].type,'consideration');
});
test('clinician-denied very high risk reaches standard options branch',()=>{
  const r=evaluateAssessment({...sample,'T-score':-3.5,hipVertebralOrMultipleFracturesInLast24M:false,highRisk:false});
  assert.equal(r.decision,'action_taken');assert.equal(r.trace.at(-1).rule_id,'STANDARD_OPTIONS_WITHOUT_RECENT_MAJOR_FRACTURE');
  assert.equal(r.trace.at(-1).matched,true);assert.equal(r.actions[0].type,'treatmentOptions');
});
test('missing very high risk confirmation does not default to false',()=>{
  const r=evaluateAssessment({...sample,'T-score':-3.5,hipVertebralOrMultipleFracturesInLast24M:false,highRisk:undefined});
  assert.equal(r.decision,'needs_more_information');assert.deepEqual(r.missing_inputs,['highRisk']);
  assert.deepEqual(r.actions,[]);assert.equal(r.trace.at(-1).rule_id,'HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE');
  assert.equal(r.trace.at(-1).matched,null);assert.match(r.trace.at(-1).reason,/clinician confirmation/);
});
