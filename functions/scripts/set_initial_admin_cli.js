// Firebase Functions Shell内で実行するスクリプト
// 使用方法:
// 1. firebase functions:shell
// 2. .load scripts/set_initial_admin_cli.js

// Firebase Functions Shellではadminはすでにグローバルにあるのでrequireしない

const ADMIN_UID = 'hYr5LUH4mhR60oQfVOggrjGYJjG2';

async function setInitialAdmin() {
  try {
    console.log(`\n🔧 管理者権限を設定中: ${ADMIN_UID}`);

    await admin.auth().setCustomUserClaims(ADMIN_UID, { admin: true });
    console.log(`✅ 管理者権限を設定しました`);

    // 確認
    const user = await admin.auth().getUser(ADMIN_UID);
    console.log('\n📋 Custom Claims:');
    console.log(JSON.stringify(user.customClaims, null, 2));

    console.log('\n✅ 完了しました！');
    console.log('\n⚠️  次のステップ:');
    console.log('   1. 該当ユーザーがログアウト→ログインしてトークンをリフレッシュ');
    console.log('   2. または、アプリ内で getIdToken(true) を呼び出してトークンをリフレッシュ');
    console.log('   3. 管理者メニューが表示されることを確認\n');
  } catch (error) {
    console.error('❌ エラー:', error.message);
    if (error.code === 'auth/user-not-found') {
      console.error(`\nユーザーID ${ADMIN_UID} が見つかりません。`);
      console.error('Firebase Authenticationコンソールでユーザーが存在するか確認してください。');
    }
  }
}

// 実行
setInitialAdmin();
