/**
 * 既存サークルの lastHumanPostAt フィールドをマイグレーションするスクリプト
 * 
 * 実行方法:
 * cd functions
 * node scripts/migrate_last_human_post.js
 */

const admin = require('firebase-admin');

// プロジェクトIDを使用して初期化
admin.initializeApp({
    projectId: 'positive-sns'
});

const db = admin.firestore();

async function migrateLastHumanPostAt() {
    console.log('\n🔧 lastHumanPostAt フィールドのマイグレーションを開始...\n');

    try {
        // AIユーザーのUIDリストを取得
        console.log('📋 AIユーザーリストを取得中...');
        const aiUsersSnapshot = await db.collection('users')
            .where('isAI', '==', true)
            .get();
        const aiUserIds = new Set(aiUsersSnapshot.docs.map(doc => doc.id));
        console.log(`   ${aiUserIds.size}件のAIユーザーを検出\n`);

        // 全サークルを取得
        console.log('📋 サークル一覧を取得中...');
        const circlesSnapshot = await db.collection('circles').get();
        console.log(`   ${circlesSnapshot.size}件のサークルを検出\n`);

        let updatedCount = 0;
        let skippedCount = 0;
        let noHumanPostCount = 0;

        for (const circleDoc of circlesSnapshot.docs) {
            const circleId = circleDoc.id;
            const circleName = circleDoc.data().name || circleId;

            // サークル内の投稿を新しい順に取得
            const postsSnapshot = await db.collection('posts')
                .where('circleId', '==', circleId)
                .orderBy('createdAt', 'desc')
                .limit(50)
                .get();

            // 人間ユーザーの最新投稿を探す
            let lastHumanPostAt = null;
            for (const postDoc of postsSnapshot.docs) {
                const postData = postDoc.data();
                const userId = postData.userId;
                if (userId && !aiUserIds.has(userId)) {
                    // 人間ユーザーの投稿を発見
                    lastHumanPostAt = postData.createdAt;
                    break;
                }
            }

            if (lastHumanPostAt) {
                // フィールドを更新
                await db.collection('circles').doc(circleId).update({
                    lastHumanPostAt: lastHumanPostAt
                });
                console.log(`✅ ${circleName}: lastHumanPostAt を設定`);
                updatedCount++;
            } else if (postsSnapshot.size === 0) {
                console.log(`⏭️  ${circleName}: 投稿なし（スキップ）`);
                skippedCount++;
            } else {
                console.log(`⚠️  ${circleName}: 人間の投稿なし`);
                noHumanPostCount++;
            }
        }

        console.log('\n========================================');
        console.log(`✅ マイグレーション完了`);
        console.log(`   更新: ${updatedCount}件`);
        console.log(`   投稿なし: ${skippedCount}件`);
        console.log(`   人間投稿なし: ${noHumanPostCount}件`);
        console.log('========================================\n');

    } catch (error) {
        console.error('❌ エラー:', error);
    } finally {
        process.exit();
    }
}

migrateLastHumanPostAt();
