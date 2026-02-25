# CLOSED TEST BUGS

This document tracks bugs found during closed testing.

**Test Period**: 2026-02
**Last Updated**: 2026-02-25

---

## Open

### CT-001: Tutorial gets stuck on like button in post detail

**Report Date**: 2026-02-20
**Priority**: Critical
**Screen**: Post Detail / Tutorial

**Issue**:
When post content is long or media is attached, the target like button can be outside the viewport. Tutorial step cannot proceed.

**Tasks**:
- [ ] Ensure target widget is visible before spotlight step starts
- [ ] Auto-scroll to target when needed
- [ ] Add fallback if target cannot be reached

**Related Files**:
- `lib/shared/widgets/tutorial_overlay.dart`

### CT-002: Long post card occupies screen and hides comments

**Report Date**: 2026-02-20
**Priority**: High
**Screen**: Post Detail

**Issue**:
Long post content expands card too much and comment area is not reachable as expected.

**Tasks**:
- [ ] Add max height handling and internal scroll behavior
- [ ] Consider collapsed/expanded post content behavior

### CT-003: Spreadsheet ID validation/update issue

**Report Date**: 2026-02-21
**Priority**: High
**Category**: Settings / Environment

**Issue**:
Spreadsheet ID check/update behavior is unstable.

**Tasks**:
- [ ] Verify current Spreadsheet ID
- [ ] Update to correct Spreadsheet ID

### CT-004: Tutorial spotlight position offset

**Report Date**: 2026-02-21
**Priority**: Medium
**Screen**: Tutorial

**Issue**:
Spotlight position does not align with target widget in some steps.

**Tasks**:
- [ ] Review spotlight rect calculation for each step
- [ ] Fix key timing and offset calculation

**Related Files**:
- `lib/shared/widgets/tutorial_overlay.dart`

### CT-005: Simplify NG moderation dialog actions

**Report Date**: 2026-02-24
**Priority**: Medium
**Screen**: Create Post / moderation NG dialog

**Issue**:
Two action buttons currently do the same thing (close dialog).

**Tasks**:
- [ ] Replace with one `OK` action
- [ ] Verify related help/tutorial text if needed

### CT-006: Remove video attachments from posts

**Report Date**: 2026-02-24
**Priority**: High
**Screen**: Create Post / media attachments

**Issue**:
Video attachment should be removed for cost and moderation stability.

**Tasks**:
- [ ] Hide video picker UI on create post screen
- [ ] Disable video upload path
- [ ] Stop server-side video moderation/analysis path for posts
- [ ] Update related docs and user-facing copy

---

## In Progress

- None

---

## Resolved

- None

---

## Template

```markdown
### CT-XXX: [Title]

**Report Date**: YYYY-MM-DD
**Priority**: Critical / High / Medium / Low
**Screen**: [Screen Name]

**Issue**:
[Describe issue]

**Tasks**:
- [ ] [Task]

**Related Files**:
- [path]
```
