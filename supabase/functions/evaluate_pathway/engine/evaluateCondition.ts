import type { Condition, SimpleCondition } from "../types/conditions.ts";

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

export function evaluateCondition(cond: Condition, facts: Record<string, unknown>): boolean {
    if (isSimpleCondition(cond)) {
        const { fact, operator, value } = cond;
        const actual = facts[fact];
        const fn = OPERATORS[operator as keyof typeof OPERATORS];
        if (!fn) {
            throw new Error(`Invalid operator: ${operator}`);
        }
        return !!fn(actual, value);
    }

    if ("all" in cond && cond.all) {
        return cond.all.every((c) => evaluateCondition(c, facts));
    }

    if ("any" in cond && cond.any) {
        return cond.any.some((c) => evaluateCondition(c, facts));
    }

    throw new Error(`Invalid condition structure: ${JSON.stringify(cond)}`);
}

export function getMissingRequiredFields(requiredFields: string[], facts: Record<string, unknown>): string[] {
    return requiredFields.filter(
        (field) => facts[field] === undefined || facts[field] === null
    );
}