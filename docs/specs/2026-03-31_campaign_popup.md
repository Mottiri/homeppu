# キャンペーンポップアップ機能 詳細設計書

## 1. 概要

アプリ内でキャンペーン情報をポップアップダイアログとして表示する機能。Firestoreからキャンペーンデータを取得し、期間・既読状態に応じて未読キャンペーンを表示する。

### 1.1 表示タイミング
- **初期ユーザー（チュートリアル未完了）**: チュートリアルフェーズ1完了直後
- **既存ユーザー（チュートリアル完了済み）**: ホーム画面の安定状態到達時

### 1.2 非表示制御
- 「今後表示しない」ボタン押下でキャンペーンIDをSharedPreferencesに記録（**端末単位**）
- 「閉じる」ボタンは一時的な閉じ操作（次回起動で再表示）
- 新規キャンペーンは既存の非表示設定に影響されない
- **端末単位の理由**: Firestoreへの書き込みコストを避けるため。複数端末で同じキャンペーンが表示されても実害はない

### 1.3 表示上限
- **1セッションあたり最大3件**まで表示（設定ミスによる大量モーダル防止）
- 未表示分は次回起動時に表示

---

## 2. Firestoreデータ構造

### 2.1 ドキュメントパス
```
settings/campaigns
```

### 2.2 Firestore Security Rules

既存の `settings` コレクションルール（`firestore.rules` L236-242）に `campaigns` を追加:

```firestore
match /settings/{docId} {
  allow read: if isAuthenticated() && (
    docId == "stampSheetCatalog" ||
    docId == "stampSheetLayoutCatalog" ||
    docId == "campaigns"
  );
  allow write: if false;
}
```

- **読み取り**: `isAuthenticated()`（認証済みユーザー）に許可
- **書き込み**: 完全禁止（Firebase Console からのみ管理）
- **公開範囲**: キャンペーン情報は全認証ユーザーに公開して問題ない（機密情報を含まない。BANユーザーに表示されても実害なし）

### 2.3 ドキュメント構造
```json
{
  "campaigns": [
    {
      "id": "release_celebration",
      "title": "リリース記念キャンペーン",
      "body": "ほめっぷのリリースを記念して\n期間限定アセットが登場！",
      "imagePath": "assets/campaigns/release_celebration.webp",
      "footerNote": "徳ポイントを使って各画面から購入できます",
      "startDate": "<Timestamp>",
      "endDate": "<Timestamp>",
      "isActive": true
    }
  ]
}
```

### 2.4 フィールド仕様

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `id` | string | 必須 | キャンペーンの一意識別子。SharedPreferencesのキーにも使用。終了したキャンペーンはドキュメントから削除する運用を想定 |
| `title` | string | 必須 | ポップアップのタイトル |
| `body` | string | 必須 | 本文。`\n`で改行対応 |
| `imagePath` | string | 省略可 | アプリバンドルアセットのパス。省略時はテキストのみ表示 |
| `footerNote` | string | 省略可 | フッターの補足テキスト |
| `startDate` | Timestamp | 必須 | キャンペーン開始日時（この時刻以降に表示） |
| `endDate` | Timestamp | 必須 | キャンペーン終了日の**翌日JST 00:00:00のUTC値**を設定する（exclusive end）。例: 4/30まで → JST 5/1 00:00 → UTC `2026-04-30T15:00:00Z`。**日付単位・JST前提運用専用** |
| `isActive` | boolean | 必須 | 手動制御フラグ。`false`で即時非表示 |

### 2.5 バリデーション（型検証を含む）

エントリを**スキップする**条件（`fromMap` に渡す前にチェック）:
- `id` が `String` でない、または空文字
- `title` が `String` でない
- `body` が `String` でない
- `startDate` が `Timestamp` でない
- `endDate` が `Timestamp` でない
- `isActive` が `bool` でなく `true` でもない
- `endDate` < 現在時刻（期限切れ）
- `startDate` > 現在時刻（まだ開始前）
- `isActive` が `false`

### 2.6 期間判定の境界条件

