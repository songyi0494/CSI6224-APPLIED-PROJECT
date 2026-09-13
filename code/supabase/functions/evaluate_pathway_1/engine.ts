import document from './pathway_1.json' with { type: 'json' };
import type { Condition, PathwayDocument } from './types.ts';

export const RULE_VERSION = 'pathway1-2026-09-13.1';
const doc = document as PathwayDocument;
type Facts = Record<string, unknown>;
type Outcome = { matched: boolean | null; missing: string[] };
export type TraceEntry = {
  rule_id: string; matched: boolean | null; input: Facts; reason: string;
};
const labels: Record<string, string> = {
  ENTRY: 'Pathway entry conditions',
  MENOPAUSAL_HORMONAL_THERAPY: 'Menopause and treatment consideration',
  RENAL_DYSFUNCTION: 'Kidney function condition',
  ON_OSTEOPOROSIS_TREATMENT: 'Previous osteoporosis treatment',
  RESIDENTIAL_CARE_OR_SEVERE_FRAILTY_OR_SHORT_LIFE_EXPECTANCY: 'Care setting, frailty and life expectancy',
  ADHERENCE_CONCERN: 'Medication adherence or cognitive impairment',
  DXA_NOT_WITHIN_2YEARS: 'Bone density test timing',
  DXA_DISAVAILABLE: 'Bone density test availability',
  T_SCORE: 'Bone density condition',
  RECENT_MAJOR_FRACTURES: 'Recent major fractures',
  HIGH_RISK_WITHOUT_RECENT_MAJOR_FRACTURE: 'High risk without recent major fracture',
  STANDARD_OPTIONS_WITHOUT_RECENT_MAJOR_FRACTURE: 'No recent major fracture or high-risk flag',
};
function keys(c: Condition): string[] {
  return 'fact' in c ? [c.fact] : [...new Set((c.all ?? c.any ?? []).flatMap(keys))];
}
function condition(c: Condition, facts: Facts): Outcome {
  if (!('fact' in c)) {
    const outcomes = (c.all ?? c.any ?? []).map(x => condition(x, facts));
    if (c.all && outcomes.some(x => x.matched === false)) return { matched: false, missing: [] };
    if (c.any && outcomes.some(x => x.matched === true)) return { matched: true, missing: [] };
    const missing = [...new Set(outcomes.flatMap(x => x.missing))];
    return { matched: missing.length ? null : !!c.all, missing };
  }
  const a = facts[c.fact], b = c.value;
  if (a === undefined || a === null || a === '') return { matched: null, missing: [c.fact] };
  const numeric = ['lessThan', 'lessThanOrEqual', 'greaterThan', 'greaterThanOrEqual'].includes(c.operator);
  if ((numeric && (typeof a !== 'number' || !Number.isFinite(a))) ||
      (['equals', 'notEquals'].includes(c.operator) && typeof a !== typeof b) ||
      (['in', 'notIn'].includes(c.operator) && (!Array.isArray(b) || !b.every(v => typeof v === typeof a)))) {
    return { matched: null, missing: [c.fact] };
  }
  let matched: boolean;
  switch (c.operator) {
    case 'equals': matched = a === b; break;
    case 'notEquals': matched = a !== b; break;
    case 'lessThan': matched = (a as number) < (b as number); break;
    case 'lessThanOrEqual': matched = (a as number) <= (b as number); break;
    case 'greaterThan': matched = (a as number) > (b as number); break;
    case 'greaterThanOrEqual': matched = (a as number) >= (b as number); break;
    case 'in': matched = (b as unknown[]).includes(a); break;
    case 'notIn': matched = !(b as unknown[]).includes(a); break;
    default: throw new Error('Unsupported rule operator');
  }
  return { matched, missing: [] };
}

export function evaluateAssessment(facts: Facts) {
  const trace: TraceEntry[] = [];
  const actions: Record<string, unknown>[] = [];
  const finish = (pathway: string | null, decision: string, reason: string, missing: string[] = []) => ({
    pathway, decision, routing_reason: reason, rule_version: RULE_VERSION,
    actions, trace, missing_inputs: missing,
    warnings: ['Decision support requires clinician review.'],
  });
  const treated = facts.osteoporosisTreatmentStatus;
  if (typeof treated !== 'boolean') return finish(null, 'needs_more_information', 'Treatment history has not been confirmed.', ['osteoporosisTreatmentStatus']);
  if (treated) return finish('PATHWAY2', 'not_integrated', 'Previous or current osteoporosis treatment was recorded.');
  const reason = 'No previous or current osteoporosis treatment was recorded.';
  function inspect(id: string, c: Condition) {
    const result = condition(c, facts);
    trace.push({ rule_id: id, matched: result.matched,
      input: Object.fromEntries(keys(c).map(k => [k, facts[k] ?? null])),
      reason: `${labels[id] ?? 'Clinical condition'}: ${result.matched === null ? 'information needed' : result.matched ? 'met' : 'not met'}.`,
    });
    return result;
  }
  const entry = inspect('ENTRY', doc.conditions);
  if (entry.matched === null) return finish('PATHWAY1', 'needs_more_information', reason, entry.missing);
  if (!entry.matched) return finish('PATHWAY1', 'not_applicable', reason);
  for (const rule of doc.rules) {
    const result = inspect(rule.id, rule.when);
    if (result.matched === null) {
      // do not publish partial actions when a relevant condition is unknown
      actions.length = 0;
      return finish('PATHWAY1', 'needs_more_information', reason, result.missing);
    }
    if (result.matched) {
      actions.push(...rule.then);
      if (rule.stopPathway) break;
    }
  }
  return finish('PATHWAY1', actions.length ? 'action_taken' : 'no_action', reason);
}
