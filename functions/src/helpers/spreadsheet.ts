/**
 * Google Spreadsheet関連のヘルパー関数
 */

import { google } from "googleapis";
import { SPREADSHEET_ID } from "../config/constants";
import { sheetsServiceAccountKey } from "../config/secrets";
import { db } from "./firebase";

/**
 * FirestoreからスプレッドシートIDを取得する。
 * 未設定・取得失敗時は constants.ts のフォールバック値を使用。
 */
async function getSpreadsheetId(): Promise<string> {
  try {
    const doc = await db.collection("settings").doc("spreadsheet").get();
    if (doc.exists) {
      const id = doc.data()?.inquirySpreadsheetId;
      if (typeof id === "string" && id.trim().length > 0) {
        return id.trim();
      }
    }
  } catch (error) {
    console.warn(
      "Failed to fetch spreadsheet config from Firestore, using fallback:",
      error
    );
  }
  return SPREADSHEET_ID;
}

/**
 * 問い合わせをGoogleスプレッドシートに追記
 */
export async function appendInquiryToSpreadsheet(data: {
  inquiryId: string;
  userId: string;
  category: string;
  subject: string;
  firstMessage: string;
  conversationLog: string;
  resolvedAt: string;
  resolutionCategory: string;
  remarks: string;
  createdAt: string;
}): Promise<void> {
  try {
    // サービスアカウントキーを取得
    const keyJson = sheetsServiceAccountKey.value();
    if (!keyJson) {
      console.error("SHEETS_SERVICE_ACCOUNT secret not found");
      return;
    }

    const credentials = JSON.parse(keyJson);
    const auth = new google.auth.GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/spreadsheets"],
    });

    const sheets = google.sheets({ version: "v4", auth });

    // 行データを作成
    const row = [
      data.createdAt, // A: 日時
      data.userId, // B: UID
      data.category, // C: カテゴリ
      data.subject, // D: 件名
      data.firstMessage, // E: 内容
      data.conversationLog, // F: 会話全文
      data.resolvedAt, // G: 解決日
      data.resolutionCategory, // H: 解決後カテゴリ
      data.remarks, // I: 備考
    ];

    // スプレッドシートIDを取得（Firestore優先、フォールバックあり）
    const spreadsheetId = await getSpreadsheetId();

    // スプレッドシートに追記
    await sheets.spreadsheets.values.append({
      spreadsheetId,
      range: "A:I",
      valueInputOption: "USER_ENTERED",
      requestBody: {
        values: [row],
      },
    });

    console.log(
      `Appended inquiry ${data.inquiryId} to spreadsheet (${spreadsheetId})`
    );
  } catch (error) {
    console.error("Error appending to spreadsheet:", error);
    // スプレッドシート書き込みエラーは致命的ではないので、スローしない
  }
}
