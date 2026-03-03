/**
 * 画像モデレーションCallable関数
 * Phase 7: index.ts から分離
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";

import { LOCATION } from "../config/constants";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { IMAGE_MODERATION_CALLABLE_PROMPT } from "../ai/prompts/moderation";
import { MediaModerationResult } from "../types";
import { requireAuth } from "../helpers/auth";
import { ErrorMessages } from "../helpers/errors";
import { logAIProviderUsage } from "../helpers/ai-usage";
import { createAIProviderFactory } from "../ai/provider";

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_MIME_TYPES = new Set([
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
]);

function estimateBase64Bytes(base64: string): number {
    const normalized = base64.replace(/\s/g, "");
    const padding = normalized.endsWith("==") ? 2 : normalized.endsWith("=") ? 1 : 0;
    return Math.floor((normalized.length * 3) / 4) - padding;
}

function blockedBySystem(reason: string): MediaModerationResult {
    return {
        isInappropriate: true,
        category: "adult",
        confidence: 1,
        reason,
    };
}

function logModeration(message: string, data?: Record<string, unknown>) {
    if (data) {
        console.log(`[IMG_MOD] ${message}`, data);
        return;
    }
    console.log(`[IMG_MOD] ${message}`);
}

/**
 * アップロード前の画像をモデレーション
 * Base64エンコードされた画像データを受け取り、不適切かどうか判定
 */
export const moderateImageCallable = onCall(
    { secrets: [geminiApiKey, openaiApiKey], region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const { imageBase64, mimeType = "image/jpeg" } = request.data;
        logModeration("request_received", {
            mimeType: typeof mimeType === "string" ? mimeType : "invalid",
            hasImageBase64: !!imageBase64,
        });

        if (!imageBase64) {
            logModeration("simple_check_blocked", { reason: "missing_image_base64" });
            throw new HttpsError("invalid-argument", ErrorMessages.IMAGE_BASE64_REQUIRED);
        }
        if (typeof imageBase64 !== "string") {
            logModeration("simple_check_blocked", { reason: "image_base64_not_string" });
            throw new HttpsError("invalid-argument", ErrorMessages.INVALID_ARGUMENT);
        }
        if (typeof mimeType !== "string" || !ALLOWED_MIME_TYPES.has(mimeType)) {
            logModeration("simple_check_blocked", {
                reason: "invalid_mime_type",
                mimeType: typeof mimeType === "string" ? mimeType : "invalid",
            });
            throw new HttpsError("invalid-argument", ErrorMessages.INVALID_ARGUMENT);
        }
        const estimatedBytes = estimateBase64Bytes(imageBase64);
        if (estimatedBytes > MAX_IMAGE_BYTES) {
            logModeration("simple_check_blocked", {
                reason: "image_too_large",
                estimatedBytes,
                maxBytes: MAX_IMAGE_BYTES,
            });
            throw new HttpsError("invalid-argument", ErrorMessages.INVALID_ARGUMENT);
        }
        logModeration("simple_check_pass", {
            mimeType,
            estimatedBytes,
        });

        // 認証チェック
        requireAuth(request, ErrorMessages.UNAUTHENTICATED_EN);

        try {
            const aiFactory = createAIProviderFactory();

            const prompt = IMAGE_MODERATION_CALLABLE_PROMPT;

            const result = await aiFactory.generateWithImage(prompt, imageBase64, mimeType);
            const responseText = result.text.trim();
            logAIProviderUsage("image_moderation_callable", result, { mimeType, estimatedBytes });
            logModeration("ai_raw_response", {
                preview: responseText.slice(0, 300),
            });

            let jsonText = responseText;
            // JSONブロックを抽出
            const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
            if (jsonMatch) {
                jsonText = jsonMatch[1];
            }

            const parsed = JSON.parse(jsonText) as Partial<MediaModerationResult>;
            const category = parsed.category;
            const confidence = Number(parsed.confidence ?? 0);
            const isInappropriate = parsed.isInappropriate === true;
            const reason =
                typeof parsed.reason === "string" && parsed.reason.trim()
                    ? parsed.reason
                    : "判定理由なし";
            const validCategory =
                category === "adult" ||
                category === "violence" ||
                category === "hate" ||
                category === "dangerous" ||
                category === "none";

            if (!validCategory) {
                console.error(`moderateImageCallable invalid category: ${String(category)}`);
                logModeration("ai_parse_blocked", { reason: "invalid_category", category: String(category) });
                return blockedBySystem("モデレーション判定形式エラー");
            }

            // Safety override:
            // If model indicates adult with moderate confidence, block even when flag is false.
            const shouldBlockBySafetyOverride =
                category === "adult" && Number.isFinite(confidence) && confidence >= 0.4;

            const moderationResult: MediaModerationResult = {
                isInappropriate: isInappropriate || shouldBlockBySafetyOverride,
                category,
                confidence: Number.isFinite(confidence) ? confidence : 0,
                reason,
            };

            logModeration("ai_result", {
                isInappropriate: moderationResult.isInappropriate,
                category: moderationResult.category,
                confidence: moderationResult.confidence,
                safetyOverride: shouldBlockBySafetyOverride,
                reason: moderationResult.reason,
            });

            return moderationResult;

        } catch (error) {
            console.error("moderateImageCallable ERROR:", error);
            logModeration("ai_error_blocked", {
                reason: "exception",
            });
            // Fail-close: 判定失敗時はブロック
            return blockedBySystem("モデレーションエラー");
        }
    }
);
