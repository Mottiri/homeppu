# モデレーション機能設計

## 概要
投稿コンテンツ（テキスト・画像・動画）の適切性を判定し、不適切なコンテンツをブロックまたはフラグ付けする機能。

## モデレーション対象

| 対象 | テキスト | 画像 | 動画 |
|------|:-------:|:----:|:----:|
| **投稿** | ✅ | ✅ | ✅ |
| **サークル画像** | - | ✅ | - |
| **タスク添付** | - | - | - |

## 三段階判定方式

| 判定 | confidence | 処理 |
|------|------------|------|
| **明確NG** | ≥ 0.7 | 投稿ブロック + メディア削除 + 徳ポイント減少 |
| **曖昧** | 0.5-0.7 | 投稿許可 + フラグ付け + 管理者通知 |
| **OK** | < 0.5 | 投稿許可 |

## モデレーション実装

### 1. テキストモデレーション
```typescript
// Cloud Functions: createPostWithModeration
const result = await model.generateContent([
  systemPrompt,
  `投稿内容: ${content}`
]);
```

### 2. メディアモデレーション（投稿）

#### 2.1 クライアント側（高速・オンデバイス）
- `NsfwDetectorService.checkImage()` / `checkVideo()`
- 即座にNGをブロック

#### 2.2 サーバー側（詳細・Gemini）
- `createPostWithModeration`内で実行
- URLからメディアをダウンロードして審査

### 3. サークル画像モデレーション

#### Base64方式（アップロード前審査）
```dart
// Flutter: ImageModerationService
final base64Image = base64Encode(bytes);
final result = await callable.call({
  'imageBase64': base64Image,
  'mimeType': mimeType,
});
```

```typescript
// Cloud Functions: moderateImageCallable
const imagePart = {
  inlineData: { mimeType, data: imageBase64 }
};
```

## モデレーションNG時のメディア削除

投稿がモデレーションでNGになった場合、アップロード済みメディアをStorageから自動削除。

```typescript
// createPostWithModeration内
for (const item of mediaItems) {
  const url = new URL(item.url);
  const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
  if (pathMatch) {
    const storagePath = decodeURIComponent(pathMatch[1]);
    await admin.storage().bucket().file(storagePath).delete();
  }
}
```

## ブロックカテゴリ

| カテゴリ | 説明 | 日本語表示 |
|----------|------|-----------|
| `adult` | 成人向けコンテンツ | 成人向けコンテンツ |
| `violence` | 暴力的な内容 | 暴力的なコンテンツ |
| `hate` | 差別的な内容 | 差別的なコンテンツ |
| `dangerous` | 危険な行為 | 危険なコンテンツ |

## 徳ポイント連携

| イベント | 徳ポイント変動 |
|----------|--------------|
| モデレーションNG | -20 |
| テキスト違反 | -10 |

## 関連設計書
- [管理者機能設計](admin_features.md) - フラグ付き投稿のレビュー機能
- [孤立メディアクリーンアップ設計](orphaned_media_cleanup_design.md) - 削除漏れメディアの定期削除
