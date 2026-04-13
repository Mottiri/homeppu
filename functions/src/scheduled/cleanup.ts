/**
 * スケジュールされたクリーンアップ関数
 * Phase 7: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { db } from "../helpers/firebase";
import { deleteStorageFileByPath, deleteStorageFileFromUrl } from "../helpers/storage";
import { LOCATION } from "../config/constants";
import { NOTIFICATION_TITLES } from "../config/messages";

/**
 * 孤立メディアクリーンアップ
 * Cloud Schedulerで毎日実行
 * 24時間以上経過した孤立メディアを削除
 */
export const cleanupOrphanedMedia = onSchedule(
    {
        schedule: "0 3 * * *", // 毎日午前3時 JST
        timeZone: "Asia/Tokyo",
        region: LOCATION,
        timeoutSeconds: 600, // 10分タイムアウト
    },
    async () => {
        console.log("=== cleanupOrphanedMedia START ===");
        const now = Date.now();
        const TWENTY_FOUR_HOURS = 24 * 60 * 60 * 1000;
        const threshold = admin.firestore.Timestamp.fromMillis(now - TWENTY_FOUR_HOURS);
        const pendingSnapshot = await db.collection("pendingMedia")
            .where("createdAt", "<=", threshold)
            .get();

        let deletedCount = 0;
        let checkedCount = 0;
        let resolvedCount = 0;

        for (const pendingDoc of pendingSnapshot.docs) {
            checkedCount++;
            try {
                const pendingData = pendingDoc.data();
                const storagePath = typeof pendingData.storagePath === "string" ? pendingData.storagePath : "";
                const type = typeof pendingData.type === "string" ? pendingData.type : "";

                if (!storagePath || !type) {
                    console.warn(`pendingMedia ${pendingDoc.id} is missing required fields`);
                    await pendingDoc.ref.delete();
                    resolvedCount++;
                    continue;
                }

                let isAttached = false;
                switch (type) {
                case "post_image": {
                    const postSnapshot = await db.collection("posts")
                        .where("mediaStoragePaths", "array-contains", storagePath)
                        .limit(1)
                        .get();
                    isAttached = !postSnapshot.empty;
                    break;
                }
                case "circle_icon": {
                    const circleSnapshot = await db.collection("circles")
                        .where("iconImageStoragePath", "==", storagePath)
                        .limit(1)
                        .get();
                    isAttached = !circleSnapshot.empty;
                    break;
                }
                case "circle_cover": {
                    const circleSnapshot = await db.collection("circles")
                        .where("coverImageStoragePath", "==", storagePath)
                        .limit(1)
                        .get();
                    isAttached = !circleSnapshot.empty;
                    break;
                }
                default:
                    console.warn(`Unknown pendingMedia type: ${type}`);
                    break;
                }

                if (isAttached) {
                    await pendingDoc.ref.delete();
                    resolvedCount++;
                    continue;
                }

                await deleteStorageFileByPath(storagePath);
                await pendingDoc.ref.delete();
                deletedCount++;
            } catch (error) {
                console.error(`Error checking pending media ${pendingDoc.id}:`, error);
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

        // AI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
        const oldAIHistorySnapshot = await db.collection("aiPostHistory")
            .where("date", "<", twoDaysAgoStr)
            .get();

        let aiHistoryDeleted = 0;
        for (const doc of oldAIHistorySnapshot.docs) {
            await doc.ref.delete();
            aiHistoryDeleted++;
        }

        console.log(
            `=== cleanupOrphanedMedia COMPLETE: checked=${checkedCount}, ` +
            `deleted=${deletedCount}, resolved=${resolvedCount}, ` +
            `circleAiHistoryDeleted=${historyDeleted}, aiHistoryDeleted=${aiHistoryDeleted} ===`
        );
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
        region: LOCATION,
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

        let warnedCount = 0;
        let deletedCount = 0;
        let skippedCount = 0;

        for (const doc of inquiriesSnapshot.docs) {
            const inquiry = doc.data();
            const inquiryId = doc.id;
            const resolvedAt = inquiry.resolvedAt?.toDate?.();

            if (!resolvedAt) {
                skippedCount++;
                continue;
            }

            // 7日以上経過 → 削除
            if (resolvedAt <= sevenDaysAgo) {
                await deleteInquiryWithArchive(inquiryId, inquiry);
                deletedCount++;
                continue;
            }

            // 6日以上経過 & 7日未満 → 削除予告通知
            if (resolvedAt <= sixDaysAgo && resolvedAt > sevenDaysAgo) {
                await sendDeletionWarning(inquiryId, inquiry);
                warnedCount++;
                continue;
            }

            skippedCount++;
        }

        console.log(
            `=== cleanupResolvedInquiries completed: scanned=${inquiriesSnapshot.size}, ` +
            `warned=${warnedCount}, deleted=${deletedCount}, skipped=${skippedCount} ===`
        );
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

        // 4. メッセージサブコレクションを削除
        const batch = db.batch();
        messagesSnapshot.docs.forEach((msgDoc) => {
            batch.delete(msgDoc.ref);
        });
        await batch.commit();

        // 5. Storage画像を削除（存在する場合）
        for (const msgDoc of messagesSnapshot.docs) {
            const msg = msgDoc.data();
            if (msg.imageUrl) {
                await deleteStorageFileFromUrl(msg.imageUrl);
            }
        }

        // 6. 問い合わせ本体を削除
        await inquiryRef.delete();
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
            title: NOTIFICATION_TITLES.INQUIRY_DELETE_WARNING,
            body: notifyBody,
            inquiryId,
            isRead: false,
            createdAt: now,
        });

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
        region: LOCATION,
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

            // 削除対象のドキュメントを結合
            const allDocs = [...reviewedSnapshot.docs, ...dismissedSnapshot.docs];

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
            }

            console.log(
                `cleanupReports complete: reviewed=${reviewedSnapshot.size}, ` +
                `dismissed=${dismissedSnapshot.size}, deleted=${deletedCount}`
            );
        } catch (error) {
            console.error("Error in cleanupReports:", error);
        }
    }
);

