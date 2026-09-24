import type { DecisionTreeRule } from "./types/decisionTree.ts";
import pathway1 from "./rules/pathway_1.json" with { type: "json" };
import pathway2 from "./rules/pathway_2.json" with { type: "json" };
import { evaluateDecisionTree } from "./engine/evaluateDecisionTree.ts";

const docs: Record<string, DecisionTreeRule> = {
    PATHWAY1: pathway1 as DecisionTreeRule,
    PATHWAY2: pathway2 as DecisionTreeRule,
};

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

        const result = evaluateDecisionTree(docs, facts as Record<string, unknown>, "PATHWAY1");

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