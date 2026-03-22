import { setGlobalOptions } from "firebase-functions/v2";

import { LOCATION } from "./config/constants";

// Global Options for v2 functions
setGlobalOptions({ region: LOCATION });

// ===============================================
// Callable
// ===============================================
export { initializeNameParts, getNameParts, updateUserName } from "./callable/names";
export { reportContent } from "./callable/reports";
export {
    createInquiry,
    sendInquiryMessage,
    sendInquiryReply,
    updateInquiryStatus,
} from "./callable/inquiries";
export {
    createCommentWithModeration,
    addUserReaction,
    removeUserReaction,
    likeCommentAsPostOwner,
    setActiveStampSheet,
    archiveAndStartNextStampSheet,
    syncStampSheetSnapshot,
} from "./callable/comments";
export { grantRewardedReactionUnlock } from "./callable/rewarded_reactions";
export { createPostWithModeration } from "./callable/posts";
export { initializeAIAccounts, generateAIPosts } from "./callable/ai";
export {
    deleteCircle,
    cleanupDeletedCircle,
    startCircleBrowseTrial,
    endCircleBrowseTrial,
    approveJoinRequest,
    rejectJoinRequest,
    sendJoinRequest,
    joinCircle,
    leaveCircle,
    searchCircles,
    createCircle,
    updateCircle,
} from "./callable/circles";
export {
    followUser,
    unfollowUser,
    getFollowStatus,
    getVirtueHistory,
    getVirtueStatus,
    checkPasswordResetTarget,
} from "./callable/users";
export { getVirtueShopConfig, purchaseVirtueItem } from "./callable/virtue_shop";

export {
    cleanUpUserFollows,
    deleteAllAIUsers,
    cleanupOrphanedCircleAIs,
    backfillPublicUsers,
    backfillCircleNameTokens,
    adminDeletePostWithPenalty,
    setAdminRole,
    removeAdminRole,
    banUser,
    permanentBanUser,
    unbanUser,
} from "./callable/admin";

// ===============================================
// Triggers
// ===============================================
export { onCircleCreated, onCircleUpdated } from "./triggers/circles";
export { onPostCreated } from "./triggers/posts";
export { onNotificationCreated, onCommentCreatedNotify, onReactionAddedNotify } from "./triggers/notifications";
export { onReactionCreated } from "./triggers/reactions";
export { onUserCreated, onUserUpdated, onUserDeleted } from "./triggers/users";

// ===============================================
// Scheduled
// ===============================================
export { checkGhostCircles, evolveCircleAIs, triggerEvolveCircleAIs } from "./scheduled/circles";
export {
    cleanupOrphanedMedia,
    cleanupResolvedInquiries,
    cleanupReports,
    cleanupBannedUsers,
    cleanupUnverifiedUsers,
} from "./scheduled/cleanup";

// ===============================================
// Circle AI
// ===============================================
export { generateCircleAIPosts, executeCircleAIPost, triggerCircleAIPosts } from "./circle-ai/posts";

// ===============================================
// HTTP
// ===============================================
export { generateAICommentV1, generateAIReactionV1, executeAIPostGeneration } from "./http/ai-generation";
export { moderateImageCallable } from "./http/image-moderation";
export { revenueCatWebhook } from "./http/revenuecat";
