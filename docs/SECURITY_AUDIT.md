# セキュリティ監査レポート

**作成日**: 2026年1月7日
**最終更新**: 2026年1月12日（#15 Cloud Tasks OIDC認証対応完了）
**対象**: homeppu プロジェクト
**監査範囲**: Firestore/Storage セキュリティルール、Cloud Functions、クライアントコード、設計書整合性

---

## 概要

本レポートは、homeppuプロジェクトのセキュリティ監査結果をまとめたものです。発見された問題を重大度別に分類し、推奨される修正方針を記載しています。

**発見された問題数**: 21件
- 重大: 5件
- 高: 4件
- 中: 4件
- 低: 6件
- 情報: 2件

---

## 発見された問題一覧

| # | 重大度 | 問題 | 影響範囲 |
|---|--------|------|----------|
| 1 | **重大** | Firestoreルールの重複定義 | `firebase/firestore.rules` |
| 2 | **重大** | 問い合わせ添付画像が全ユーザー閲覧可能 | `firebase/storage.rules` |
| 3 | **重大** | namePartsコレクションのルール未定義 | `firebase/firestore.rules` |
| 4 | **重大** | ハードコードされた管理者シークレット | `functions/src/index.ts` |
| 5 | **高** | initializeNamePartsに認証チェックなし | `functions/src/index.ts` |
| 6 | **高** | 複数の管理者用Cloud Functionsに認証チェックなし | `functions/src/index.ts` |
| 7 | **高** | deleteAllAIUsersに管理者チェックなし | `functions/src/index.ts` |
| 8 | **中** | Storageの後方互換性パスで他者ファイル削除可能 | `firebase/storage.rules` |
| 9 | **中** | サークル画像が認証済みユーザーなら誰でも削除可能 | `firebase/storage.rules` |
| 10 | **低** | ユーザーのメールアドレスが全ユーザーに公開 | `firebase/firestore.rules` |
| 11 | **低** | Google SheetsスプレッドシートIDのハードコード | `functions/src/index.ts` |
| 12 | **中** | google-services.jsonが.gitignoreに未登録 | `.gitignore`, `android/app/` |
| 13 | **低** | banAppealsとban_appealsの重複コレクション | `firebase/firestore.rules` |
| 14 | **情報** | Firebase設定のクライアントサイド露出 | `lib/firebase_options.dart` |
| 15 | ~~**中**~~ | ~~onRequest関数の認証が不十分~~ ✅ 完了 | `functions/src/index.ts` |
| 16 | **高** | createPostWithRateLimitの入力バリデーション不足 | `functions/src/index.ts` |
| 17 | **低** | App Checkが無効になっている関数あり | `functions/src/index.ts` |
| 18 | **情報** | 一部コレクションの明示的ルール未定義 | `firebase/firestore.rules` |
| 19 | **低** | デバッグログにAIプロンプト情報が出力 | `functions/src/index.ts` |
| 20 | **低** | google-services_BU.jsonバックアップファイル | `android/app/` |
| 21 | **重大** | AIモードサークルの一覧表示制限が未実装 | `firebase/firestore.rules` |

---

## 問題詳細

### 1. 【重大】Firestoreルールの重複定義

**ファイル**: `firebase/firestore.rules`

**問題内容**:  
以下のコレクションが2回定義されており、後のルールが前のルールを上書きしています。

| コレクション | 1回目の定義 | 2回目の定義 |
|-------------|-------------|-------------|
| `posts` | 行97-145 | 行224-254 |
| `circles` | 行148-168 | 行294-322 |
| `circleJoinRequests` | 行170-191 | 行324-346 |

**リスク**:  
- ルールの意図しない上書きにより、セキュリティチェックが無効化される可能性
- 1回目の`posts`ルールでは`isNotBanned()`チェックがあるが、2回目にはBANチェックがない箇所がある
- メンテナンス時の混乱と誤設定のリスク

**推奨対応**:  
重複を解消し、各コレクションに対して単一の統合されたルールを定義する。

---

### 2. 【重大】問い合わせ添付画像が全ユーザー閲覧可能

**ファイル**: `firebase/storage.rules` 行149-157

**現在のルール**:
```javascript
match /inquiries/{fileName} {
  allow read: if isAuthenticated();  // ← 問題
  allow write: if isAuthenticated()
               && isValidProfileSize()
               && isImage();
  allow delete: if isAdmin();
}
```

**リスク**:  
- 認証済みユーザーであれば誰でも他人の問い合わせ添付画像を閲覧可能
- 問い合わせには個人情報やセンシティブな内容（スクリーンショット等）が含まれる可能性
- **プライバシー侵害のリスクが極めて高い**

**推奨対応**:  
パスにユーザーIDを含め、本人または管理者のみ読み取り可能にする。

```javascript
// 推奨される修正案
match /inquiries/{userId}/{fileName} {
  allow read: if isAuthenticated() && (request.auth.uid == userId || isAdmin());
  allow write: if isAuthenticated() 
               && request.auth.uid == userId 
               && isValidProfileSize() 
               && isImage();
  allow delete: if isAdmin();
}
```

**注意**: この修正を行う場合、クライアント側のアップロードパスも変更が必要。

---

### 3. 【重大】namePartsコレクションのルール未定義

**ファイル**: `firebase/firestore.rules`

**問題内容**:  
`nameParts`コレクションに対するセキュリティルールが定義されていません。

**リスク**:  
- Firestoreはデフォルトで全アクセス拒否だが、明示的なルールがないと意図が不明確
- 将来のルール変更時に誤って全アクセス許可してしまうリスク

**推奨対応**:
```javascript
match /nameParts/{partId} {
  allow read: if isAuthenticated();
  allow write: if false;  // Cloud Functionsのみ
}
```

