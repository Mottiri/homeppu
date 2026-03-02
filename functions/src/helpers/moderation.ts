/**
 * メディアモデレーション関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import * as https from "https";
import { GoogleGenerativeAI, Part } from "@google/generative-ai";
import { MediaModerationResult, MediaItem } from "../types";
import { logAIUsage } from "./ai-usage";
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
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    imageUrl: string,
    mimeType: string = "image/jpeg"
): Promise<MediaModerationResult> {
    try {
        console.log(`moderateImage: Starting moderation for ${imageUrl.substring(0, 100)}...`);
        const imageBuffer = await downloadFile(imageUrl);
        const base64Image = imageBuffer.toString("base64");
        console.log(`moderateImage: Downloaded image, size=${imageBuffer.length} bytes`);

        const prompt = IMAGE_MODERATION_PROMPT;

        const imagePart: Part = {
            inlineData: {
                mimeType: mimeType,
                data: base64Image,
            },
        };

        const result = await model.generateContent([prompt, imagePart]);
        const responseText = result.response.text().trim();
        logAIUsage("media_moderation_image", result.response, {
            mimeType,
        });
        console.log(`moderateImage: Raw response: ${responseText.substring(0, 200)}`);

        let jsonText = responseText;
        // JSON部分を抽出
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
            jsonText = jsonMatch[1];
        } else {
            // ブレースで囲まれた部分を抽出
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
        // Fail Closed: エラー時は不適切として扱う（安全第一）
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
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    mediaItems: MediaItem[]
): Promise<{ passed: boolean; failedItem?: MediaItem; result?: MediaModerationResult }> {
    for (const item of mediaItems) {
        if (item.type === "image") {
            const result = await moderateImage(model, item.url, item.mimeType || "image/jpeg");
            if (result.isInappropriate && result.confidence >= 0.7) {
                return { passed: false, failedItem: item, result };
            }
        }
        // fileタイプはスキップ（PDFなどのモデレーションは複雑なため）
    }

    return { passed: true };
}
