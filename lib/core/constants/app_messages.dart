/// アプリ内メッセージ定義
///
/// 「ほめっぷ」のフレンドリーなトーンを全画面で統一するためのメッセージ集。
///
/// 使用例:
/// ```dart
/// SnackBarHelper.showSuccess(context, AppMessages.success.postCreated);
/// SnackBarHelper.showError(context, AppMessages.error.general);
/// ```
class AppMessages {
  AppMessages._();

  // ===== 成功メッセージ =====
  static const success = _SuccessMessages();

  // ===== エラーメッセージ =====
  static const error = _ErrorMessages();

  // ===== 確認ダイアログ =====
  static const confirm = _ConfirmMessages();

  // ===== ボタン・ラベル =====
  static const label = _LabelMessages();

  // ===== 空状態 =====
  static const empty = _EmptyMessages();

  // ===== ローディング =====
  static const loading = _LoadingMessages();

  // ===== サークル関連 =====
  static const circle = _CircleMessages();

  // ===== ホーム関連 =====
  static const home = _HomeMessages();

  // ===== 目標関連 =====
  static const goal = _GoalMessages();

  // ===== オンボーディング関連 =====
  static const onboarding = _OnboardingMessages();

  // ===== 認証関連 =====
  static const auth = _AuthMessages();

  // ===== 通知関連 =====
  static const notification = _NotificationMessages();

  // ===== カレンダー関連 =====
  static const calendar = _CalendarMessages();

  // ===== 問い合わせ関連 =====
  static const inquiry = _InquiryMessages();

  // ===== プロフィール関連 =====
  static const profile = _ProfileMessages();
}

/// 成功メッセージ
class _SuccessMessages {
  const _SuccessMessages();

  // 投稿関連
  String get postCreated => '投稿できたよ！みんなに届くのを待っててね✨';
  String get postDeleted => '投稿を削除したよ！';
  String get commentCreated => 'コメントを送ったよ！';

  // サークル関連
  String get circleCreated => 'サークルを作成したよ！🎉';
  String get circleJoined => 'サークルに参加したよ！';
  String get circleLeft => 'サークルを退会したよ';
  String get circleDeleted => 'サークルを削除しました';
  String get circleUpdated => 'サークルを更新しました';

  // タスク関連
  String get taskCreated => 'タスクを追加したよ！';
  String get taskCompleted => 'タスク完了！お疲れさま✨';
  String get taskDeleted => 'タスクを削除したよ';
  String taskDeletedCount(int count) => '$count件を削除しました';
  String get categoryDeleted => 'カテゴリを削除しました';
  String get taskCompletionReverted => '完了を取り消しました';
  String get taskCompletionRevertedWithPostDeleted =>
      '完了を取り消しました。自動投稿を削除しました';
  String taskCompletedWithVirtue(int streak) => '🎉 タスク完了！ (+徳ポイント)';
  String taskMilestone(int streak, String message) =>
      '🎉 $streak日連続達成！$message！';

  // 目標関連
  String get goalCreated => '目標を作成しました！頑張りましょう✨';
  String get goalUpdated => '目標を更新しました！';

  // ユーザー関連
  String get profileUpdated => 'プロフィールを更新したよ！';
  String get nameChanged => '名前を変更したよ！';
  String get followed => 'フォローしたよ！';
  String get unfollowed => 'フォロー解除したよ';

  // 通報関連
  String get reportSent => '通報を受け付けたよ。確認するね';

  // 問い合わせ関連
  String get inquirySent => '問い合わせを送信したよ！';
  String get replySent => '返信を送ったよ！';

  // 汎用
  String get saved => '保存しました';
  String get copied => 'コピーしました';
}

/// エラーメッセージ
class _ErrorMessages {
  const _ErrorMessages();

  // 汎用
  String get general => 'ごめんね、うまくいかなかったみたい\n😢 もう一度試してみてね';
  String get network => 'ネットワークの調子が悪いみたい🌐\n接続を確認してね';
  String get unauthorized => 'ログインが必要だよ';
  String get permissionDenied => 'この操作はできないみたい';
  String get banned => 'アカウントが制限されているため、この操作はできません';

