/**
 * AI Provider Abstraction Layer
 * OpenAIとGeminiの両方をサポートし、フォールバック機能を提供
 */

import { GoogleGenerativeAI } from "@google/generative-ai";
import * as admin from "firebase-admin";
import { AI_MODELS } from "../config/constants";

// ===============================================
// Types & Interfaces
// ===============================================

export interface AIOptions {
    temperature?: number;
    maxTokens?: number;
    systemPrompt?: string;
}

export interface AIResponse {
    text: string;
    provider: "gemini" | "openai";
    usedFallback: boolean;
}

export interface AISettings {
    primaryProvider: "gemini" | "openai";
    enableFallback: boolean;
}

// ===============================================
// AI Provider Interface
// ===============================================

export interface AIProvider {
    name: "gemini" | "openai";
    generateText(prompt: string, options?: AIOptions): Promise<string>;
    generateWithImage(prompt: string, imageBase64: string, mimeType: string, options?: AIOptions): Promise<string>;
}

// ===============================================
// Gemini Provider Implementation
// ===============================================

export class GeminiProvider implements AIProvider {
    name: "gemini" = "gemini";
    private apiKey: string;

    constructor(apiKey: string) {
        this.apiKey = apiKey;
    }

    async generateText(prompt: string, options?: AIOptions): Promise<string> {
        const genAI = new GoogleGenerativeAI(this.apiKey);
        const model = genAI.getGenerativeModel({
            model: AI_MODELS.GEMINI_DEFAULT,
            generationConfig: {
                temperature: options?.temperature ?? 0.7,
                maxOutputTokens: options?.maxTokens ?? 4096,
            },
        });

        const systemPrompt = options?.systemPrompt || "";
        const fullPrompt = systemPrompt ? `${systemPrompt}\n\n${prompt}` : prompt;

        const result = await model.generateContent(fullPrompt);
        const response = result.response;
        const text = response.text();

        // デバッグ: Geminiのレスポンス詳細をログ出力
        const candidate = response.candidates?.[0];
        console.log("[GEMINI DEBUG]", JSON.stringify({
            finishReason: candidate?.finishReason,
            contentLength: text?.length || 0,
            usageMetadata: response.usageMetadata,
            safetyRatings: candidate?.safetyRatings?.map(r => ({ category: r.category, probability: r.probability })),
        }));

        // finish_reasonがMAX_TOKENSの場合は警告
        if (candidate?.finishReason === "MAX_TOKENS") {
            console.warn("[GEMINI WARNING] Response was truncated due to MAX_TOKENS limit!");
        }

        return text;
    }

    async generateWithImage(prompt: string, imageBase64: string, mimeType: string, options?: AIOptions): Promise<string> {
        const genAI = new GoogleGenerativeAI(this.apiKey);
        const model = genAI.getGenerativeModel({
            model: AI_MODELS.GEMINI_DEFAULT,
            generationConfig: {
                temperature: options?.temperature ?? 0.7,
                maxOutputTokens: options?.maxTokens ?? 4096,
            },
        });

        const imagePart = {
            inlineData: {
                data: imageBase64,
                mimeType: mimeType,
            },
        };

        const systemPrompt = options?.systemPrompt || "";
        const fullPrompt = systemPrompt ? `${systemPrompt}\n\n${prompt}` : prompt;

        const result = await model.generateContent([fullPrompt, imagePart]);
        const response = result.response;
        return response.text();
    }
}

// ===============================================
// OpenAI Provider Implementation
// ===============================================

export class OpenAIProvider implements AIProvider {
    name: "openai" = "openai";
    private apiKey: string;

    constructor(apiKey: string) {
        this.apiKey = apiKey;
    }

    async generateText(prompt: string, options?: AIOptions): Promise<string> {
        const messages: Array<{ role: string; content: string }> = [];

        if (options?.systemPrompt) {
            messages.push({ role: "system", content: options.systemPrompt });
        }
        messages.push({ role: "user", content: prompt });

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({
                model: AI_MODELS.OPENAI_DEFAULT,
                messages: messages,
                temperature: options?.temperature ?? 0.7,
                max_tokens: options?.maxTokens ?? 1024,
            }),
        });

        if (!response.ok) {
            const error = await response.text();
            throw new Error(`OpenAI API error: ${response.status} - ${error}`);
        }

        const data = await response.json() as { choices: Array<{ message: { content: string }, finish_reason?: string }>, usage?: { prompt_tokens: number, completion_tokens: number } };

        // Debug: Log the full response to analyze empty comments
        console.log("OpenAI response:", JSON.stringify({
            hasChoices: !!data.choices?.length,
            finishReason: data.choices?.[0]?.finish_reason,
            contentLength: data.choices?.[0]?.message?.content?.length || 0,
            usage: data.usage,
        }));

        return data.choices[0]?.message?.content || "";
    }

    async generateWithImage(prompt: string, imageBase64: string, mimeType: string, options?: AIOptions): Promise<string> {
        const messages: Array<{ role: string; content: unknown }> = [];

        if (options?.systemPrompt) {
            messages.push({ role: "system", content: options.systemPrompt });
        }

        messages.push({
            role: "user",
            content: [
                { type: "text", text: prompt },
                {
                    type: "image_url",
                    image_url: {
                        url: `data:${mimeType};base64,${imageBase64}`,
                    },
                },
            ],
        });

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({
                model: AI_MODELS.OPENAI_DEFAULT,
                messages: messages,
                temperature: options?.temperature ?? 0.7,
                max_tokens: options?.maxTokens ?? 1024,
            }),
        });

        if (!response.ok) {
            const error = await response.text();
            throw new Error(`OpenAI API error: ${response.status} - ${error}`);
        }

        const data = await response.json() as { choices: Array<{ message: { content: string } }> };
        return data.choices[0]?.message?.content || "";
    }
}

