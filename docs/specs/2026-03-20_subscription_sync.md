# サブスクリプション同期 詳細設計書

## 1. 背景・課題

### 現状の問題
ユーザーがRevenueCat経由で定期購入を完了しても、Firestoreの`users/{uid}.isSubscriber`が更新されないケースが発生。

### 原因分析
既存のWebhook実装（`functions/src/http/revenuecat.ts`）は`INITIAL_PURCHASE`/`RENEWAL`/`PRODUCT_CHANGE`等を正しく処理する実装済み。しかし本番環境では以下のいずれかの原因でFirestoreが更新されていない:

- RevenueCat側のWebhook配送に欠損がある可能性（配送ログで要確認）
- RevenueCat側の`app_user_id`/`aliases`/`transferred_to`の識別子運用に問題がある可能性（匿名ID→Firebase UID移行時）
- 初回購入時のイベント種別がWebhookに到達していない可能性

### 確認項目（運用側）
- [ ] RevenueCatダッシュボードのWebhook配送ログで、該当ユーザーのイベント到達有無を確認
- [ ] 該当ユーザーの`app_user_id`/`aliases`/`transferred_to`の実データを確認
- [ ] 初回購入時に送信されたイベント種別を確認

### 対策方針
上記の根本原因調査と並行して、**フォールバック策**としてCallable Cloud Functionによる能動的同期を実装する。Webhookが正常に動作する場合でも、Callableによる二重チェックは安全性を高める。

### 影響
- ユーザーが課金済みなのにアプリ上で未課金と表示される（最悪のケース）
- PayWall画面で再購入ボタンが表示され、二重課金のリスク

---

## 2. 解決方針

Callable Cloud Functionを新設し、RevenueCat REST APIでサーバー側検証を行い、Firestoreを更新する。既存Webhookはそのまま維持し、Callableはフォールバック策として能動的同期を追加する。

### アーキテクチャ
```
[Flutter App]
  ├─ 購入成功後 → syncSubscriptionStatus() 呼び出し
  ├─ アプリ起動時 → syncSubscriptionStatus() (fire-and-forget)
  ├─ CustomerInfoリスナー → syncSubscriptionStatus() (fire-and-forget)
  └─ アプリ復帰時 → syncSubscriptionStatus() (fire-and-forget)
         ↓
[Cloud Function: syncSubscriptionStatus]
  ├─ requireAuth() で認証確認
  ├─ RevenueCat REST API (GET /v1/subscribers/{uid}) で検証
  ├─ Firestore users/{uid}.isSubscriber を更新
  └─ { isSubscriber: boolean } を返却
         ↓
[Firestore]
  └─ currentUserProvider (StreamProvider) が変更を検知 → UI自動更新
```

---

## 3. 実装詳細

### 3.1 Cloud Function: `syncSubscriptionStatus`

**ファイル:** `functions/src/callable/subscription.ts` (新規)

```typescript
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { LOCATION } from "../config/constants";
import { COLLECTIONS } from "../config/collections";
import { revenueCatServerApiKey } from "../config/secrets";
import { SYSTEM_ERRORS, SUBSCRIPTION_ERRORS } from "../config/messages";

export const syncSubscriptionStatus = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
    secrets: [revenueCatServerApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    const userId = requireAuth(request);

    const apiKey = revenueCatServerApiKey.value();
    if (!apiKey) {
      console.error("REVENUECAT_SERVER_API_KEY is not set");
      throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
    }

    // RevenueCat REST API でサブスクリプション情報を取得
    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      {
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!response.ok) {
      console.error(`RevenueCat API error: ${response.status} ${response.statusText}`);
      throw new HttpsError("internal", SUBSCRIPTION_ERRORS.SYNC_FAILED);
    }

    const data = await response.json();

    // アクティブなエンタイトルメントの確認
    const entitlements = data?.subscriber?.entitlements ?? {};
    const nowMs = Date.now();
    const isSubscriber = Object.values(entitlements).some((e: any) => {
      const expiresDate = e.expires_date ? new Date(e.expires_date).getTime() : null;
      return expiresDate === null || expiresDate > nowMs;
    });

    // Firestore 更新（webhook handler と同じパターン + メタデータ）
    await db.collection(COLLECTIONS.USERS).doc(userId).set(
      {
        isSubscriber,
        subscriptionLastSyncedAt: FieldValue.serverTimestamp(),
        subscriptionSource: "callable",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log(`syncSubscriptionStatus: userId=${userId}, isSubscriber=${isSubscriber}`);
    return { isSubscriber };
  }
);
```

