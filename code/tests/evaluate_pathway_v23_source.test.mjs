import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const sourceUrl = new URL(
  '../supabase/functions/evaluate_pathway/index.ts',
  import.meta.url,
);
const source = await readFile(sourceUrl, 'utf8');

test('tracked evaluate_pathway source preserves the deployed v23 CORS contract', () => {
  assert.match(
    source,
    /"Access-Control-Allow-Headers":\s*\n\s*"authorization, x-client-info, apikey, content-type"/,
  );
  assert.match(source, /if \(req\.method === "OPTIONS"\)/);

  const sharedHeaderUses = source.match(/\.\.\.corsHeaders/g) ?? [];
  assert.equal(sharedHeaderUses.length, 3);
  assert.match(source, /headers: corsHeaders/);
});

test('tracked evaluate_pathway source preserves revision-bound persistence', () => {
  assert.match(source, /pathway_revision: number/);
  assert.match(source, /investigation_revision: number/);
  assert.match(source, /supabase\.rpc\("save_rule_evaluation"/);
  assert.match(
    source,
    /p_expected_pathway_revision:\s*clinicalCase\.pathway_revision/,
  );
  assert.match(
    source,
    /p_expected_investigation_revision:\s*clinicalCase\.investigation_revision/,
  );
});
