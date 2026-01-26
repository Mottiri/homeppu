/**
 * 画像モデレーションCallable関数
 * Phase 7: index.ts から分離
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenerativeAI, Part } from "@google/generative-ai";

import { AI_MODELS, LOCATION } from "../config/constants";
import { geminiApiKey } from "../config/secrets";
import { IMAGE_MODERATION_CALLABLE_PROMPT } from "../ai/prompts/moderation";
import { MediaModerationResult } from "../types";

/**
 * アップロード前の画像をモデレーション
 * Base64エンコードされた画像データを受け取り、不適切かどうか判定
 */
export const moderateImageCallable = onCall(
    { secrets: [geminiApiKey], region: LOCATION },
    async (request) => {
        const { imageBase64, mimeType = "image/jpeg" } = request.data;

        if (!imageBase64) {
            throw new HttpsError("invalid-argument", "imageBase64 is required");
        }

        // 認証チェック
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        try {
            const apiKey = geminiApiKey.value();
            const genAI = new GoogleGenerativeAI(apiKey);
            const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

            const prompt = IMAGE_MODERATION_CALLABLE_PROMPT;

            const imagePart: Part = {
                inlineData: {
                    mimeType: mimeType,
                    data: imageBase64,
                },
            };

            const result = await model.generateContent([prompt, imagePart]);
            const responseText = result.response.text().trim();

            let jsonText = responseText;
            // JSONブロックを抽出
            const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
            if (jsonMatch) {
                jsonText = jsonMatch[1];
            }

            const moderationResult = JSON.parse(jsonText) as MediaModerationResult;

            console.log(`Image moderation result: ${JSON.stringify(moderationResult)}`);

            return moderationResult;

        } catch (error) {
            console.error("moderateImageCallable ERROR:", error);
            // エラー時は許可（サービス継続性を優先）
            return {
                isInappropriate: false,
                category: "none",
                confidence: 0,
                reason: "モデレーションエラー",
            };
        }
    }
);
