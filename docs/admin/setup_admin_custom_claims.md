# 管理者Custom Claims設定手順

## 概要

このドキュメントは、ハードコードされた管理者UIDから、Firebase Custom Claimsベースの管理者権限システムへの移行手順を説明します。

## 前提条件

- Firebase Admin SDK がインストールされていること
- プロジェクトの管理者権限があること
- Node.js環境が利用可能であること

## 手順

### 1. Cloud Functionsをデプロイ

管理者権限管理用のCloud Functionsをデプロイします。

```bash
cd functions
npm run deploy
```

以下の関数がデプロイされます：
- `setAdminRole` - 管理者権限を付与
- `removeAdminRole` - 管理者権限を削除

### 2. 既存の管理者にCustom Claimを設定

既存の管理者UID（`hYr5LUH4mhR60oQfVOggrjGYJjG2`）にCustom Claimを設定します。

#### 方法A: Firebase CLIを使用（推奨）

Firebase Functions Shellを起動：

```bash
cd functions
firebase functions:shell
```

シェル内で以下を実行：

```javascript
const admin = require('firebase-admin');
admin.auth().setCustomUserClaims('hYr5LUH4mhR60oQfVOggrjGYJjG2', { admin: true }).then(() => console.log('✅ 管理者権限を設定しました'));
```

または、用意されたスクリプトを読み込み：

```javascript
.load scripts/set_initial_admin_cli.js
```

#### 方法B: Firebase Consoleを使用

1. [Firebase Console](https://console.firebase.google.com/) を開く
2. Authentication → Users でユーザーを探す
3. ユーザーのUIDをコピー
4. Cloud Functions経由で設定するか、Firebase Admin SDKを使用

**注意**: Firebase Consoleから直接Custom Claimsは設定できません。方法Aを使用してください。

### 3. ユーザー側でトークンを再取得

Custom Claimsが設定されたら、該当ユーザーはログアウト→ログインするか、アプリを再起動してトークンをリフレッシュする必要があります。

または、以下のコードでトークンを強制リフレッシュ：

```dart
final user = FirebaseAuth.instance.currentUser;
await user?.getIdToken(true); // forceRefresh
```

### 4. 動作確認

1. **管理者としてログイン**
   - UID `hYr5LUH4mhR60oQfVOggrjGYJjG2` でログイン

2. **管理者メニューの表示確認**
   - プロフィール画面に管理者メニューアイコンが表示されることを確認

3. **管理者専用機能の動作確認**
   - 通報管理画面にアクセス可能か確認
   - 要審査投稿管理画面にアクセス可能か確認
   - 問い合わせ管理が機能するか確認

### 5. 追加の管理者を設定（必要に応じて）

既存の管理者は、アプリ内から新しい管理者を追加できます（将来の機能として実装予定）。

または、上記のスクリプトを再利用して別のUIDに管理者権限を付与：

```javascript
await admin.auth().setCustomUserClaims('新しい管理者のUID', { admin: true });
```

## トラブルシューティング

### Custom Claimsが反映されない

- ユーザーがログアウト→ログインしてトークンをリフレッシュしているか確認
- `getIdToken(true)` で強制リフレッシュを試す
- Firebase Consoleでユーザーが存在するか確認

### 管理者メニューが表示されない

1. Custom Claimsが正しく設定されているか確認：

```javascript
const user = await admin.auth().getUser('UID');
console.log(user.customClaims);
// 期待値: { admin: true }
```

2. クライアント側でCustom Claimsを取得できているか確認：

```dart
final user = FirebaseAuth.instance.currentUser;
final idTokenResult = await user?.getIdTokenResult();
print(idTokenResult?.claims?['admin']); // 期待値: true
```

3. `isAdminProvider` が正しく動作しているか確認

### セキュリティルールでアクセス拒否される

- Firestoreセキュリティルールがデプロイされているか確認
- `isAdmin()` 関数が定義されているか確認

```
firebase deploy --only firestore:rules
firebase deploy --only storage
```

## セキュリティ上の注意

1. **Custom Claimsの変更はCloud Functions経由のみ**
   - クライアントから直接Custom Claimsを変更することはできません
   - `setAdminRole` / `removeAdminRole` 関数は管理者のみ実行可能

2. **管理者の削除**
   - 最後の管理者を削除しないよう注意
   - `removeAdminRole` 関数は自分自身の権限削除を防ぐようになっています

3. **定期的な権限監査**
   - 管理者リストを定期的に確認
   - 不要になった管理者権限は速やかに削除

## 関連ファイル

- [functions/src/index.ts](../../functions/src/index.ts) - 管理者権限管理関数
- [firebase/firestore.rules](../../firebase/firestore.rules) - Firestoreセキュリティルール
- [firebase/storage.rules](../../firebase/storage.rules) - Storageセキュリティルール
- [lib/shared/providers/auth_provider.dart](../../lib/shared/providers/auth_provider.dart) - 管理者判定プロバイダー

## 更新履歴

- 2025-01-03: 初版作成 - Custom Claimsベースの管理者システムへ移行
