# Notification Push Auto-Send Spec (onNotificationCreated)

Date: 2026-01-25
Owner role: Feature Spec Owner

## What We Are Changing (Proposed)
- Restore `onNotificationCreated` as the single push-sending trigger.
- Add per-notification push control without breaking existing flows.
- Record push delivery state on the notification document for operability.

This aligns with the project decision: “when a notification document is created, push should be sent automatically,” while allowing explicit opt-out.

## Background / Current Risk
- Many functions create notification docs and assume `onNotificationCreated` will push.
- In the current source tree, `onNotificationCreated` is missing.
- Re-deploying functions without restoring it could stop most push notifications.

## Source of Truth Alignment
- `docs/cloud_functions_reference.md` states `onNotificationCreated` exists.
- `docs/INDEX_TS_REFACTORING_PLAN.md` expects it in `triggers/notifications.ts`.
- Code is treated as truth on conflicts; this spec resolves the mismatch.

## Proposed Data Contract (Minimal Additions)
All fields are optional and backward compatible.

Notification document new fields:
- `pushPolicy`: `"always" | "never" | "bySettings"` (optional)
- `pushStatus`: `"pending" | "sent" | "skipped" | "error"` (set by trigger)
- `pushSentAt`: Timestamp (set when sent)
- `pushErrorCode`: string (set when error)
- `pushSkippedReason`: string (set when skipped)

Policy defaults if `pushPolicy` is omitted:
- `comment` / `reaction` -> `"bySettings"`
- all other types -> `"always"`

## Proposed Trigger Logic
Path: `users/{userId}/notifications/{notificationId}` on create only.

High-level flow:
1. Read notification doc.
2. Resolve `pushPolicy` (explicit or default).
3. If `pushPolicy == "never"` -> set `pushStatus="skipped"`.
4. If `pushPolicy == "bySettings"` and user setting disables this type -> skip.
5. Otherwise attempt `sendPushOnly(...)`.
6. Update doc with `pushStatus` and metadata.

Important guardrails:
- Only `onCreate` is used (no update-trigger loop).
- Settings check is applied only to `comment` and `reaction`.

## Rollout / Safety Notes
- Do not deploy all functions until this trigger is restored.
- A narrow deploy (`--only functions:onNotificationCreated`) is safer.
- Existing notifications will not re-trigger; this is acceptable for now.

## Acceptance Criteria
- Inquiry notifications (`inquiry_received`, `inquiry_user_reply`, `inquiry_reply`, `inquiry_status_changed`) push to admins/users.
- Comment/reaction respect user settings.
- Setting `pushPolicy="never"` results in in-app notification only (no push).
- Push outcome is recorded on the notification doc.

## Files Expected to Change (Implementation Phase)
- `functions/src/triggers/notifications.ts`
- `functions/src/index.ts`
- `docs/cloud_functions_reference.md`
- `docs/INDEX_TS_REFACTORING_PLAN.md`

