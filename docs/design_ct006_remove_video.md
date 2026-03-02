# CT-006: 動画添付機能の完全削除 詳細設計書

## スコープ
- **対象**: 投稿における動画添付機能の完全削除（新規投稿での動画選択・アップロード・再生機能すべて）
- **対象**: 動画関連パッケージ（`video_player`, `chewie`, `video_thumbnail`）の削除
- **対象**: サーバー側の動画モデレーション・動画分析処理の削除
- **対象**: Storageルールの動画関連ルール削除
- **非対象**: Firestoreの既存投稿データ（動画付き投稿のドキュメントは残す）
- **非対象**: Storageの既存動画ファイル（自然に残す、手動削除は行わない）
- **非対象**: `post_model.dart` の `MediaType.video` enum値（後方互換のため残す）

## 問題
- 動画添付機能はクローズドテスト中に利用頻度が低く、アプリサイズ・複雑性の増加要因となっている
- `video_player`、`chewie`、`video_thumbnail` の3パッケージがアプリサイズを増大させている
- 動画モデレーション処理（Gemini File API経由）はコストが高く、処理時間も長い
- 機能を削除することで、アプリの軽量化・保守性向上・モデレーションコスト削減を図る

## 方針
動画関連の全コードパスを削除し、画像のみのメディア添付に簡略化する。
既存の動画付き投稿については後方互換性を維持し、サムネイルがあればサムネイル画像を表示、なければ動画アイコンのみ表示（再生不可）とする。

---

## 修正対象ファイル

### カテゴリ1: パッケージ削除

#### 1-1. `pubspec.yaml`

**変更内容**:
- 以下の3パッケージを削除

```yaml
# 削除対象
video_player: ^2.9.3
chewie: ^1.10.0
video_thumbnail: ^0.5.6
```

**変更後**: `flutter pub get` を実行して依存関係を更新する。

---

### カテゴリ2: ファイル削除

#### 2-1. `lib/shared/widgets/video_player_screen.dart`

**操作**: ファイル全体を削除

**理由**: 動画再生画面は不要になる。`video_player` および `chewie` パッケージに依存しているため、パッケージ削除に伴い必ず削除が必要。

---

### カテゴリ3: クライアント側修正（Flutter）

#### 3-1. `lib/features/post/presentation/screens/create_post_screen.dart`

**変更内容**:

1. `_showMediaPicker()` メソッド（L268-337）から「動画を選択」オプションを削除
   - `_MediaPickerOption(icon: Icons.videocam, label: '動画を選択', ...)` のブロックを削除

2. `_pickVideo()` メソッド（L383-402）を全体削除

```dart
// 削除: _showMediaPicker() 内の以下のブロック
_MediaPickerOption(
  icon: Icons.videocam,
  label: '動画を選択',
  color: Colors.orange,
  onTap: () {
    Navigator.pop(context);
    _pickVideo();
  },
),

// 削除: メソッド全体
Future<void> _pickVideo() async {
  // ...（L383-402全体）
}
```

#### 3-2. `lib/shared/services/media_service.dart`

**変更内容**:

1. `video_thumbnail` インポートを削除（L9）
   ```dart
   // 削除
   import 'package:video_thumbnail/video_thumbnail.dart';
   ```

2. `path_provider` インポートを削除（L7）— `_generateAndUploadThumbnail` でのみ使用
   ```dart
   // 削除（他で使用されていなければ）
   import 'package:path_provider/path_provider.dart';
   ```

3. 定数 `maxVideoSize` を削除（L19）
   ```dart
   // 削除
   static const int maxVideoSize = 30 * 1024 * 1024;
   ```

4. 定数 `allowedVideoExtensions` を削除（L30-35）
   ```dart
   // 削除
   static const List<String> allowedVideoExtensions = [
     'mp4', 'mov', 'avi', 'mkv',
   ];
   ```

5. `pickVideo()` メソッドを削除（L55-60）

6. `recordVideo()` メソッドを削除（L62-67）

7. `_generateAndUploadThumbnail()` メソッドを削除（L128-175）

8. `uploadFile()` メソッド内の修正:
   - 動画サイズ判定の分岐を削除し、`maxImageSize` のみ使用
   - ストレージパスの `${type.name}s` を `images` に固定（動画パスが生成されないようにする）
   - サムネイル生成呼び出し部分を削除（L110-116）

   ```dart
   // Before
   final maxSize = type == MediaType.video ? maxVideoSize : maxImageSize;
   // After
   final maxSize = maxImageSize;

   // Before
   final storagePath = 'posts/$userId/${type.name}s/$uniqueFileName';
   // After（画像のみになるため）
   final storagePath = 'posts/$userId/images/$uniqueFileName';

   // 削除: サムネイル生成部分
   String? thumbnailUrl;
   if (type == MediaType.video) {
     thumbnailUrl = await _generateAndUploadThumbnail(
       videoPath: filePath,
       userId: userId,
     );
   }
   ```