---

### 4. 【重大】ハードコードされた管理者シークレット

**ファイル**: `functions/src/index.ts` 行4142付近

**現在のコード**:
```typescript
export const cleanUpUserFollows = functionsV1.region("asia-northeast1").https.onRequest(async (request, response) => {
  const key = request.query.key;
  if (key !== "admin_secret_homeppu_2025") {  // ← ハードコード
    response.status(403).send("Forbidden");
    return;
  }
  // ...
});
```

**リスク**:  
- ソースコードにアクセスできる人（開発者、リポジトリアクセス者）がこのシークレットを知ることができる
- GitHubなどにpushされた場合、履歴に永久に残る
- シークレットのローテーションが困難

**推奨対応**:  
Firebase Functions Secrets（`defineSecret`）または環境変数を使用する。

```typescript
import { defineSecret } from "firebase-functions/params";

const adminSecret = defineSecret("ADMIN_SECRET");

export const cleanUpUserFollows = functionsV1.region("asia-northeast1")
  .runWith({ secrets: [adminSecret] })
  .https.onRequest(async (request, response) => {
    if (request.query.key !== adminSecret.value()) {
      response.status(403).send("Forbidden");
      return;
    }
    // ...
  });
```

---

### 5. 【高】initializeNamePartsに認証チェックなし

**ファイル**: `functions/src/index.ts` 行3211付近

**現在のコード**:
```typescript
export const initializeNameParts = onCall(
  { region: "asia-northeast1" },
  async () => {
    // 認証チェックなし
    const batch = db.batch();
    // ...
  }
);
```

**リスク**:  
- 管理者用の初期化関数だが、認証も権限チェックもない
- 誰でも呼び出してデータを上書き可能

**推奨対応**:
```typescript
export const initializeNameParts = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }
    // ...
  }
);
```

---

### 6. 【高】複数の管理者用Cloud Functionsに認証チェックなし

**ファイル**: `functions/src/index.ts`

**問題内容**:  
以下の管理者用Cloud Functionsに認証チェックがなく、誰でも呼び出し可能です。

| 関数名 | 行番号 | 機能 |
|--------|--------|------|
| `initializeAIAccounts` | 1783 | AIアカウントを初期化（20体生成） |
| `generateAIPosts` | 1900 | AI投稿を生成 |
| `cleanupOrphanedCircleAIs` | 4293 | 孤児サークルAIを削除 |
| `triggerCircleAIPosts` | 6056 | サークルAI投稿を手動トリガー |
| `triggerEvolveCircleAIs` | 6293 | サークルAI成長を手動トリガー |

**現在のコード例**:
```typescript
export const initializeAIAccounts = onCall(
  { region: "asia-northeast1", secrets: [geminiApiKey], timeoutSeconds: 300 },
  async () => {
    // 認証チェックなし - 誰でも呼び出し可能
    const apiKey = geminiApiKey.value();
    // ...
  }
);
```

**リスク**:  
- 認証されていないユーザーがAIアカウントやAI投稿を操作可能
- 悪意あるユーザーがデータを破壊または汚染できる
- APIコスト（Gemini API）を不正に消費される可能性

**推奨対応**:  
すべての管理者用関数に認証・権限チェックを追加する。

```typescript
export const initializeAIAccounts = onCall(
  { region: "asia-northeast1", secrets: [geminiApiKey], timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }
    // ...
  }
);
```

---

### 7. 【高】deleteAllAIUsersに管理者チェックなし

**ファイル**: `functions/src/index.ts` 行4200付近

**現在のコード**:
```typescript
export const deleteAllAIUsers = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 540,
  memory: "1GB"
}).https.onCall(async (data, context) => {
  // 簡易セキュリティ: ログイン必須
  if (!context.auth) {
    throw new functionsV1.https.HttpsError("unauthenticated", "ログインが必要です");
  }
  // 管理者チェックがない
  // ...
});
```

**リスク**:  
- ログインしていれば誰でも全AIユーザーとその投稿・コメント・リアクションを削除可能
- サービス全体のデータ破壊につながる重大なリスク

**推奨対応**:
```typescript
// 管理者チェックを追加
if (!context.auth) {
  throw new functionsV1.https.HttpsError("unauthenticated", "ログインが必要です");
}
const userIsAdmin = await isAdmin(context.auth.uid);
if (!userIsAdmin) {
  throw new functionsV1.https.HttpsError("permission-denied", "管理者権限が必要です");
}
```

---

### 8. 【中】Storageの後方互換性パスで他者ファイル削除可能

**ファイル**: `firebase/storage.rules` 行120-128

**現在のルール**:
```javascript
match /posts/{postId}/{fileName} {
  allow read: if isAuthenticated();
  allow write: if isAuthenticated() 
               && isValidImageSize() 
               && isImage();
  allow delete: if isAuthenticated();  // ← 問題：誰でも削除可能
}
```

**リスク**:  
- 認証済みユーザーなら他人の投稿画像を削除可能
- 悪意あるユーザーによるデータ破壊のリスク

**推奨対応**:  
後方互換性パスを廃止するか、削除を管理者のみに制限する。

```javascript
allow delete: if isAdmin();
```

---

### 9. 【中】サークル画像が認証済みユーザーなら誰でも削除可能

**ファイル**: `firebase/storage.rules` 行130-138

**現在のルール**:
```javascript
match /circles/{circleId}/{imageType}/{fileName} {
  allow read: if isAuthenticated();
  allow write: if isAuthenticated() 
               && isValidProfileSize() 
               && isImage();
  allow delete: if isAuthenticated();  // ← 問題：誰でも削除可能
}
```

