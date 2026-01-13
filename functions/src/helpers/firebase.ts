/**
 * Firebase Admin SDK 初期化モジュール
 * 全モジュールで共有するFirebaseインスタンスを提供
 */

import * as admin from "firebase-admin";

// 初期化（複数回呼ばれても安全）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// 共有インスタンスをエクスポート
export const db = admin.firestore();
export const auth = admin.auth();
export const storage = admin.storage();

// FieldValue等のユーティリティも再エクスポート
export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;