  // 投稿関連
  String get postFailed => '投稿できなかったみたい。もう一度試してみてね';
  String get deleteFailed => '削除できなかったみたい';
  String get moderationBlocked => 'この内容は投稿できないみたい😢';
  String get postDeletedNotice => 'この投稿は削除されました';

  // バリデーション
  String get emptyContent => '内容を入力してね';
  String get tooLong => '文字数オーバーだよ';

  // フォロー関連
  String get followFailed => 'フォローに失敗しました';
  String get unfollowFailed => 'フォロー解除に失敗しました';

  // 動的エラー（引数付き）
  String withDetail(String detail) => 'エラーが発生しました: $detail';
  String loadFailed(String target) => '$targetの読み込みに失敗しました';
  String updateFailed(String target) => '$targetの更新に失敗しました';
  String deleteFailed2(String target) => '$targetの削除に失敗しました';
}

/// 確認ダイアログメッセージ
class _ConfirmMessages {
  const _ConfirmMessages();

  // 削除確認
  String deletePost() => 'この投稿を削除する？\nこの操作は取り消せないよ';
  String deleteTask() => 'このタスクを削除する？';
  String deleteCircle(String name) => '「$name」を削除する？\nメンバー全員がアクセスできなくなるよ';
  String deleteComment() => 'このコメントを削除する？';
  String deleteCategory() => 'このカテゴリを削除する？';

  // 退会・解除
  String leaveCircle() => '本当にこのサークルを退会する？';
  String unfollow(String name) => '$name さんのフォローを解除する？';

  // ログアウト
  String get logout => '本当にログアウトする？\nまた会えるのを楽しみにしてるね💫';

  // アカウント削除
  String get deleteAccount => '本当にアカウントを削除する？\nすべてのデータが消えちゃうよ😢';
}

/// ボタン・ラベルメッセージ
class _LabelMessages {
  const _LabelMessages();

  // ボタン
  String get ok => 'OK';
  String get cancel => 'キャンセル';
  String get confirm => '確認';
  String get delete => '削除';
  String get save => '保存';
  String get send => '送信';
  String get close => '閉じる';
  String get retry => '再試行';
  String get yes => 'はい';
  String get no => 'いいえ';
  String get done => '完了';
  String get edit => '編集';
  String get create => '作成';
}

/// ローディングメッセージ
class _LoadingMessages {
  const _LoadingMessages();

  String get general => 'ちょっと待っててね...';
  String get sending => '送信中...';
  String get saving => '保存中...';
  String get deleting => '削除中...';
  String get uploading => 'アップロード中...';
}

/// 空状態メッセージ
class _EmptyMessages {
  const _EmptyMessages();

  String get posts => 'まだ投稿がないよ\n最初の投稿をしてみよう！';
  String get comments => 'まだコメントがないよ';
  String get notifications => '通知はまだないよ';
  String get tasks => 'タスクがないよ\n新しいタスクを追加してみよう！';
  String get circles => 'サークルがないよ\n新しいサークルを探してみよう！';
  String get followers => 'まだフォロワーがいないよ';
  String get following => 'まだ誰もフォローしていないよ';
  String get goals => '目標がないよ\n新しい目標を設定してみよう！';
}

/// サークル関連メッセージ
class _CircleMessages {
  const _CircleMessages();

  String get joinRequestTitle => '参加申請';
  String get joinRequestMessage =>
      'このサークルは招待制です。\nオーナーに参加申請を送信しますか？';
  String get joinRequestConfirm => '申請する';
  String get joinRequestSent => '参加申請を送信しました';
  String get joinRequestsTitle => '参加申請';
  String get joinRequestsEmpty => '参加申請はありません';
  String get joinApproveSuccess => '参加を承認しました';
  String get joinRejectTitle => '申請を拒否';
  String get joinRejectConfirm => '拒否';
  String get joinRejectSuccess => '申請を拒否しました';
  String joinRejectMessage(String name) => '$nameさんの申請を拒否しますか？';
  String get loadingDisplayName => '読み込み中...';
  String get tooltipReject => '拒否';
  String get tooltipApprove => '承認';

  String get leaveTitle => 'サークルを退会';
  String get leaveMessage => '本当にこのサークルを退会しますか？';
  String get leaveConfirm => '退会する';

