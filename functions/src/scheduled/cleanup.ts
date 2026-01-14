/**
 * スケジュールされたクリーンアップ関数
 * Phase 7: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { db } from "../helpers/firebase";
import { deleteStorageFileFromUrl } from "../helpers/storage";

/**
 * 孤立メディアクリーンアップ
 * Cloud Schedulerで毎日実行
 * 24時間以上経過した孤立メディアを削除
 */
export const cleanupOrphanedMedia = onSchedule(
    {
        schedule: "0 3 * * *", // 毎日午前3時 JST
        timeZone: "Asia/Tokyo",
        region: "asia-northeast1",
        timeoutSeconds: 600, // 10分タイムアウト
    },
    async () => {
        console.log("=== cleanupOrphanedMedia START ===");
        const bucket = admin.storage().bucket();
        const now = Date.now();
        const TWENTY_FOUR_HOURS = 24 * 60 * 60 * 1000;

        let deletedCount = 0;
        let checkedCount = 0;

        // ===============================================
        // 1. 投稿メディアのクリーンアップ
        // ===============================================
        console.log("Checking posts media...");
        const [postFiles] = await bucket.getFiles({ prefix: "posts/" });

        for (const file of postFiles) {
            checkedCount++;
            try {
                const [metadata] = await file.getMetadata();
                const customMetadata = metadata.metadata || {};
                const uploadedAtStr = customMetadata.uploadedAt;
                const uploadedAt = uploadedAtStr ? parseInt(String(uploadedAtStr)) : 0;
                const postId = customMetadata.postId ? String(customMetadata.postId) : null;

                // 24時間以上経過していないならスキップ
                if (now - uploadedAt < TWENTY_FOUR_HOURS) continue;

                // postId未設定（古いファイル）はスキップ
                if (!postId) continue;

                let shouldDelete = false;

                if (postId === "PENDING") {
                    // 投稿前に離脱したケース
                    shouldDelete = true;
                    console.log(`Orphan (PENDING): ${file.name}`);
                } else {
                    // 投稿が存在するか確認
                    const postDoc = await db.collection("posts").doc(postId).get();
                    if (!postDoc.exists) {
                        shouldDelete = true;
                        console.log(`Orphan (post deleted): ${file.name}`);
                    }
                }

                if (shouldDelete) {
                    await file.delete();
                    deletedCount++;
                }
            } catch (error) {
                console.error(`Error checking ${file.name}:`, error);
            }
        }

        // ===============================================
        // 2. サークル画像のクリーンアップ
        // ===============================================
        console.log("Checking circles media...");
        const [circleFiles] = await bucket.getFiles({ prefix: "circles/" });

        for (const file of circleFiles) {
            checkedCount++;
            try {
                const [metadata] = await file.getMetadata();
                const timeCreated = metadata.timeCreated;
                const createdAt = timeCreated ? new Date(timeCreated).getTime() : 0;

                // 24時間以上経過していないならスキップ
                if (now - createdAt < TWENTY_FOUR_HOURS) continue;

                // パスからcircleIdを抽出: circles/{circleId}/icon/{fileName}
                const pathParts = file.name.split("/");
                if (pathParts.length >= 2) {
                    const circleId = pathParts[1];
                    const circleDoc = await db.collection("circles").doc(circleId).get();

                    if (!circleDoc.exists) {
                        console.log(`Orphan (circle deleted): ${file.name}`);
                        await file.delete();
                        deletedCount++;
                    }
                }
            } catch (error) {
                console.error(`Error checking ${file.name}:`, error);
            }
        }

        // ===============================================
        // 3. タスク添付のクリーンアップ
        // ===============================================
        console.log("Checking task attachments...");
        const [taskFiles] = await bucket.getFiles({ prefix: "task_attachments/" });

        for (const file of taskFiles) {
            checkedCount++;
            try {
                const [metadata] = await file.getMetadata();
                const taskTimeCreated = metadata.timeCreated;
                const taskCreatedAt = taskTimeCreated ? new Date(taskTimeCreated).getTime() : 0;

                // 24時間以上経過していないならスキップ
                if (now - taskCreatedAt < TWENTY_FOUR_HOURS) continue;

                // パスからtaskIdを抽出: task_attachments/{userId}/{taskId}/{fileName}
                const pathParts = file.name.split("/");
                if (pathParts.length >= 3) {
                    const taskId = pathParts[2];
                    const taskDoc = await db.collection("tasks").doc(taskId).get();

                    if (!taskDoc.exists) {
                        console.log(`Orphan (task deleted): ${file.name}`);
                        await file.delete();
                        deletedCount++;
                    }
                }
            } catch (error) {
                console.error(`Error checking ${file.name}:`, error);
            }
        }

        // ===============================================
        // 4. 孤立サークル投稿のクリーンアップ（Firestore）
        // ===============================================
        console.log("Checking orphaned circle posts...");
        let orphanedPostsDeleted = 0;

        const circlePostsSnapshot = await db.collection("posts")
            .where("circleId", "!=", null)
            .limit(500)
            .get();

        const circleExistsCache: Map<string, boolean> = new Map();

        for (const postDoc of circlePostsSnapshot.docs) {
            try {
                const postData = postDoc.data();
                const circleId = postData.circleId;

                if (!circleId) continue;

                let circleExists = circleExistsCache.get(circleId);
                if (circleExists === undefined) {
                    const circleDoc = await db.collection("circles").doc(circleId).get();
                    circleExists = circleDoc.exists;
                    circleExistsCache.set(circleId, circleExists);
                }

                if (!circleExists) {
                    console.log(`Orphaned circle post found: ${postDoc.id} (circleId: ${circleId})`);

                    const deleteRefs: FirebaseFirestore.DocumentReference[] = [];

                    // コメント削除
                    const comments = await db.collection("comments").where("postId", "==", postDoc.id).get();
                    comments.docs.forEach((c) => deleteRefs.push(c.ref));

                    // リアクション削除
                    const reactions = await db.collection("reactions").where("postId", "==", postDoc.id).get();
                    reactions.docs.forEach((r) => deleteRefs.push(r.ref));

                    // 投稿自体を削除
                    deleteRefs.push(postDoc.ref);

                    // バッチ削除
                    const batch = db.batch();
                    deleteRefs.forEach((ref) => batch.delete(ref));
                    await batch.commit();

                    // メディアも削除
                    const mediaItems = postData.mediaItems || [];
                    for (const media of mediaItems) {
                        if (media.url && media.url.includes("firebasestorage.googleapis.com")) {
                            try {
                                const urlParts = media.url.split("/o/")[1];
                                if (urlParts) {
                                    const filePath = decodeURIComponent(urlParts.split("?")[0]);
                                    await bucket.file(filePath).delete().catch(() => { });
                                }
                            } catch (e) {
                                console.error(`Media delete failed:`, e);
                            }
                        }
                    }

                    orphanedPostsDeleted++;
                }
            } catch (error) {
                console.error(`Error checking post ${postDoc.id}:`, error);
            }
        }

        // ===============================================
        // 5. 孤立コメントのクリーンアップ（Firestore）
        // ===============================================
        console.log("Checking orphaned comments...");
        let orphanedCommentsDeleted = 0;

        const commentsSnapshot = await db.collection("comments")
            .limit(1000)
            .get();

        const postExistsCache: Map<string, boolean> = new Map();

        for (const commentDoc of commentsSnapshot.docs) {
            try {
                const commentData = commentDoc.data();
                const postId = commentData.postId;

                if (!postId) continue;

                let postExists = postExistsCache.get(postId);
                if (postExists === undefined) {
                    const postDocRef = await db.collection("posts").doc(postId).get();
                    postExists = postDocRef.exists;
                    postExistsCache.set(postId, postExists);
                }

                if (!postExists) {
                    console.log(`Orphaned comment found: ${commentDoc.id} (postId: ${postId})`);
                    await commentDoc.ref.delete();
                    orphanedCommentsDeleted++;
                }
            } catch (error) {
                console.error(`Error checking comment ${commentDoc.id}:`, error);
            }
        }

        // ===============================================
        // 6. 孤立リアクションのクリーンアップ（Firestore）
        // ===============================================
        console.log("Checking orphaned reactions...");
        let orphanedReactionsDeleted = 0;

        const reactionsSnapshot = await db.collection("reactions")
            .limit(1000)
            .get();

        for (const reactionDoc of reactionsSnapshot.docs) {
            try {
                const reactionData = reactionDoc.data();
                const postId = reactionData.postId;

                if (!postId) continue;

                let postExists = postExistsCache.get(postId);
                if (postExists === undefined) {
                    const postDocRef = await db.collection("posts").doc(postId).get();
                    postExists = postDocRef.exists;
                    postExistsCache.set(postId, postExists);
                }

                if (!postExists) {
                    console.log(`Orphaned reaction found: ${reactionDoc.id} (postId: ${postId})`);
                    await reactionDoc.ref.delete();
                    orphanedReactionsDeleted++;
                }
            } catch (error) {
                console.error(`Error checking reaction ${reactionDoc.id}:`, error);
            }
        }

        // サークルAI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
        const twoDaysAgo = new Date();
        twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
        const twoDaysAgoStr = twoDaysAgo.toISOString().split("T")[0];

        const oldHistorySnapshot = await db.collection("circleAIPostHistory")
            .where("date", "<", twoDaysAgoStr)
            .get();

        let historyDeleted = 0;
        for (const doc of oldHistorySnapshot.docs) {
            await doc.ref.delete();
            historyDeleted++;
        }
        if (historyDeleted > 0) {
            console.log(`Deleted ${historyDeleted} old circleAIPostHistory documents`);
        }

        // AI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
        const oldAIHistorySnapshot = await db.collection("aiPostHistory")
            .where("date", "<", twoDaysAgoStr)
            .get();

        let aiHistoryDeleted = 0;
        for (const doc of oldAIHistorySnapshot.docs) {
            await doc.ref.delete();
            aiHistoryDeleted++;
        }
        if (aiHistoryDeleted > 0) {
            console.log(`Deleted ${aiHistoryDeleted} old aiPostHistory documents`);
        }

        console.log(`=== cleanupOrphanedMedia COMPLETE: checked=${checkedCount}, deleted=${deletedCount}, orphanedPosts=${orphanedPostsDeleted}, orphanedComments=${orphanedCommentsDeleted}, orphanedReactions=${orphanedReactionsDeleted} ===`);
    }
);

