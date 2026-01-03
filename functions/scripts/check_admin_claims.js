// Firebase Functions Shell内で実行するスクリプト
// 使用方法:
// 1. firebase functions:shell
// 2. .load scripts/check_admin_claims.js

// Firebase Functions Shellではadminはすでにグローバルにあるのでrequireしない

const ADMIN_UID = 'hYr5LUH4mhR60oQfVOggrjGYJjG2';

async function checkAdminClaims() {
  try {
    console.log(`\n🔍 Custom Claims確認中: ${ADMIN_UID}`);

    const user = await admin.auth().getUser(ADMIN_UID);

    console.log('\n📋 ユーザー情報:');
    console.log(`  UID: ${user.uid}`);
    console.log(`  Email: ${user.email}`);
    console.log(`  DisplayName: ${user.displayName}`);

    console.log('\n🔐 Custom Claims:');
    if (user.customClaims) {
      console.log(JSON.stringify(user.customClaims, null, 2));

      if (user.customClaims.admin === true) {
        console.log('\n✅ 管理者権限が正しく設定されています！');
      } else {
        console.log('\n⚠️  管理者権限が設定されていません');
      }
    } else {
      console.log('  なし');
      console.log('\n⚠️  Custom Claimsが設定されていません');
    }

    console.log('\n📝 次のステップ:');
    console.log('  1. ユーザーがログアウト→ログインしてトークンをリフレッシュ');
    console.log('  2. アプリで管理者メニューが表示されることを確認\n');
  } catch (error) {
    console.error('❌ エラー:', error.message);
    if (error.code === 'auth/user-not-found') {
      console.error(`\nユーザーID ${ADMIN_UID} が見つかりません。`);
    }
  }
}

// 実行
checkAdminClaims();