  String get deleteTitle => 'サークルを削除';
  String deletePrompt(String name) => '「$name」を削除しますか？';
  String get deleteDetails =>
      '• 全ての投稿・コメントが削除されます\n• メンバーに通知が送信されます\n• この操作は取り消せません';
  String get deleteReasonLabel => '削除理由（任意）';
  String get deleteReasonHint => 'メンバーに伝えたいことがあれば';
  String get deleteConfirm => '削除する';
  String get deleteInProgress => 'サークルを削除中...';

  String get rulesTitle => 'サークルルール';
  String get rulesConsentMessage => '参加するにはルールに同意する必要があります';
  String get rulesAgree => '同意して参加';

  String get pinnedPostsTitle => 'ピン留め投稿';
  String get pinnedTopLabel => 'トップ表示';
  String get pinnedTopAction => 'トップに表示';
  String get pinnedRemove => 'ピン留め解除';
  String get pinnedSectionTitle => 'ピン留め';
  String pinnedCount(int count) => '$count件';

  String get postsTitle => 'みんなの投稿';
  String get circleDeleted => 'このサークルは削除されました';
  String get loginToJoin => 'ログインして参加';
  String get memberCountSuffix => '人';
  String get ruleLabel => 'ルール';
  String get joinButton => '参加する';
  String get joinRequestButton => '参加申請';
  String get joinedLabel => '参加中';
  String get requestPendingLabel => '申請中';

  // サークル一覧画面
  String get listTitle => 'サークル';
  String get searchHint => 'サークルを検索';
  String get tabAll => 'みんなの';
  String get tabJoined => '参加中';
  String get searchNotFound => '見つかりませんでした';
  String get searchError => '検索中にエラーが発生しました';
  String get listError => 'エラーが発生しました';
  String get emptyTitle => 'まだサークルがないよ';
  String get emptyDescription => '最初のサークルを作ってみよう！';
  String get createCircle => 'サークルを作る';
  String get emptyJoined => '参加中のサークルがありません';
  String get emptyGeneric => 'サークルがありません';
  String get filterLabel => 'フィルター';
  String filterWithCount(int count) => 'フィルター($count)';
  String memberCountLabel(int count) => '$count人';
  String postCountLabel(int count) => '$count件';
  String get aiModeLabel => 'AIモード';
  String get inviteOnlyLabel => '招待制';
  String get noPostsYet => 'まだ投稿なし';
  String postedAt(String time) => '$timeに投稿あり';
  String get humanPostsNone => '人間投稿なし';
  String humanPostAt(String time) => '人間: $time';
  String get sortNewest => '新着順';
  String get sortActive => 'アクティブ順';
  String get sortPopular => '人気順';
  String get sortPostCount => '投稿数順';
  String get sortHumanPostOldest => '人間投稿古い順';
  String get filterHasSpace => '空きあり';
  String get filterHasPosts => '投稿あり';
}

/// ホーム関連メッセージ
class _HomeMessages {
  const _HomeMessages();

  String get tabRecommended => 'おすすめ';
  String get tabFollowing => 'フォロー中';
  String get timelineLoading => 'みんなの投稿を読み込み中...';
  String get emptyPostsTitle => 'まだ投稿がないよ';
  String get emptyPostsDescription => '最初の投稿をしてみよう！';
  String get emptyFollowingTitle => 'まだ誰もフォローしていないよ';
  String get emptyFollowingDescription =>
      '「おすすめ」タブで気になる人を\n見つけてフォローしてみよう！';
}

/// 目標関連メッセージ
class _GoalMessages {
  const _GoalMessages();

