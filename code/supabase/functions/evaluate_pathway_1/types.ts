export type Operator =
    | 'equals'
    | 'notEquals'
    | 'lessThan'
    | 'lessThanOrEqual'
    | 'greaterThan'
    | 'greaterThanOrEqual'
    | 'in'
    | 'notIn'

export interface SimpleCondition {
    fact: string;
    operator: Operator;
    value?: unknown;
}

export interface CompoundCondition {
    all?: Condition[];
    any?: Condition[];
}

export type Condition = SimpleCondition | CompoundCondition;

export interface Action {
    type: string;
    [key: string]: unknown;
}

export interface Rule {
    id: string;
    when: Condition;
    then: Action[];
    stopPathway?: boolean;
}

export interface EntryConditionRoot {
    type: 'entryCondition';
    conditions: string;
}

export interface PathwayDocument {
    metadata: {
        id: string;
        title: string;
    };
    requiredFields: string[];
    root: EntryConditionRoot;
    conditions: Condition;
    investigations?: {
        id: string;
        label: string;
        items: {
            code: string;
            label: string;
        }[];
    };
    commonAdvice?: unknown[];
    rules: Rule[];
}

export interface TraceCondition {
    fact: string;
    value: unknown;
    operator: string;
    expected: unknown;
    result: boolean;
}

export interface TraceEntry {
    ruleId: string;
    matched: boolean;
    conditions: TraceCondition[];
    actionsTriggered: Action[];
}

export interface EvaluationError {
    code: "MISSING_REQUIRED_FIELDS";
    fields: string[];
}

export interface EvaluationResult {
    pathway: string;
    decision: 'not_applicable' | 'action_taken' | 'no_action';
    actions: Action[];
    trace: TraceEntry[];
    error?: EvaluationError;
}