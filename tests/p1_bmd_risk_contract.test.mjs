import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {evaluateCasePathway} from '../supabase/functions/evaluate_pathway/engine/evaluateCasePathway.ts';
import {factSchema} from '../supabase/functions/evaluate_pathway/engine/factSchema.ts';
const docs=Object.fromEntries([1,2].map(n=>[`PATHWAY${n}`,JSON.parse(readFileSync(new URL(`../supabase/functions/evaluate_pathway/rules/pathway_${n}.json`,import.meta.url)))]));
const context={sex:'female',age:71,postmenopausal:true,questionnaireRevision:1,ageAsOf:'2026-10-09'};
const base={minimalTraumaFracture:'yes',fractureSite:'hip',eGFR:true,osteoporosisTreatmentStatus:false,frailtyResidentialOrLimitedLifeExpectancy:false,adherenceConcern:false,testAvailability:true};
const run=(facts={})=>evaluateCasePathway(docs,{...base,...facts},context);
const retired=['femoralNeckTscore','hipTscore','lumbarSpineTscore','recentFractureWithin2Y','historyOf2orMoreFractures','clinicalRiskFactors','FRAX10YmajorOsteoporoticFractureRiskPercent','FRAX10YmajorHipFractureRiskPercent'];

test('A: P1 T-score Yes follows threshold-met branch',()=>{
 const r=run({tScoreAtOrBelowMinus2_5AnySite:true});
 assert.equal(r.status,'question');assert.equal(r.nodeId,'RECENT_MAJOR_FRACTURES');
 assert.equal(r.trace.find(t=>t.nodeId==='T_SCORE_CHECK').matched,true);
});
test('B: P1 T-score No follows original threshold-not-met branch',()=>{
 const r=run({tScoreAtOrBelowMinus2_5AnySite:false});
 assert.equal(r.status,'complete');assert.equal(r.trace.at(-1).nodeId,'LEAF_ZOLEDRONIC_OR_RISEDRONATE_OR_DENOSUMAB_GP');
 assert.equal(r.trace.some(t=>t.nodeId==='HIGH_RISK_CHECK'),false);
});
test('C: missing or null T-score requests confirmation',()=>{
 for(const facts of [{},{tScoreAtOrBelowMinus2_5AnySite:null}]) {
  const r=run(facts);assert.equal(r.status,'question');assert.deepEqual(r.requiredFacts,['tScoreAtOrBelowMinus2_5AnySite']);
  assert.equal(r.question,'Is the T-score -2.5 or lower at any of these sites?');
  assert.equal(r.helperText,'Femoral neck, hip, or lumbar spine.');
 }
});
const afterBmd={tScoreAtOrBelowMinus2_5AnySite:true,hipVertebralOrMultipleFracturesInLast24M:false};
test('D: very-high-risk Yes follows existing privately funded referral',()=>{
 const r=run({...afterBmd,veryHighFractureRisk:true});
 assert.equal(r.status,'complete');assert.equal(r.trace.at(-1).nodeId,'LEAF_PRIVATELY_FUNDED_OSTEOANABOLIC_REFERRAL');
});
test('E: very-high-risk No follows existing standard branch',()=>{
 const r=run({...afterBmd,veryHighFractureRisk:false});
 assert.equal(r.status,'complete');assert.equal(r.trace.at(-1).nodeId,'LEAF_ZOLEDRONIC_OR_RISEDRONATE_OR_DENOSUMAB_GP');
});
test('F: missing or null very-high risk is not No and carries the full criterion',()=>{
 for(const facts of [{},{veryHighFractureRisk:null}]) {
  const r=run({...afterBmd,...facts});assert.equal(r.status,'question');assert.deepEqual(r.requiredFacts,['veryHighFractureRisk']);
  assert.equal(r.question,'Does the patient meet the very-high-fracture-risk criteria?');
  assert.equal(r.helperText,'T-score ≤ -3.0, plus at least one of: recent fracture within 2 years, two or more fractures, relevant clinical risk factors, FRAX major risk ≥30%, or FRAX hip risk ≥4.5%.');
 }
});
test('uncertain, strings and numeric values never become Boolean No',()=>{
 for(const key of ['tScoreAtOrBelowMinus2_5AnySite','veryHighFractureRisk']) for(const value of [-3.1,30,'true','No','not_sure']) {
  const r=run({...afterBmd,[key]:value});assert.equal(r.status,'error');assert.equal(r.error.code,'INVALID_FACT_VALUE');
 }
});
test('history is not authority even when old components appear to satisfy criteria',()=>{
 const old={femoralNeckTscore:-3.1,hipTscore:-1,lumbarSpineTscore:-1,recentFractureWithin2Y:true,historyOf2orMoreFractures:true,clinicalRiskFactors:true,FRAX10YmajorOsteoporoticFractureRiskPercent:35,FRAX10YmajorHipFractureRiskPercent:5};
 assert.deepEqual(run(old).requiredFacts,['tScoreAtOrBelowMinus2_5AnySite']);
 assert.deepEqual(run({...old,...afterBmd}).requiredFacts,['veryHighFractureRisk']);
 assert.equal(run({...old,...afterBmd,veryHighFractureRisk:false}).trace.at(-1).nodeId,'LEAF_ZOLEDRONIC_OR_RISEDRONATE_OR_DENOSUMAB_GP');
 assert.equal(old.femoralNeckTscore,-3.1);
});
test('obsolete fields have no schema, required-field or condition authority',()=>{
 const p1=docs.PATHWAY1;
 for(const key of retired) {
  assert.equal(key in factSchema,false);assert.equal(p1.requiredFields.includes(key),false);
  assert.equal(JSON.stringify(Object.values(p1.nodes).map(n=>n.condition)).includes(key),false);
 }
 assert.deepEqual(p1.nodes.T_SCORE_CHECK.condition,{fact:'tScoreAtOrBelowMinus2_5AnySite',operator:'equals',value:true});
 assert.deepEqual(p1.nodes.HIGH_RISK_CHECK.condition,{fact:'veryHighFractureRisk',operator:'equals',value:true});
});
test('existing earlier renal, treatment and recent-major-fracture branches do not require composite answers',()=>{
 assert.equal(run({eGFR:false}).status,'complete');
 assert.equal(run({frailtyResidentialOrLimitedLifeExpectancy:true}).status,'complete');
 assert.equal(run({tScoreAtOrBelowMinus2_5AnySite:true,hipVertebralOrMultipleFracturesInLast24M:true}).trace.at(-1).nodeId,'LEAF_OSTEOANABOLIC_REFERRAL');
});
test('G: P2 lowBMD remains strict below -3.0 and independent of both P1 facts',()=>{
 const p2=docs.PATHWAY2.nodes.CHECK_BMD;
 assert.equal(p2.question,'Does the patient have a BMD T-score below -3.0 at any site?');
 assert.deepEqual(p2.condition,{fact:'lowBMD',operator:'equals',value:true});
 const treatment={osteoporosisTreatmentStatus:true,antiresorptiveTreatmentStatus:true,antiresorptiveTreatmentOver12Months:true,adheredToTheTreatment:true,symptomaticFractureInLast12M:true,multipleFractures:true,priorMIorStroke:false,sequencingFromDenosumab:false};
 for(const p1Bool of [true,false]) {
  const r=run({...treatment,tScoreAtOrBelowMinus2_5AnySite:p1Bool,veryHighFractureRisk:p1Bool,lowBMD:false});
  assert.equal(r.trace.at(-1).nodeId,'LEAF_STANDARD_ANTIRESORPTIVE_OPTIONS');
  const yes=run({...treatment,tScoreAtOrBelowMinus2_5AnySite:p1Bool,veryHighFractureRisk:p1Bool,lowBMD:true});
  assert.equal(yes.trace.at(-1).nodeId,'LEAF_ROMOSOZUMAB_REFERRAL');
 }
 assert.deepEqual(run(treatment).requiredFacts,['lowBMD']);
});