9. `_getMimeType()` メソッドから動画MIMEタイプを削除:
   ```dart
   // 削除対象のcase文
   case 'mp4':
     return 'video/mp4';
   case 'mov':
     return 'video/quicktime';
   case 'avi':
     return 'video/x-msvideo';
   case 'mkv':
     return 'video/x-matroska';
   ```

10. `getMediaType()` メソッドから動画判定を削除:
    ```dart
    // Before
    MediaType getMediaType(String filePath) {
      final ext = path.extension(filePath).toLowerCase().replaceAll('.', '');
      if (allowedVideoExtensions.contains(ext)) {
        return MediaType.video;
      }
      return MediaType.image;
    }

    // After
    MediaType getMediaType(String filePath) {
      return MediaType.image;
    }
    ```

#### 3-3. `lib/shared/services/nsfw_detector_service.dart`

**変更内容**:

1. `video_thumbnail` インポートを削除（L4）
   ```dart
   // 削除
   import 'package:video_thumbnail/video_thumbnail.dart';
   ```

2. `path_provider` インポートを削除（L5）
   ```dart
   // 削除
   import 'package:path_provider/path_provider.dart';
   ```

3. `checkVideo()` メソッド全体を削除（L77-122）

#### 3-4. `lib/features/home/presentation/widgets/post_card.dart`

**変更内容**:

1. `video_player_screen.dart` インポートを削除（L19）
   ```dart
   // 削除
   import '../../../../shared/widgets/video_player_screen.dart';
   ```

2. `_buildMediaItem()` メソッド内の `case MediaType.video:` を変更（L803-852）
   - 再生ボタンオーバーレイを削除
   - `_showVideoPlayer()` へのタップ遷移を削除
   - サムネイルがあればサムネイル画像を表示（タップしても何も起きない）
   - サムネイルがなければ動画アイコンのみ表示

   ```dart
   // After
   case MediaType.video:
     // 既存動画は再生不可。サムネイルがあればサムネイル画像を表示。
     if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
       return CachedNetworkImage(
         imageUrl: item.thumbnailUrl!,
         height: height,
         width: double.infinity,
         fit: BoxFit.cover,
         errorWidget: (context, url, error) => Container(
           height: height,
           color: Colors.grey.shade200,
           child: const Icon(Icons.videocam_off, color: Colors.grey),
         ),
       );
     }
     return Container(
       height: height,
       color: Colors.grey.shade200,
       child: const Center(
         child: Icon(
           Icons.videocam_off,
           color: Colors.grey,
           size: 48,
         ),
       ),
     );
   ```

3. `_showVideoPlayer()` メソッドを削除（L884-889）

#### 3-5. `lib/features/profile/presentation/widgets/profile_post_card.dart`

**変更内容**:

1. `_buildMediaIcons()` メソッド（L337-393）から動画アイコン表示部分を削除
   - `videoCount` の算出とその表示ブロック（L341-390）を削除
   - 画像アイコンのみを表示する

   ```dart
   // 削除対象
   final videoCount = widget.post.allMedia
       .where((m) => m.type == MediaType.video)
       .length;
   // ...
   if (videoCount > 0) { ... }
   ```

#### 3-6. `lib/shared/models/post_model.dart`

**変更内容**: 最小限の変更のみ

1. `MediaType` enum の `video` は**残す**（後方互換性のため）
   ```dart
   // 変更なし
   enum MediaType { image, video, file }
   ```

2. `videos` ゲッターにコメントを追加（新規投稿では使用されないことを明記）
   ```dart
   /// 動画のみ（レガシーデータ用。新規投稿では動画は添付不可）
   List<MediaItem> get videos =>
       allMedia.where((m) => m.type == MediaType.video).toList();
   ```

---

### カテゴリ4: サーバー側修正（Cloud Functions）

#### 4-1. `functions/src/helpers/moderation.ts`

**変更内容**:

1. `moderateVideo()` 関数（L108-189）を全体削除
   - `GoogleAIFileManager` のインポートも不要であれば削除
   - `fs`, `os`, `path` のインポートも `moderateVideo` でのみ使用されていれば削除

2. `VIDEO_MODERATION_PROMPT` のインポートを削除（L17）
   ```typescript
   // Before
   import {
       IMAGE_MODERATION_PROMPT,
       VIDEO_MODERATION_PROMPT,
   } from "../ai/prompts/moderation";
   // After
   import {
       IMAGE_MODERATION_PROMPT,
   } from "../ai/prompts/moderation";
   ```

3. `moderateMedia()` 関数内の動画チェック分岐を削除（L205-209）
   ```typescript
   // 削除
   } else if (item.type === "video") {
       const result = await moderateVideo(apiKey, model, item.url, item.mimeType || "video/mp4");
       if (result.isInappropriate && result.confidence >= 0.7) {
           return { passed: false, failedItem: item, result };
       }
   }
   ```

