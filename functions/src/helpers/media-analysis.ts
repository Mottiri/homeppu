/**
 * AIコメント用メディア分析関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import { AIProviderFactory } from "../ai/provider";
import { MediaItem } from "../types";
import { logAIProviderUsage } from "./ai-usage";
import { downloadFile } from "./moderation";
import {
    IMAGE_ANALYSIS_PROMPT,
} from "../ai/prompts/media-analysis";

/**
 * 画像の内容を分析して説明を生成
 */
export async function analyzeImageForComment(
    aiFactory: AIProviderFactory,
    imageUrl: string,
    mimeType: string = "image/jpeg"
): Promise<string | null> {
    try {
        const imageBuffer = await downloadFile(imageUrl);
        const base64Image = imageBuffer.toString("base64");

        const prompt = IMAGE_ANALYSIS_PROMPT;

        const result = await aiFactory.generateWithImage(prompt, base64Image, mimeType);
        const description = result.text.trim();
        logAIProviderUsage("media_analysis_image", result, { mimeType });

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
    aiFactory: AIProviderFactory,
    mediaItems: MediaItem[]
): Promise<string[]> {
    const descriptions: string[] = [];

    for (const item of mediaItems) {
        try {
            if (item.type === "image") {
                const desc = await analyzeImageForComment(aiFactory, item.url, item.mimeType || "image/jpeg");
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
