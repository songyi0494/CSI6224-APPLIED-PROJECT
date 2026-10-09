import type { Condition } from "./condition.ts"
import type { Action } from "./action.ts"

export interface DecisionNode {
    type: "decision";
    question: string;
    helperText?: string;
    condition: Condition;
    yes: string;
    no: string;
}

export interface LeafNode {
    type: "leaf";
    actions: Action[];
}

export interface ReviewNode {
    type: "review";
    code: "ELIGIBILITY_NOT_MET" | "ELIGIBILITY_INFORMATION_REQUIRED";
    message: string;
}

export type TreeNode = DecisionNode | LeafNode | ReviewNode;

export interface DecisionTreeRule {
    metadata: {
        id: string;
        title: string;
    },
    root: string;
    nodes: Record<string, TreeNode>;
}

export interface TraceEntry {
    pathwayId?: string;
    nodeId: string;
    nodeType: "decision" | "leaf" | "review";
    matched?: boolean;
    nextNodeId?: string;
    actionsTriggered: Action[];
}

export interface EvaluationError {
    code: "MISSING_REQUIRED_FIELDS" | "INVALID_FACT_VALUE" | "NODE_NOT_FOUND" | "REDIRECT_LOOP" | "PATHWAY_NOT_FOUND" | "ELIGIBILITY_NOT_MET" | "ELIGIBILITY_INFORMATION_REQUIRED";
    fields?: string[];
    nodeId?: string;
    pathwayId?: string;
    message?: string;
}

export interface QuestionState {
    status: "question";
    pathwayId: string;
    nodeId: string;
    question: string;
    helperText?: string;
    requiredFacts: string[];
}

export interface CompletedState {
    status: "complete";
    pathwayId: string;
    actions: Action[];
}

export interface ErrorState {
    status: "error";
    pathwayId: string;
    error: EvaluationError;
    actions: Action[];
}

export type EvaluationResultStep =
    | QuestionState
    | CompletedState
    | ErrorState;

export type EvaluationResult = EvaluationResultStep & {
    trace: TraceEntry[];
}