4. `moderateMedia()` の引数から `apiKey` を削除（`moderateVideo` でのみ使用されていた場合）

#### 4-2. `functions/src/helpers/media-analysis.ts`

**変更内容**:

1. `analyzeVideoForComment()` 関数（L57-122）を全体削除
   - `GoogleAIFileManager` のインポートも不要であれば削除
   - `fs`, `os`, `path` のインポートも `analyzeVideoForComment` でのみ使用されていれば削除

2. `VIDEO_ANALYSIS_PROMPT` のインポートを削除（L17）
   ```typescript
   // Before
   import {
       IMAGE_ANALYSIS_PROMPT,
       VIDEO_ANALYSIS_PROMPT,
   } from "../ai/prompts/media-analysis";
   // After
   import {
       IMAGE_ANALYSIS_PROMPT,
   } from "../ai/prompts/media-analysis";
   ```

3. `analyzeMediaForComment()` 内の動画分岐を削除（L141-145）
   ```typescript
   // 削除
   } else if (item.type === "video") {
       const desc = await analyzeVideoForComment(apiKey, model, item.url, item.mimeType || "video/mp4");
       if (desc) {
           descriptions.push(`【動画】${desc} `);
       }
   }
   ```

4. `analyzeMediaForComment()` の引数から `apiKey` を削除（`analyzeVideoForComment` でのみ使用されていた場合）

#### 4-3. `functions/src/ai/prompts/moderation.ts`

**変更内容**:
- `VIDEO_MODERATION_PROMPT` 定数を削除（L28-42）

#### 4-4. `functions/src/ai/prompts/media-analysis.ts`

**変更内容**:
- `VIDEO_ANALYSIS_PROMPT` 定数を削除（L28-42）

#### 4-5. `functions/src/callable/posts.ts`

**変更内容**:
- L341のメディアモデレーション失敗メッセージから動画分岐を簡略化
  ```typescript
  // Before
  mediaResult.failedItem?.type === "video" ? "video" : "image",
  // After
  "image",
  ```
- `moderateMedia` の引数変更に合わせて呼び出し側も修正（`apiKey` が不要になった場合）

#### 4-6. `functions/src/types/index.ts`

**変更内容**: 変更なし
- `type: "image" | "video" | "file"` の `"video"` は後方互換のため残す（Firestoreの既存データ読み取りに必要）

---

### カテゴリ5: Storageルール

#### 5-1. `firebase/storage.rules`

**変更内容**:

1. `isValidVideoSize()` 関数を削除（L30-32）
   ```
   // 削除
   function isValidVideoSize() {
     return request.resource.size < 100 * 1024 * 1024;
   }
   ```

2. `isVideo()` 関数を削除（L42-44）
   ```
   // 削除
   function isVideo() {
     return request.resource.contentType.matches('video/.*');
   }
   ```

3. Post videos パスのルールを削除（L79-86）
   ```
   // 削除
   match /posts/{userId}/videos/{fileName} {
     allow read: if isAuthenticated();
     allow write: if isAuthenticated()
                  && request.auth.uid == userId
                  && isValidVideoSize()
                  && isVideo();
     allow delete: if isAuthenticated() && request.auth.uid == userId;
   }
   ```

4. Post thumbnails パスのルールを削除（L89-96）
   ```
   // 削除
   match /posts/{userId}/thumbnails/{fileName} {
     allow read: if isAuthenticated();
     allow write: if isAuthenticated()
                  && request.auth.uid == userId
                  && isValidProfileSize()
                  && isImage();
     allow delete: if isAuthenticated() && request.auth.uid == userId;
   }
   ```

**注意**: 既存の動画・サムネイルファイルはStorageに残るが、readルールが削除されるため、既存動画のサムネイルURLがCDN経由でキャッシュされていない場合はアクセスできなくなる。ただし `post_card.dart` でサムネイルURLを `CachedNetworkImage` で表示しており、Firebase Storage URLにはトークンが含まれているため、Storageルール削除後もURLトークンが有効な間はアクセス可能。長期的にはアクセス不可となるが、動画アイコンのフォールバック表示で対応済み。

---

## 処理フロー

### 変更前（動画添付あり）
```
ユーザーがメディア追加ボタンをタップ
  ↓
BottomSheet表示:「写真を選択」「写真を撮影」「動画を選択」
  ↓ 「動画を選択」
_pickVideo() → ImagePicker.pickVideo()
  ↓
NsfwDetectorService.checkVideo() → VideoThumbnail でサムネイル抽出 → NSFW判定
  ↓
MediaService.uploadFile(type: video)
  ↓
Firebase Storage posts/{userId}/videos/ にアップロード
  ↓
_generateAndUploadThumbnail() → posts/{userId}/thumbnails/ にサムネイルアップロード
  ↓
Cloud Functions: moderateVideo() → Gemini File API で動画モデレーション
  ↓
Cloud Functions: analyzeVideoForComment() → Gemini File API で動画分析
```

