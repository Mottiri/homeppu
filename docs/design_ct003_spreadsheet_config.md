# CT-003: スプレッドシートID Firestore Config化 詳細設計書

## スコープ
- **対象**: スプレッドシートIDのハードコードをFirestore Config化し、運用での切替を容易にする
- **非対象**: スプレッドシートの認証情報（SHEETS_SERVICE_ACCOUNT）は既にFirebase Secretで管理されており変更不要

## 問題
- スプレッドシートIDが `functions/src/config/constants.ts` にハードコードされている
- スプレッドシートを切り替えるにはソースコード変更＋デプロイが必要
- 運用上、問い合わせ記録用スプレッドシートの切替を容易にしたい

## 方針
Firestoreの `settings` コレクションに設定ドキュメントを配置し、実行時に読み取る。

### Firestoreドキュメント構造
```
settings/spreadsheet
{
  "inquirySpreadsheetId": "<SPREADSHEET_ID>"
}
```

- `settings` コレクションは既に `COLLECTIONS.SETTINGS` として定義済み
- ドキュメント名は `spreadsheet`（将来的に他のスプレッドシート設定も追加可能）

### フォールバック
- Firestoreからの取得に失敗した場合、現在のハードコード値をフォールバックとして使用
- これによりFirestoreに設定がまだ登録されていない状態でも動作する

## 修正対象ファイル

### 1. `functions/src/helpers/spreadsheet.ts`（主な変更）

**変更内容**:
- `SPREADSHEET_ID` の静的インポートを削除
- Firestoreから `settings/spreadsheet` ドキュメントを読み取り、`inquirySpreadsheetId` を取得
- 取得失敗時は `constants.ts` のフォールバック値を使用
- ログで使用中のスプレッドシートIDを出力（運用確認用）

```typescript
// Before
import { SPREADSHEET_ID } from "../config/constants";
// ...
spreadsheetId: SPREADSHEET_ID,

// After
import { db } from "./firebase";
import { SPREADSHEET_ID } from "../config/constants"; // フォールバック用

async function getSpreadsheetId(): Promise<string> {
  try {
    const doc = await db.collection("settings").doc("spreadsheet").get();
    if (doc.exists) {
      const id = doc.data()?.inquirySpreadsheetId;
      if (typeof id === "string" && id.length > 0) {
        return id;
      }
    }
  } catch (error) {
    console.warn("Failed to fetch spreadsheet config from Firestore, using fallback:", error);
  }
  return SPREADSHEET_ID;
}
```

### 2. `functions/src/config/constants.ts`（変更なし）
- `SPREADSHEET_ID` はフォールバック値として残す
- コメントを追加して、Firestoreが優先されることを明記

## 処理フロー

```
appendInquiryToSpreadsheet() 呼び出し
  ↓
getSpreadsheetId() 実行
  ↓
Firestore settings/spreadsheet を読み取り
  ↓ 成功 → inquirySpreadsheetId を使用
  ↓ 失敗 or 未設定 → constants.ts の SPREADSHEET_ID を使用
  ↓
Google Sheets API で追記
```

## 運用手順（切替時）

### Firebaseコンソールから
1. Firestore → `settings` コレクション → `spreadsheet` ドキュメント
2. `inquirySpreadsheetId` フィールドを新しいスプレッドシートIDに更新
3. 次の問い合わせ解決時から新しいスプレッドシートに書き込まれる

### CLIから
```bash
# Firebase Admin SDKやfirebaseコマンドで設定
```

## テスト観点
- Firestoreに設定がある場合、その値が使われること
- Firestoreに設定がない場合、フォールバック値が使われること
- Firestoreの読み取りエラー時にフォールバックすること
- スプレッドシートへの書き込みが正常に動作すること
