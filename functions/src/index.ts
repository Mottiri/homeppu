import { setGlobalOptions } from "firebase-functions/v2";

import { LOCATION } from "./config/constants";

// Global Options for v2 functions
setGlobalOptions({ region: LOCATION });

// ===============================================
// Callable
// ===============================================
export { initializeNameParts, getNameParts, updateUserName } from "./callable/names";
export { reportContent } from "./callable/reports";
export { createTask, getTasks } from "./callable/tasks";
export {
    createInquiry,
    sendInquiryMessage,
    sendInquiryReply,
    updateInquiryStatus,
} from "./callable/inquiries";
export { createCommentWithModeration, addUserReaction } from "./callable/comments";
export { createPostWithRateLimit, createPostWithModeration } from "./callable/posts";
export { initializeAIAccounts, generateAIPosts } from "./callable/ai";
export {
    deleteCircle,
    cleanupDeletedCircle,
    approveJoinRequest,
    rejectJoinRequest,
    sendJoinRequest,
} from "./callable/circles";
export {
    followUser,
    unfollowUser,
    getFollowStatus,
    getVirtueHistory,
    getVirtueStatus,
} from "./callable/users";
export {
    cleanUpUserFollows,
    deleteAllAIUsers,
    cleanupOrphanedCircleAIs,
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
export { onTaskUpdated, scheduleTaskReminders, scheduleTaskRemindersOnCreate } from "./triggers/tasks";
export { onReactionCreated } from "./triggers/reactions";
export { scheduleGoalReminders, scheduleGoalRemindersOnCreate } from "./triggers/goals";

// ===============================================
// Scheduled
// ===============================================
export { scheduleAIPosts } from "./scheduled/ai-posts";
export { checkGhostCircles, evolveCircleAIs, triggerEvolveCircleAIs } from "./scheduled/circles";
export { cleanupOrphanedMedia, cleanupResolvedInquiries, cleanupReports, cleanupBannedUsers } from "./scheduled/cleanup";
export { executeTaskReminder, executeGoalReminder } from "./scheduled/reminders";

// ===============================================
// Circle AI
// ===============================================
export { generateCircleAIPosts, executeCircleAIPost, triggerCircleAIPosts } from "./circle-ai/posts";

// ===============================================
// HTTP
// ===============================================
export { generateAICommentV1, generateAIReactionV1, executeAIPostGeneration } from "./http/ai-generation";
export { moderateImageCallable } from "./http/image-moderation";
