export type Operator = 'equals' | 'in' | 'notIn';

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