- **開始**: `now >= startDate`（`isAfter` ではなく `!isBefore` を使用し、開始時刻ちょうどを含む）
- **終了**: `now < endDate`（`isBefore` を使用し、終了時刻ちょうどは含まない）
- **タイムゾーン**: 本アプリは**日本国内向け（JST固定）**。Firestoreの `Timestamp` はUTCで保存される。管理者がFirebase Consoleで設定する際は**JST基準で翌日00:00のUTC値**を設定する（例: 「4/30まで」→ JST 5/1 00:00 → UTC `2026-04-30T15:00:00Z`）。**コード内では `CampaignModel._nowJst()` で UTC+9h 固定の現在時刻を取得し、`startDate`/`endDate` も `tryFromMap` 内で JST 変換済みの状態で保持する。端末のローカルタイムゾーン設定には依存しない。**
- **endDate は exclusive end（JST基準）**: 常に「この時刻の直前まで表示」。日付単位運用では**翌日JST 00:00のUTC値**を保存する（例: 「4/30まで」→ JST 5/1 00:00 → UTC `2026-04-30T15:00:00Z`）
- **UI表示**: `endDate`（ローカル変換後）から1日引いた日を `M/d` 形式で表示（exclusive end前提のため。例: JST `2026-05-01T00:00:00` → 「4/30まで」）

---

## 3. クライアント側データモデル

### 3.1 CampaignModel

**ファイル**: `lib/shared/models/campaign_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CampaignModel {
  final String id;
  final String title;
  final String body;
  final String? imagePath;
  final String? footerNote;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  const CampaignModel({
    required this.id,
    required this.title,
    required this.body,
    this.imagePath,
    this.footerNote,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  /// safe parse: 型不正時は null を返す（呼び出し側でスキップ）
  /// 必須・optional 全フィールドの型検証を行い、例外を一切投げない
  static CampaignModel? tryFromMap(Map<String, dynamic> map) {
    // 必須フィールドの型検証
    final id = map['id'];
    final title = map['title'];
    final body = map['body'];
    final startDate = map['startDate'];
    final endDate = map['endDate'];
    final isActive = map['isActive'];

    if (id is! String || id.isEmpty) return null;
    if (title is! String) return null;
    if (body is! String) return null;
    if (startDate is! Timestamp) return null;
    if (endDate is! Timestamp) return null;
    if (isActive is! bool) return null;

    // optional フィールドの型検証（null は許容、非null時はString必須）
    final imagePathRaw = map['imagePath'];
    if (imagePathRaw != null && imagePathRaw is! String) return null;
    final footerNoteRaw = map['footerNote'];
    if (footerNoteRaw != null && footerNoteRaw is! String) return null;

    // Timestamp.toDate() はUTC DateTimeを返す → JST(+9h)に変換
    // _nowJst() と同じ基準で比較するため、保存時点でJST変換しておく
    final startDateJst = startDate.toDate().toUtc().add(const Duration(hours: 9));
    final endDateJst = endDate.toDate().toUtc().add(const Duration(hours: 9));

    return CampaignModel(
      id: id,
      title: title,
      body: body,
      imagePath: imagePathRaw as String?,
      footerNote: footerNoteRaw as String?,
      startDate: startDateJst,
      endDate: endDateJst,
      isActive: isActive,
    );
  }

  /// JST基準の現在時刻を取得（端末タイムゾーン非依存）
  static DateTime _nowJst() {
    final utcNow = DateTime.now().toUtc();
    return utcNow.add(const Duration(hours: 9));
  }

  /// 現在有効なキャンペーンか判定（JST基準）
  bool get isCurrentlyActive {
    final now = _nowJst();
    return isActive && !now.isBefore(startDate) && now.isBefore(endDate);
  }
}
```

変更点:
- `fromMap` → `tryFromMap`（null返却型のsafe parse）
- 型検証を `tryFromMap` 内で実施（`Timestamp` キャスト例外を防止）
- 期間判定: `isAfter` → `!isBefore`（開始時刻ちょうどを含む）
- **JST固定変換**: `_nowJst()` でUTC+9h固定の現在時刻を取得。`startDate`/`endDate` も `tryFromMap` 内でJST変換済みの状態で保持。端末タイムゾーンに依存しない

---

## 4. Service設計

### 4.1 CampaignService