/**
 * 問い合わせ自動クリーンアップ（毎日実行）
 * - 6日経過: 削除予告通知
 * - 7日経過: 本体削除 + アーカイブ保存
 */
export const cleanupResolvedInquiries = onSchedule(
    {
        schedule: "0 3 * * *", // 毎日午前3時（日本時間）
        timeZone: "Asia/Tokyo",
        region: "asia-northeast1",
    },
    async () => {
        console.log("=== cleanupResolvedInquiries started ===");

        const now = new Date();
        const sixDaysAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
        const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

        // 解決済みの問い合わせを取得
        const inquiriesSnapshot = await db.collection("inquiries")
            .where("status", "==", "resolved")
            .get();

        console.log(`Found ${inquiriesSnapshot.size} resolved inquiries`);

        for (const doc of inquiriesSnapshot.docs) {
            const inquiry = doc.data();
            const inquiryId = doc.id;
            const resolvedAt = inquiry.resolvedAt?.toDate?.();

            if (!resolvedAt) {
                console.log(`Inquiry ${inquiryId} has no resolvedAt, skipping`);
                continue;
            }

            // 7日以上経過 → 削除
            if (resolvedAt <= sevenDaysAgo) {
                console.log(`Deleting inquiry ${inquiryId} (resolved at ${resolvedAt})`);
                await deleteInquiryWithArchive(inquiryId, inquiry);
                continue;
            }

            // 6日以上経過 & 7日未満 → 削除予告通知
            if (resolvedAt <= sixDaysAgo && resolvedAt > sevenDaysAgo) {
                console.log(`Sending deletion warning for inquiry ${inquiryId}`);
                await sendDeletionWarning(inquiryId, inquiry);
            }
        }

        console.log("=== cleanupResolvedInquiries completed ===");
    }
);

