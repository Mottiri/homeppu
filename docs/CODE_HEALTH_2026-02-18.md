# CODE_HEALTH_2026-02-18

## What changed
- Functions ESLint scope narrowed to `src/**/*.ts` so operational JS scripts are excluded from TS lint.
- Re-enabled unused symbol detection via `@typescript-eslint/no-unused-vars`.
- Cleaned unused symbols found in review:
  - `functions/src/ai/prompts/comment.ts`
  - `functions/src/ai/prompts/post-generation.ts`
  - `functions/src/http/ai-generation.ts`
  - `functions/src/callable/admin.ts`
  - `functions/src/callable/ai.ts`
  - `functions/src/callable/users.ts`
  - `functions/src/callable/virtue_shop.ts`
  - `functions/src/triggers/posts.ts`
- Removed dead/commented constant from `lib/shared/widgets/avatar_parts_widget.dart`.
- Switched router diagnostics to debug-only in `lib/core/router/app_router.dart`.

## Intentional behavior
- `functions/src/scheduled/ai-posts.ts` remains temporarily disabled by product/ops decision (cost control).