**リスク**:  
- サークルオーナー以外でもサークル画像を削除可能
- 他サークルの画像を悪意を持って削除される可能性

**推奨対応**:  
削除は管理者のみに制限し、オーナーによる削除はCloud Functions経由で行う。

---

### 10. 【低】ユーザーのメールアドレスが全ユーザーに公開

**ファイル**: `firebase/firestore.rules` 行46-48

**現在のルール**:
```javascript
match /users/{userId} {
  allow read: if isAuthenticated();
  // ...
}
```

**リスク**:  
- ユーザードキュメントに`email`フィールドが含まれる
- 認証済みユーザーなら誰でも他ユーザーのメールアドレスを取得可能
- プライバシーリスク（軽度）

**推奨対応**:  
以下のいずれかを検討：
1. クライアント側で`email`フィールドを取得しない（select句なし）
2. Firestoreルールでフィールドレベルの制限は不可のため、emailを別コレクションに分離
3. リスクを許容（SNSではメアドの公開は一般的でないが、表示名等は必要）

---

### 11. 【低】Google SheetsスプレッドシートIDのハードコード

**ファイル**: `functions/src/index.ts` 行28

**現在のコード**:
```typescript
const SPREADSHEET_ID = "1XsgrEmsdIkc5Cd_y8sIkBXFImshHPbqqxwJu9wWv4BY";
```

**リスク**:  
- スプレッドシートIDがソースコードに公開されている
- ただし、アクセスはサービスアカウント（`sheetsServiceAccountKey`）で制御されているため、**リスクは低い**
- スプレッドシートの共有設定が適切であれば問題なし

**推奨対応**:  
環境変数または Secrets Manager に移行することが望ましいが、優先度は低い。
共有設定で「サービスアカウントのみ編集可能」となっていることを確認すること。

---

### 12. 【中】google-services.jsonが.gitignoreに未登録

**ファイル**: `.gitignore`, `android/app/google-services.json`

**問題内容**:  
Androidの`google-services.json`ファイルが`.gitignore`に含まれていないため、GitHubなどに公開される可能性があります。

**リスク**:  
- Firebase プロジェクトの設定情報（APIキー、プロジェクトID等）が公開される
- 直接的な攻撃にはつながりにくいが、プロジェクト情報の漏洩
- 他のセキュリティ対策（Firestoreルール等）が適切であれば影響は限定的

**推奨対応**:  
`.gitignore`に以下を追加：
```
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

**注意**: 既にコミットされている場合は履歴から削除が必要。

---

### 13. 【低】banAppealsとban_appealsの重複コレクション

**ファイル**: `firebase/firestore.rules` 行75-94, 393-434

**問題内容**:  
`banAppeals`（camelCase）と`ban_appeals`（snake_case）の両方にルールが定義されています。

**リスク**:  
- どちらのコレクションが実際に使用されているか不明確
- メンテナンス時の混乱
- セキュリティ上の問題は軽度（両方とも適切な権限チェックあり）

**推奨対応**:  
実際に使用しているコレクション名を確認し、不要なルールを削除する。

---

### 14. 【情報】Firebase設定のクライアントサイド露出

**ファイル**: `lib/firebase_options.dart`

**問題内容**:  
Firebase APIキーやプロジェクトIDがクライアントサイドコードに含まれています。

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSy...',  // ← 公開される
  appId: '1:632480860678:android:...',
  messagingSenderId: '632480860678',
  projectId: 'positive-sns',
  storageBucket: 'positive-sns.firebasestorage.app',
);
```

**リスク**:  
- **これはFirebaseの設計上正常です** - Firebaseはクライアントサイドでの使用を想定
- APIキーだけでは不正操作はできない（Firestore/Storage/Authルールで保護）
- ただし、`.gitignore`に入っていて良い（自動生成ファイル）

**結論**:  
`.gitignore`に`firebase_options.dart`が含まれているため、リポジトリには通常公開されない。ただし、ビルドしたアプリには含まれるため、Firestore/Storage/Authのルールでの保護が重要。

**推奨対応**:  
特に対応不要。ただし、以下を確認すること：
1. Firestoreルールが適切に設定されている
2. Storageルールが適切に設定されている  
3. Firebase Authentication の設定が適切
4. App Check の導入を検討（不正クライアントからのリクエストをブロック）

---

### 15. 【中】onRequest関数の認証が不十分

**ファイル**: `functions/src/index.ts`

**問題内容**:  
以下の`onRequest`（HTTP関数）は、適切な認証チェックが不十分です：

| 関数名 | 行番号 | 問題 |
|--------|--------|------|
| `generateAIReactionV1` | 4074 | Cloud Tasksからの呼び出しを想定しているが、誰でもアクセス可能 |
| `cleanUpUserFollows` | 4140 | ハードコードシークレット（#4で既出） |
| `executeGoalReminder` | 6820 | Bearer tokenチェックはあるが、トークンの検証が不十分 |

**現在のコード (executeGoalReminder)**:
```typescript
export const executeGoalReminder = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).send("Unauthorized");
      return;
    }
    // トークンの検証がない - Cloud Tasksのサービスアカウント検証が必要
    // ...
  }
);
```

**リスク**:  
- 任意のBearerトークンを送信すれば認証をバイパス可能
- Cloud Tasks以外からの不正なリクエストを受け入れる可能性

**推奨対応**:  
Cloud Tasksからの呼び出しには、OIDCトークンを使用し、正しく検証する：

```typescript
import { OAuth2Client } from "google-auth-library";

const client = new OAuth2Client();

async function verifyCloudTasksToken(req: Request): Promise<boolean> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return false;
  }
  const token = authHeader.split("Bearer ")[1];
  try {
    const ticket = await client.verifyIdToken({
      idToken: token,
      audience: `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/executeGoalReminder`,
    });
    return true;
  } catch {
    return false;
  }
}
```

