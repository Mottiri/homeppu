import { defineSecret } from "firebase-functions/params";

// Gemini API Key
export const geminiApiKey = defineSecret("GEMINI_API_KEY");

// OpenAI API Key
export const openaiApiKey = defineSecret("OPENAI_API_KEY");

// Google Sheets サービスアカウントキー
export const sheetsServiceAccountKey = defineSecret("SHEETS_SERVICE_ACCOUNT");