**設計根拠:**
- `enforceAppCheck: true` — 全callableで統一されたパターン
- `requireAuth()` — `helpers/auth.ts` の既存ヘルパー
- `{ merge: true }` — `revenuecat.ts:167` の既存webhook handlerと同じ更新パターン
- RevenueCat REST APIのレスポンス形式: `subscriber.entitlements` にエンタイトルメント情報が含まれる
- `expires_date` は ISO 8601 文字列（RevenueCat API v1 の仕様）
- `subscriptionLastSyncedAt` / `subscriptionSource` — 障害切り分け用メタデータ（運営がFirestoreを見るだけで「いつ、どのソースで更新されたか」を即座に判断可能）

### 3.1b 既存Webhook handlerへのメタデータ追加

**ファイル:** `functions/src/http/revenuecat.ts` (既存修正)

Firestore更新部分（167行目付近）にメタデータを追加:
```typescript
await db.collection(COLLECTIONS.USERS).doc(userId).set(
    {
        isSubscriber,
        subscriptionLastSyncedAt: FieldValue.serverTimestamp(),
        subscriptionSource: "webhook",
        updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
);
```

### 3.2 メッセージ定数追加

**ファイル:** `functions/src/config/messages.ts`

```typescript
// SYSTEM_ERRORS セクションの後に追加
export const SUBSCRIPTION_ERRORS = {
    SYNC_FAILED: "サブスクリプション情報の取得に失敗しました",
} as const;
```

### 3.3 シークレット追加

**ファイル:** `functions/src/config/secrets.ts`

```typescript
// 追加行
export const revenueCatServerApiKey = defineSecret("REVENUECAT_SERVER_API_KEY");
```

**注意:** Flutter側の`REVENUECAT_API_KEY`（公開SDK鍵）とは異なるサーバー用秘密鍵。RevenueCatダッシュボードの Project Settings > API Keys > Secret API key から取得。

### 3.4 エクスポート追加

**ファイル:** `functions/src/index.ts`

```typescript
// 追加行
export { syncSubscriptionStatus } from "./callable/subscription";
```

### 3.5 Flutter: `subscription_service.dart` 変更

**ファイル:** `lib/shared/services/subscription_service.dart`

追加内容:
```dart
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants/app_constants.dart';

// クラス内に追加
bool _listenerAttached = false;
DateTime? _lastSyncAt;
static const _minSyncInterval = Duration(seconds: 30);

/// Cloud Functionを呼び出してサブスクリプション状態を同期
/// - 前回syncから30秒以内の場合はスキップ（過剰呼び出し防止）
/// - force: true で間隔チェックをバイパス（購入直後など）
/// 成功時: isSubscriberの値を返却
/// 失敗時: falseを返却（エラーログ出力）
Future<bool> syncSubscriptionStatus({bool force = false}) async {
  // debounce: 前回syncから最小間隔未満ならスキップ
  if (!force && _lastSyncAt != null) {
    final elapsed = DateTime.now().difference(_lastSyncAt!);
    if (elapsed < _minSyncInterval) {
      if (kDebugMode) {
        debugPrint('syncSubscriptionStatus skipped (debounce: ${elapsed.inSeconds}s)');
      }
      return false;
    }
  }

  try {
    final functions = FirebaseFunctions.instanceFor(
      region: AppConstants.functionsRegion,
    );
    final callable = functions.httpsCallable(
      'syncSubscriptionStatus',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call();
    _lastSyncAt = DateTime.now();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['isSubscriber'] == true;
  } catch (e) {
    debugPrint('syncSubscriptionStatus failed: $e');
    return false;
  }
}

/// CustomerInfoリスナーを登録（エンタイトルメント変更時に自動sync）
/// 複数回呼び出しても安全（_listenerAttachedフラグで重複防止）
void attachCustomerInfoListener() {
  if (!_configured || _listenerAttached) return;
  _listenerAttached = true;

  Purchases.addCustomerInfoUpdateListener((customerInfo) {
    final hasActive = customerInfo.entitlements.active.isNotEmpty;
    if (hasActive) {
      syncSubscriptionStatus(); // fire-and-forget
    }
  });

  if (kDebugMode) {
    debugPrint('RevenueCat CustomerInfo listener attached.');
  }
}
```