// ===============================================
// AI Provider Factory with Fallback
// ===============================================

export class AIProviderFactory {
    private geminiProvider: GeminiProvider | null = null;
    private openaiProvider: OpenAIProvider | null = null;
    private settings: AISettings | null = null;
    private settingsLoadedAt: number = 0;
    private readonly SETTINGS_CACHE_TTL = 60000; // 1分キャッシュ

    constructor(
        geminiApiKey: string,
        openaiApiKey: string
    ) {
        if (geminiApiKey) {
            this.geminiProvider = new GeminiProvider(geminiApiKey);
        }
        if (openaiApiKey) {
            this.openaiProvider = new OpenAIProvider(openaiApiKey);
        }
    }

    /**
     * Firestore から設定を読み込む（キャッシュ付き）
     */
    private async loadSettings(): Promise<AISettings> {
        const now = Date.now();
        if (this.settings && (now - this.settingsLoadedAt) < this.SETTINGS_CACHE_TTL) {
            return this.settings;
        }

        try {
            const db = admin.firestore();
            const doc = await db.collection("settings").doc("ai").get();
            if (doc.exists) {
                const data = doc.data();
                this.settings = {
                    primaryProvider: data?.primaryProvider || "openai",
                    enableFallback: data?.enableFallback !== false, // デフォルトtrue
                };
            } else {
                // デフォルト設定
                this.settings = {
                    primaryProvider: "openai",
                    enableFallback: true,
                };
            }
            this.settingsLoadedAt = now;
            return this.settings;
        } catch (error) {
            console.error("Failed to load AI settings:", error);
            // エラー時はデフォルト設定
            return {
                primaryProvider: "openai",
                enableFallback: true,
            };
        }
    }

    /**
     * プロバイダーを取得
     */
    private getProvider(name: "gemini" | "openai"): AIProvider | null {
        if (name === "gemini") return this.geminiProvider;
        if (name === "openai") return this.openaiProvider;
        return null;
    }

    /**
     * テキスト生成（フォールバック付き）
     */
    async generateText(prompt: string, options?: AIOptions): Promise<AIResponse> {
        const settings = await this.loadSettings();
        const primaryName = settings.primaryProvider;
        const fallbackName = primaryName === "gemini" ? "openai" : "gemini";

        const primary = this.getProvider(primaryName);
        const fallback = settings.enableFallback ? this.getProvider(fallbackName) : null;

        // プライマリで試行
        if (primary) {
            try {
                const text = await primary.generateText(prompt, options);
                return { text, provider: primaryName, usedFallback: false };
            } catch (error) {
                console.error(`Primary provider (${primaryName}) failed:`, error);
                if (!fallback) throw error;
            }
        }

        // フォールバックで試行
        if (fallback) {
            try {
                console.log(`Falling back to ${fallbackName}...`);
                const text = await fallback.generateText(prompt, options);
                return { text, provider: fallbackName, usedFallback: true };
            } catch (error) {
                console.error(`Fallback provider (${fallbackName}) failed:`, error);
                throw error;
            }
        }

        throw new Error("No AI provider available");
    }

    /**
     * 画像付きテキスト生成（フォールバック付き）
     */
    async generateWithImage(
        prompt: string,
        imageBase64: string,
        mimeType: string,
        options?: AIOptions
    ): Promise<AIResponse> {
        const settings = await this.loadSettings();
        const primaryName = settings.primaryProvider;
        const fallbackName = primaryName === "gemini" ? "openai" : "gemini";

        const primary = this.getProvider(primaryName);
        const fallback = settings.enableFallback ? this.getProvider(fallbackName) : null;

        // プライマリで試行
        if (primary) {
            try {
                const text = await primary.generateWithImage(prompt, imageBase64, mimeType, options);
                return { text, provider: primaryName, usedFallback: false };
            } catch (error) {
                console.error(`Primary provider (${primaryName}) failed:`, error);
                if (!fallback) throw error;
            }
        }

        // フォールバックで試行
        if (fallback) {
            try {
                console.log(`Falling back to ${fallbackName}...`);
                const text = await fallback.generateWithImage(prompt, imageBase64, mimeType, options);
                return { text, provider: fallbackName, usedFallback: true };
            } catch (error) {
                console.error(`Fallback provider (${fallbackName}) failed:`, error);
                throw error;
            }
        }

        throw new Error("No AI provider available");
    }
}
