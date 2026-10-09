export interface Action {
    type: string;
    [key: string]: unknown;
}