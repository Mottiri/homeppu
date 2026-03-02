/**
 * AIコメント用メディア分析関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import { GoogleGenerativeAI, Part } from "@google/generative-ai";
import { MediaItem } from "../types";
import { logAIUsage } from "./ai-usage";
import { downloadFile } from "./moderation";
import {
    IMAGE_ANALYSIS_PROMPT,
} from "../ai/prompts/media-analysis";

/**
 * 画像の内容を分析して説明を生成
 */
export async function analyzeImageForComment(
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    imageUrl: string,
    mimeType: string = "image/jpeg"
): Promise<string | null> {
    try {
        const imageBuffer = await downloadFile(imageUrl);
        const base64Image = imageBuffer.toString("base64");

        const prompt = IMAGE_ANALYSIS_PROMPT;

        const imagePart: Part = {
            inlineData: {
                mimeType: mimeType,
                data: base64Image,
            },
        };

        const result = await model.generateContent([prompt, imagePart]);
        const description = result.response.text()?.trim();
        logAIUsage("media_analysis_image", result.response, {
            mimeType,
        });

        console.log("Image analysis result:", description);
        return description || null;
    } catch (error) {
        console.error("Image analysis error:", error);
        return null;
    }
}

/**
 * メディアアイテムを分析して説明を生成
 */
export async function analyzeMediaForComment(
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    mediaItems: MediaItem[]
): Promise<string[]> {
    const descriptions: string[] = [];

    for (const item of mediaItems) {
        try {
            if (item.type === "image") {
                const desc = await analyzeImageForComment(model, item.url, item.mimeType || "image/jpeg");
                if (desc) {
                    descriptions.push(`【画像】${desc} `);
                }
            }
        } catch (error) {
            console.error(`Failed to analyze media item: `, error);
        }
    }

    return descriptions;
}