---

### 16. 【高】createPostWithRateLimitの入力バリデーション不足

**ファイル**: `functions/src/index.ts` 行2097-2106

**現在のコード**:
```typescript
const data = request.data;
// ...（レート制限チェック）...

// 投稿を作成
const postRef = db.collection("posts").doc();
await postRef.set({
  ...data,  // ← クライアントからのデータをそのまま展開
  userId: userId,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
  commentCount: 0,
  isVisible: true,
});
```

**リスク**:  
- クライアントから任意のフィールドを送信可能
- `isBanned: true`や`virtue: 99999`など、保護されるべきフィールドを含めて送信できる可能性
- ただし、投稿ドキュメントにはこれらのフィールドがないため、直接的な影響は低い
- 予期しないフィールドがFirestoreに保存される可能性

**推奨対応**:  
許可されたフィールドのみを明示的に抽出する。

```typescript
const { content, userDisplayName, userAvatarIndex, postMode, circleId, mediaItems } = request.data;

await postRef.set({
  content: content || "",
  userDisplayName: userDisplayName || "Unknown",
  userAvatarIndex: userAvatarIndex || 0,
  postMode: postMode || "mixed",
  circleId: circleId || null,
  mediaItems: Array.isArray(mediaItems) ? mediaItems : [],
  userId: userId,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
  commentCount: 0,
  isVisible: true,
});
```

---

### 17. 【低】App Checkが無効になっている関数あり

**ファイル**: `functions/src/index.ts` 行4010

**現在のコード**:
```typescript
export const addUserReaction = onCall(
  { region: LOCATION, enforceAppCheck: false },  // ← App Check無効
  async (request) => {
    // ...
  }
);
```

**リスク**:  
- App Checkが無効の場合、不正なクライアント（カスタムスクリプト等）からのリクエストをブロックできない
- ボットによる大量リクエストのリスク

**推奨対応**:  
本番環境ではApp Checkを有効化することを検討する。ただし、開発中は無効のままで問題ない。

```typescript
export const addUserReaction = onCall(
  { region: LOCATION, enforceAppCheck: true },  // 本番環境では有効化
  async (request) => {
    // ...
  }
);
```

---

### 18. 【情報】一部コレクションの明示的ルール未定義

**ファイル**: `firebase/firestore.rules`

**問題内容**:  
以下のコレクションは明示的なルールが定義されていませんが、Firestoreのデフォルト動作（全アクセス拒否）により保護されています。

| コレクション | 用途 | 現状 |
|-------------|------|------|
| `sentReminders` | リマインダー送信履歴 | Cloud Functionsのみ使用 |
| `aiPostHistory` | AI投稿履歴 | Cloud Functionsのみ使用 |
| `inquiry_archives` | 問い合わせアーカイブ | Cloud Functionsのみ使用 |
| `nameParts` | 名前パーツマスタ | Cloud Functionsのみ使用 |

**リスク**:  
- Firestoreはルール未定義のコレクションへのクライアントアクセスを拒否するため、**セキュリティリスクは低い**
- ただし、明示的なルールがないとメンテナンス時に意図が不明確になる可能性

**推奨対応**:  
明示的に「Cloud Functionsのみ」と定義することで意図を明確にする。

```javascript
// 内部専用コレクション（Cloud Functionsのみ）
match /sentReminders/{docId} {
  allow read, write: if false;
}

match /aiPostHistory/{docId} {
  allow read, write: if false;
}

match /inquiry_archives/{docId} {
  allow read, write: if false;
}

match /nameParts/{partId} {
  allow read: if isAuthenticated();
  allow write: if false;
}
```

---

### 19. 【低】デバッグログにAIプロンプト情報が出力

**ファイル**: `functions/src/index.ts` 行3775-3777, `functions/src/ai/provider.ts` 行71, 153

**問題内容**:  
Cloud Functionsのログに `[AI PROMPT DEBUG]` や `[GEMINI DEBUG]` としてAIへのプロンプト全文が出力されています。

**現在のコード**:
```typescript
console.log(`[AI PROMPT DEBUG] ===== PROMPT START =====`);
console.log(prompt);
console.log(`[AI PROMPT DEBUG] ===== PROMPT END =====`);
```

**リスク**:  
- 本番環境のCloud Logsにプロンプト内容が永続的に記録される
- プロンプトにはユーザーの投稿内容やコメント内容が含まれる場合がある
- ログへのアクセス権がある人物がユーザーコンテンツを閲覧可能
- **セキュリティリスクは低い**（ログアクセスには管理者権限が必要なため）

**推奨対応**:  
本番環境ではデバッグログを無効化する、または環境変数で制御する。

```typescript
// 環境変数でデバッグモードを制御
const DEBUG_MODE = process.env.DEBUG_MODE === 'true';

if (DEBUG_MODE) {
  console.log(`[AI PROMPT DEBUG] ===== PROMPT START =====`);
  console.log(prompt);
  console.log(`[AI PROMPT DEBUG] ===== PROMPT END =====`);
}
```

---

### 20. 【低】google-services_BU.jsonバックアップファイル

**ファイル**: `android/app/google-services_BU.json`

**問題内容**:  
Firebase設定ファイルのバックアップが `google-services_BU.json` として存在し、`.gitignore` に含まれていないため、リポジトリにコミットされる可能性があります。

**リスク**:  
- Firebase プロジェクト設定情報が公開される
- **セキュリティリスクは低い**（設定情報だけでは攻撃は困難、Firestoreルール等で保護）
- ただし、不要なファイルがリポジトリに含まれるのは好ましくない

