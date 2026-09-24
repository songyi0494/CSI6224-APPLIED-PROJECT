import type { Action } from "../types/action.ts";
import type { TraceEntry, EvaluationError, DecisionTreeRule, EvaluationResult, TreeNode } from "../types/decisionTree.ts";
import { evaluateCondition, getRequiredFactsFromCondition } from "./evaluateCondition.ts";

function evaluateSingleTree(doc: DecisionTreeRule, facts: Record<string, unknown>): {
    pathway: string;
    actions: Action[];
    trace: TraceEntry[];
    nextQuestion?: {
        nodeId: string;
        question: string;
        requiredFacts: string[];
    }
    error?: EvaluationError;
} {
    const trace: TraceEntry[] = [];

    let currentNodeId = doc.root;

    while (true) {
        const node: TreeNode | undefined = doc.nodes[currentNodeId];

        if (!node) {
            return {
                pathway: doc.metadata.id,
                actions: [],
                trace,
                error: {
                    code: "NODE_NOT_FOUND",
                    nodeId: currentNodeId,
                    pathwayId: doc.metadata.id,
                    message: `Node not found: ${currentNodeId}`,
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
                actions: node.actions,
                trace,
            };
        }

        const evaluateResult = evaluateCondition(node.condition, facts);

        if (evaluateResult === "unknown") {
            trace.push({
                pathwayId: doc.metadata.id,
                nodeId: currentNodeId,
                nodeType: "decision",
                actionsTriggered: [],
            });

            return {
                pathway: doc.metadata.id,
                actions: [],
                trace,
                nextQuestion: {
                    nodeId: currentNodeId,
                    question: node.question,
                    requiredFacts: getRequiredFactsFromCondition(node.condition),
                },
            };
        }

        const matched = evaluateResult === "true";
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
                status: "error",
                pathwayId: currentPathway,
                error: {
                    code: "REDIRECT_LOOP",
                    pathwayId: currentPathway,
                    message: `Redirect loop detected at ${currentPathway}`,
                },
                actions: finalActions,
                trace: fullTrace,
            };
        }
        visitedPathways.add(currentPathway);

        const doc = docs[currentPathway];

        if (!doc) {
            return {
                status: "error",
                pathwayId: currentPathway,
                error: {
                    code: "PATHWAY_NOT_FOUND",
                    pathwayId: currentPathway,
                    message: `Pathway not found: ${currentPathway}`,
                },
                actions: finalActions,
                trace: fullTrace,
            };
        }

        const result = evaluateSingleTree(doc, facts);
        fullTrace.push(...result.trace);

        if (result.error) {
            return {
                status: "error",
                pathwayId: currentPathway,
                error: result.error,
                actions: finalActions,
                trace: fullTrace,
            };
        }

        if (result.nextQuestion) {
            return {
                status: "question",
                pathwayId: currentPathway,
                nodeId: result.nextQuestion.nodeId,
                question: result.nextQuestion.question,
                requiredFacts: result.nextQuestion.requiredFacts,
                trace: fullTrace,
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
            status: "complete",
            pathwayId: currentPathway,
            actions: finalActions,
            trace: fullTrace,
        };
    }
}