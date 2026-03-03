# CT-010: 全AI使用箇所にOpenAIフォールバックを実装

## 概要

現在、AIコメント生成（`generateAICommentV1`）のみが`AIProviderFactory`によるフォールバックを持つ。
残りのAI使用箇所にも同じフォールバック機構を適用し、Gemini障害時のサービス停止リスクを排除する。

## スコープ

### 対象（7箇所）

| # | ファイル | 関数 | 用途 | 呼び出し型 |
|---|---------|------|------|-----------|
| 1 | `callable/posts.ts` | `createPostWithModeration` | 投稿テキストモデレーション | `generateText` |
| 2 | `callable/posts.ts` | （上記内で`moderateMedia`呼び出し） | 投稿画像モデレーション | `generateWithImage` |
| 3 | `http/image-moderation.ts` | `moderateImageCallable` | 画像モデレーション（単体） | `generateWithImage` |
| 4 | `callable/comments.ts` | `createCommentWithModeration` / `moderateText` | コメントテキストモデレーション | `generateText` |
| 5 | `helpers/moderation.ts` | `moderateImage` / `moderateMedia` | 画像モデレーション共通ヘルパー | `generateWithImage` |
| 6 | `helpers/media-analysis.ts` | `analyzeImageForComment` / `analyzeMediaForComment` | AI返信用画像分析 | `generateWithImage` |
| 7 | `triggers/posts.ts` | `onPostCreated`（上記6を呼び出し） | 投稿トリガー | （6経由） |
| 8 | `circle-ai/posts.ts` | `executeCircleAIPost` / `triggerCircleAIPosts` | サークルAI投稿生成 | `generateText` |

### スコープ外

- `executeAIPostGeneration` — 運営手動実行のため
- `generateBioWithGemini` / `initializeAIAccounts` — 運営手動実行のため

## 設計

### 1. OpenAIデフォルトモデルの変更

```typescript
// functions/src/config/constants.ts
export const AI_MODELS = {
  GEMINI_DEFAULT: "gemini-2.5-flash",
  OPENAI_DEFAULT: "gpt-5-nano",  // gpt-4o-mini → gpt-5-nano
} as const;
```

### 2. `createAIProviderFactory` ヘルパーの共有化

現在 `http/ai-generation.ts` 内にローカル定義されている `createAIProviderFactory()` を、
`ai/provider.ts` にエクスポート関数として移動し、全ファイルからインポート可能にする。

```typescript
// ai/provider.ts に追加
import { defineSecret } from "firebase-functions/params";

export const geminiApiKey = defineSecret("GEMINI_API_KEY");
export const openaiApiKey = defineSecret("OPENAI_API_KEY");

export function createAIProviderFactory(): AIProviderFactory {
    return new AIProviderFactory(
        geminiApiKey.value(),
        openaiApiKey.value()
    );
}
```

### 3. ヘルパー関数のシグネチャ変更

#### `helpers/moderation.ts`

```typescript
// Before:
export async function moderateImage(
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    imageUrl: string,
    mimeType?: string
): Promise<MediaModerationResult>

// After:
export async function moderateImage(
    aiFactory: AIProviderFactory,
    imageUrl: string,
    mimeType?: string
): Promise<MediaModerationResult>
```

内部では `aiFactory.generateWithImage(prompt, base64, mimeType)` を使用。
`moderateMedia` も同様に変更。

#### `helpers/media-analysis.ts`

```typescript
// Before:
export async function analyzeImageForComment(
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    imageUrl: string,
    mimeType?: string
): Promise<string | null>

// After:
export async function analyzeImageForComment(
    aiFactory: AIProviderFactory,
    imageUrl: string,
    mimeType?: string
): Promise<string | null>
```

### 4. 各呼び出し元の変更パターン

全ての呼び出し元で以下のパターンに統一:

```typescript
import { createAIProviderFactory, geminiApiKey, openaiApiKey } from "../ai/provider";

// Cloud Function定義に secrets を追加
secrets: [geminiApiKey, openaiApiKey]

// 関数内
const aiFactory = createAIProviderFactory();
const result = await aiFactory.generateText(prompt);
// or
const result = await aiFactory.generateWithImage(prompt, base64, mimeType);
```

### 5. `logAIUsage` の扱い

`AIProviderFactory` は `AIResponse { text, provider, usedFallback }` を返すため、
Gemini固有の `usageMetadata` は取得できない。

**方針**: `logAIUsage` 呼び出しを `logAIProviderUsage` に置き換え。
provider名とfallback使用有無をログに記録する。

```typescript
// helpers/ai-usage.ts に追加
export function logAIProviderUsage(
    label: string,
    response: AIResponse,
    context: Record<string, unknown> = {}
): void {
    console.log("[AI USAGE]", JSON.stringify({
        label,
        provider: response.provider,
        usedFallback: response.usedFallback,
        responseLength: response.text.length,
        ...context,
    }));
}
```

### 6. secrets宣言の追加が必要なファイル

| ファイル | 現在のsecrets | 追加 |
|---------|--------------|------|
| `callable/posts.ts` | `[geminiApiKey]` | `openaiApiKey` |
| `http/image-moderation.ts` | `[geminiApiKey]` | `openaiApiKey` |
| `callable/comments.ts` | `[geminiApiKey]` | `openaiApiKey` |
| `triggers/posts.ts` | `[geminiApiKey]` | `openaiApiKey` |
| `circle-ai/posts.ts` | `["GEMINI_API_KEY"]` | `"OPENAI_API_KEY"` |

## 変更ファイル一覧

1. `functions/src/config/constants.ts` — OPENAI_DEFAULT を gpt-5-nano に変更
2. `functions/src/ai/provider.ts` — `createAIProviderFactory`, secret定義をエクスポート
3. `functions/src/helpers/ai-usage.ts` — `logAIProviderUsage` 追加
4. `functions/src/helpers/moderation.ts` — AIProviderFactory受け取りに変更
5. `functions/src/helpers/media-analysis.ts` — AIProviderFactory受け取りに変更
6. `functions/src/callable/posts.ts` — AIProviderFactory使用に変更
7. `functions/src/http/image-moderation.ts` — AIProviderFactory使用に変更
8. `functions/src/callable/comments.ts` — AIProviderFactory使用に変更
9. `functions/src/triggers/posts.ts` — AIProviderFactory使用に変更
10. `functions/src/circle-ai/posts.ts` — AIProviderFactory使用に変更
11. `functions/src/http/ai-generation.ts` — ローカル`createAIProviderFactory`を共有版に置換

## リスク・注意点

- デプロイ後、OpenAI API Keyが Firebase Secret Manager に設定済みであることが前提
- gpt-5-nano は最新モデルのため、レスポンス形式の互換性を実機テストで確認が必要
- Firestore `settings/ai` の `primaryProvider` のデフォルトは `"gemini"`。OpenAIをプライマリにしたい場合はFirestoreで設定変更が必要