**推奨対応**:  
1. 不要であれば `google-services_BU.json` を削除する
2. または `.gitignore` に追加する

```
# .gitignore に追加
android/app/google-services*.json
ios/Runner/GoogleService-Info*.plist
```

---

### 21. 【重大】AIモードサークルの一覧表示制限が未実装

**ファイル**: `firebase/firestore.rules` 行208-236

**問題内容**:
設計書（`docs/design/implementation_plan.md`）では、AIモードサークル（`aiMode: "aiOnly"`）は作成者のみ表示すべきと規定されていますが、Firestoreルールでは全認証ユーザーが読み取り可能になっています。

**現在のルール**:
```javascript
match /circles/{circleId} {
  // 読み取り: 認証済みユーザーは誰でも（クライアント側でフィルタリング）
  allow read: if isAuthenticated();  // ← 問題
  // ...
}
```

**クライアント側の実装** (`lib/shared/services/circle_service.dart:60-64`):
```dart
// クライアント側でフィルター（セキュリティ的に不十分）
.where((c) => c.aiMode != CircleAIMode.aiOnly || c.ownerId == userId)
```

**リスク**:
- **プライバシー侵害**: AIモードサークルは個人の練習用空間として設計されており、他人に見られることは想定されていない
- **セキュリティルール違反**: クライアント側フィルターのみではFirestore REST API経由でのアクセスを防げない
- **設計違反**: 設計書の要件「AIモードサークルは作成者のみ一覧表示」を満たしていない

**攻撃シナリオ**:
```bash
# Firestore REST API経由でアクセス可能
curl -X GET \
  'https://firestore.googleapis.com/v1/projects/positive-sns/databases/(default)/documents/circles' \
  -H 'Authorization: Bearer <ユーザーの認証トークン>'

# レスポンス: 全サークル（AIモード含む）が返される
# → 他人の個人的な目標・練習内容が露出
```

**推奨対応**:
Firestoreルールにサーバー側保護を追加する。

```javascript
match /circles/{circleId} {
  // 修正: AIモードサークルは作成者のみ読み取り可能
  allow read: if isAuthenticated() && (
    resource.data.aiMode != "aiOnly" ||
    resource.data.ownerId == request.auth.uid ||
    isAdmin()
  );

  // 他のルールは変更なし
  allow create: if isAuthenticated() && (isNotBanned() || isAdmin());
  allow update: if isAuthenticated() && (
    (isOwner(resource.data.ownerId) && isNotBanned()) ||
    isAdmin() ||
    // ... 以下略
  );
  allow delete: if isAuthenticated() && (
    (isOwner(resource.data.ownerId) && isNotBanned()) ||
    isAdmin()
  );
}
```

**影響範囲**:
- **修正箇所**: `firebase/firestore.rules` の1行のみ
- **クライアント側**: 変更不要（既存フィルターはそのまま）
- **テスト**: AIモードサークルの閲覧権限テストが必要

---

## 修正優先度

| 優先度 | 対応項目 |
|--------|----------|
| **最優先** | #21 AIモードサークルの一覧表示制限（設計違反） |
| **最優先** | #2 問い合わせ添付画像の閲覧制限 |
| **最優先** | #7 deleteAllAIUsersに管理者チェック追加 |
| **最優先** | #1 Firestoreルール重複の解消 |
| **最優先** | #4 ハードコードシークレットの移行 |
| **高** | #6 管理者用Cloud Functions全般に認証チェック追加 |
| **高** | #3 namePartsルールの追加 |
| **高** | #5 initializeNamePartsの認証追加 |
| **高** | #16 createPostWithRateLimitの入力バリデーション |
| **中** | #8, #9 Storage削除権限の見直し |
| **中** | #12 google-services.jsonを.gitignoreに追加 |
| ~~**中**~~ | ~~#15 onRequest関数の認証強化~~ ✅ 完了 |
| **低** | #10 メールアドレス公開の検討 |
| **低** | #11 スプレッドシートID移行（任意） |
| **低** | #13 banAppeals重複コレクションの整理 |
| **低** | #17 App Checkの有効化検討 |
| **低** | #19 デバッグログの本番環境無効化 |
| **低** | #20 バックアップファイルの削除または.gitignore追加 |
| **情報** | #14 Firebase設定の確認（対応不要） |
| **情報** | #18 内部コレクションのルール明示化（推奨） |

---

## 補足事項

### 確認済み・問題なしの項目

以下の項目は確認の結果、問題なしと判断しました：

| 項目 | 結果 |
|------|------|
| **セッション管理** | Firebase Authenticationが自動管理 ✓ |
| **CSRF保護** | Firebase Cloud Functionsが内蔵保護 ✓ |
| **XSS対策** | Flutter/Dartのフレームワークが自動エスケープ ✓ |
| **パスワードポリシー** | Firebase Authenticationが強制 ✓ |
| **ブルートフォース保護** | Firebase Authenticationが自動制限 ✓ |
| **依存関係** | 最新バージョンを使用中 ✓ |
| **シークレット管理** | `defineSecret`を使用（cleanUpUserFollows除く） ✓ |
| **HTTPS** | Firebase Hostingが強制 ✓ |

### 軽微な推奨事項

- `debugPrint('AuthService: Starting signUp for email: $email')` - 本番環境ではメールアドレスをログに出力しないことを推奨
- App Checkの導入を検討（不正クライアントからの保護強化）

---

## 修正時の注意事項

1. **Firestoreルールの変更はテスト必須**  
   ルール変更により既存機能が動作しなくなる可能性があるため、変更前後で十分なテストを行うこと。

2. **Storage パスの変更はマイグレーション必要**  
   問い合わせ添付画像のパス変更を行う場合、既存ファイルのマイグレーションが必要。