/**
 * 問い合わせを削除し、アーカイブに保存
 */
async function deleteInquiryWithArchive(
    inquiryId: string,
    inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
    try {
        const inquiryRef = db.collection("inquiries").doc(inquiryId);

        // 1. メッセージを取得して会話ログを作成
        const messagesSnapshot = await inquiryRef.collection("messages")
            .orderBy("createdAt", "asc")
            .get();

        let conversationLog = "";
        let firstMessage = "";

        messagesSnapshot.docs.forEach((msgDoc, index) => {
            const msg = msgDoc.data();
            const msgDate = msg.createdAt?.toDate?.() || new Date();
            const dateStr = `${msgDate.getFullYear()}-${String(msgDate.getMonth() + 1).padStart(2, "0")}-${String(msgDate.getDate()).padStart(2, "0")} ${String(msgDate.getHours()).padStart(2, "0")}:${String(msgDate.getMinutes()).padStart(2, "0")}`;
            const sender = msg.senderType === "admin" ? "運営チーム" : "ユーザー";
            conversationLog += `[${dateStr} ${sender}]\n${msg.content}\n\n`;

            if (index === 0) {
                firstMessage = msg.content || "";
            }
        });

        // 2. カテゴリラベル
        const categoryLabels: { [key: string]: string } = {
            bug: "バグ報告",
            feature: "機能要望",
            account: "アカウント関連",
            other: "その他",
        };
        const categoryLabel = categoryLabels[inquiry.category] || inquiry.category;

        // 3. アーカイブに保存
        await db.collection("inquiry_archives").add({
            originalInquiryId: inquiryId,
            userId: inquiry.userId,
            userDisplayName: inquiry.userDisplayName,
            category: categoryLabel,
            subject: inquiry.subject,
            firstMessage,
            conversationLog: conversationLog.trim(),
            createdAt: inquiry.createdAt,
            resolvedAt: inquiry.resolvedAt,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
        });

        console.log(`Archived inquiry ${inquiryId}`);

        // 4. メッセージサブコレクションを削除
        const batch = db.batch();
        messagesSnapshot.docs.forEach((msgDoc) => {
            batch.delete(msgDoc.ref);
        });
        await batch.commit();

        console.log(`Deleted ${messagesSnapshot.size} messages for inquiry ${inquiryId}`);

        // 5. Storage画像を削除（存在する場合）
        for (const msgDoc of messagesSnapshot.docs) {
            const msg = msgDoc.data();
            if (msg.imageUrl) {
                await deleteStorageFileFromUrl(msg.imageUrl);
            }
        }

        // 6. 問い合わせ本体を削除
        await inquiryRef.delete();
        console.log(`Deleted inquiry ${inquiryId}`);

    } catch (error) {
        console.error(`Error deleting inquiry ${inquiryId}:`, error);
    }
}

