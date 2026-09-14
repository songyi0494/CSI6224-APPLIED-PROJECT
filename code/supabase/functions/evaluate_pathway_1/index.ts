import { createClient } from 'npm:@supabase/supabase-js@2';
import { evaluateAssessment } from './engine.ts';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

type Facts = Record<string, unknown>;

function clinicianFactsToEvaluatorFacts(clinicianFacts: Facts): Facts {
  const facts: Facts = {};
  const put = (key: string, value: unknown) => {
    if (value !== undefined && value !== null && value !== '') facts[key] = value;
  };
  put('eGFR', clinicianFacts.eGFR);
  put('clinicalFrailtyScore', clinicianFacts.clinicalFrailtyScore);
  put('lifeExpectancy', clinicianFacts.lifeExpectancy);
  put('knownPoorMedicationAdherence', clinicianFacts.knownPoorMedicationAdherence);
  put('cognitiveImpairment', clinicianFacts.cognitiveImpairment);
  if (typeof clinicianFacts.dxaImpractical === 'boolean') {
    facts.testAvailable = !clinicianFacts.dxaImpractical;
  }
  put('testWithinLast2Years', clinicianFacts.dxaDoneWithinPrevious2Years);
  put('T-score', clinicianFacts.tScoreValue);
  put('tScoreSite', clinicianFacts.tScoreSite);
  put(
    'hipVertebralOrMultipleFracturesInLast24M',
    clinicianFacts.hipVertebralOrMultipleFracturesInLast24M,
  );
  put('highRisk', clinicianFacts.clinicianConfirmedVeryHighRisk);
  put('yearSincePostmenopausal', clinicianFacts.yearsSinceMenopause);
  put('isRobustWoman', clinicianFacts.robustWoman);
  return facts;
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (req.method !== 'POST') return new Response('{}', { status: 405, headers });
  try {
    const authorization = req.headers.get('Authorization');
    if (!authorization) return new Response('{}', { status: 401, headers });
    const url = Deno.env.get('SUPABASE_URL')!;
    const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return new Response('{}', { status: 401, headers });
    const { assessment_id, revision } = await req.json();
    if (typeof assessment_id !== 'string' || !Number.isInteger(revision)) throw new Error('Invalid request');
    const { data: assessment, error: loadError } = await caller.rpc('get_assessment', { p_id: assessment_id });
    if (loadError || !assessment) return new Response('{}', { status: 403, headers });
    if (assessment.revision !== revision) return new Response('{}', { status: 409, headers });
    const { data: isClinician } = await caller.rpc('has_role', { required_role: 'clinician' });
    const patientCanEvaluate =
      assessment.patient_id === user.id &&
      assessment.status === 'draft' &&
      assessment.facts?.osteoporosisTreatmentStatus === true;
    const clinicianCanEvaluate = isClinician === true && assessment.status === 'clinician_input_required';
    if (!patientCanEvaluate && !clinicianCanEvaluate) return new Response('{}', { status: 403, headers });
    // evaluate persisted facts, never a client-supplied recommendation or pathway
    const result = evaluateAssessment({
      ...assessment.facts,
      ...clinicianFactsToEvaluatorFacts(assessment.clinician_facts ?? {}),
    });
    const backend = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const { error } = await backend.rpc('complete_evaluation', {
      p_actor: user.id, p_id: assessment_id, p_revision: revision, p_result: result,
    });
    if (error) return new Response(JSON.stringify({ error: 'Assessment could not be submitted. Reload and try again.' }), { status: 409, headers });
    // raw evaluations remain private until clinician approval
    return new Response(JSON.stringify({ assessment_id }), { headers });
  } catch {
    return new Response(JSON.stringify({ error: 'Assessment could not be submitted.' }), { status: 400, headers });
  }
});
