import { createHash } from "crypto";

export function summarizeTextForLog(text: string | null | undefined): {
    length: number;
    sha256Prefix: string | null;
} {
    const value = typeof text === "string" ? text : "";
    return {
        length: value.length,
        sha256Prefix: value.length > 0
            ? createHash("sha256").update(value).digest("hex").slice(0, 12)
            : null,
    };
}

export function summarizeErrorForLog(error: unknown): Record<string, unknown> {
    if (error && typeof error === "object") {
        const candidate = error as {
            name?: unknown;
            message?: unknown;
            code?: unknown;
            status?: unknown;
        };

        return {
            name: typeof candidate.name === "string" ? candidate.name : undefined,
            message: typeof candidate.message === "string" ? candidate.message : String(error),
            code: typeof candidate.code === "string" || typeof candidate.code === "number"
                ? candidate.code
                : undefined,
            status: typeof candidate.status === "string" || typeof candidate.status === "number"
                ? candidate.status
                : undefined,
        };
    }

    return { message: String(error) };
}
