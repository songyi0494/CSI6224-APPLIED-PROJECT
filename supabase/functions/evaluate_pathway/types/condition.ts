export type Operator =
    | 'equals'
    | 'notEquals'
    | 'lessThan'
    | 'lessThanOrEqual'
    | 'greaterThan'
    | 'greaterThanOrEqual'
    | 'in'
    | 'notIn';

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