3. **Cloud Functionsのシークレット移行**  
   シークレットをSecrets Managerに移行後、既存のハードコード値は削除すること。

4. **デプロイ順序**  
   Firestoreルール → Cloud Functions → クライアントの順でデプロイし、整合性を保つこと。

---

## 参考ファイル

- `firebase/firestore.rules` - Firestoreセキュリティルール
- `firebase/storage.rules` - Storageセキュリティルール  
- `functions/src/index.ts` - Cloud Functions
- `lib/shared/providers/auth_provider.dart` - 認証プロバイダー
- `lib/firebase_options.dart` - Firebase設定

---

*本レポートは自動セキュリティ監査ツールによる分析結果をもとに作成されました。*

---

## 修正履歴

### 2026-01-07 セキュリティ修正（即対応項目）

以下の問題を修正しました：

#### ✅ #12 + #20: `.gitignore`の更新
- **修正内容**: Firebase設定ファイルを`.gitignore`に追加
- **変更ファイル**: `.gitignore`
- **追加内容**:
  ```
  android/app/google-services*.json
  ios/Runner/GoogleService-Info*.plist
  ```

#### ✅ #7: `deleteAllAIUsers`に管理者チェック追加
- **修正内容**: ログインチェックに加え、管理者権限チェック（`isAdmin()`）を追加
- **変更ファイル**: `functions/src/index.ts`
- **リスク軽減**: 一般ユーザーによるAI全データ削除を防止

#### ✅ #5: `initializeNameParts`に認証チェック追加
- **修正内容**: 認証チェック + 管理者権限チェックを追加
- **変更ファイル**: `functions/src/index.ts`

#### ✅ #6: 管理者用Cloud Functionsに認証チェック追加
以下の全関数に認証 + 管理者権限チェックを追加：
- `initializeAIAccounts`
- `generateAIPosts`
- `cleanupOrphanedCircleAIs`
- `triggerCircleAIPosts`
- `triggerEvolveCircleAIs`

- **変更ファイル**: `functions/src/index.ts`
- **リスク軽減**: 不正なAPIコスト消費、データ汚染・破壊を防止

#### ✅ #2: 問い合わせ添付画像の閲覧制限
- **修正内容**: 
  - Storageパスを `/inquiries/{fileName}` → `/inquiries/{userId}/{fileName}` に変更
  - 本人または管理者のみ閲覧可能に
- **変更ファイル**: 
  - `firebase/storage.rules`
  - `lib/shared/services/media_service.dart`
  - `lib/features/settings/presentation/screens/inquiry_form_screen.dart`
  - `lib/features/settings/presentation/screens/inquiry_detail_screen.dart`
- **リスク軽減**: 他ユーザーの問い合わせ添付画像の閲覧を防止

#### ✅ #1: Firestoreルールの重複定義
- **修正内容**: 
  - 1回目の定義（posts/circles/circleJoinRequests）を削除（約100行）
  - 2回目の定義に `isNotBanned()` チェックを追加
  - ルールを単一定義に統合
- **追補**: `posts` の `reactions` / `commentCount` フィールド更新にも `isNotBanned()` を適用し、BAN中ユーザーによる改ざんを防止
- **変更ファイル**: `firebase/firestore.rules`
- **リスク軽減**: ルールの意図しない上書きを防止、BAN中ユーザーの操作を制限

### 2026-01-08 セキュリティ修正（追加対応）

#### ✅ #3: namePartsコレクションのルール追加
- **修正内容**: 
  - 認証済みユーザーは読み取り可能（名前生成に必要）
  - 書き込みはCloud Functionsのみ（クライアントからは不可）
- **変更ファイル**: `firebase/firestore.rules`
- **追加ルール**:
  ```javascript
  match /nameParts/{partId} {
    allow read: if isAuthenticated();
    allow write: if false;
  }
  ```

### 2026-01-09 セキュリティ修正

#### ✅ #4: ハードコードされた管理者シークレットの解消
- **修正内容**: 
  - `cleanUpUserFollows`関数を`onRequest`+シークレット方式から`onCall`+Firebase Auth+isAdmin方式に変更
  - ハードコードされた`"admin_secret_homeppu_2025"`を完全削除
  - 他の管理関数と同じ認証パターンに統一
- **変更ファイル**: `functions/src/index.ts`
- **セキュリティ向上**:
  - 二要素認証（ログイン + 管理者権限）
  - 実行者のユーザーIDがログに記録される
  - シークレット漏洩リスクがなくなった

---

### 2026-01-09 セキュリティ監査（全体調査）

#### 🔍 新規発見: #21 AIモードサークルの一覧表示制限が未実装
- **発見経緯**: 設計書（`implementation_plan.md`）との整合性確認中に発見
- **問題内容**:
  - AIモードサークル（`aiMode: "aiOnly"`）は作成者のみ表示すべき（設計書要件）
  - Firestoreルールでは全認証ユーザーが読み取り可能
  - クライアント側フィルターのみで保護（セキュリティ的に不十分）
- **影響**:
  - Firestore REST API経由で他人のAIサークルにアクセス可能
  - 個人の練習用サークル（目標・悩み等）が露出する可能性
- **対応状況**: 未対応（ドキュメント追記のみ）
- **推奨対応**: Firestoreルール210行目を修正
  ```javascript
  allow read: if isAuthenticated() && (
    resource.data.aiMode != "aiOnly" ||
    resource.data.ownerId == request.auth.uid ||
    isAdmin()
  );
  ```

#### ✅ 検証済み: #22 サークル削除時のメンバー通知
- **調査結果**: 既に実装済み（`functions/src/index.ts:4955-4986`）
- **実装内容**:
  - 削除理由あり/なしの両方に対応
  - 全メンバーに通知送信（AIメンバーを除外）
  - プッシュ通知 + アプリ内通知の両方対応
