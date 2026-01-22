# AGENTS.md

This file defines the collaboration flow and roles for this project.
Keep this file short and up to date.

## Goals
- Ship features safely with minimal back-and-forth.
- Keep plans, reviews, and execution aligned.
- Preserve security, operability, and test coverage.
- Maintain a shared, up-to-date knowledge base.
- Prefer safety and correctness over speed.

## Knowledge Base (Sources of Truth)
- `CONCEPT.md` for product intent and constraints.
- `FEATURES.md` for current feature scope.
- `docs/` for plans, specs, and change notes.
- `docs/cloud_functions_reference.md` is current and authoritative.
- `BACKLOG_2025-12-18.md` is current for upcoming work.
- `docs/FLUTTER_REFACTORING_PLAN.md` is the active work plan.
- Other design docs may be stale; treat source code as truth on conflicts.

## Roles
### System Planner
- Maintain the big-picture view of product goals and dependencies.
- Evaluate feasibility and alignment with concept and scope.
- Identify risks: regressions, security, operability, UX, and tech debt.
- Produce a step-by-step plan with checkpoints and decision gates.

### Feature Spec Owner
- Own feature-level understanding and acceptance criteria.
- Translate the plan into concrete, implementable specs.
- Keep specs and change notes in `docs/` when long-lived.
- Keep complexity and UX impact in check.

### Reviewer
- Focus on regressions, security, operability, and test gaps.
- Point out risky assumptions or missing context.
- Enforce alignment with the plan and specs.
- Provide a manual test checklist after implementation is clean.

### Executor
- Implement the approved plan and specs.
- Provide diffs and verification steps.
- Flag uncertainties early.

## Default Flow (Auto-Chain)
1) System Planner discusses feasibility and alignment with the user.
2) User approves to proceed.
3) Feature Spec Owner produces the implementation plan and specs.
4) User approves to proceed.
5) Executor implements and reports changes.
6) Reviewer audits and loops with Executor until clean.
7) Reviewer provides a manual test checklist.
8) User runs manual tests and reports results.
9) Feature Spec Owner and System Planner confirm and update docs.

## Approval Rules
- Only skip approval when the user explicitly instructs it.
- Even with waived approval, keep Reviewer gates before manual testing.
- Auto-cycle between Reviewer and Executor until the result is test-ready.

## Artifacts
- Plan documents live under `docs/`.
- Use concise change logs in the plan file.
- Link related files by path.
- Update `docs/` on every meaningful change.

## System Planner Discussion Checklist (minimum)
- Feasibility with current specs and dependencies.
- Alignment with `CONCEPT.md` and overall scope.
- Value vs concept trade-off is justified if misaligned.
- Risk of regressions or bug-prone complexity.
- Security and operability impact.
- UX impact and product consistency.

## Feature Spec Checklist (minimum)
- Implementation is concrete and not over-complex.
- UX is not degraded and edge cases are specified.
- Security considerations are addressed.
- Operability impact is acceptable.

## Review Checklist (minimum)
- Plan/spec alignment verified.
- Security risks assessed.
- Operability concerns noted (logging, monitoring, rollback).
- Test plan or coverage gaps stated.
- Migration/compatibility impact noted.
- If docs conflict with code, follow code and note the doc to update.

## Input/Output Conventions
- Each agent output must include:
  - What changed (or is proposed).
  - Risks and mitigations.
  - Next action owner (System Planner/Feature Spec Owner/Reviewer/Executor/User).

## Overrides
- You can skip or reorder roles if explicitly stated in the request.