**ファイル**: `lib/shared/services/campaign_service.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/campaign_model.dart';

class CampaignService {
  static const String _dismissedKeyPrefix = 'campaign_dismissed_';
  static const int maxDisplayPerSession = 3;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<CampaignModel>> getActiveCampaigns() async {
    try {
      final doc = await _firestore.doc('settings/campaigns').get();
      if (!doc.exists) return [];
      final data = doc.data();
      if (data == null) return [];

      final rawList = data['campaigns'];
      if (rawList is! List) return [];

      final campaigns = <CampaignModel>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final campaign = CampaignModel.tryFromMap(map);
        if (campaign == null) continue;
        if (!campaign.isCurrentlyActive) continue;
        campaigns.add(campaign);
      }
      return campaigns;
    } catch (e) {
      debugPrint('キャンペーン取得エラー: $e');
      return [];
    }
  }

  Future<void> dismiss(String campaignId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_dismissedKeyPrefix$campaignId', true);
  }

  Future<List<CampaignModel>> getUnreadCampaigns() async {
    final campaigns = await getActiveCampaigns();
    final prefs = await SharedPreferences.getInstance();
    return campaigns.where((c) {
      return !(prefs.getBool('$_dismissedKeyPrefix${c.id}') ?? false);
    }).toList();
  }
}
```

変更点:
- `getActiveCampaigns` を `try-catch` で囲み、エラー時は空リスト返却（サイレントスキップ）
- `tryFromMap` を使用し、型不正エントリは自動スキップ
- `maxDisplayPerSession` 定数を定義（表示側で使用）

---

## 5. Provider設計

**ファイル**: `lib/shared/providers/campaign_provider.dart`

```dart
final campaignServiceProvider = Provider<CampaignService>((ref) => CampaignService());

final unreadCampaignsProvider = FutureProvider<List<CampaignModel>>((ref) async {
  final service = ref.read(campaignServiceProvider);
  return service.getUnreadCampaigns();
});
```

---

## 6. 表示フロー

### 6.1 表示前提条件（全ユーザー共通）

キャンペーンポップアップは以下の条件を満たす場合に表示する:

1. `currentUser.tutorialPhase1Completed == true`（チュートリアルPhase1完了済み）
2. `_campaignPopupsShown == false`（セッション内で未表示）

**`_campaignPopupsShown`**: 表示済みフラグ（最初のダイアログ表示成功後に `true`）。通信失敗時はセットされないため、次回 `build()` で再試行可能。

```dart
bool _canShowCampaignPopups() {
  final user = ref.read(currentUserProvider).valueOrNull;
  if (user == null) return false;
  if (!user.tutorialPhase1Completed) return false;
  if (_campaignPopupsShown) return false;
  return true;
}
```

実装位置: `build()` 内の既存副作用（BAN遷移、チュートリアル遷移）の**後方**に配置し、`addPostFrameCallback` で非同期実行する。

### 6.2 既存ユーザー（tutorialPhase1Completed == true）

```
MainShell.build()
  → _canShowCampaignPopups() == true
  → _campaignPopupsShown = true（予約前にセット — 同フレーム複数build対策）
  → addPostFrameCallback で _showCampaignPopupsIfNeeded() を実行
```

**重要**: `_campaignPopupsShown = true` を `addPostFrameCallback` 予約**前**にセットする。Flutterの `build()` は1フレーム中に複数回呼ばれることがあるため、予約前にフラグを立てて重複予約を防止。

### 6.3 初期ユーザー（Phase1を今完了した場合）

```
_onPhase1StepChanged(prev, next) で検知:
  → prev != null
  → prev != TutorialPhase1Step.inactive（遷移前はアクティブだった）
  → next == TutorialPhase1Step.inactive（完了して inactive に）
  → !_campaignPopupsShown
  → _campaignPopupsShown = true（予約前にセット）
  → addPostFrameCallback で _showCampaignPopupsIfNeeded() を実行
```

注意: `restoreOrStart()` による復元時は `prev == null`（`fireImmediately: true` の初回発火）のため、この条件には合致しない。これにより初回完了と復元を区別できる。

**既存リスナーとの整合性**: キャンペーン表示トリガーは既存ロジックの**後方に追加**し、既存の条件分岐には干渉しない。

### 6.4 _showCampaignPopupsIfNeeded

```dart
Future<void> _showCampaignPopupsIfNeeded() async {
  if (!mounted) {
    _campaignPopupsShown = false; // リセットして次回再試行可能に
    return;
  }

  try {
    final service = ref.read(campaignServiceProvider);
    final campaigns = await service.getUnreadCampaigns();

    if (!mounted || campaigns.isEmpty) {
      _campaignPopupsShown = false; // 取得失敗・空の場合はリセット
      return;
    }

    final displayLimit = CampaignService.maxDisplayPerSession;
    for (var i = 0; i < campaigns.length && i < displayLimit; i++) {
      if (!mounted) return;

      await showCampaignDialog(
        context: context,
        campaign: campaigns[i],
        service: service,
      );
    }
  } catch (e) {
    debugPrint('キャンペーン表示エラー: $e');
    _campaignPopupsShown = false; // エラー時はリセットして次回再試行
  }
}
```