- **結論**: 問題なし（誤検知）

---

**残りの対応項目**（未対応）:
- #8, #9: Storage削除権限の見直し
- #10: メールアドレス公開の検討
- #11: スプレッドシートID移行
- #13: banAppeals重複コレクションの整理
- #15: onRequest関数の認証強化
- #16: createPostWithRateLimitの入力バリデーション
- #17: App Checkの有効化検討
- #18: 内部コレクションのルール明示化
- #19: デバッグログの本番環境無効化
- **#21: AIモードサークルの一覧表示制限（新規）**

#### ✅ #8 + #9: Storage削除権限の見直し（2026-01-09）
- **問題内容**:
  - #8: 後方互換パス（`/posts/{postId}/{fileName}`）で認証済みなら誰でもファイル削除可能
  - #9: サークル画像（`/circles/{circleId}/...`）も同様
- **修正内容**:
  1. **Storage Security Rules変更**:
     - 後方互換パス: `allow delete: if isAdmin();` に変更（クライアント削除禁止）
     - サークル画像: `allow delete: if isAdmin();` に変更（クライアント削除禁止）
  2. **自動削除機能の実装・強化**:
     - 共通ヘルパー関数 `deleteStorageFileFromUrl(url)` を新規作成
     - `onCircleUpdated`: 画像URL変更時に古い画像を自動削除するロジック追加
     - `onPostDeleted`: ヘルパー関数を使用するようリファクタリング
     - `cleanupDeletedCircle`: ヘルパー関数を使用するようリファクタリング
- **変更ファイル**:
  - `firebase/storage.rules`
  - `functions/src/index.ts`
- **セキュリティ向上**:
  - 悪意あるユーザーによる他者ファイル削除が不可能に
  - 画像の自動クリーンアップでStorageのゴミデータ蓄積を防止

---

**残りの対応項目**（未対応）:
- #10: メールアドレス公開の検討
- #11: スプレッドシートID移行
- #13: banAppeals重複コレクションの整理
- #15: onRequest関数の認証強化
- #16: createPostWithRateLimitの入力バリデーション
- #17: App Checkの有効化検討
- #18: 内部コレクションのルール明示化
- #19: デバッグログの本番環境無効化
- **#21: AIモードサークルの一覧表示制限（新規）**

---

### 2026-01-10 セキュリティ確認・テスト

#### ✅ #2関連: 問い合わせ添付画像のセキュリティテスト実施
- **テスト内容**: 
  - 問い合わせ自動クリーンアップ（`cleanupResolvedInquiries`）がStorageの画像を正しく削除するか確認
  - 結果: 正常に動作（解決から7日経過で問い合わせ本体・メッセージ・添付画像を削除、アーカイブに保存）
- **関連ドキュメント**: `docs/design/cleanup_processing_design.md` に処理詳細を追加

#### ✅ Firestoreセキュリティルールの追加修正
- **問題発見**: 
  - 問い合わせチャットの「閲覧中」通知抑制機能実装時、`userViewing`フィールドの更新が`PERMISSION_DENIED`エラー
  - 原因: `inquiries`コレクションの更新ルールが`hasUnreadReply`のみ許可していた
- **修正内容**: 
  - `userViewing`フィールドもユーザーが更新可能に
- **変更ファイル**: `firebase/firestore.rules` 行286-291
- **修正後のルール**:
  ```javascript
  allow update: if isAuthenticated() && (
    // 本人は hasUnreadReply と userViewing のみ更新可能
    isOwner(resource.data.userId) && 
    request.resource.data.diff(resource.data).affectedKeys().hasOnly(['hasUnreadReply', 'userViewing'])
  ) || (
    // 管理者は全フィールド更新可能
    isAdmin()
  );
  ```
- **関連ドキュメント**: `docs/KNOWN_ISSUES.md` に問題と解決を記録済み

#### 📝 ドキュメント整備
- **作成**: `docs/design/cleanup_processing_design.md`
  - 全5つの定期クリーンアップ処理を網羅
  - 検出ロジック、削除方法、保持期間を詳細記載
  - ソースコード参照（行番号）を記載

---

### 2026-01-11 セキュリティ修正

#### ✅ #21: AIモードサークルの一覧表示制限
- **問題内容**: 
  - AIモードサークル（`aiMode: "aiOnly"`）は作成者のみ表示すべき（設計書要件）
  - Firestoreルールでは全認証ユーザーが読み取り可能だった
- **修正内容**: 
  - Firestoreルールを修正し、AIモードサークルは作成者または管理者のみ読み取り可能に
- **変更ファイル**: `firebase/firestore.rules` 行210-215
- **修正後のルール**:
  ```javascript
  // 読み取り: AIモードサークルは作成者のみ、それ以外は認証済みユーザー誰でも
  allow read: if isAuthenticated() && (
    resource.data.aiMode != "aiOnly" ||
    resource.data.ownerId == request.auth.uid ||
    isAdmin()
  );
  ```
- **備考**: クライアント側フィルターも既に実装済みのため、二重で保護

---

### #15: onRequest関数の認証強化（対応設計）

#### 問題の詳細

以下の6つの `onRequest` 関数は、Cloud Tasksからの呼び出しを想定していますが、**認証ヘッダーの存在チェックのみ**で、トークンの正当性を検証していません。

| 関数名 | 行番号 | 用途 |
|--------|--------|------|
| `generateAICommentV1` | 3663 | AIコメント生成 |
| `generateAIReactionV1` | 4114 | AIリアクション生成 |
| `executeAIPostGeneration` | 4406 | AI投稿生成 |
| `executeTaskReminder` | 4851 | タスクリマインダー通知 |
| `cleanupDeletedCircle` | 5068 | サークル削除クリーンアップ |
| `executeCircleAIPost` | 6032 | サークルAI投稿 |

