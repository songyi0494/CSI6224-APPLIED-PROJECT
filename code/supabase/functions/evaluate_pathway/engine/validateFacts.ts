type ruleFact =
    | { type: "boolean" }
    | { type: "number" }

export function validateFacts(
    facts: Record<string, unknown>,
    schema: Record<string, ruleFact>
): { valid: true } | { valid: false; errors: string[]; fields: string[] } {
    const errors: string[] = [];
    const fields: string[] = [];

    for (const [factName, rule] of Object.entries(schema)) {
        const value = facts[factName];

        if (value === undefined || value === null) continue;

        if (rule.type === "boolean" && typeof value !== "boolean") {
            errors.push(`${factName} must be boolean`);
            fields.push(factName);
            continue;
        }

        if (rule.type === "number" ) {
            if (typeof value !== "number" || Number.isNaN(value)) {
                errors.push(`${factName} must be number`);
                fields.push(factName);
                continue;
            }
        }
    }

    if (errors.length > 0) {
        return { valid: false, errors, fields: [...new Set(fields)] };
    }

    return { valid: true };
}
