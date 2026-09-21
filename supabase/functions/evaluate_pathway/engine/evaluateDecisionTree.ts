import type { Action } from "../types/action.ts";
import type { DecisionTreeRule, EvaluationResult, TraceEntry, TreeNode } from "../types/decisionTree.ts";
import { evaluateCondition, getMissingRequiredFields } from "./evaluateCondition.ts";

function evaluateSingleTree(doc: DecisionTreeRule, facts: Record<string, unknown>): {
    pathway: string;
    decision: EvaluationResult["decision"];
    actions: Action[];
    trace: TraceEntry[];
    error?: EvaluationResult["error"];
} {
    const missingFields = getMissingRequiredFields(doc.requiredFields, facts);
    const actions: Action[] = [];
    const trace: TraceEntry[] = [];

    if (missingFields.length > 0) {
        return {
            pathway: doc.metadata.id,
            decision: "not_applicable",
            actions,
            trace,
            error: {
                code: "MISSING_REQUIRED_FIELDS",
                fields: missingFields,
                pathwayId: doc.metadata.id,
            },
        };
    }

    let currentNodeId = doc.root;

    while (true) {
        const node: TreeNode | undefined = doc.nodes[currentNodeId];

        if (!node) {
            return {
                pathway: doc.metadata.id,
                decision: "not_applicable",
                actions,
                trace,
                error: {
                    code: "NODE_NOT_FOUND",
                    nodeId: currentNodeId,
                    pathwayId: doc.metadata.id,
                },
            };
        }

        if (node.type === "leaf"){
            trace.push({
                pathwayId: doc.metadata.id,
                nodeId: currentNodeId,
                nodeType: "leaf",
                actionsTriggered: node.actions,
            });

            return {
                pathway: doc.metadata.id,
                decision: node.actions.length ? "action_taken" : "no_action",
                actions: node.actions,
                trace,
            };
        }

        if (currentNodeId === "HIGH_RISK_CHECK") {
            const highRiskFields = [
                "recentFractureWithin2Y",
                "historyOf2orMoreFractures",
                "clinicalRiskFactors",
                "FRAX10YmajorOsteoporoticFractureRiskPercent",
                "FRAX10YmajorHipFractureRiskPercent"
            ];

            const missingFields = highRiskFields.filter(
                (field) => facts[field] === undefined || facts[field] === null
            );

            if (missingFields.length > 0) {
                return {
                    pathway: doc.metadata.id,
                    decision: "not_applicable",
                    actions,
                    trace,
                    error: {
                        code: "MISSING_REQUIRED_FIELDS",
                        fields: missingFields,
                        pathwayId: doc.metadata.id,
                    },
                };
            }
        }

        const matched = evaluateCondition(node.condition, facts);
        const nextNodeId = matched ? node.yes : node.no;

        trace.push({
            pathwayId: doc.metadata.id,
            nodeId: currentNodeId,
            nodeType: "decision",
            matched,
            nextNodeId,
            actionsTriggered: [],
        });

        currentNodeId = nextNodeId;
    }
}

export function evaluateDecisionTree(
    docs: Record<string, DecisionTreeRule>,
    facts: Record<string, unknown>,
    startPathway = "PATHWAY1"
): EvaluationResult {
    const visitedPathways = new Set<string>();
    const fullTrace: TraceEntry[] = [];
    const finalActions: Action[] = [];

    let currentPathway = startPathway;
    
    while (true) {
        if (visitedPathways.has(currentPathway)) {
            return {
                pathway: currentPathway,
                decision: "not_applicable",
                actions: finalActions,
                trace: fullTrace,
                error: {
                    code: "REDIRECT_LOOP",
                    pathwayId: currentPathway,
                },
            };
        }
        visitedPathways.add(currentPathway);

        const doc = docs[currentPathway];
        if (!doc) {
            return {
                pathway: currentPathway,
                decision: "not_applicable",
                actions: finalActions,
                trace: fullTrace,
                error: {
                    code: "PATHWAY_NOT_FOUND",
                    pathwayId: currentPathway,
                },
            };
        }

        const result = evaluateSingleTree(doc, facts);
        fullTrace.push(...result.trace);

        if (result.error) {
            return {
                pathway: currentPathway,
                decision: "not_applicable",
                actions: finalActions,
                trace: fullTrace,
                error: result.error,
            };
        }

        const redirectAction = result.actions.find(
            (a) => a.type === "pathwayRedirect" && typeof a.targetPathway === "string"
        );

        const nonRedirectActions = result.actions.filter(
            (a) => !(a.type === "pathwayRedirect" && typeof a.targetPathway === "string")
        );

        finalActions.push(...nonRedirectActions);

        if (redirectAction && typeof redirectAction.targetPathway === "string") {
            currentPathway = redirectAction.targetPathway;
            continue;
        }

        return {
            pathway: currentPathway,
            decision: finalActions.length ? "action_taken" : "no_action",
            actions: finalActions,
            trace: fullTrace,
        };
    }
}