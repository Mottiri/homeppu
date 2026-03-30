# nonPurchasableItems（購入不可アイテム制御）詳細設計書

## 1. 背景・要件

### 1.1 背景
徳ショップで販売しているアイテム（アバターパーツ、名前パーツ、リアクションスタンプ、スタンプシート）の中には、期間限定で販売を停止したいケースがある。例えばリリース記念限定アイテムの販売期間終了後、アイテム自体は既購入ユーザーが引き続き使用できるが、新規購入は不可にしたい。

### 1.2 要件
1. 管理者がFirebase Consoleから特定アイテムの購入を停止・再開できること
2. 購入停止中のアイテムは、サーバー側で購入トランザクションを拒否すること
3. クライアント側で未購入かつ購入不可のアイテムをUI上ベストエフォートで非表示にすること（configキャッシュが最新であれば非表示、古い場合はサーバーが最終防御）
4. 既に購入済みのアイテムの使用（装備・送信等）には一切影響しないこと
5. スタンプシートの `isActive=false` は完全無効化（表示もされない）、`nonPurchasableItems` は購入のみブロック（カタログには購入済みなら表示）

### 1.3 対象外
- リアルタイムリスナーによる即座反映（コスト懸念のため不採用）
- 使用フロー（装備、スタンプ押下、リアクション送信）の変更
- 管理画面UIの構築（Firebase Console直接編集）

---

## 2. Firestoreデータ構造

### 2.1 ドキュメントパス
```
settings/virtueShop
```

### 2.2 追加フィールド
```json
{
  "nonPurchasableItems": {
    "avatar_part:hair_16": true,
    "stamp_sheet:sakura": true,
    "reaction_stamp:fire": true,
    "name_part:prefix_pre_26": true
  }
}
```

### 2.3 キーフォーマット仕様
```
{itemType}:{itemId}
```

| itemType | itemId例 | 完全キー例 |
|----------|----------|-----------|
| `name_part` | Firestoreドキュメント ID | `name_part:prefix_pre_26` |
| `avatar_part` | パーツID（hair_16等） | `avatar_part:hair_16` |
| `reaction_stamp` | リアクションID（fire等） | `reaction_stamp:fire` |
| `stamp_sheet` | シートID（sakura等） | `stamp_sheet:sakura` |

### 2.4 バリデーションルール
- 値が `true`（厳密な boolean）のエントリのみ有効とする
- `false`、`0`、`null`、文字列等は無視（購入可能扱い）
- キーは `{itemType}:{itemId}` 形式で、コロンが1つのみ、前後ともに空でないこと
- `itemType` は `name_part`, `avatar_part`, `reaction_stamp`, `stamp_sheet` の4種のみ許可
- 上記に合致しないエントリは無視（管理者の入力ミスを安全に処理）

---

## 3. サーバー側変更

### 3.1 `functions/src/config/messages.ts`

`VIRTUE_MESSAGES` セクション（252行目付近）に購入不可エラーメッセージを追加:

```typescript
export const VIRTUE_MESSAGES = {
    POST_CREATE_GRANT_REASON: "投稿作成による徳ポイント加算",
    COMMENT_THANKS_GIVEN_GRANT_REASON: "コメントにいいね！した",
    COMMENT_THANKS_RECEIVED_GRANT_REASON: "コメントがいいね！された",
    ADMIN_DELETE_POST_PENALTY_REASON: "運営削除（通報対応）",
    ITEM_NOT_PURCHASABLE: "このアイテムは期間限定アイテムです。現在期限が過ぎているため購入できません。",  // 追加
} as const;
```

### 3.2 `functions/src/callable/virtue_shop.ts`

**変更1:** `VirtueShopConfig` 型に追加（14行目付近）

```typescript
type VirtueShopConfig = {
    namePartCostsByRarity: Record<string, number>;
    avatarPartCostsByRarity: Record<string, number>;
    reactionCostsById: Record<string, number>;
    stampSheetCostsByRarity: Record<string, number>;
    nonPurchasableItems: Set<string>;  // 追加
};
```

