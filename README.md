# ほめっぷ 🌸

**世界一優しいSNS** - 承認欲求による疲弊を解消し、自己肯定感を最大化する

## 概要

ほめっぷは、ユーザーが日常や努力を投稿すると、AIまたは他ユーザーから「圧倒的な称賛・肯定」が得られるSNSアプリです。

### 主な機能

- **3つの投稿モード**: AIモード / ミックスモード / 人間モード
- **ポジティブなリアクション**: いいね、すごい、がんばれ、わかる
- **徳システム**: ポジティブな行動で徳が上がり、ネガティブな行動で下がる
- **サークル機能**: 同じ目標を持つ仲間とコミュニティを形成
- **AI褒めロジック**: 投稿内容を詳細に分析し、具体的に褒める

## 技術スタック

- **Frontend**: Flutter 3.x
- **Backend**: Firebase (Authentication, Firestore, Storage, Functions)
- **状態管理**: Riverpod
- **ルーティング**: Go Router

## セットアップ

### 1. 前提条件

- Flutter SDK 3.10.1以上
- Firebase CLI
- Firebase プロジェクト

### 2. Firebase設定

```bash
# Firebase CLIのインストール（未インストールの場合）
npm install -g firebase-tools

# Firebaseにログイン
firebase login

# FlutterFire CLIのインストール
dart pub global activate flutterfire_cli

# Firebaseプロジェクトの設定
flutterfire configure --project=YOUR_PROJECT_ID
```

### 3. パッケージのインストール

```bash
flutter pub get
```

### 4. Firestoreルールのデプロイ

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 5. アプリの実行

```bash
flutter run
```

## プロジェクト構造

```
lib/
├── core/
│   ├── constants/      # 定数・カラー定義
│   ├── theme/          # テーマ設定
│   ├── router/         # ルーティング設定
│   └── utils/          # ユーティリティ
├── features/
│   ├── auth/           # 認証機能
│   ├── home/           # ホーム・タイムライン
│   ├── post/           # 投稿機能
│   ├── profile/        # プロフィール・設定
│   └── circle/         # サークル機能
└── shared/
    ├── models/         # データモデル
    ├── providers/      # 共通Provider
    └── widgets/        # 共通ウィジェット
```

## デザインコンセプト

- **暖色系・パステルカラー**: 攻撃性のない配色
- **丸みを帯びたデザイン**: 柔らかく優しい印象
- **フレンドリーなメッセージ**: システムメッセージも温かみのあるトーンで統一

## 今後の開発予定

- [ ] AI褒めロジック（Cloud Functions）
- [ ] 通知機能
- [ ] 画像投稿機能
- [ ] サークル作成・管理機能
- [ ] 徳システムの詳細実装
- [ ] 通報機能

## ライセンス

Private - All Rights Reserved

---

Created with ❤️ for a kinder social media experience.