  String get title => '目標';
  String get streamError => 'エラーが発生しました';
  String get inProgressTitle => '進行中の目標';
  String get reorderDone => '完了';
  String get reorderLabel => '並替';
  String get headerTitle => '目標を達成しよう！';
  String get headerDescription => '小さな積み重ねが大きな成果に✨';
  String get hallOfFameTitle => '殿堂入り';
  String get hallOfFameSubtitle => '達成した目標を見る';
  String get newGoal => '新しい目標';
  String get notFound => '目標が見つかりません';
  String get completeButton => '目標を達成する！';
  String get revertButton => '未完了に戻す（再開）';
  String get accumulationTitle => 'これまでの積み上げ';
  String get tabIncomplete => '未完了';
  String get tabComplete => '完了';
  String get emptyTasksTitle => 'まだタスクがありません';
  String get emptyTasksDescription => 'タスクを作成して目標に紐づけよう';
  String get taskAddPrompt => 'タスクを追加してください';
  String get deleteGoalTitle => '目標を削除';
  String get deleteGoalMessage =>
      '紐づいているすべてのタスクも削除されます。\nこの操作は取り消せません。';
  String get congratsTitle => 'おめでとう！🎉';
  String get hallOfFamePrompt => '目標を「殿堂入り」にしますか？';
  String get deleteFutureTasksNote => '未来のタスクがあれば削除されます';
  String get hallOfFameConfirm => '殿堂入りへ';
  String get completeSuccess => 'おめでとう！目標を達成しました！🎊';
  String get resumed => '目標を再開しました';
  String get deadlineToday => '今日まで！';
  String deadlineRemainingDays(int days) => 'あと$days日';
  String deadlineOverdueDays(int days) => '$days日超過';
  String get unitMinutes => '分';
  String get unitHours => '時間';
  String get unitDays => '日';
  String get dateToday => '今日';
  String get dateTomorrow => '明日';
  String get dateYesterday => '昨日';
  String daysLater(int days) => '$days日後';

  String get completedTitle => '殿堂入り';
  String get completedEmptyTitle => 'まだ達成した目標はありません';
  String get completedEmptyDescription => '目標を達成すると、ここに表示されます';
}

/// オンボーディング関連メッセージ
class _OnboardingMessages {
  const _OnboardingMessages();

  String get skip => 'スキップ';
  String get next => '次へ';
  String get start => 'はじめる';
  String get alreadyHaveAccount => 'すでにアカウントをお持ちの方';

  String get page1Title => 'ようこそ、ほめっぷへ';
  String get page1Description =>
      '世界一優しいSNSへようこそ！\nここでは誰もがあなたを応援してくれるよ';
  String get page2Title => 'たくさん褒められよう';
  String get page2Description =>
      '日常の小さなことを投稿するだけで\nAIや仲間から温かい言葉が届くよ';
  String get page3Title => 'ポジティブな空間';
  String get page3Description =>
      'ネガティブな言葉は一切なし\n安心して自分を表現してね';
}

/// 通知関連メッセージ
class _NotificationMessages {
  const _NotificationMessages();

  String get title => '通知';
  String get markAllRead => '全て既読にする';
  String get empty => 'まだ通知はありません';
  String get tabTimeline => 'TL';
  String get tabTask => 'タスク';
  String get tabCircle => 'サークル';
  String get tabSupport => 'サポート';
  String minutesAgo(int minutes) => '$minutes分前';
  String hoursAgo(int hours) => '$hours時間前';
}

/// カレンダー関連メッセージ
class _CalendarMessages {
  const _CalendarMessages();

  String get title => 'カレンダー';
  List<String> get weekdayLabels => const ['月', '火', '水', '木', '金', '土', '日'];
}

/// 問い合わせ関連メッセージ
class _InquiryMessages {
  const _InquiryMessages();

  String get listTitle => '問い合わせ・要望';
  String get emptyTitle => 'まだ問い合わせがありません';
  String get emptyDescription => 'お困りごとや要望があれば\nお気軽にお送りください！';
  String get newInquiry => '新規問い合わせ';
  String get formTitle => '新規問い合わせ';
  String get detailTitle => '問い合わせ詳細';
  String get send => '送信';
  String get categoryLabel => 'カテゴリ';
  String get subjectLabel => '件名';
  String get subjectHint => '問い合わせの件名を入力';
  String get subjectRequired => '件名を入力してください';
  String get contentLabel => '内容';
  String get contentHint => 'お問い合わせ内容を詳しく記入してください';
  String get contentRequired => '内容を入力してください';
  String get screenshotOptional => 'スクリーンショット（任意）';
  String get screenshotHelp =>
      'バグ報告の場合は画面のスクリーンショットを添付すると解決が早くなります';
  String get attachImage => '画像を添付';
  String get messageHint => 'メッセージを入力...';
  String get imageOnlyMessage => '（画像を添付しました）';
}

/// 認証関連メッセージ
class _AuthMessages {
  const _AuthMessages();