**フラグ制御のポイント:**
- `_campaignPopupsShown` を `build()` / `_onPhase1StepChanged` 内で予約**前**にセットし、同フレーム内の重複予約を防止
- 通信失敗・空レスポンス・`!mounted` の場合はフラグをリセットし、次回 `build()` で再試行可能
- ダイアログ表示成功後はフラグが `true` のまま維持され、同セッション内で再表示しない

---

## 7. UI設計

### 7.1 Widget構成

**ファイル**: `lib/shared/widgets/campaign_popup_dialog.dart`

```
showCampaignDialog()
  └─ Dialog (borderRadius: 24)
       └─ Container (maxWidth: 340, maxHeight: 画面高さ * 0.75)
            └─ Column
                 ├─ Flexible
                 │    └─ SingleChildScrollView
                 │         ├─ タイトル (titleLarge, bold)
                 │         ├─ 本文 (bodyMedium)
                 │         ├─ [if imagePath] キャンペーン画像
                 │         │    └─ ClipRRect(borderRadius: 12)
                 │         │         └─ Image.asset(errorBuilder: 非表示フォールバック)
                 │         ├─ [if footerNote] フッターノート (bodySmall)
                 │         └─ 期限表示 AppMessages.campaignEndDate(M/d)
                 └─ ボタンエリア（固定）
                      ├─ AppMessages.label.close (FilledButton, AppColors.primary)
                      └─ AppMessages.label.dontShowAgain (TextButton, 控えめ)
```

**全UI文言は `AppMessages` 経由で参照する**（プロジェクト規約: ハードコード禁止）。

### 7.2 期限表示のフォーマット

```dart
String _formatEndDate(DateTime endDate) {
  // endDate は tryFromMap 内で JST 変換済み（翌日JST 0時）なので、前日を表示
  // 端末タイムゾーンに依存しない
  final displayDate = endDate.subtract(const Duration(days: 1));
  return AppMessages.campaignEndDate(displayDate.month, displayDate.day);
}
```

### 7.3 AppMessages 定数

ボタン文言は既存の共通ラベルを再利用する（重複定義しない）:

```dart
// 既存（lib/core/constants/app_messages.dart L227, L243）— そのまま使用
String get close => '閉じる';          // AppMessages.label.close
String get dontShowAgain => '今後表示しない';  // AppMessages.label.dontShowAgain

// 新規追加（キャンペーン固有の文言のみ）
static String campaignEndDate(int month, int day) => '〜$month/$dayまで';
```

### 7.4 デザイン方針
- 暖色系パステルカラー（AppColors.primary）
- 角丸24px（既存ダイアログと統一）
- barrierDismissible: false（明示的にボタンで閉じる）
- `AppMessages.label.close` を主ボタン、`AppMessages.label.dontShowAgain` は控えめなTextButton
- CONCEPT.mdの「安全な空間」に合致する押しつけがましくないUI
- 画像アセットが存在しない場合は `errorBuilder` で画像部分を非表示にフォールバック

---

## 8. SharedPreferences管理

| キー | 値 | 説明 |
|---|---|---|
| `campaign_dismissed_{campaignId}` | `true` | 今後表示しない設定済み |
| 未設定（null） | - | 未読・表示対象 |

- **スコープ**: 端末単位（アカウント単位ではない）
- **理由**: Firestoreへの書き込みコスト回避。複数端末で同じキャンペーンが表示されても実害なし
- **将来拡張**: アカウント同期が必要になった場合、キー形式を維持したまま Firestore の `users/{uid}/preferences` に移行可能

---

## 9. ファイル構成

### 9.1 新規作成

| ファイルパス | 説明 |
|---|---|
| `lib/shared/models/campaign_model.dart` | キャンペーンデータモデル |
| `lib/shared/services/campaign_service.dart` | Firestore読み取り + SharedPreferences |
| `lib/shared/providers/campaign_provider.dart` | Riverpod Provider |
| `lib/shared/widgets/campaign_popup_dialog.dart` | ポップアップUI |
| `assets/campaigns/` | キャンペーン画像格納ディレクトリ |

### 9.2 既存ファイル変更

