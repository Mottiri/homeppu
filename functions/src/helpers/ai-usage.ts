type UsageMetadata = {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
};

function toFiniteNumber(value: unknown): number | undefined {
    if (typeof value !== "number" || !Number.isFinite(value)) {
        return undefined;
    }
    return value;
}

export function extractUsageMetadata(response: unknown): UsageMetadata | null {
    if (!response || typeof response !== "object") {
        return null;
    }

    const usage = (response as { usageMetadata?: unknown }).usageMetadata;
    if (!usage || typeof usage !== "object") {
        return null;
    }

    const typed = usage as Record<string, unknown>;
    const promptTokenCount = toFiniteNumber(typed.promptTokenCount);
    const candidatesTokenCount = toFiniteNumber(typed.candidatesTokenCount);
    const totalTokenCount = toFiniteNumber(typed.totalTokenCount);

    if (
        promptTokenCount === undefined &&
        candidatesTokenCount === undefined &&
        totalTokenCount === undefined
    ) {
        return null;
    }

    return {
        promptTokenCount,
        candidatesTokenCount,
        totalTokenCount,
    };
}

export function logAIUsage(
    label: string,
    response: unknown,
    context: Record<string, unknown> = {}
): void {
    const usage = extractUsageMetadata(response);
    if (!usage) {
        return;
    }

    console.log("[AI USAGE]", JSON.stringify({
        label,
        ...context,
        ...usage,
    }));
}

export function logAIProviderUsage(
    label: string,
    response: { text: string; provider: string; usedFallback: boolean },
    context: Record<string, unknown> = {}
): void {
    console.log("[AI USAGE]", JSON.stringify({
        label,
        provider: response.provider,
        usedFallback: response.usedFallback,
        responseLength: response.text.length,
        ...context,
    }));
}
