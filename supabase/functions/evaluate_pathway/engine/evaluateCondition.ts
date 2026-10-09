import type { Condition, SimpleCondition } from "../types/condition.ts";

const OPERATORS = {
    equals: (a: unknown, b: unknown) => a === b,
    notEquals: (a: unknown, b: unknown) => a !== b,
    lessThan: (a: unknown, b: unknown) => typeof a === "number" && typeof b === "number" && a < b,
    lessThanOrEqual: (a: unknown, b: unknown) => typeof a === "number" && typeof b === "number" && a <= b,
    greaterThan: (a: unknown, b: unknown) => typeof a === "number" && typeof b === "number" && a > b,
    greaterThanOrEqual: (a: unknown, b: unknown) => typeof a === "number" && typeof b === "number" && a >= b,
    in: (a: unknown, list: unknown) => Array.isArray(list) && list.includes(a),
    notIn: (a: unknown, list: unknown) => !Array.isArray(list) || !list.includes(a),
};

function isSimpleCondition(cond: Condition): cond is SimpleCondition {
    return "fact" in cond && "operator" in cond;
}

export function getRequiredFactsFromCondition(cond: Condition): string[] {
    if(isSimpleCondition(cond)) {
        return [cond.fact];
    }

    const children = cond.all ?? cond.any ?? [];
    return [...new Set(children.flatMap(getRequiredFactsFromCondition))];
}

export function evaluateCondition(cond: Condition, facts: Record<string, unknown>): "true" | "false" | "unknown" {
    if (isSimpleCondition(cond)) {
        const { fact, operator, value } = cond;
        
        if (!(fact in facts) || facts[fact] === undefined || facts[fact] === null) {
            return "unknown";
        }

        const actual = facts[fact];
        const fn = OPERATORS[operator as keyof typeof OPERATORS];
        if (!fn) {
            throw new Error(`Invalid operator: ${operator}`);
        }
        return fn(actual, value) ? "true" : "false";
    }

    if ("all" in cond && cond.all) {
        let hasUnknown = false;

        for (const c of cond.all) {
            const result = evaluateCondition(c, facts);
            if (result === "false") {
                return "false";
            }
            if (result === "unknown") {
                hasUnknown = true;
            }
        }

        return hasUnknown ? "unknown" : "true";
    }

    if ("any" in cond && cond.any) {
        let hasUnknown = false;

        for (const c of cond.any) {
            const result = evaluateCondition(c, facts);
            if (result === "true") {
                return "true";
            }
            if (result === "unknown") {
                hasUnknown = true;
            }
        }

        return hasUnknown ? "unknown" : "false";
    }

    throw new Error(`Invalid condition structure: ${JSON.stringify(cond)}`);
}