| ファイルパス | 変更内容 |
|---|---|
| `lib/features/home/presentation/screens/main_shell.dart` | キャンペーン表示トリガー追加（`_campaignPopupsShown` フラグ、`_canShowCampaignPopups()` ガード関数、`_onPhase1StepChanged` の条件追加、`build()` 内のチェック） |
| `lib/core/constants/app_messages.dart` | キャンペーン関連メッセージ追加 |
| `pubspec.yaml` | `assets/campaigns/` 追加 |
| `firebase/firestore.rules` | `settings/campaigns` の読み取り許可追加 |

---

## 10. エッジケース考慮

- **同フレーム複数build()**: `_campaignPopupsShown` を `addPostFrameCallback` 予約**前**にセットすることで重複予約を防止
- **Firestoreアクセスエラー**: `try-catch` でサイレントスキップ。`_campaignPopupsShown` をリセットし次回再試行可能
- **画像アセット不在**: `Image.asset` の `errorBuilder` で画像部分を非表示にフォールバック
- **チュートリアルとの競合**: `tutorialPhase1Completed == true` でのみ表示。`_onPhase1StepChanged` は `prev != null && next == inactive` でのみトリガーし、復元時（`prev == null`）は除外
- **BAN状態のユーザー**: ポップアップ表示自体は許容（実害なし）。Firestore readは認証済みなら可能
- **アプリ再起動**: `_campaignPopupsShown` はインメモリフラグ。「閉じる」のみのキャンペーンは再表示、「今後表示しない」はSharedPreferencesで永続化
- **複数キャンペーンの表示順序**: Firestoreの配列順序で表示。1セッション最大3件
- **型不正データ**: `tryFromMap` で型検証。不正エントリは自動スキップ（例外を投げない）
- **期間境界**: 開始時刻ちょうどは含む（`!isBefore`）、終了時刻ちょうどは含まない（`isBefore`）

---

## 11. 実装順序

1. `firebase/firestore.rules` に `campaigns` の読み取り許可追加 + デプロイ
2. `CampaignModel` 作成（`tryFromMap` での safe parse）
3. `CampaignService` 作成（Firestore読み取り + SharedPreferences）
4. `campaign_provider.dart` 作成
5. `campaign_popup_dialog.dart` 作成
6. `app_messages.dart` にメッセージ追加
7. `assets/campaigns/` ディレクトリ + `pubspec.yaml` 更新
8. `main_shell.dart` に表示トリガー追加
9. Firestoreにテストデータ投入 + 動作確認

---

## 12. 検証項目

実装後に以下の境界条件を確認する:

| # | 検証項目 | 期待結果 |
|---|---------|---------|
| 1 | チュートリアル未完了ユーザーでアプリ起動 | ポップアップが表示されない |
| 2 | チュートリアルPhase1完了直後 | ポップアップが表示される |
| 3 | チュートリアル復元時（`restoreOrStart()` → `prev == null`） | ポップアップが表示されない（既存ユーザー経路で表示） |
| 4 | 通信失敗（Firestoreタイムアウト等）後、次回 `build()` 発火 | 再試行される（`_campaignPopupsShown` がリセット済み） |
| 5 | Firestore配列に型不正エントリ混在 | 正常エントリのみ表示、クラッシュなし |
| 6 | 3件以上のキャンペーンが未読状態 | 最大3件まで表示、残りは次回起動時 |
| 7 | 「今後表示しない」押下後、アプリ再起動 | そのキャンペーンは表示されない |
| 8 | 「閉じる」のみで閉じた後、アプリ再起動 | そのキャンペーンが再表示される |

---

## 13. リスクと対策


| リスク | 対策 |
|---|---|
| Firestore読み取りコスト | 起動時1回のみ読み取り。リアルタイムリスナー不使用 |
| 画像アセットのアプリサイズ増加 | WebP形式で圧縮。将来的にリモート画像対応も可能 |
| チュートリアル中の表示タイミング | Phase1完了を確実に待ち、復元と初回完了を区別 |
| 大量キャンペーン設定ミス | 1セッション最大3件の表示上限 |
| 型不正データによるクラッシュ | tryFromMap での safe parse |

## 14. 次のアクション担当者

- **デザイナー**: キャンペーン画像の作成、ポップアップUIの最終デザイン確認
- **実装者**: 上記設計に基づくコード実装
- **ユーザー**: キャンペーン画像の提供、文言の最終確認