**設計根拠:**
- `FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion)` — `circle_service.dart` 等と同じ呼び出しパターン
- エラー時は`false`を返しクラッシュしない — 購入自体は成功しているため、syncの失敗でアプリを壊さない
- リスナーはアクティブなエンタイトルメントがある場合のみsync呼び出し — 無駄なAPI呼び出しを防止

### 3.6 Flutter: `subscription_screen.dart` 変更

**ファイル:** `lib/features/profile/presentation/screens/subscription_screen.dart`

#### 購入フロー修正（`_purchase()` メソッド）

```dart
Future<void> _purchase() async {
  if (_package == null) {
    _showPurchaseFailedDialog();
    return;
  }
  setState(() => _isProcessing = true);
  try {
    // 1. RevenueCat購入実行
    await SubscriptionService.instance.purchasePackage(_package!);

    // 2. サーバー側同期（30秒timeout、購入直後なのでforce: true）
    final isSubscriber = await SubscriptionService.instance
        .syncSubscriptionStatus(force: true)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => false,
        );

    // 3. Firestoreストリーム再取得
    ref.invalidate(currentUserProvider);

    if (mounted) {
      if (isSubscriber) {
        // sync成功 → 成功メッセージ
        SnackBarHelper.showSuccess(
          context,
          AppMessages.success.purchaseCompleted,
        );
      } else {
        // sync未確認 → 待機状態（既存UIで「有効化中...」表示）
        setState(() => _isAwaitingSubscriptionSync = true);
      }
    }
  } on PlatformException catch (e) {
    final errorCode = PurchasesErrorHelper.getErrorCode(e);
    if (errorCode != PurchasesErrorCode.purchaseCancelledError && mounted) {
      _showPurchaseFailedDialog();
    }
  } catch (_) {
    if (mounted) {
      _showPurchaseFailedDialog();
    }
  } finally {
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }
}
```

#### PopScope追加（`build()` メソッド）

```dart
@override
Widget build(BuildContext context) {
  // ... 既存の変数宣言 ...

  return PopScope(
    canPop: !_isProcessing,  // 購入処理中は戻る操作をブロック
    child: Stack(
      children: [
        Scaffold(/* ... 既存のScaffold ... */),
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    ),
  );
}
```

#### 同期失敗時の回復導線

sync失敗（timeout含む）で`_isAwaitingSubscriptionSync = true`になった場合:

1. **30秒タイマー**: awaiting-sync状態開始から30秒後に自動的に回復UIを表示
2. **回復UI**: 「反映に時間がかかっています」メッセージ + 「購入を復元する」ボタン
3. **購入復元ボタン**: `SubscriptionService.instance.syncSubscriptionStatus(force: true)` を再実行
4. **それでも失敗**: 「運営にお問い合わせください」リンクを表示

```dart
// _isAwaitingSubscriptionSync = true 設定時に開始
Timer? _syncTimeoutTimer;

void _startSyncTimeout() {
  _syncTimeoutTimer?.cancel();
  _syncTimeoutTimer = Timer(const Duration(seconds: 30), () {
    if (mounted && _isAwaitingSubscriptionSync) {
      setState(() => _isAwaitingSubscriptionSync = false);
      _showSyncFailedDialog();
    }
  });
}

void _showSyncFailedDialog() {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppMessages.error.syncFailedTitle),
      content: Text(AppMessages.error.syncFailedMessage),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            _retrySyncSubscription();
          },
          child: Text(AppMessages.label.restorePurchase),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/inquiry');
          },
          child: Text(AppMessages.profile.inquiryTitle),
        ),
      ],
    ),
  );
}

Future<void> _retrySyncSubscription() async {
  setState(() => _isProcessing = true);
  try {
    final isSubscriber = await SubscriptionService.instance
        .syncSubscriptionStatus(force: true)
        .timeout(const Duration(seconds: 30), onTimeout: () => false);
    ref.invalidate(currentUserProvider);
    if (mounted) {
      if (isSubscriber) {
        SnackBarHelper.showSuccess(context, AppMessages.success.purchaseCompleted);
      } else {
        _showSyncFailedDialog(); // 再度失敗 → ダイアログ再表示
      }
    }
  } catch (_) {
    if (mounted) _showSyncFailedDialog();
  } finally {
    if (mounted) setState(() => _isProcessing = false);
  }
}
```