**変更2:** ヘルパー関数を追加（99行目付近、`readVirtueShopConfig` の前）

```typescript
const VALID_ITEM_TYPES = new Set(["name_part", "avatar_part", "reaction_stamp", "stamp_sheet"]);

function readNonPurchasableItems(value: unknown): Set<string> {
    if (!value || typeof value !== "object") return new Set();
    const result = new Set<string>();
    for (const [key, flag] of Object.entries(value as Record<string, unknown>)) {
        if (flag !== true) continue;
        const sepIndex = key.indexOf(":");
        if (sepIndex <= 0 || sepIndex === key.length - 1) continue;
        if (sepIndex !== key.lastIndexOf(":")) continue;  // コロンは1つのみ
        const itemType = key.slice(0, sepIndex);
        if (!VALID_ITEM_TYPES.has(itemType)) continue;
        result.add(key);
    }
    return result;
}

function toNonPurchasableKey(itemType: string, itemId: string): string {
    return `${itemType}:${itemId}`;
}
```

**バリデーション:** 許可された4つの `itemType`（`name_part`, `avatar_part`, `reaction_stamp`, `stamp_sheet`）のみ受け付ける。不正なキーは無視される。

**変更3:** `readVirtueShopConfig` 内で読み込み

```typescript
const nonPurchasableItems = readNonPurchasableItems(data?.nonPurchasableItems);
return { ..., nonPurchasableItems };
```

**変更4:** `getVirtueShopConfig` の返却値に追加

```typescript
return {
    ...既存フィールド,
    nonPurchasableItems: Array.from(config.nonPurchasableItems),
};
```

**変更5:** `purchaseVirtueItem` のトランザクション内、既存の `alreadyUnlocked` チェック（278〜285行目）の**直後**に挿入

```typescript
// 既存コード: alreadyUnlocked チェック（278-285行目）
const unlockedList: string[] = userData[unlockField] || [];
if (unlockedList.includes(unlockValue)) {
    return { success: true, alreadyUnlocked: true, virtue: userData.virtue ?? 0 };
}

// ↓ ここに購入不可チェックを挿入（購入済みユーザーは上で return 済み）
const nonPurchasableKey = toNonPurchasableKey(itemType, itemId);
if (config.nonPurchasableItems.has(nonPurchasableKey)) {
    logger.info("purchaseVirtueItem blocked: non-purchasable", {
        userId, itemType, itemId, nonPurchasableKey,
    });
    throw new HttpsError("failed-precondition", VIRTUE_MESSAGES.ITEM_NOT_PURCHASABLE, {
        reason: "ITEM_NOT_PURCHASABLE",
    });
}
```

**重要:** 購入不可チェックは `alreadyUnlocked` の後に配置する。これにより購入済みユーザーは従来通り `alreadyUnlocked: true` で正常返却され、未購入ユーザーのみが購入不可エラーを受ける。

**注意:** `HttpsError` の第3引数 `details` に `reason` フィールドを含める。クライアントは `e.details` の `reason` で分岐し、メッセージ文字列との比較には依存しない。

**変更6:** `VIRTUE_MESSAGES` のインポートを追加

---

## 4. クライアント側変更

### 4.1 `lib/shared/services/virtue_shop_service.dart`

`VirtueShopConfig` に `nonPurchasableItems` フィールドとヘルパーを追加:

```dart
final Set<String> nonPurchasableItems;

// コンストラクタに追加
this.nonPurchasableItems = const {},

// fromMap に追加
final nonPurchasableRaw = map['nonPurchasableItems'];
final nonPurchasableItems = <String>{};
if (nonPurchasableRaw is List) {
  for (final item in nonPurchasableRaw) {
    if (item is String && item.contains(':')) {
      nonPurchasableItems.add(item);
    }
  }
}

// ヘルパーメソッド
bool isNonPurchasable(String itemType, String itemId) {
  return nonPurchasableItems.contains('$itemType:$itemId');
}
```

### 4.2 `lib/core/constants/app_messages.dart`

エラーメッセージ追加:
```dart
String get itemNotPurchasable => 'このアイテムは期間限定アイテムです。現在期限が過ぎているため購入できません。';
```