/**
 * 削除予告通知を送信
 */
async function sendDeletionWarning(
    inquiryId: string,
    inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
    try {
        const userId = inquiry.userId;
        const now = admin.firestore.FieldValue.serverTimestamp();
        const notifyBody = `「${inquiry.subject}」は明日削除されます（ステータス: 解決済み）`;

        // アプリ内通知
        await db.collection("users").doc(userId).collection("notifications").add({
            type: "inquiry_deletion_warning",
            title: "問い合わせ削除予告",
            body: notifyBody,
            inquiryId,
            isRead: false,
            createdAt: now,
        });

        console.log(`Sent deletion warning to user ${userId} for inquiry ${inquiryId}`);
    } catch (error) {
        console.error(`Error sending deletion warning for inquiry ${inquiryId}:`, error);
    }
}

/**
 * 毎日深夜に実行されるレポートクリーンアップ処理
 * 対処済み（reviewed/dismissed）かつ1ヶ月以上前のレポートを削除する
 */
export const cleanupReports = onSchedule(
    {
        schedule: "every day 00:00",
        timeZone: "Asia/Tokyo",
        timeoutSeconds: 300,
        region: "asia-northeast1",
    },
    async () => {
        console.log("Starting cleanupReports function...");

        try {
            // 1ヶ月前の日時を計算
            const cutoffDate = new Date();
            cutoffDate.setMonth(cutoffDate.getMonth() - 1);
            const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

            // Reviewed reports
            const reviewedSnapshot = await db
                .collection("reports")
                .where("status", "==", "reviewed")
                .where("createdAt", "<", cutoffTimestamp)
                .get();

            // Dismissed reports
            const dismissedSnapshot = await db
                .collection("reports")
                .where("status", "==", "dismissed")
                .where("createdAt", "<", cutoffTimestamp)
                .get();

            console.log(
                `Found ${reviewedSnapshot.size} reviewed and ${dismissedSnapshot.size} dismissed reports to delete.`
            );

            // 削除対象のドキュメントを結合
            const allDocs = [...reviewedSnapshot.docs, ...dismissedSnapshot.docs];

            if (allDocs.length === 0) {
                console.log("No reports to delete.");
                return;
            }

            // バッチ処理で削除（500件ずつ）
            const MAX_BATCH_SIZE = 500;
            const chunks = [];
            for (let i = 0; i < allDocs.length; i += MAX_BATCH_SIZE) {
                chunks.push(allDocs.slice(i, i + MAX_BATCH_SIZE));
            }

            let deletedCount = 0;
            for (const chunk of chunks) {
                const batch = db.batch();
                chunk.forEach((doc) => {
                    batch.delete(doc.ref);
                });
                await batch.commit();
                deletedCount += chunk.length;
                console.log(`Deleted batch of ${chunk.length} reports.`);
            }

            console.log(`Cleanup completed. Total deleted: ${deletedCount}`);
        } catch (error) {
            console.error("Error in cleanupReports:", error);
        }
    }
);

