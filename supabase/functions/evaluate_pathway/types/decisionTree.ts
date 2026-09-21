import type { Condition } from "./condition.ts"
import type { Action } from "./action.ts"

export interface DecisionNode {
    type: "decision";
    question: string;
    condition: Condition;
    yes: string;
    no: string;
}

export interface LeafNode {
    type: "leaf";
    actions: Action[];
}

export type TreeNode = DecisionNode | LeafNode;

export interface DecisionTreeRule {
    metadata: {
        id: string;
        title: string;
    },
    requiredFields: string[];
    root: string;
    nodes: Record<string, TreeNode>;
}

export interface TraceEntry {
    pathwayId?: string;
    nodeId: string;
    nodeType: "decision" | "leaf";
    matched?: boolean;
    nextNodeId?: string;
    actionsTriggered: Action[];
}

export interface EvaluationError {
    code: "MISSING_REQUIRED_FIELDS" | "NODE_NOT_FOUND" | "REDIRECT_LOOP" | "PATHWAY_NOT_FOUND";
    fields?: string[];
    nodeId?: string;
    pathwayId?: string;
}

export interface EvaluationResult {
    pathway: string;
    decision: "not_applicable" | "action_taken" | "no_action";
    actions: Action[];
    trace: TraceEntry[];
    error?: EvaluationError;
}