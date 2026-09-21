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
            throw new Error(`Invalid Content Type`);
        }

        const { caseId } = await req.json();

        if (!caseId || typeof caseId !== "string") {
            throw new Error(`Invalid case ID`);
        }

        const { data: clinicalCase, error: clinicalCaseError } =
            await supabase
                .from("clinical_cases")
                .select("id, patient_facts, clinician_facts, assigned_clinician_id, status")
                .eq("id", caseId)
                .eq("assigned_clinician_id", userData.user.id)
                .eq("status", "in_progress")
                .single();

        if (clinicalCaseError) {
            throw clinicalCaseError;
        }

        const facts = {
            ...clinicalCase.patient_facts,
            ...clinicalCase.clinician_facts,
        };

        const result = evaluateDecisionTree(docs, facts as Record<string, unknown>, "PATHWAY1");

        const { error: saveError } =
            await supabase.rpc("save_rule_evaluation", {
                p_case_id: caseId,
                p_evaluation: result,
            });

        if (saveError) {
            throw saveError;
        }

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