/**
 * 永久BANユーザーのデータ削除クリーンアップ（毎日午前4時）
 */
export const cleanupBannedUsers = onSchedule(
    {
        schedule: "0 4 * * *",
        timeZone: "Asia/Tokyo",
        region: "asia-northeast1",
        timeoutSeconds: 540,
    },
    async () => {
        console.log("=== cleanupBannedUsers START ===");
        const now = admin.firestore.Timestamp.now();

        const snapshot = await db.collection("users")
            .where("banStatus", "==", "permanent")
            .where("permanentBanScheduledDeletionAt", "<=", now)
            .limit(20)
            .get();

        if (snapshot.empty) {
            console.log("No users to delete");
            return;
        }

        console.log(`Found ${snapshot.size} users to scheduled delete`);

        for (const doc of snapshot.docs) {
            try {
                const uid = doc.id;
                console.log(`Deleting banned user: ${uid}`);

                await admin.auth().deleteUser(uid).catch(e => {
                    console.warn(`Auth delete failed for ${uid}:`, e);
                });

                // ユーザードキュメント削除
                await db.collection("users").doc(uid).delete();

            } catch (error) {
                console.error(`Error deleting user ${doc.id}:`, error);
            }
        }

        console.log("=== cleanupBannedUsers COMPLETE ===");
    }
);
