import { createClient } from "npm:@supabase/supabase-js@2";
import type { DecisionTreeRule } from "./types/decisionTree.ts";
import pathway1 from "./rules/pathway_1.json" with { type: "json" };
import pathway2 from "./rules/pathway_2.json" with { type: "json" };
import { evaluateDecisionTree } from "./engine/evaluateDecisionTree.ts";

const docs: Record<string, DecisionTreeRule> = {
    PATHWAY1: pathway1 as DecisionTreeRule,
    PATHWAY2: pathway2 as DecisionTreeRule,
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const publishableKeys = JSON.parse(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")!
);

const supabasePublishableKey = publishableKeys["default"];

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

        const authHeader = req.headers.get("Authorization");

        if (!authHeader) {
            throw new Error("Missing Authorization header");
        }

        const supabase = createClient(
            supabaseUrl,
            supabasePublishableKey,
            {
                global: {
                    headers: {
                        Authorization: authHeader,
                    },
                },
            }
        );

        const { data: userData, error: userError } =
            await supabase.auth.getUser();

        if (userError) {
            throw new Error(`USER ERROR: ${userError.message}`);
        }

        if (!userData.user) {
            throw new Error("User not found");
        }

        const contentType = req.headers.get("Content-Type") || "";
        if (!contentType.includes("application/json")) {
            throw new Error("Invalid Content Type");
        }

        const { caseId } = await req.json();

        if (!caseId || typeof caseId !== "string") {
            throw new Error("Invalid case ID");
        }

        const { data: caseContext, error: caseContextError } =
            await supabase.rpc('get_pathway_case_context', {
                p_case_id: caseId,
            })
        
        if(caseContextError) {
            throw caseContextError;
        }

        if (!caseContext || typeof caseContext !== "object" || Array.isArray(caseContext)){
            throw new Error("Invalid pathway case context");
        }

        const clinicalCase = caseContext as {
            id: string;
            clinician_facts: Record<string, unknown> | null;
            assigned_clinician_id: string;
            status: string;
            pathway_revision: number;
        };

        const facts = clinicalCase.clinician_facts as Record<string, unknown> | null;

        if (!facts || typeof facts !== "object" || Array.isArray(facts)) {
            throw new Error(
                `Invalid clinician_facts received: ${JSON.stringify(facts)}`
            );
        }

        const result = evaluateDecisionTree(docs, facts, "PATHWAY1");

        if (result.status === "complete") {
            const { error: saveError } =
                await supabase.rpc("save_rule_evaluation", {
                    p_case_id: caseId,
                    p_evaluation: result,
                });

            if (saveError) {
                throw saveError;
            }
        }

        return new Response(JSON.stringify(result), {
            status: 200,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
        });
    } catch (err) {
        let message = "Unkown error";

        if (err instanceof Error) {
            message = err.message;
        } else if (
            typeof err === "object" && err !== null && "message" in err && typeof err.message === "string"
        ) {
            message = err.message;
        }

        return new Response(JSON.stringify({ error: message }), {
            status: 400,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
        });
    }
});