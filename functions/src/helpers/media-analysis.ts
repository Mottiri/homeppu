/**
 * AIコメント用メディア分析関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { GoogleGenerativeAI, Part } from "@google/generative-ai";
import { GoogleAIFileManager } from "@google/generative-ai/server";
import { MediaItem } from "../types";
import { downloadFile } from "./moderation";
import {
    IMAGE_ANALYSIS_PROMPT,
    VIDEO_ANALYSIS_PROMPT,
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

        console.log("Image analysis result:", description);
        return description || null;
    } catch (error) {
        console.error("Image analysis error:", error);
        return null;
    }
}

/**
 * 動画の内容を分析して説明を生成
 */
export async function analyzeVideoForComment(
    apiKey: string,
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    videoUrl: string,
    mimeType: string = "video/mp4"
): Promise<string | null> {
    const tempFilePath = path.join(os.tmpdir(), `video_analysis_${Date.now()}.mp4`);

    try {
        // 動画をダウンロード
        const videoBuffer = await downloadFile(videoUrl);
        fs.writeFileSync(tempFilePath, videoBuffer);

        // Gemini File APIにアップロード
        const fileManager = new GoogleAIFileManager(apiKey);
        const uploadResult = await fileManager.uploadFile(tempFilePath, {
            mimeType: mimeType,
            displayName: `analysis_video_${Date.now()} `,
        });

        // アップロード完了を待つ
        let file = uploadResult.file;
        while (file.state === "PROCESSING") {
            await new Promise((resolve) => setTimeout(resolve, 2000));
            const result = await fileManager.getFile(file.name);
            file = result;
        }

        if (file.state === "FAILED") {
            throw new Error("Video processing failed");
        }

        const prompt = VIDEO_ANALYSIS_PROMPT;

        const videoPart: Part = {
            fileData: {
                mimeType: file.mimeType,
                fileUri: file.uri,
            },
        };

        const result = await model.generateContent([prompt, videoPart]);
        const description = result.response.text()?.trim();

        // アップロードしたファイルを削除
        try {
            await fileManager.deleteFile(file.name);
        } catch (e) {
            console.log("Failed to delete uploaded file:", e);
        }

        console.log("Video analysis result:", description);
        return description || null;
    } catch (error) {
        console.error("Video analysis error:", error);
        return null;
    } finally {
        // 一時ファイルを削除
        if (fs.existsSync(tempFilePath)) {
            fs.unlinkSync(tempFilePath);
        }
    }
}

/**
 * メディアアイテムを分析して説明を生成
 */
export async function analyzeMediaForComment(
    apiKey: string,
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
            } else if (item.type === "video") {
                const desc = await analyzeVideoForComment(apiKey, model, item.url, item.mimeType || "video/mp4");
                if (desc) {
                    descriptions.push(`【動画】${desc} `);
                }
            }
        } catch (error) {
            console.error(`Failed to analyze media item: `, error);
        }
    }

    return descriptions;
}
