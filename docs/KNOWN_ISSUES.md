# 既知の不具合リスト

このドキュメントでは、現在確認されている不具合とその対応状況を記録します。

---

## 🟡 対応中

（現在なし）

---

## 🟠 テスト待機中

### 1. `cleanupBannedUsers` 関数のインデックスエラー

**発生日**: 2026-01-10  
**症状**: Cloud Schedulerで `cleanupBannedUsers` が失敗
```
Error: 0 FAILED_PRECONDITION: The query requires an index.
```

**原因**: Firestoreの複合インデックス不足
- コレクション: `users`
- フィールド: `banStatus`, `permanentBanScheduledDeletionAt`

**対応**: 
- Firebaseコンソールから複合インデックスを作成（2026-01-10）
- ステータス: **インデックス作成完了待ち → 動作テスト待機中**

**次のステップ**:
- [ ] インデックス作成完了を確認（Firebase Console → Firestore → インデックス）
- [ ] Cloud Schedulerから手動実行してテスト
- [ ] 次回の定期実行（毎日午前4時）で正常動作を確認

---

## 🟢 解決済み

### 1. 問い合わせチャット: ユーザー側の通知抑制が動作しない

**発生日**: 2026-01-10  
**症状**:
- 管理者が問い合わせ画面を開いている間の通知抑制: ✅ 動作
- ユーザーが問い合わせ画面を開いている間の通知抑制: ❌ 動作せず（通知が届く）

**原因**: Firestoreセキュリティルールで `userViewing` フィールドの更新権限がなかった

**対応**:
1. デバッグログを追加して原因特定
2. `firebase/firestore.rules` の inquiries コレクションルールを修正
   - `hasOnly(['hasUnreadReply'])` → `hasOnly(['hasUnreadReply', 'userViewing'])`
3. Firestoreルールをデプロイ

**解決日**: 2026-01-10

### 1. `cleanupBannedUsers` 関数のインデックスエラー

**発生日**: 2026-01-10  
**症状**: Cloud Schedulerで `cleanupBannedUsers` が失敗
```
Error: 0 FAILED_PRECONDITION: The query requires an index.
```

**原因**: Firestoreの複合インデックス不足
- コレクション: `users`
- フィールド: `banStatus`, `permanentBanScheduledDeletionAt`

**対応**: 
- Firebaseコンソールから複合インデックスを作成（2026-01-10）
- ステータス: **インデックス作成完了待ち → 動作テスト待機中**

**次のステップ**:
- [ ] インデックス作成完了を確認（Firebase Console → Firestore → インデックス）
- [ ] Cloud Schedulerから手動実行してテスト
- [ ] 次回の定期実行（毎日午前4時）で正常動作を確認

---

## 🟢 解決済み

（現在なし）

---

## 📋 テンプレート

新しい不具合を追加する際は、以下のテンプレートを使用してください：

```markdown
### X. [不具合タイトル]

**発生日**: YYYY-MM-DD  
**症状**: 
[不具合の症状を簡潔に記述]

**再現手順**:
1. 
2. 
3. 

**原因**: 
[判明している場合は記述]

**対応**: 
[対応内容または対応予定]

**関連コミット**: [コミットハッシュ]
```
