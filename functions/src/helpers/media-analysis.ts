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

        const prompt = `
この画像の内容を分析して、SNS投稿者を褒めるための情報を提供してください。

【重要なルール】
1. 専門的な内容（資格試験、プログラミング、専門書、学習アプリ、技術文書、問題集など）の場合：
- 画像内のテキストを断片的に解釈しないでください
  - 「何の勉強・学習をしているか」だけを簡潔に説明してください（例：「資格試験の勉強」「プログラミング学習」）
- 詳細な内容には触れず「専門的で難しそう」「すごい挑戦」という観点で説明してください
  - 例: 「資格試験の学習アプリで勉強している画像です。専門的な内容に取り組んでいて頑張っています。」
- 悪い例: 「心理療法士の問題を解いている」← 画像内テキストの断片的解釈はNG

2. 一般的な内容（料理、運動、風景、作品、ペットなど）の場合：
- 具体的に何が写っているか説明してください
  - 褒めポイントを含めてください
  - 例: 「手作りのケーキの写真です。デコレーションがとても丁寧です。」

3. 画像内にテキストが含まれる場合でも、そのテキストの一部だけを切り取って解釈しないでください。
文脈を誤解する原因になります。

【回答形式】
2〜3文で簡潔に説明してください。
`;

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

        const prompt = `
この動画の内容を分析して、SNS投稿者を褒めるための情報を提供してください。

【重要なルール】
1. 専門的な内容（勉強、プログラミング、技術作業、資格試験など）の場合：
- 画面内のテキストを断片的に解釈しないでください
  - 「何の勉強・作業をしているか」だけを簡潔に説明してください
    - 詳細な内容には触れず「専門的で難しそう」「すごい挑戦」という観点で説明してください
      - 例: 「資格試験の勉強をしている動画です。専門的な内容に取り組んでいて頑張っています。」

2. 一般的な内容（運動、料理、ゲーム、趣味など）の場合：
- 具体的に何をしている動画か説明してください
  - 褒めポイントを含めてください
  - 例: 「ランニングの動画です。良いペースで走っていて、フォームも綺麗です。」

3. 動画内にテキストが含まれる場合でも、そのテキストの一部だけを切り取って解釈しないでください。

【回答形式】
2〜3文で簡潔に説明してください。
`;

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
