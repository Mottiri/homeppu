# CLOSED TEST BUGS

This document tracks bugs found during closed testing.

**Test Period**: 2026-02
**Last Updated**: 2026-02-27
**Note**: CT numbers are permanent identifiers. Closed items retain their original CT number.

---

## Open

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

### CT-009: プロフィール編集画面のアイコン設定時の文言修正

**Report Date**: 2026-02-27
**Priority**: Low
**Screen**: Profile Edit / Icon Setting

**Issue**:
アイコン設定時に「アバターを選んでね」と表示されているが、ユーザーが選ぶのはアイコンであるため「アイコンを選んでね」に修正する。

**Tasks**:
- [ ] 該当の文言箇所を特定する
- [ ] 「アバターを選んでね」→「アイコンを選んでね」に変更

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

### CT-002: Long post card occupies screen and hides comments

**Report Date**: 2026-02-20
**Resolved Date**: 2026-02-27
**Priority**: High
**Screen**: Post Detail

**Issue**:
Long post content expands card too much and comment area is not reachable as expected.

**Resolution**:
実機再確認の結果、スクロール自体は正常に動作していた。以前の報告時はCT-001のチュートリアル制御（NeverScrollableScrollPhysics）の影響でスクロール不可だった可能性が高い。CT-001修正後は長文投稿カードが画面を占有していてもスクロールでコメントに到達可能。文字数上限の引き下げ（CT-008）で投稿カードの占有問題自体も軽減される見込み。

### CT-003: Spreadsheet ID validation/update issue

**Report Date**: 2026-02-21
**Resolved Date**: 2026-02-27
**Priority**: High
**Category**: Settings / Environment

**Issue**:
Spreadsheet ID check/update behavior is unstable.

**Resolution**:
- [x] スプレッドシートIDをFirestore Config化（`settings/spreadsheet.inquirySpreadsheetId`）
- [x] Firestore未設定時は `constants.ts` のフォールバック値を使用
- [x] 運用時はFirebaseコンソールからデプロイ不要で切替可能

**Fix**: `getSpreadsheetId()` 関数を追加し、Firestore `settings/spreadsheet` ドキュメントからIDを動的に取得。フォールバック付きで安全に移行可能。

**Related Files**:
- `functions/src/helpers/spreadsheet.ts`
- `docs/design_ct003_spreadsheet_config.md`

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
