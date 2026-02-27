# CLOSED TEST BUGS

This document tracks bugs found during closed testing.

**Test Period**: 2026-02
**Last Updated**: 2026-02-27

---

## Open

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

### CT-007: Unify copyright text to "ほめっぷ"

**Report Date**: 2026-02-26
**Priority**: Medium
**Screen**: Global (all screens / footer / legal text)

**Issue**:
All copyright notations should be switched to "ほめっぷ".

**Tasks**:
- [ ] Locate all copyright strings in app and related docs
- [ ] Replace notation with "ほめっぷ"
- [ ] Verify no old notation remains

### CT-008: 投稿の文字数上限を引き下げる

**Report Date**: 2026-02-27
**Priority**: High
**Screen**: Create Post

**Issue**:
現在の投稿文字数上限（500文字）では、上限いっぱいで投稿された場合にタイムラインが非常に見にくくなる。文字数上限を **200文字** に引き下げる。

**200文字とする理由**:
- TLの一覧性を確保し、スクロール負担を軽減する
- 「ほめる」アプリの特性上、気持ちを端的に伝える文化を促進する
- 日本語200文字は十分な表現力があり、SNS投稿として自然な長さである

**Tasks**:
- [ ] クライアント側のバリデーション（文字数カウント・制限）を500→200に更新
- [ ] サーバー側のバリデーションを500→200に更新
- [ ] ユーザー向けの表示テキスト（カウンター等）を更新

---

## In Progress

- None

---

## Resolved

### CT-001: Tutorial gets stuck on like button in post detail

**Report Date**: 2026-02-20
**Resolved Date**: 2026-02-27
**Priority**: Critical
**Screen**: Post Detail / Tutorial

**Issue**:
When post content is long or media is attached, the target like button can be outside the viewport. Tutorial step cannot proceed.

**Resolution**:
- [x] Ensure target widget is visible before spotlight step starts
- [x] Auto-scroll to target when needed
- [x] Add fallback if target cannot be reached

**Fix**: Eager build化 + `Scrollable.ensureVisible`による自動スクロール。フォールバック時はスクロール禁止解除で手動操作可能。

**Related Files**:
- `lib/features/post/presentation/screens/post_detail_screen.dart`
- `docs/design_ct001_tutorial_autoscroll.md`

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
