# サブスク設定手順（RevenueCat + Google Play Console）

この資料は、RevenueCat を使ったサブスク課金の準備に必要な
Google Play Console 側の設定手順と、RevenueCat 連携の最小手順をまとめたものです。

## 前提
- Android で先行リリース
- サブスクは RevenueCat 管理
- サーバー側で isSubscriber を更新（Webhook 経由）

---

## 1. Google Play Console 側の準備

### 1-1. アプリ作成（未作成の場合）
1. Play Console → すべてのアプリ → アプリを作成
2. アプリ名 / デフォルト言語 / アプリ種別を設定
3. 作成

### 1-2. 支払いプロフィール（Merchant）
1. Play Console → 設定 → 支払いプロファイル
2. 開発者の支払い情報を登録

### 1-3. App Signing の有効化
1. Play Console → 設定 → アプリの署名
2. Play App Signing を有効化

---

## 2. 定期購入（Subscription）の作成

1. Play Console → 収益化（Monetize）→ 商品 → 定期購入
2. サブスク商品を作成
   - 商品ID（例: premium_monthly）
   - 名前 / 説明
3. ベースプランを作成
   - 価格（JPY）
   - 請求期間（例: 1か月）
4. オファーを作成（任意）
   - 無料トライアル / 割引等

> RevenueCat は「商品ID / Base Plan ID / Offer ID」を参照するため、
> ここで作成した ID は控えておく。

---

## 3. テスト設定（実機検証用）

### 3-1. ライセンステスター登録
1. Play Console → 設定 → ライセンステスト
2. テスト用 Google アカウントを追加

### 3-2. 内部テスト配布（必須）
1. Play Console → テスト → 内部テスト
2. AAB をアップロード
3. リリース作成 → テスター追加 → 配布

> 課金の実機テストは、内部テスト配布版でのみ可能。

---

## 4. Play Developer API 連携（RevenueCat 用）

1. Play Console → 設定 → API アクセス
2. Google Cloud プロジェクトを作成/リンク
3. サービスアカウントを作成
4. Play Console に権限付与
   - サブスクリプション管理
   - 注文閲覧
5. サービスアカウントの JSON キーを発行

---

## 5. RevenueCat 側の設定

1. RevenueCat → Apps → Android
2. サービスアカウント JSON をアップロード
3. Play Console の商品ID / Base Plan / Offer を同期
4. Webhook を設定（Cloud Functions の URL）

---

## 5-1. RevenueCat Webhook 設定（必須）

### Webhook URL
- Cloud Functions: `revenueCatWebhook`
- デプロイ後のURLを RevenueCat に設定

### 署名シークレット
- Functions の Secret に `REVENUECAT_WEBHOOK_SECRET` を登録
- RevenueCat の Webhook 設定と同じ値を使用

---

## 5-2. サブスク解除時フォールバック設定（Firestore）

サブスク解約時に Epic アイテムが設定されている場合、
以下の固定値に自動で置き換える。

`settings/subscriptionFallback` に以下のドキュメントを作成：

```
{
  "namePrefix": "prefix_01",
  "nameSuffix": "suffix_01",
  "avatarParts": {
    "hairId": "hair_01",
    "eyesId": "eyes_01",
    "mouthId": "mouth_01",
    "eyebrowsId": "eyebrows_01"
  }
}
```

---

## 6. 動作確認（最小チェック）

1. テスト購入 → isSubscriber = true
2. 解約 → isSubscriber = false
3. 解約時に Common パーツへ自動フォールバック
4. アプリ再起動後も状態が維持される

---

## 注意
- RevenueCat を使っても Play Console の定期購入設定は必須。
- isSubscriber はサーバー側のみで更新する（クライアント更新は禁止）。
- Flutter 側は `purchases_flutter` を使用し、起動時/ログイン時に `Purchases.logIn(uid)` を実行する。
  - APIキーは `--dart-define=REVENUECAT_API_KEY=...` で渡す。
