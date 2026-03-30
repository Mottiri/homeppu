# nonPurchasableItems（購入不可アイテム制御）詳細設計書

## 1. 背景・要件

### 1.1 背景
徳ショップで販売しているアイテム（アバターパーツ、名前パーツ、リアクションスタンプ、スタンプシート）の中には、期間限定で販売を停止したいケースがある。例えばリリース記念限定アイテムの販売期間終了後、アイテム自体は既購入ユーザーが引き続き使用できるが、新規購入は不可にしたい。

### 1.2 要件
1. 管理者がFirebase Consoleから特定アイテムの購入を停止・再開できること
2. 購入停止中のアイテムは、サーバー側で購入トランザクションを拒否すること
3. クライアント側で未購入かつ購入不可のアイテムをUI上非表示にすること
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
- 値が `true`（truthy boolean）のエントリのみ有効とする
- `false`、`0`、`null`、文字列等は無視（購入可能扱い）
- キーフォーマットが不正なエントリは無視

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
    ITEM_NOT_PURCHASABLE: "このアイテムは現在購入できません。",  // 追加
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
function readNonPurchasableItems(value: unknown): Set<string> {
    if (!value || typeof value !== "object") return new Set();
    const result = new Set<string>();
    for (const [key, flag] of Object.entries(value as Record<string, unknown>)) {
        if (flag === true && key.includes(":")) {
            result.add(key);
        }
    }
    return result;
}

function toNonPurchasableKey(itemType: string, itemId: string): string {
    return `${itemType}:${itemId}`;
}
```

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

**変更5:** `purchaseVirtueItem` のトランザクション内、179行目 `const config = readVirtueShopConfig(...)` の直後に挿入

```typescript
const nonPurchasableKey = toNonPurchasableKey(itemType, itemId);
if (config.nonPurchasableItems.has(nonPurchasableKey)) {
    logger.info("purchaseVirtueItem blocked: non-purchasable", {
        userId, itemType, itemId, nonPurchasableKey,
    });
    throw new HttpsError("failed-precondition", VIRTUE_MESSAGES.ITEM_NOT_PURCHASABLE);
}
```

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
String get itemNotPurchasable => 'このアイテムは現在購入できません。';
```

### 4.3 各購入画面の変更

共通パターン:

1. **`initState` で config invalidate:**
   ```dart
   Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
   ```

2. **アイテムリストのフィルタリング:**
   ```dart
   // 未購入 AND 購入不可 → 非表示
   // 購入済み → 常に表示
   final visible = items.where((item) {
     if (isOwned(item)) return true;
     return !(shopConfig?.isNonPurchasable(itemType, item.id) ?? false);
   }).toList();
   ```

3. **エラーハンドリング:**
   ```dart
   on FirebaseFunctionsException catch (e) {
     if (e.message == AppMessages.error.itemNotPurchasable) {
       // 「このアイテムは現在購入できません」表示
     } else { ... }
   }
   ```

対象画面:
- `avatar_edit_screen.dart` — アバターパーツ
- `name_edit_screen.dart` — 名前パーツ
- `stamp_sheet_catalog_screen.dart` — スタンプシート
- `post_card.dart` — リアクションスタンプ

---

## 5. エラーハンドリング契約

| 状況 | HttpsError code | message |
|------|----------------|---------|
| 購入不可アイテム | `failed-precondition` | `このアイテムは現在購入できません。` |
| 徳ポイント不足 | `failed-precondition` | `徳ポイントが足りません。` |

**重要:** 両側のメッセージ文字列は完全一致させること。クライアントは `e.message` との比較で分岐するため。

---

## 6. Config リフレッシュ戦略

| タイミング | 方法 |
|-----------|------|
| 購入画面遷移時 | `ref.invalidate(virtueShopConfigProvider)` in `initState` |
| 購入成功後 | 既存の invalidate を維持 |

**最悪ケース:** キャッシュ古い → 購入ボタン見える → サーバー拒否 → 「購入できません」表示。データ不整合は発生しない。

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
