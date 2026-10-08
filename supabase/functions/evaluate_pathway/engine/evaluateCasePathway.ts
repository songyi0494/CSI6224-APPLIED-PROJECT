import { evaluateDecisionTree } from "./evaluateDecisionTree.ts";
import { validateFacts } from "./validateFacts.ts";
import { factSchema } from "./factSchema.ts";
import type { DecisionTreeRule, EvaluationResult } from "../types/decisionTree.ts";

export const contractVersion = "songyi-p1p2-20261008";

// This context is produced by the protected RPC, never by the request body.
export interface EligibilityContext {
    sex: string | null;
    age: number | null;
    postmenopausal: boolean | null;
    questionnaireRevision: number | null;
    ageAsOf: string;
}

export function demographicEligibility(context: EligibilityContext | null | undefined): boolean | null {
    if (!context || !context.sex) return null;
    if (context.sex === "female") return typeof context.postmenopausal === "boolean" ? context.postmenopausal : null;
    if (context.sex === "male") return typeof context.age === "number" && Number.isInteger(context.age) && context.age >= 0 ? context.age > 50 : null;
    if (["another term", "another_term", "other"].includes(context.sex)) return false;
    return null;
}

export function evaluateCasePathway(
    docs: Record<string, DecisionTreeRule>,
    clinicianFacts: Record<string, unknown>,
    context: EligibilityContext | null | undefined,
): EvaluationResult {
    const demographic = demographicEligibility(context);
    if (demographic === null) {
        const fields = !context?.sex ? ["sex"] : context.sex === "female" ? ["postmenopausal"] : ["age"];
        return { status: "error", pathwayId: "PATHWAY1", actions: [], trace: [], error: {
            code: "ELIGIBILITY_INFORMATION_REQUIRED", fields,
            message: `More information is required before the recommendation can be completed. Check the recorded ${fields.join(", ")} in the patient profile or submitted questionnaire.`,
        } };
    }
    const facts: Record<string, unknown> = { ...clinicianFacts, p1DemographicEligible: demographic };
    // A historical raw eGFR is not a threshold confirmation. Ask again;
    // never derive a Boolean from the old number or overwrite stored history.
    if (typeof facts.eGFR === "number") delete facts.eGFR;
    // Old >=12-month answers have a different meaning and are not consumed.
    delete facts.antiresorptiveTreatmentDuration;
    const validation = validateFacts(facts, factSchema);
    if (!validation.valid) return { status: "error", pathwayId: "PATHWAY1", actions: [], trace: [], error: {
        code: "INVALID_FACT_VALUE", fields: validation.fields, message: validation.errors.join("; "),
    } };
    return evaluateDecisionTree(docs, facts);
}
