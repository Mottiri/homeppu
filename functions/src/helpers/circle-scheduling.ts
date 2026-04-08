const DAY_MS = 24 * 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

export const GHOST_THRESHOLD_DAYS = 365;
export const EMPTY_THRESHOLD_DAYS = 30;
export const DELETE_GRACE_DAYS = 7;

const INITIAL_AI_POST_MIN_DELAY_MINUTES = 30;
const INITIAL_AI_POST_MAX_DELAY_MINUTES = 6 * 60;
const NEXT_AI_POST_MIN_DELAY_MINUTES = 18 * 60;
const NEXT_AI_POST_MAX_DELAY_MINUTES = 30 * 60;
const AI_POST_RETRY_MIN_DELAY_MINUTES = 60;
const AI_POST_RETRY_MAX_DELAY_MINUTES = 180;

function addMs(date: Date, deltaMs: number): Date {
  return new Date(date.getTime() + deltaMs);
}

function randomInt(min: number, max: number): number {
  return min + Math.floor(Math.random() * (max - min + 1));
}

export function addDays(date: Date, days: number): Date {
  return addMs(date, days * DAY_MS);
}

export function computeInitialGhostCheckAt(createdAt: Date = new Date()): Date {
  return addDays(createdAt, EMPTY_THRESHOLD_DAYS);
}

export function computeNextGhostCheckAt(params: {
  createdAt: Date;
  lastHumanPostAt?: Date | null;
  ghostWarningNotifiedAt?: Date | null;
}): Date {
  if (params.ghostWarningNotifiedAt) {
    return addDays(params.ghostWarningNotifiedAt, DELETE_GRACE_DAYS);
  }
  if (params.lastHumanPostAt) {
    return addDays(params.lastHumanPostAt, GHOST_THRESHOLD_DAYS);
  }
  return computeInitialGhostCheckAt(params.createdAt);
}

export function computeInitialCircleAIPostAt(baseDate: Date = new Date()): Date {
  return addMs(
    baseDate,
    randomInt(INITIAL_AI_POST_MIN_DELAY_MINUTES, INITIAL_AI_POST_MAX_DELAY_MINUTES) * MINUTE_MS
  );
}

export function computeNextCircleAIPostAt(baseDate: Date = new Date()): Date {
  return addMs(
    baseDate,
    randomInt(NEXT_AI_POST_MIN_DELAY_MINUTES, NEXT_AI_POST_MAX_DELAY_MINUTES) * MINUTE_MS
  );
}

export function computeCircleAIPostRetryAt(baseDate: Date = new Date()): Date {
  return addMs(
    baseDate,
    randomInt(AI_POST_RETRY_MIN_DELAY_MINUTES, AI_POST_RETRY_MAX_DELAY_MINUTES) * MINUTE_MS
  );
}