**変更前との差分:**
- `_purchase()`: purchasePackage成功後にsyncSubscriptionStatus呼び出しを追加
- `_purchase()`: `purchaseSucceeded`フラグ削除、sync結果で分岐
- `_purchase()`: sync失敗時に`_startSyncTimeout()`を呼び出し
- `build()`: `Stack`の外側に`PopScope`ラップ追加
- 新規: `_showSyncFailedDialog()` — 回復導線ダイアログ
- 新規: `_retrySyncSubscription()` — 再試行ロジック

### 3.7 Flutter: `main_shell.dart` 変更

**ファイル:** `lib/features/home/presentation/screens/main_shell.dart`

```dart
// initState() 内に追加（既存コードの後に）
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  // ... 既存のコード ...

  // サブスクリプション同期（アプリ起動時）
  SubscriptionService.instance.attachCustomerInfoListener();
  SubscriptionService.instance.syncSubscriptionStatus(); // fire-and-forget
}

// 新規メソッド追加
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  if (state == AppLifecycleState.resumed) {
    // アプリ復帰時にサブスクリプション状態を再同期
    SubscriptionService.instance.syncSubscriptionStatus(); // fire-and-forget
  }
}
```

**設計根拠:**
- `WidgetsBindingObserver` は既にmixin済み（:33行目）
- `didChangeAppLifecycleState` は未実装 → 新規追加
- fire-and-forget: 結果を待たない → UIブロックなし
- アプリ復帰時のsync: Play Store サブスクリプション管理画面から戻った場合を想定

### 3.8 ヘッダー画像の購読解除時降格（既存バグ修正）

**ファイル:** `functions/src/triggers/users.ts`

現在、サブスクリプション解除時（`isSubscriber: true → false`）にプロフィール画像とEpicパーツは降格されるが、**ヘッダー画像は降格されない**。PayWall画面でヘッダー画像をプレミアム特典として表示しているため、解約後もヘッダー画像が残るのは不整合。

**修正箇所:** `applySubscriptionFallbackIfNeeded` 関数（193行目付近）または `onUserUpdated` トリガー内の降格処理に、ヘッダー画像の削除を追加:

```typescript
// isSubscriber が false になった場合の降格処理に追加
if (afterData.headerImageUrl) {
  // Storage からヘッダー画像を削除
  await deleteStorageFileFromUrl(afterData.headerImageUrl);
  updates.headerImageUrl = FieldValue.delete();
}
```

**注意:** `deleteStorageFileFromUrl` は既存のヘルパー（`helpers/storage.ts`）を使用。

### 3.9 メッセージ追加

**ファイル:** `lib/core/constants/app_messages.dart`

```dart
// ErrorMessages クラスに追加
String get syncFailedTitle => '購入の反映に時間がかかっています';
String get syncFailedMessage => '購入は完了していますが、反映に時間がかかっています。\n「購入を復元する」をお試しください。';

// LabelMessages クラスに追加
String get restorePurchase => '購入を復元する';
```

---

## 4. セキュリティ考慮事項

| 項目 | 対策 |
|------|------|
| 認証 | `requireAuth()` でFirebase Auth認証済みユーザーのみ許可 |
| App Check | `enforceAppCheck: true` で正規アプリからのリクエストのみ許可 |
| クライアント信頼 | クライアントの主張は一切信用しない。常にRevenueCat APIで検証 |
| API鍵管理 | RevenueCatサーバー鍵はFirebase Secretで管理、クライアントには露出しない |
| Firestore rules | `isSubscriber` フィールドはクライアント書き込みブロック済み（既存） |
| レート制限 | App Checkで不正リクエストを防止。Flutter側で`_lastSyncAt`ベースの30秒最小間隔debounceを実装 |

---

## 5. エッジケース

| ケース | 対処 |
|--------|------|
| RevenueCat API ダウン | HttpsError返却、Flutter側catchしてawaiting-sync状態→Firestoreストリームで最終的に反映 |
| 通信タイムアウト | Flutter側30秒timeout、awaiting-sync状態にフォールバック |
| 購入中にアプリ終了 | 次回起動時のstartup syncでキャッチ |
| webhook と callable の競合 | 両方とも同じ値を`merge:true`で書くため問題なし |
| 戻るボタンで購入画面離脱 | PopScope(canPop: !_isProcessing)でブロック |
| listener重複登録 | `_listenerAttached`フラグで防止 |
| RevenueCatにユーザーレコードなし | 空のentitlementsとなり、isSubscriber: falseで更新 |
| エンタイトルメントが期限切れ | expires_date比較でisSubscriber: falseとなる |

