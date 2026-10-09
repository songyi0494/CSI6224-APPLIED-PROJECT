import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {evaluateCasePathway} from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
import {factSchema} from '../supabase/functions/evaluate_pathway/engine/factSchema.ts';
const docs=Object.fromEntries([1,2].map(n=>[`PATHWAY${n}`,JSON.parse(readFileSync(new URL(`../supabase/functions/evaluate_pathway/rules/pathway_${n}.json`,import.meta.url)))]));
const ctx={sex:'female',age:71,postmenopausal:true,questionnaireRevision:1,ageAsOf:'2026-10-09'};
const key='frailtyResidentialOrLimitedLifeExpectancy';
const helper='Lives in residential care, Clinical Frailty Scale score 6 or higher, or life expectancy less than 7 years.';
const base={minimalTraumaFracture:'yes',fractureSite:'hip',eGFR:true,osteoporosisTreatmentStatus:false};
const run=(facts={})=>evaluateCasePathway(docs,{...base,...facts},ctx);
for(const reason of ['A residential care','B Clinical Frailty Scale 6 or higher','C life expectancy less than 7 years']) {
 test(`${reason}: clinician Yes reaches the same existing branch with no raw values`,()=>{
  // The clinician confirms the whole OR condition; the reason is test context,
  // not a raw component sent to or calculated by the rule engine.
  const facts={[key]:true};const r=run(facts);
  assert.equal(r.status,'complete');assert.equal(r.trace.at(-1).nodeId,'LEAF_DENOSUMAB_GP');
  assert.deepEqual(r.actions,docs.PATHWAY1.nodes.LEAF_DENOSUMAB_GP.actions);
  assert.deepEqual(Object.keys(facts),[key]);
 });
}
test('D none present: confirmed No continues to adherence',()=>{
 const r=run({[key]:false});assert.equal(r.status,'question');assert.equal(r.nodeId,'ADHERENCE_CONCERN');
 assert.equal(r.trace.find(t=>t.nodeId==='RESIDENTIAL_OR_FRAILTY').matched,false);
});
test('E missing and null remain incomplete and request one Boolean',()=>{
 for(const facts of [{},{[key]:null}]) {
  const r=run(facts);assert.equal(r.status,'question');assert.deepEqual(r.requiredFacts,[key]);
  assert.equal(r.question,'Does the patient have any of these factors?');assert.equal(r.helperText,helper);
  assert.deepEqual(r.actions ?? [],[]);
 }
});
test('uncertain and numeric confirmation cannot mean No',()=>{
 for(const value of ['not_sure','No','true',6,7,5,0]) {
  const r=run({[key]:value});assert.equal(r.status,'error');assert.equal(r.error.code,'INVALID_FACT_VALUE');
 }
});
test('old true residential care, CFS 7 or life expectancy 5 do not create new authority',()=>{
 for(const history of [{liveInResidentialCare:true},{clinicalFrailtyScore:7},{lifeExpectancy:5},{liveInResidentialCare:true,clinicalFrailtyScore:7,lifeExpectancy:5}]) {
  assert.deepEqual(run(history).requiredFacts,[key]);
  assert.equal(run({...history,[key]:false}).nodeId,'ADHERENCE_CONCERN');
 }
});
test('old unknown or invalid component types cannot block fresh confirmation or supply it',()=>{
 const history={clinicalFrailtyScore:'Not sure',lifeExpectancy:'Unavailable',liveInResidentialCare:'Yes'};
 assert.deepEqual(run(history).requiredFacts,[key]);
 assert.equal(run({...history,[key]:true}).status,'complete');
});
test('there is one active care authority and no numeric P1 input rule mismatch',()=>{
 for(const old of ['liveInResidentialCare','clinicalFrailtyScore','lifeExpectancy']) {
  assert.equal(old in factSchema,false);assert.equal(docs.PATHWAY1.requiredFields.includes(old),false);
  assert.equal(JSON.stringify(Object.values(docs.PATHWAY1.nodes).map(n=>n.condition)).includes(old),false);
 }
 assert.deepEqual(docs.PATHWAY1.nodes.RESIDENTIAL_OR_FRAILTY.condition,{fact:key,operator:'equals',value:true});
 function check(condition) {
  if(!condition)return;
  if('fact' in condition) {assert.ok(factSchema[condition.fact]);assert.notEqual(factSchema[condition.fact].type,'number');}
  else for(const child of condition.any ?? condition.all ?? []) check(child);
 }
 for(const node of Object.values(docs.PATHWAY1.nodes))check(node.condition);
});
test('accepted early renal and P2 paths do not require the care decision until traversed',()=>{
 assert.equal(run({eGFR:false}).status,'complete');
 const p2=run({osteoporosisTreatmentStatus:true});assert.equal(p2.pathwayId,'PATHWAY2');assert.deepEqual(p2.requiredFacts,['antiresorptiveTreatmentStatus']);
 const redirect=run({osteoporosisTreatmentStatus:true,antiresorptiveTreatmentStatus:false});
 assert.equal(redirect.nodeId,'RESIDENTIAL_OR_FRAILTY');assert.deepEqual(redirect.requiredFacts,[key]);
});
