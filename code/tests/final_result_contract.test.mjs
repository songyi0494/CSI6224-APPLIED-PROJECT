import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../supabase/migrations/202609290002_final_result_contract.sql',
  import.meta.url,
);
const sql = await readFile(migrationUrl, 'utf8');

test('clinician detail returns the persisted terminal evaluation', () => {
  assert.match(sql, /'rule_evaluation', v_case\.rule_evaluation/);
  assert.match(sql, /'pathway_revision', v_case\.pathway_revision/);
  assert.match(sql, /'questionnaire_response_id', v_case\.questionnaire_response_id/);
});

test('Common Advice reuses the existing generator for evaluated cases', () => {
  assert.match(sql, /create or replace function public\.review_clinical_case_results/);
  assert.match(sql, /v_case\.status not in \('in_progress', 'evaluated'\)/);
  assert.match(sql, /'vitaminD'/);
  assert.match(sql, /'calcium'/);
  assert.match(sql, /'protein'/);
  assert.match(sql, /'lifestyleAdvice'/);
});

test('final decision accepts only Approve and Withhold product actions', () => {
  assert.match(sql, /p_decision not in \('approved', 'withheld'\)/);
  assert.match(sql, /approved_actions_snapshot/);
  assert.match(sql, /approved_common_advice_snapshot/);
  assert.match(sql, /released_at/);
});

test('patient projection is approved-only and omits raw clinical internals', () => {
  const projectionStart = sql.indexOf(
    'create or replace function public.get_patient_approved_results',
  );
  assert.notEqual(projectionStart, -1);
  const projection = sql.slice(projectionStart);
  assert.match(projection, /d\.decision = 'approved'/);
  assert.match(projection, /d\.released_at is not null/);
  assert.doesNotMatch(projection, /rule_evaluation/);
  assert.doesNotMatch(projection, /clinician_facts/);
  assert.doesNotMatch(projection, /results_review/);
});