---

## 6. コスト影響

- RevenueCat REST API: 無料（RevenueCat料金に含まれる）
- Cloud Function呼び出し: アプリ起動1回 + 購入1回 + CustomerInfo変更時 + アプリ復帰時 → 微量
- 追加Firestore書き込み: sync呼び出しごとに1 write → 微量
- メモリ: 256MiB（最小構成）

---

## 7. 実装順序

1. `functions/src/config/messages.ts` — `SUBSCRIPTION_ERRORS` 定数追加
2. `functions/src/config/secrets.ts` — `revenueCatServerApiKey` 追加
3. `functions/src/callable/subscription.ts` — 新規作成（メタデータ付きFirestore更新）
4. `functions/src/http/revenuecat.ts` — 既存webhook handlerにメタデータ追加（subscriptionLastSyncedAt, subscriptionSource）
5. `functions/src/triggers/users.ts` — ヘッダー画像の購読解除時降格処理追加
6. `functions/src/index.ts` — エクスポート追加
7. Firebase CLI — `firebase functions:secrets:set REVENUECAT_SERVER_API_KEY`
8. Functions デプロイ — `firebase deploy --only functions`
9. `lib/core/constants/app_messages.dart` — syncFailedTitle, syncFailedMessage, restorePurchase 追加
10. `lib/shared/services/subscription_service.dart` — sync(debounce付き) + listener 追加
11. `lib/features/profile/presentation/screens/subscription_screen.dart` — 購入フロー修正 + PopScope + 回復導線
12. `lib/features/home/presentation/screens/main_shell.dart` — 起動・復帰sync

---

## 8. 検証方法

1. Cloud Function デプロイ後、Firebase コンソールで`syncSubscriptionStatus`関数が表示されることを確認
2. RevenueCat テストユーザーで購入 → Firestore `isSubscriber: true` + `subscriptionSource: "callable"` + `subscriptionLastSyncedAt` が設定されることを確認
3. アプリ再起動 → startup sync のデバッグログ出力を確認
4. 購入処理中に戻るボタン → PopScopeでブロックされることを確認
5. `_isProcessing` 中のオーバーレイ → sync完了まで表示され続けることを確認
6. sync失敗シミュレーション → 30秒後に回復ダイアログが表示されることを確認
7. 回復ダイアログの「購入を復元する」ボタン → 再sync実行されることを確認
8. RevenueCat APIキー未設定時 → Cloud Functionがエラーログを出力し、アプリがクラッシュしないことを確認
9. サブスク解約 → ヘッダー画像がFirestoreから削除されることを確認（既存バグ修正）

---

## 9. リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| RevenueCat REST APIの仕様変更 | sync失敗 | エラーハンドリングで吸収、既存webhookがフォールバック |
| アプリ復帰時の大量sync呼び出し | コスト増 | `_lastSyncAt`ベースの30秒debounceで抑制。購入直後のみ`force: true`でバイパス |
| Secret未設定でのデプロイ | 全sync失敗 | ログ出力で即時検知可能。webhookは引き続き動作 |

---

## 10. 将来課題（今回スコープ外）

| 課題 | 概要 | 優先度 |
|------|------|--------|
| TRANSFER時の旧所有者解除 | transferred_from側のisSubscriber解除が未実装 | 低（現状同一ユーザーが複数UIDを持つケースは稀） |
| entitlement/product allowlist | どのentitlementがプレミアムかの明示的定義 | 低（現状プラン1つのみ） |
| プラットフォーム別API key | iOS対応時のRevenueCat APIキー分離 | 低（現状Android only） |
| 状態モデル拡張 | subscriptionExpiresAt, subscriptionEntitlement等の追加保持 | 中（運用負荷軽減） |

---

## 11. 次のアクション担当者

- **実装者:** 上記実装順序に従いコード実装
- **ユーザー:** RevenueCatダッシュボードからSecret API keyを取得し、Firebase Secretに設定
- **レビュワー:** 実装完了後にコードレビュー