### 4.3 各購入画面の変更

#### リフレッシュ戦略

| 画面 | config リフレッシュ | 理由 |
|------|-------------------|------|
| `avatar_edit_screen.dart` | する（`initState` で invalidate） | 画面遷移は低頻度、フェッチ遅延は許容 |
| `name_edit_screen.dart` | する（同上） | 同上 |
| `stamp_sheet_catalog_screen.dart` | する（config + カタログ両方） | カタログも再取得して `isActive` の最新状態を反映 |
| `stamp_sheet_screen.dart` | **しない**（キャッシュ利用） | スタンプ使用中画面、購入は副次機能 |
| `post_card.dart` | **しない**（キャッシュ利用） | 高頻度操作、遅延ゼロを優先 |

#### 購入画面（アバター/名前）の共通パターン

1. **`initState` で config invalidate + config 取得完了まで購入UIを非表示:**
   ```dart
   @override
   void initState() {
     super.initState();
     Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
   }

   // build 内: config がロード中の場合は購入ボタンを出さない
   final shopConfig = ref.watch(virtueShopConfigProvider);
   // shopConfig.when(data: ..., loading: ..., error: ...)
   ```

#### スタンプシートカタログ画面の追加パターン

`stamp_sheet_catalog_screen.dart` では config に加えてカタログデータも再取得する:

```dart
@override
void initState() {
  super.initState();
  // config と カタログ両方を最新化
  Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
  _catalogFuture = _sheetService.fetchCatalog();  // カタログも再取得
}
```

**理由:** カタログには `isActive` フラグが含まれており、管理者が `isActive=false` に変更した場合もこの画面で反映される。現在の実装では `initState` で `fetchCatalog()` を呼んでいるため、画面遷移のたびにカタログは再取得される（既存動作を維持）。

2. **アイテムリストのフィルタリング（config 取得完了後、グリッド/リスト構築前）:**

   フィルタリングは**描画前のデータ構築段階**で行う。タップ時の判定ではなく、そもそもリスト/グリッドに含めない:

   ```dart
   // グリッド/リスト構築前にフィルタ
   // 未購入 AND 購入不可 → リストに含めない（UIに表示されない）
   // 購入済み or 購入可能 → リストに含める（既存の所有・サブスク判定はそのまま維持）
   final visible = items.where((item) {
     if (isOwned(item)) return true;  // 購入済み → 常に表示
     return !config.isNonPurchasable(itemType, item.id);  // 購入不可 → 除外
   }).toList();
   ```

   **各画面の具体的なフィルタ挿入位置:**
   - `avatar_edit_screen.dart`: `_buildPartsGrid()` 内、パーツIDリスト構築後・GridView.builder の前
   - `name_edit_screen.dart`: `_buildPartsList()` 内、パーツリストのグループ化処理の前
   - `stamp_sheet_catalog_screen.dart`: `build()` 内、`sheets` リスト取得後・ソート/GridView構築の前

#### リアクションスタンプ（post_card.dart）のパターン

リアクションオーバーレイは高頻度で開かれるため、config の invalidate は行わない。キャッシュ済みの config をそのまま使用する:

```dart
// キャッシュから即座に取得（通信なし、遅延ゼロ）
final shopConfig = ref.watch(virtueShopConfigProvider).valueOrNull;

// shopConfig が null（未取得）の場合は全アイテム表示（サーバーが最終防御）
// shopConfig が取得済みの場合はフィルタリング適用
```

#### エラーハンドリング（全画面共通）

`HttpsError` の `details.reason` フィールドで分岐する（メッセージ文字列に依存しない）:

```dart
on FirebaseFunctionsException catch (e) {
  final reason = (e.details is Map) ? e.details['reason'] : null;
  if (reason == 'ITEM_NOT_PURCHASABLE') {
    // 「このアイテムは現在購入できません」表示
    SnackBarHelper.showError(context, AppMessages.error.itemNotPurchasable);
    // config を再フェッチして購入不可アイテムをUIから除去
    ref.invalidate(virtueShopConfigProvider);
  } else if (e.message == AppMessages.error.notEnoughVirtue) {
    // 既存の徳ポイント不足表示
  } else {
    // 汎用エラー
  }
}
```