const CLEANUP_QUERY_BATCH_SIZE = 100;
const CLEANUP_DELETE_BATCH_SIZE = 400;
const BANNED_USER_SUBCOLLECTIONS = [
    "notifications",
    "categories",
    "stampSheet",
    "stampSheetArchives",
    "purchases",
    "virtueDaily",
];

async function commitDeleteBatch(
    refs: FirebaseFirestore.DocumentReference[]
): Promise<void> {
    for (let i = 0; i < refs.length; i += CLEANUP_DELETE_BATCH_SIZE) {
        const batch = db.batch();
        refs.slice(i, i + CLEANUP_DELETE_BATCH_SIZE).forEach((ref) => batch.delete(ref));
        await batch.commit();
    }
}

async function deleteStoragePrefix(prefix: string): Promise<number> {
    const bucket = admin.storage().bucket();
    const [files] = await bucket.getFiles({ prefix });
    let deleted = 0;

    for (const file of files) {
        try {
            await file.delete();
            deleted++;
        } catch (error) {
            console.warn(`Failed to delete storage file ${file.name}:`, error);
        }
    }

    return deleted;
}

async function deleteUserSubcollection(userId: string, subcollection: string): Promise<number> {
    let deleted = 0;

    while (true) {
        const snapshot = await db
            .collection("users")
            .doc(userId)
            .collection(subcollection)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (snapshot.empty) {
            return deleted;
        }

        await commitDeleteBatch(snapshot.docs.map((doc) => doc.ref));
        deleted += snapshot.size;
    }
}