### 変更後（動画添付なし）
```
ユーザーがメディア追加ボタンをタップ
  ↓
BottomSheet表示:「写真を選択」「写真を撮影」
  ↓
_pickImages() or _takePhoto() → ImagePicker
  ↓
NsfwDetectorService.checkImage() → NSFW判定
  ↓
MediaService.uploadFile(type: image)
  ↓
Firebase Storage posts/{userId}/images/ にアップロード
  ↓
Cloud Functions: moderateImage() → 画像モデレーション
  ↓
Cloud Functions: analyzeImageForComment() → 画像分析
```

### 既存動画付き投稿の表示フロー
```
PostCard が MediaItem(type: video) を受信
  ↓
thumbnailUrl が存在する → サムネイル画像を静止画像として表示
thumbnailUrl が存在しない → videocam_off アイコンを表示
  ↓
タップしても再生画面には遷移しない（onTap なし）
```

---

## 後方互換性

| 項目 | 対応方針 |
|------|---------|
| `MediaType.video` enum | 残す（Firestoreの既存データデシリアライズに必要） |
| 既存動画付き投稿のFirestoreデータ | 変更なし。`mediaItems` 内に `type: "video"` のアイテムがそのまま残る |
| 既存動画ファイル（Storage） | 削除しない。自然に残す |
| 既存サムネイルファイル（Storage） | 削除しない。自然に残す |
| 既存動画付き投稿の表示 | サムネイルがあればサムネイル画像を静止画として表示。なければ動画アイコン（`videocam_off`）のみ表示 |
| 既存動画の再生 | 不可（`VideoPlayerScreen` を削除するため） |
| `functions/src/types/index.ts` の `"video"` 型 | 残す（既存データの型整合性維持のため） |
| プロフィール画面の動画アイコン表示 | 削除（`profile_post_card.dart` の動画カウント表示を削除） |

---

## 削除されるファイル一覧

| ファイルパス | 理由 |
|-------------|------|
| `lib/shared/widgets/video_player_screen.dart` | 動画再生画面の全コード |

---

## 削除されるパッケージ一覧

| パッケージ | バージョン | 理由 |
|-----------|-----------|------|
| `video_player` | `^2.9.3` | 動画再生に使用。機能削除に伴い不要 |
| `chewie` | `^1.10.0` | 動画再生UIコントロール。機能削除に伴い不要 |
| `video_thumbnail` | `^0.5.6` | 動画サムネイル生成。機能削除に伴い不要 |

---

## テスト観点

### クライアント側

1. **投稿作成画面**
   - メディア追加BottomSheetに「写真を選択」「写真を撮影」の2項目のみ表示されること
   - 「動画を選択」オプションが存在しないこと
   - 画像の選択・撮影・NSFW判定・アップロードが従来通り正常に動作すること

2. **投稿表示（PostCard）**
   - 画像のみの投稿が正常に表示されること
   - 既存の動画付き投稿（サムネイルあり）でサムネイル画像が表示されること
   - 既存の動画付き投稿（サムネイルなし）で `videocam_off` アイコンが表示されること
   - 既存動画付き投稿のメディアをタップしても再生画面に遷移しないこと
   - 画像と動画が混在する既存投稿で、画像は通常表示・動画はサムネイル/アイコン表示となること

3. **プロフィール投稿カード**
   - 動画アイコン・動画カウントが表示されないこと
   - 画像アイコン・画像カウントは従来通り表示されること

4. **ビルド確認**
   - `flutter pub get` が正常に完了すること
   - `flutter build apk` / `flutter build ios` がエラーなく完了すること
   - 未使用インポートの警告が出ないこと

### サーバー側

5. **メディアモデレーション**
   - 画像モデレーションが従来通り正常に動作すること
   - `moderateMedia()` が画像のみ処理し、動画タイプのアイテムをスキップすること

6. **メディア分析（AIコメント用）**
   - 画像分析が従来通り正常に動作すること
   - `analyzeMediaForComment()` が画像のみ分析し、動画タイプのアイテムをスキップすること

7. **Storageルール**
   - `firebase deploy --only storage` が正常に完了すること
   - 画像のアップロード・読み取りが従来通り動作すること
   - 動画パスへの新規アップロードが拒否されること

### 回帰テスト

8. **既存機能への影響なし確認**
   - 画像添付投稿の作成 → 表示 → モデレーション → AIコメント生成の全フローが正常動作すること
   - プロフィール画面の投稿一覧表示が正常であること
   - サークル投稿の画像添付が正常であること