**ポイント:** 購入不可エラーを受けた際に config を invalidate するため、次回描画で該当アイテムがUIから消える。

対象画面:
- `avatar_edit_screen.dart` — アバターパーツ
- `name_edit_screen.dart` — 名前パーツ
- `stamp_sheet_catalog_screen.dart` — スタンプシートカタログ（一覧から購入）
- `stamp_sheet_screen.dart` — スタンプシート画面（使用中画面から購入、L663付近）
- `post_card.dart` — リアクションスタンプ

---

## 5. エラーハンドリング契約

| 状況 | HttpsError code | message | details.reason |
|------|----------------|---------|----------------|
| 購入不可アイテム | `failed-precondition` | `このアイテムは期間限定アイテムです。現在期限が過ぎているため購入できません。` | `ITEM_NOT_PURCHASABLE` |
| 徳ポイント不足 | `failed-precondition` | `徳ポイントが足りません。` | （なし — 既存パターン維持） |

**判定方法:** クライアントは `e.details['reason']` で分岐する。メッセージ文字列との比較には依存しない。
- `reason == 'ITEM_NOT_PURCHASABLE'` → 購入不可メッセージ表示 + config invalidate
- `reason` が未設定 → 既存の `e.message` 比較にフォールバック（後方互換性）

**注意:** 既存の徳ポイント不足エラーは `e.message` 比較のまま（今回のスコープ外）。将来的に全購入エラーを `details.reason` ベースに統一することを推奨。

---

## 6. Config リフレッシュ戦略

### 6.1 キャッシュの仕組み

`virtueShopConfigProvider` は Riverpod の `FutureProvider`。初回アクセス時に1回フェッチし、以降はアプリのメモリ上にキャッシュ。`invalidate` すると次回アクセス時に再フェッチ。

### 6.2 リフレッシュタイミング

| タイミング | 方法 | 対象画面 |
|-----------|------|---------|
| 購入画面遷移時 | `ref.invalidate(virtueShopConfigProvider)` in `initState` | アバター/名前/スタンプシートカタログ |
| リアクションオーバーレイ表示時 | **リフレッシュしない**（キャッシュ利用） | post_card.dart |
| 購入不可エラー受信時 | `ref.invalidate(virtueShopConfigProvider)` | 全画面共通 |
| 購入成功後 | 既存の invalidate を維持 | 全画面共通 |

### 6.3 購入画面のローディング

購入画面（アバター/名前/スタンプシート）では `initState` で config を invalidate した後、config 取得完了まで購入関連UI（未購入パーツの表示・購入ボタン）を非表示にする。購入済みアイテムは config に依存しないため即座に表示可能。

### 6.4 最悪ケースのシナリオ

リアクションオーバーレイ（config をリフレッシュしない画面）で:
1. キャッシュが古い → 購入不可アイテムが見える
2. ユーザーが購入ボタンを押す
3. サーバーが `ITEM_NOT_PURCHASABLE` で拒否
4. クライアントが「このアイテムは現在購入できません」を表示
5. config を invalidate → 次回描画で該当アイテムが非表示に

→ **データ不整合は発生しない。** UXとして一度だけ購入ボタンが見えるが、実害はない。

---

## 7. デプロイ手順

1. Firestore: `settings/virtueShop` に `nonPurchasableItems: {}` を追加
2. Functions デプロイ: `firebase deploy --only "functions:default:getVirtueShopConfig,functions:default:purchaseVirtueItem"`
3. サーバー動作確認
4. アプリビルド・配信

**ロールバック:** `nonPurchasableItems` を空 `{}` にするだけで全アイテム購入可能に戻る。

---

## 8. リスクと緩和策

| リスク | 緩和策 |
|--------|--------|
| 管理者のキー入力ミス | バリデーション（コロン必須）で不正キー無視 |
| configキャッシュ古い | サーバー側チェックで最終防御 |
| isActive との混乱 | 仕様書で明確に区別 |