async function deletePostDocument(
    postDoc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): Promise<void> {
    if (!postDoc.exists) return;

    const postData = postDoc.data() || {};
    const postId = postDoc.id;

    while (true) {
        const commentsSnapshot = await db
            .collection("comments")
            .where("postId", "==", postId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();
        if (commentsSnapshot.empty) break;
        await commitDeleteBatch(commentsSnapshot.docs.map((doc) => doc.ref));
    }

    while (true) {
        const reactionsSnapshot = await db
            .collection("reactions")
            .where("postId", "==", postId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();
        if (reactionsSnapshot.empty) break;
        await commitDeleteBatch(reactionsSnapshot.docs.map((doc) => doc.ref));
    }

    const mediaItems = Array.isArray(postData.mediaItems) ? postData.mediaItems : [];
    for (const media of mediaItems) {
        if (typeof media?.url === "string" && media.url.length > 0) {
            await deleteStorageFileFromUrl(media.url);
        }
        if (typeof media?.thumbnailUrl === "string" && media.thumbnailUrl.length > 0) {
            await deleteStorageFileFromUrl(media.thumbnailUrl);
        }
    }

    await postDoc.ref.delete().catch((error) => {
        console.warn(`Failed to delete post ${postId}:`, error);
    });
}

async function deletePostsByUser(userId: string): Promise<number> {
    let deleted = 0;

    while (true) {
        const postsSnapshot = await db
            .collection("posts")
            .where("userId", "==", userId)
            .limit(20)
            .get();

        if (postsSnapshot.empty) {
            return deleted;
        }

        for (const postDoc of postsSnapshot.docs) {
            await deletePostDocument(postDoc);
            deleted++;
        }
    }
}

async function deleteUserInquiries(userId: string): Promise<number> {
    let deleted = 0;

    while (true) {
        const inquiriesSnapshot = await db
            .collection("inquiries")
            .where("userId", "==", userId)
            .limit(10)
            .get();

        if (inquiriesSnapshot.empty) {
            return deleted;
        }

        for (const inquiryDoc of inquiriesSnapshot.docs) {
            while (true) {
                const messagesSnapshot = await inquiryDoc.ref
                    .collection("messages")
                    .limit(CLEANUP_QUERY_BATCH_SIZE)
                    .get();

                if (messagesSnapshot.empty) break;

                for (const messageDoc of messagesSnapshot.docs) {
                    const imageUrl = messageDoc.data().imageUrl;
                    if (typeof imageUrl === "string" && imageUrl.length > 0) {
                        await deleteStorageFileFromUrl(imageUrl);
                    }
                }

                await commitDeleteBatch(messagesSnapshot.docs.map((doc) => doc.ref));
            }

            await inquiryDoc.ref.delete();
            deleted++;
        }
    }
}

async function deleteDocsByField(
    collectionName: string,
    fieldName: string,
    value: string
): Promise<number> {
    let deleted = 0;

    while (true) {
        const snapshot = await db
            .collection(collectionName)
            .where(fieldName, "==", value)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (snapshot.empty) {
            return deleted;
        }

        await commitDeleteBatch(snapshot.docs.map((doc) => doc.ref));
        deleted += snapshot.size;
    }
}

async function updateUserArrayReferences(
    arrayField: "following" | "followers",
    countField: "followingCount" | "followersCount",
    targetUserId: string
): Promise<number> {
    let updated = 0;

    while (true) {
        const snapshot = await db
            .collection("users")
            .where(arrayField, "array-contains", targetUserId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (snapshot.empty) {
            return updated;
        }

        for (const userDoc of snapshot.docs) {
            const values = Array.isArray(userDoc.data()[arrayField])
                ? (userDoc.data()[arrayField] as string[])
                : [];
            const nextValues = values.filter((id) => id !== targetUserId);
            await userDoc.ref.update({
                [arrayField]: nextValues,
                [countField]: nextValues.length,
            });
            updated++;
        }
    }
}

async function cleanupCircleById(circleId: string): Promise<void> {
    const circleDoc = await db.collection("circles").doc(circleId).get();
    if (!circleDoc.exists) return;

    while (true) {
        const postsSnapshot = await db
            .collection("posts")
            .where("circleId", "==", circleId)
            .limit(20)
            .get();

        if (postsSnapshot.empty) break;

        for (const postDoc of postsSnapshot.docs) {
            await deletePostDocument(postDoc);
        }
    }

    while (true) {
        const joinRequestsSnapshot = await db
            .collection("circleJoinRequests")
            .where("circleId", "==", circleId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (joinRequestsSnapshot.empty) break;
        await commitDeleteBatch(joinRequestsSnapshot.docs.map((doc) => doc.ref));
    }

    await deleteStoragePrefix(`circles/${circleId}/`);

    const generatedAIs = Array.isArray(circleDoc.data()?.generatedAIs) ? circleDoc.data()?.generatedAIs : [];
    for (const ai of generatedAIs) {
        const aiId = typeof ai?.id === "string" ? ai.id : "";
        if (!aiId.startsWith("circle_ai_")) continue;

        await deleteUserSubcollection(aiId, "notifications");
        await db.collection("users").doc(aiId).delete().catch(() => { });
    }

    await circleDoc.ref.delete().catch((error) => {
        console.warn(`Failed to delete circle ${circleId}:`, error);
    });
}

async function deleteOwnedCircles(userId: string): Promise<number> {
    let deleted = 0;

    while (true) {
        const circlesSnapshot = await db
            .collection("circles")
            .where("ownerId", "==", userId)
            .limit(10)
            .get();

        if (circlesSnapshot.empty) {
            return deleted;
        }

        for (const circleDoc of circlesSnapshot.docs) {
            await cleanupCircleById(circleDoc.id);
            deleted++;
        }
    }
}

async function removeUserFromCircles(userId: string): Promise<number> {
    let updated = 0;

    while (true) {
        const circlesSnapshot = await db
            .collection("circles")
            .where("memberIds", "array-contains", userId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (circlesSnapshot.empty) break;

        for (const circleDoc of circlesSnapshot.docs) {
            const data = circleDoc.data();
            if (data.ownerId === userId) continue;

            const memberIds = Array.isArray(data.memberIds) ? data.memberIds as string[] : [];
            const nextMemberIds = memberIds.filter((memberId) => memberId !== userId);
            const maxMembers = Number(data.maxMembers ?? 20);
            const updateData: Record<string, unknown> = {
                memberIds: nextMemberIds,
                memberCount: nextMemberIds.length,
                hasSpace: nextMemberIds.length < maxMembers,
            };
            if (data.subOwnerId === userId) {
                updateData.subOwnerId = null;
            }

            await circleDoc.ref.update(updateData);
            updated++;
        }
    }

    while (true) {
        const subOwnerSnapshot = await db
            .collection("circles")
            .where("subOwnerId", "==", userId)
            .limit(CLEANUP_QUERY_BATCH_SIZE)
            .get();

        if (subOwnerSnapshot.empty) {
            return updated;
        }

        for (const circleDoc of subOwnerSnapshot.docs) {
            if (circleDoc.data().ownerId === userId) continue;
            await circleDoc.ref.update({ subOwnerId: null });
            updated++;
        }
    }
}

async function disableBannedAuthUser(userId: string): Promise<void> {
    try {
        await admin.auth().updateUser(userId, { disabled: true });
    } catch (error) {
        console.warn(`Auth disable failed for ${userId}:`, error);
    }
}

async function cleanupBannedUserAppData(
    userDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
    const userId = userDoc.id;
    const userData = userDoc.data();

    await disableBannedAuthUser(userId);

    if (typeof userData.profileImageStoragePath === "string" && userData.profileImageStoragePath.length > 0) {
        await admin.storage().bucket().file(userData.profileImageStoragePath).delete().catch(() => { });
    }
    if (typeof userData.profileImageUrl === "string" && userData.profileImageUrl.length > 0) {
        await deleteStorageFileFromUrl(userData.profileImageUrl);
    }
    if (typeof userData.headerImageUrl === "string" && userData.headerImageUrl.length > 0) {
        await deleteStorageFileFromUrl(userData.headerImageUrl);
    }

    await deleteStoragePrefix(`users/${userId}/profile/`);
    await deleteStoragePrefix(`headers/${userId}.`);
    await deleteStoragePrefix(`posts/${userId}/`);
    await deleteStoragePrefix(`inquiries/${userId}/`);

    const deletedOwnedCircles = await deleteOwnedCircles(userId);
    const deletedPosts = await deletePostsByUser(userId);
    const deletedInquiries = await deleteUserInquiries(userId);
    const deletedInquiryArchives = await deleteDocsByField("inquiry_archives", "userId", userId);
    const deletedJoinRequests = await deleteDocsByField("circleJoinRequests", "userId", userId);
    const deletedBanAppeals = await deleteDocsByField("banAppeals", "bannedUserId", userId);
    const deletedVirtueHistory = await deleteDocsByField("virtueHistory", "userId", userId);
    const followingRefsUpdated = await updateUserArrayReferences("following", "followingCount", userId);
    const followerRefsUpdated = await updateUserArrayReferences("followers", "followersCount", userId);
    const circlesUpdated = await removeUserFromCircles(userId);

    for (const subcollection of BANNED_USER_SUBCOLLECTIONS) {
        await deleteUserSubcollection(userId, subcollection);
    }

    await userDoc.ref.delete();

    console.log(
        `cleanupBannedUserAppData COMPLETE: ${userId} ` +
        `ownedCircles=${deletedOwnedCircles} posts=${deletedPosts} inquiries=${deletedInquiries} ` +
        `inquiryArchives=${deletedInquiryArchives} joinRequests=${deletedJoinRequests} ` +
        `banAppeals=${deletedBanAppeals} virtueHistory=${deletedVirtueHistory} ` +
        `followingRefs=${followingRefsUpdated} followerRefs=${followerRefsUpdated} circlesUpdated=${circlesUpdated}`
    );
}

/**
 * 永久BANユーザーのデータ削除クリーンアップ（毎日午前4時）
 */
export const cleanupBannedUsers = onSchedule(
    {
        schedule: "0 4 * * *",
        timeZone: "Asia/Tokyo",
        region: LOCATION,
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

        for (const doc of snapshot.docs) {
            try {
                await cleanupBannedUserAppData(doc);
            } catch (error) {
                console.error(`Error deleting user ${doc.id}:`, error);
            }
        }

        console.log("=== cleanupBannedUsers COMPLETE ===");
    }
);



export const cleanupUnverifiedUsers = onSchedule(
    {
        schedule: "0 4 * * *",
        timeZone: "Asia/Tokyo",
        region: LOCATION,
        timeoutSeconds: 540,
    },
    async () => {
        // 未認証ユーザー（emailVerified=false）を一定時間経過後に削除
        console.log("=== cleanupUnverifiedUsers START ===");
        const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;

        let deleted = 0;
        let checked = 0;
        let nextPageToken: string | undefined;

        do {
            const result = await admin.auth().listUsers(1000, nextPageToken);
            nextPageToken = result.pageToken;

            for (const user of result.users) {
                checked++;
                if (user.emailVerified) continue;

                const creationTime = user.metadata.creationTime
                    ? new Date(user.metadata.creationTime).getTime()
                    : 0;
                if (!creationTime || creationTime > cutoff) continue;

                try {
                    const userDoc = await db.collection("users").doc(user.uid).get();
                    if (userDoc.exists && userDoc.data()?.isAI) {
                        continue;
                    }

                    await admin.auth().deleteUser(user.uid).catch((e) => {
                        console.warn(`Auth delete failed for ${user.uid}:`, e);
                    });
                    await db.collection("users").doc(user.uid).delete().catch((e) => {
                        console.warn(`Firestore delete failed for ${user.uid}:`, e);
                    });
                    deleted++;
                } catch (error) {
                    console.error(`Error deleting unverified user ${user.uid}:`, error);
                }
            }
        } while (nextPageToken);

        console.log(
            `=== cleanupUnverifiedUsers COMPLETE: checked=${checked}, deleted=${deleted} ===`
        );
    }
);


