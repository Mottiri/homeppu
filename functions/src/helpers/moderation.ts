/**
 * メディアモデレーション関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import * as https from "https";
import { AIProviderFactory } from "../ai/provider";
import { MediaModerationResult, MediaItem } from "../types";
import { logAIProviderUsage } from "./ai-usage";
import {
    IMAGE_MODERATION_PROMPT,
} from "../ai/prompts/moderation";

/**
 * URLからファイルをダウンロード
 */
export async function downloadFile(url: string): Promise<Buffer> {
    return new Promise((resolve, reject) => {
        https.get(url, (response) => {
            // リダイレクト対応
            if (response.statusCode === 301 || response.statusCode === 302) {
                const redirectUrl = response.headers.location;
                if (redirectUrl) {
                    downloadFile(redirectUrl).then(resolve).catch(reject);
                    return;
                }
            }

            if (response.statusCode !== 200) {
                reject(new Error(`Failed to download: ${response.statusCode} `));
                return;
            }

            const chunks: Buffer[] = [];
            response.on("data", (chunk) => chunks.push(chunk));
            response.on("end", () => resolve(Buffer.concat(chunks)));
            response.on("error", reject);
        }).on("error", reject);
    });
}

/**
 * 画像をモデレーション
 */
export async function moderateImage(
    aiFactory: AIProviderFactory,
    imageUrl: string,
    mimeType: string = "image/jpeg"
): Promise<MediaModerationResult> {
    try {
        console.log(`moderateImage: Starting moderation for ${imageUrl.substring(0, 100)}...`);
        const imageBuffer = await downloadFile(imageUrl);
        const base64Image = imageBuffer.toString("base64");
        console.log(`moderateImage: Downloaded image, size=${imageBuffer.length} bytes`);

        const prompt = IMAGE_MODERATION_PROMPT;

        const result = await aiFactory.generateWithImage(prompt, base64Image, mimeType);
        const responseText = result.text.trim();
        logAIProviderUsage("media_moderation_image", result, { mimeType });
        console.log(`moderateImage: Raw response: ${responseText.substring(0, 200)}`);

        let jsonText = responseText;
        // JSON表現を抽出
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
            jsonText = jsonMatch[1];
        } else {
            // ブレースで囲まれた表現を抽出
            const braceMatch = responseText.match(/\{[\s\S]*\}/);
            if (braceMatch) {
                jsonText = braceMatch[0];
            }
        }

        const parsed = JSON.parse(jsonText) as MediaModerationResult;
        console.log(`moderateImage: Parsed result: isInappropriate=${parsed.isInappropriate}, category=${parsed.category}, confidence=${parsed.confidence}`);
        return parsed;
    } catch (error) {
        console.error("moderateImage error:", error);
        // Fail Closed: エラー時は不適切として扱う（最悪のケース）
        return {
            isInappropriate: true,
            category: "dangerous",
            confidence: 1.0,
            reason: "モデレーション処理エラー - 安全のためブロック",
        };
    }
}

/**
 * メディアアイテムをモデレーション
 */
export async function moderateMedia(
    aiFactory: AIProviderFactory,
    mediaItems: MediaItem[]
): Promise<{ passed: boolean; failedItem?: MediaItem; result?: MediaModerationResult }> {
    const imageResults = await Promise.all(
        mediaItems.map(async (item, index) => {
            if (item.type !== "image") {
                return null;
            }
            const result = await moderateImage(aiFactory, item.url, item.mimeType || "image/jpeg");
            return { item, index, result };
        })
    );

    const concerning = imageResults
        .filter((entry): entry is { item: MediaItem; index: number; result: MediaModerationResult } => Boolean(entry))
        .filter((entry) => entry.result.isInappropriate && entry.result.confidence >= 0.5)
        .sort((a, b) => a.index - b.index)[0];

    if (concerning) {
        return { passed: false, failedItem: concerning.item, result: concerning.result };
    }

    return { passed: true };
}