  // ログイン
  String get loginUserNotFound => 'このメールアドレスは登録されていないみたい🔍';
  String get loginWrongPassword => 'パスワードが違うみたい🔐';
  String get loginInvalidEmail => 'メールアドレスの形式を確認してね📧';
  String get loginTooManyRequests => 'ちょっと休憩してからまた試してね⏰';

  // 登録
  String get registerEmailAlreadyInUse => 'このメールアドレスはすでに使われているみたい📧';
  String get registerWeakPassword => 'もう少し強いパスワードにしてね🔐';
  String get registerInvalidEmail => 'メールアドレスの形式を確認してね📧';
}

/// プロフィール関連メッセージ
class _ProfileMessages {
  const _ProfileMessages();

  // 設定画面
  String get settingsTitle => '設定';
  String get profileEditTitle => 'プロフィール編集';
  String get headerImageLabel => 'ヘッダー画像';
  String get defaultHeaderLabel => 'デフォルト画像';
  String get processing => '処理中...';
  String get changeImage => '画像を変更';
  String get selectFromDefault => 'またはデフォルトから選択';
  String get nameLabel => 'なまえ';
  String get tapToSetName => 'タップして名前を設定';
  String get tapToChangeName => 'タップして名前を変更';
  String get bioLabel => '自己紹介';
  String get bioHint => '自己紹介を入力（任意）';
  String get notificationSettingsTitle => '通知設定';
  String get allOff => 'すべてオフ';
  String get customizing => 'カスタマイズ中';
  String get commentNotificationTitle => 'コメント通知';
  String get commentNotificationSubtitle => '投稿へのコメントを通知します';
  String get reactionNotificationTitle => 'リアクション通知';
  String get reactionNotificationSubtitle => '投稿へのリアクションを通知します';
  String get autoPostSettingsTitle => '自動投稿設定';
  String get milestonesTitle => 'ストリーク達成時';
  String get milestonesSubtitle => '連続達成（マイルストーン）した時に自動で投稿します';
  String get goalAutoPostTitle => '目標達成時';
  String get goalAutoPostSubtitle => '目標を達成した時に自動で投稿します';
  String get privacyTitle => '公開範囲';
  String privacyCurrent(String label) => '現在: $label';
  String get privacyInfo =>
      '次回以降の投稿から適用されます\n過去の投稿は変わりません';
  String privacyChangeTitle(String label) => '$labelに変更';
  String privacyChangeMessage(String label) =>
      '公開範囲を「$label」に変更しますか？\n\n次回以降の投稿から適用されます。';
  String get privacyChangeConfirm => '変更する';
  String privacyChanged(String label) => '公開範囲を「$label」に変更しました';
  String get inquiryTitle => '問い合わせ・要望';
  String get inquirySubtitle => 'バグ報告や機能要望を送信';
  String get aboutTitle => 'アプリについて';
  String get helpTitle => 'ヘルプ';
  String get termsTitle => '利用規約';
  String get privacyPolicyTitle => 'プライバシーポリシー';
  String get logoutTitle => 'ログアウト';
  String get headerResetTitle => 'ヘッダー画像をリセット';
  String get headerResetMessage => 'ヘッダー画像をデフォルトに戻しますか？';
  String get headerResetConfirm => 'リセット';
  String get headerChangeSuccess => 'ヘッダー画像を変更しました！';
  String get headerChangeFailed => 'ヘッダー画像の変更に失敗しました';
  String get headerResetSuccess => 'ヘッダー画像をリセットしました';
  String get headerResetFailed => 'リセットに失敗しました';
  String get changeFailed => '変更に失敗しました';
  String get savedFriendly => '保存できたよ！';

  String get nameEditTitle => '名前を変更';
  String get previewLabel => 'プレビュー';
  String get prefixTab => '前半（形容詞）';
  String get suffixTab => '後半（名詞）';
  String get selectParts => 'パーツを選択してください';
  String get namePartsLoadFailed => 'パーツの読み込みに失敗しました';
  String get nameUpdateFailed => '名前の変更に失敗しました';
  String get namePartPlaceholder => '???';
  String lockedPartMessage(String partText, String rarity) =>
      '「$partText」は$rarityパーツです。徳ポイントショップでアンロックできます。';
}
