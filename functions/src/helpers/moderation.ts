/**
 * メディアモデレーション関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import * as https from "https";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { GoogleGenerativeAI, Part } from "@google/generative-ai";
import { GoogleAIFileManager } from "@google/generative-ai/server";
import { MediaModerationResult, MediaItem } from "../types";

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

        const prompt = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容、血まみれ
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
JSON形式のみで回答:
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "理由"}
`;

        const imagePart: Part = {
            inlineData: {
                mimeType: mimeType,
                data: base64Image,
            },
        };

        const result = await model.generateContent([prompt, imagePart]);
        const responseText = result.response.text().trim();
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
 * 動画をモデレーション
 */
export async function moderateVideo(
    apiKey: string,
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    videoUrl: string,
    mimeType: string = "video/mp4"
): Promise<MediaModerationResult> {
    const tempFilePath = path.join(os.tmpdir(), `video_${Date.now()}.mp4`);

    try {
        // 動画をダウンロード
        const videoBuffer = await downloadFile(videoUrl);
        fs.writeFileSync(tempFilePath, videoBuffer);

        // Gemini File APIにアップロード
        const fileManager = new GoogleAIFileManager(apiKey);
        const uploadResult = await fileManager.uploadFile(tempFilePath, {
            mimeType: mimeType,
            displayName: `moderation_video_${Date.now()} `,
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
この動画がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い映像、性的な内容
- violence: 暴力的な映像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な内容
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
必ず以下のJSON形式のみで回答してください：
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "判定理由"}
`;

        const videoPart: Part = {
            fileData: {
                mimeType: file.mimeType,
                fileUri: file.uri,
            },
        };

        const result = await model.generateContent([prompt, videoPart]);
        const responseText = result.response.text().trim();

        let jsonText = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
            jsonText = jsonMatch[1];
        } else {
            const braceMatch = responseText.match(/\{[\s\S]*\}/);
            if (braceMatch) {
                jsonText = braceMatch[0];
            }
        }

        // アップロードしたファイルを削除
        try {
            await fileManager.deleteFile(file.name);
        } catch (e) {
            console.log("Failed to delete uploaded file:", e);
        }

        return JSON.parse(jsonText) as MediaModerationResult;
    } catch (error) {
        console.error("Video moderation error:", error);
        // エラー時は許可
        return {
            isInappropriate: false,
            category: "none",
            confidence: 0,
            reason: "モデレーションエラー",
        };
    } finally {
        // 一時ファイルを削除
        if (fs.existsSync(tempFilePath)) {
            fs.unlinkSync(tempFilePath);
        }
    }
}

/**
 * メディアアイテムをモデレーション
 */
export async function moderateMedia(
    apiKey: string,
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    mediaItems: MediaItem[]
): Promise<{ passed: boolean; failedItem?: MediaItem; result?: MediaModerationResult }> {
    for (const item of mediaItems) {
        if (item.type === "image") {
            const result = await moderateImage(model, item.url, item.mimeType || "image/jpeg");
            if (result.isInappropriate && result.confidence >= 0.7) {
                return { passed: false, failedItem: item, result };
            }
        } else if (item.type === "video") {
            const result = await moderateVideo(apiKey, model, item.url, item.mimeType || "video/mp4");
            if (result.isInappropriate && result.confidence >= 0.7) {
                return { passed: false, failedItem: item, result };
            }
        }
        // fileタイプはスキップ（PDFなどのモデレーションは複雑なため）
    }

    return { passed: true };
}
