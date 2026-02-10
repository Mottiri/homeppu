/**
 * Shared virtue constants.
 * Legacy moderation deduction paths were removed.
 */

export const VIRTUE_CONFIG = {
    initial: 100,
    maxDaily: 50,
    banThreshold: 0,
    lossPerNegative: 15,
    lossPerReport: 20,
    gainPerPraise: 5,
    warningThreshold: 30,
} as const;

export const NG_WORDS = ["死ね", "殺す", "殺したい", "うざい", "暴力", "レイプ", "自殺"];