#### 現在の認証チェック（問題あり）

```typescript
const authHeader = request.headers["authorization"];
if (!authHeader) {
  response.status(403).send("Unauthorized");
  return;
}
// ↑ ヘッダーの「存在」のみ確認、トークンの検証なし
```

#### リスク

- URLを知っていれば任意のAuthorizationヘッダーで呼び出し可能
- 偽のリマインダー通知、AIコメント/投稿の偽装が可能
- サークルデータの不正削除が可能

#### 推奨対応：OIDCトークン検証

**1. 共通ヘルパー関数を追加**

```typescript
// index.ts の上部に追加
import { OAuth2Client } from "google-auth-library";

const authClient = new OAuth2Client();

/**
 * Cloud Tasksからのリクエストを検証
 * OIDCトークンを検証し、正当なリクエストかどうかを判定
 */
async function verifyCloudTasksRequest(
  request: functionsV1.https.Request,
  functionName: string
): Promise<boolean> {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return false;
  }

  const token = authHeader.split("Bearer ")[1];
  try {
    await authClient.verifyIdToken({
      idToken: token,
      audience: `https://asia-northeast1-${PROJECT_ID}.cloudfunctions.net/${functionName}`,
    });
    return true;
  } catch (error) {
    console.error("Token verification failed:", error);
    return false;
  }
}
```

**2. 各関数の認証チェックを置換**

```typescript
// Before（現状）
const authHeader = request.headers["authorization"];
if (!authHeader) {
  response.status(403).send("Unauthorized");
  return;
}

// After（修正後）
if (!await verifyCloudTasksRequest(request, "関数名")) {
  response.status(403).send("Unauthorized");
  return;
}
```

#### 変更箇所一覧

| 関数名 | 変更内容 |
|--------|---------|
| `generateAICommentV1` | 認証チェックを `verifyCloudTasksRequest(request, "generateAICommentV1")` に置換 |
| `generateAIReactionV1` | 同上 |
| `executeAIPostGeneration` | 同上 |
| `executeTaskReminder` | 同上 |
| `cleanupDeletedCircle` | 同上 |
| `executeCircleAIPost` | 同上 |

#### 依存関係

- `google-auth-library` パッケージが必要（確認が必要）

#### 対応ステータス

- **ステータス**: ✅ **完了**（2026-01-12）
- **解決方法**: 動的インポート（`await import()`）を使用し、ファイル分割なしで対応

#### 2026-01-12 対応履歴

**初回試行（失敗）**:
- `helpers/cloud-tasks-auth.ts` を作成し、OIDC認証ヘルパーを実装
- `config/constants.ts` を作成し、定数を分離
- index.ts に上記をインポートし、6つの関数に認証を適用

**発生した問題**:
- index.ts でのトップレベルインポートにより、**すべての関数**で `google-auth-library` が初期化されるようになった
- メモリ256MB制限の関数（`onCircleUpdated`, `moderateImageCallable`）でメモリ不足が発生
- デプロイエラー: `Container Healthcheck failed`

**解決策（動的インポート）**:
- 各Cloud Tasks関数内で `await import("./helpers/cloud-tasks-auth")` を使用
- 関数実行時にのみライブラリがロードされるため、他の関数に影響しない
- ファイル分割なしで安全に認証を適用可能

**追加対応**:
- サービスアカウントを `cloud-tasks-sa@${project}.iam.gserviceaccount.com` に統一
- 認証失敗時のデバッグログを追加（トークンのaud, email, 期待値を出力）

**実装済みコード**:
```typescript
// 各Cloud Tasks関数の冒頭
const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
if (!await verifyCloudTasksRequest(request, "関数名")) {
  response.status(403).send("Unauthorized");
  return;
}
```

**変更ファイル**:
- `functions/src/helpers/cloud-tasks-auth.ts` - OIDC認証ヘルパー
- `functions/src/config/constants.ts` - 関数名定数
- `functions/src/index.ts` - 6つのCloud Tasks関数に認証適用

---

**残りの対応項目**（未対応）:
- #10: メールアドレス公開の検討
- #11: スプレッドシートID移行
- #13: banAppeals重複コレクションの整理
- #16: createPostWithRateLimitの入力バリデーション（リファクタリング時に対応）
- #17: App Checkの有効化検討
- #18: 内部コレクションのルール明示化
- #19: デバッグログの本番環境無効化

---

### 2026-01-12 セキュリティ修正

#### ✅ #15: onRequest関数（Cloud Tasks）のOIDC認証強化
- **問題内容**:
  - 6つのCloud Tasks関数が認証ヘッダーの存在チェックのみで、トークンの正当性を検証していなかった
  - 任意のAuthorizationヘッダーで呼び出し可能な状態
- **修正内容**:
  - `helpers/cloud-tasks-auth.ts` にOIDC認証ヘルパーを実装
  - `google-auth-library` を使用してトークンを検証
  - **動的インポート**で他の関数への影響を回避
  - サービスアカウントを `cloud-tasks-sa@` に統一
- **対象関数**:
  - `generateAICommentV1`
  - `generateAIReactionV1`
  - `executeAIPostGeneration`
  - `executeTaskReminder`
  - `cleanupDeletedCircle`
  - `executeCircleAIPost`
- **変更ファイル**:
  - `functions/src/helpers/cloud-tasks-auth.ts`（新規）
  - `functions/src/config/constants.ts`（新規）
  - `functions/src/index.ts`
- **テスト結果**: 全関数で正常動作を確認
