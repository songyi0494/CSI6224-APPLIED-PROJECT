import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {evaluateCasePathway} from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
import {evaluateDecisionTree} from '../supabase/functions/evaluate_pathway/engine/evaluateDecisionTree.ts';
const docs=Object.fromEntries([1,2].map(n=>[`PATHWAY${n}`,JSON.parse(readFileSync(new URL(`../supabase/functions/evaluate_pathway/rules/pathway_${n}.json`,import.meta.url)))]));
const before={...docs,PATHWAY1:JSON.parse(readFileSync(new URL('../evidence/adherence-closure-20261009/before-pathway_1.json',import.meta.url)))};
const context={sex:'female',age:71,postmenopausal:true,questionnaireRevision:1,ageAsOf:'2026-10-09'};
const base={minimalTraumaFracture:'yes',fractureSite:'hip',eGFR:true,osteoporosisTreatmentStatus:false,frailtyResidentialOrLimitedLifeExpectancy:false};
const run=facts=>evaluateCasePathway(docs,{...base,...facts},context);
test('A concern Yes uses the unchanged concern action bundle',()=>{
 const r=run({adherenceConcern:true});assert.equal(r.status,'complete');
 const old=evaluateDecisionTree(before,{...base,p1DemographicEligible:true,knownPoorMedicationAdherence:true,cognitiveImpairment:false});
 assert.deepEqual(r.actions,old.actions);
 assert.equal(r.trace.find(t=>t.nodeId==='ADHERENCE_CONCERN').matched,true);
});
test('B concern No continues to the same BMD question',()=>{
 const r=run({adherenceConcern:false});assert.equal(r.nodeId,'DXA_SCAN_AVAILABILITY');
 assert.equal(r.trace.find(t=>t.nodeId==='ADHERENCE_CONCERN').matched,false);
});
for(const value of [undefined,null])test(`C missing/null ${value} requests fresh aggregate confirmation`,()=>{
 const r=run({adherenceConcern:value});assert.equal(r.status,'question');assert.equal(r.nodeId,'ADHERENCE_CONCERN');assert.deepEqual(r.requiredFacts,['adherenceConcern']);assert.deepEqual(r.actions ?? [],[]);
});
for(const history of [{knownPoorMedicationAdherence:true},{cognitiveImpairment:true},{knownPoorMedicationAdherence:false,cognitiveImpairment:false}])test(`D history ${JSON.stringify(history)} cannot supply authority`,()=>{
 const r=run(history);assert.equal(r.nodeId,'ADHERENCE_CONCERN');assert.deepEqual(r.requiredFacts,['adherenceConcern']);
 assert.equal(run({...history,adherenceConcern:false}).nodeId,'DXA_SCAN_AVAILABILITY');
});
test('invalid aggregate types are rejected and malformed history is ignored',()=>{
 for(const value of ['true',0,1,{},[]])assert.equal(run({adherenceConcern:value}).error.code,'INVALID_FACT_VALUE');
 assert.equal(run({knownPoorMedicationAdherence:'old',cognitiveImpairment:123}).nodeId,'ADHERENCE_CONCERN');
});
test('all four historical component combinations preserve their downstream actions under explicit confirmation',()=>{
 for(const [a,b] of [[true,true],[true,false],[false,true],[false,false]]){
  const rest={testAvailability:true,tScoreAtOrBelowMinus2_5AnySite:true,hipVertebralOrMultipleFracturesInLast24M:false,veryHighFractureRisk:false};
  const previous=evaluateDecisionTree(before,{...base,...rest,p1DemographicEligible:true,knownPoorMedicationAdherence:a,cognitiveImpairment:b});
  const current=run({...rest,adherenceConcern:a||b});assert.equal(current.status,previous.status);assert.deepEqual(current.actions,previous.actions);
 }
});
test('earlier renal and frailty leaves do not require untraversed adherence',()=>{
 assert.equal(run({eGFR:false}).status,'complete');assert.equal(run({frailtyResidentialOrLimitedLifeExpectancy:true}).status,'complete');
});
test('shared fracture eligibility remains unchanged',()=>{
 for(const site of ['hip','forearm'])assert.equal(run({fractureSite:site,eGFR:false}).status,'complete');
 for(const site of ['hand','ankle']) {
  const r=run({fractureSite:site});assert.equal(r.error.code,'ELIGIBILITY_NOT_MET');
  assert.equal(r.error.message,'Hand, foot, face, and ankle fractures are not eligible for the general minimal-trauma-fracture pathway.');
 }
 assert.equal(run({fractureSite:'not_sure'}).error.code,'ELIGIBILITY_INFORMATION_REQUIRED');
});
test('the aggregate change preserves every other P1 node and all leaf actions exactly',()=>{
 for(const [key,node] of Object.entries(before.PATHWAY1.nodes))if(key!=='ADHERENCE_CONCERN')assert.deepEqual(docs.PATHWAY1.nodes[key],node);
 const old=before.PATHWAY1.nodes.ADHERENCE_CONCERN,current=docs.PATHWAY1.nodes.ADHERENCE_CONCERN;
 assert.equal(current.yes,old.yes);assert.equal(current.no,old.no);
});
