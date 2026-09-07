import type { 
    Condition,
    PathwayDocument,
    EvaluationResult,
    Action,
    SimpleCondition,
} from "./types.ts";

import pathwayDoc_1 from "./pathway_1.json" with { type: "json" };
const doc = pathwayDoc_1 as PathwayDocument;

import { createClient } from "supabase";

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

function isSimpleCondition(
    cond: Condition
): cond is SimpleCondition {
    return "fact" in cond && "operator" in cond;
}

function evaluateCondition(
    cond: Condition,
    facts: Record<string, unknown>
): boolean {
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

function evaluatePathway(
    doc: PathwayDocument,
    facts: Record<string, unknown>
): EvaluationResult {
    const { metadata, root, conditions, rules } = doc;

    if (root.type !== "entryCondition") {
        throw new Error(`Invalid root: ${root}`);
    }

    const entryOK = evaluateCondition(conditions, facts);
    if (!entryOK) {
        return {
            pathway: metadata.id,
            decision: "not_applicable",
            actions: [],
            trace: ["ENTRY_CONDITION_FAILED"]
        };
    }

    const actions: Action[] = [];
    const trace: string[] = ["ENTRY_CONDITION_PASSED"];

    for (const rule of rules) {
        trace.push(rule.id);
        const match = evaluateCondition(rule.when, facts);
        if (match) {
            actions.push(...(rule.then || []));
        }
        if (rule.stopPathway) {
            trace.push("STOP_PATHWAY");
            break;
        }
    }

    return {
        pathway: metadata.id,
        decision: actions.length ? "action_taken" : "no_action",
        actions,
        trace,
    };
}

Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") {
        return new Response(null, {
            status: 204,
            headers: {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
            },
        });
    }

    try {
        const contentType = req.headers.get("Content-Type") || "";
        if (!contentType.includes("application/json")) {
            throw new Error(`Invalid Content Type`);
        }

        const { facts } = await req.json();

        if (!facts || typeof facts !== "object") {
            throw new Error(`Invalid facts object`);
        }

        const result = evaluatePathway(doc, facts as Record<string, unknown>);

        return new Response(JSON.stringify(result), {
            status: 200,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
        });
    } catch (err) {
        const message = err instanceof Error ? err.message : "Unknown error";
        return new Response(JSON.stringify({ error: message }), {
                status: 400,
                headers: {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
            });
    }
});