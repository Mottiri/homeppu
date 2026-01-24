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

  // タスク関連
  String get taskCreated => 'タスクを追加したよ！';
  String get taskCompleted => 'タスク完了！お疲れさま✨';
  String get taskDeleted => 'タスクを削除したよ';
  String taskCompletedWithVirtue(int streak) => '🎉 タスク完了！ (+徳ポイント)';
  String taskMilestone(int streak, String message) =>
      '🎉 $streak日連続達成！$message！';

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
  String get general => 'ごめんね、うまくいかなかったみたい😢\nもう一度試してみてね';
  String get network => 'ネットワークの調子が悪いみたい🌐\n接続を確認してね';
  String get unauthorized => 'ログインが必要だよ';
  String get permissionDenied => 'この操作はできないみたい';
  String get banned => 'アカウントが制限されているため、この操作はできません';

  // 投稿関連
  String get postFailed => '投稿できなかったみたい。もう一度試してみてね';
  String get deleteFailed => '削除できなかったみたい';
  String get moderationBlocked => 'この内容は投稿できないみたい😢';

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
}
