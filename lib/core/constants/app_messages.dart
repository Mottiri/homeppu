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

  // ===== オンボーディング関連 =====
  static const onboarding = _OnboardingMessages();

  // ===== チュートリアル関連 =====
  static const tutorial = _TutorialMessages();

  // ===== 認証関連 =====
  static const auth = _AuthMessages();

  // ===== 管理者関連 =====
  static const admin = _AdminMessages();

  // ===== 通知関連 =====
  static const notification = _NotificationMessages();

  // ===== カレンダー関連 =====
  static const calendar = _CalendarMessages();

  // ===== 問い合わせ関連 =====
  static const inquiry = _InquiryMessages();

  // ===== プロフィール関連 =====
  static const profile = _ProfileMessages();

  // ===== スタンプシート関連 =====
  static const stamp = _StampMessages();

  // ===== 徳ポイント関連 =====
  static const virtue = _VirtueMessages();

  // ===== キャンペーン関連 =====
  static String campaignEndDate(int month, int day) => '〜$month/$dayまで';

  // ===== サーバーエラー reason 定数 =====
  static const String reasonItemNotPurchasable = 'ITEM_NOT_PURCHASABLE';
}

/// 成功メッセージ
class _SuccessMessages {
  const _SuccessMessages();

  // 投稿関連
  String get postCreated => '投稿できたよ！みんなに届くのを待っててね✨';
  String get postDeleted => '投稿を削除したよ！';
  String get commentCreated => 'コメントを送ったよ！';
  String get commentDeleted => 'コメントを削除したよ';
  String get favoriteAdded => 'お気に入りに追加しました';
  String get favoriteRemoved => 'お気に入りから削除しました';

  // サークル関連
  String get circleCreated => 'サークルを作成したよ！🎉';
  String get circleJoined => 'サークルに参加したよ！';
  String get circleLeft => 'サークルを退会したよ';
  String get circleDeleted => 'サークルを削除しました';
  String get circleUpdated => 'サークルを更新しました';

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
  String get purchaseCompleted => '購入しました';
  String rewardedUnlockGranted(int count, int hours) =>
      '広告視聴で$hours時間、$count回分を解放しました';
  String get copied => 'コピーしました';
}

/// エラーメッセージ
class _ErrorMessages {
  const _ErrorMessages();

  // 汎用
  String get general => 'ごめんね、うまくいかなかったみたい\n😢 もう一度試してみてね';
  String get network => 'ネットワークの調子が悪いみたい🌐\n接続を確認してね';
  String get unauthorized => 'ログインが必要だよ';
  String get loginRequired => 'ログインが必要です';
  String get permissionDenied => 'この操作はできないみたい';
  String get banned => 'アカウントが制限されているため、この操作はできません';
  String get accountSuspended => 'アカウントが停止されています';
  String get deletedUserUnavailable => 'このユーザーは既に削除されています';
  String get notEnoughVirtue => '徳ポイントが足りません。';
  String get itemNotPurchasable => 'このアイテムは期間限定アイテムです。現在期限が過ぎているため購入できません。';
  String get notFoundTitle => 'あれ？ページが見つからないよ';
  String get notFoundDescription => '大丈夫、ホームに戻ろう！';
  String get purchaseFailedTitle => '購入に失敗しました';
  String get purchaseFailedSupport => '購入に失敗しました。お手数ですが運営にお問い合わせください。';
  String get purchasePendingTitle => '購入の反映に時間がかかっています';
  String get purchasePendingMessage => '購入は完了していますが、反映に時間がかかっています。\nしばらく待っても反映されない場合は「購入を復元する」をお試しください。';
  String get rewardedAdFailed => '広告の再生に失敗しました。';
  String get rewardedUnlockFailed => '一時解放に失敗しました。';
  String get epicReactionLocked => 'サブスクまたは一時解放が必要です。';

  // 投稿関連
  String get postFailed => '投稿できなかったみたい。もう一度試してみてね';
  String get deleteFailed => '削除できなかったみたい';
  String get commentDeleteFailed => 'コメントを削除できなかったみたい';
  String get moderationBlocked => 'この内容は投稿できないみたい😢';
  String get postDeletedNotice => 'この投稿は削除されました';
  String get reportFailed => '通報に失敗しました。もう一度お試しください。';
  String get reactionOwnPost => '自分の投稿にはリアクションできません';
  String get reactionLimitReached => 'この投稿へのリアクションは5回までです';

  // 動画再生
  String get videoPlaybackFailedTitle => '動画を再生できません';
  String get videoUnsupportedFormat =>
      'この動画形式はお使いの端末では再生できません。\n'
      '（HEVC/H.265形式）\n\n'
      '投稿者に別の形式で再投稿をお願いしてみてください。';
  String get videoNetworkError => 'ネットワーク接続を確認してください。';
  String get videoNotFound => '動画が見つかりませんでした。\n削除された可能性があります。';
  String get videoPlaybackFailed => '動画を再生できませんでした。\nしばらくしてから再試行してください。';

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
  String uploadFailed(String target) => '$targetのアップロードに失敗しました';
}

/// 確認ダイアログメッセージ
class _ConfirmMessages {
  const _ConfirmMessages();

  // 削除確認
  String deletePost() => 'この投稿を削除する？\nこの操作は取り消せないよ';
  String deleteCircle(String name) => '「$name」を削除する？\nメンバー全員がアクセスできなくなるよ';
  String deleteComment() => 'このコメントを削除する？';
  String get deleteTitle => '削除の確認';
  String deleteItem(String itemName, {String? additionalMessage}) =>
      additionalMessage != null
      ? '「$itemName」を削除しますか？\n$additionalMessage'
      : '「$itemName」を削除しますか？';

  // 退会・解除
  String leaveCircle() => '本当にこのサークルを退会する？';
  String unfollow(String name) => '$name さんのフォローを解除する？';

  // ログアウト
  String get logout => '本当にログアウトする？\nまた会えるのを楽しみにしてるね💫';

  // 徳ポイント・サブスク購入
  String get purchaseVirtueTitle => '徳ポイント購入';
  String purchaseVirtueMessage(int cost) => 'このアイテムを$cost徳ポイントで購入しますか？';
  String virtueCostLabel(int cost) => '$cost 徳ポイント';
  String virtueBalanceAfterPurchase(int currentVirtue, int cost) =>
      '保有: $currentVirtue → ${currentVirtue - cost}';
  String virtueBalanceShortage(int currentVirtue, int cost) =>
      '保有: $currentVirtue（あと${cost - currentVirtue}徳ポイント必要）';
  String get subscriptionOnlyTitle => 'サブスク限定';
  String subscriptionOnlyMessage() => 'このアイテムはサブスク課金限定のアイテムだよ！';
  String subscriptionOnlyMessageWithRewarded(int hours, int count) =>
      'このアイテムはプレミアム課金限定です。広告を見ると$hours時間限定で$count回までこのスタンプを使用できます。';
  String get rewardedUnlockTitle => '広告を見て解除';
  String rewardedUnlockSubtitle(int count, int hours) => '$count回 / $hours時間';
  String get premiumSubscribeTitle => 'プレミアム加入';
  String get premiumUnlockEpicSubtitle => '全Epicスタンプ無制限';

  // 投稿前インフォメーションダイアログ
  String get postAdNoticeTitle => '投稿前のお知らせ';
  String get postAdNoticeReview => '投稿内容を審査します';
  String get postAdNoticeMayShowAd => '広告が表示される場合があります';

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
  String get back => '戻る';
  String get backToHome => 'ホームへ戻る';
  String get yes => 'はい';
  String get no => 'いいえ';
  String get purchase => '購入する';
  String get restorePurchase => '購入を復元する';
  String get subscribe => '詳細';
  String get watchAd => '広告を見る';
  String get done => '完了';
  String get edit => '編集';
  String get create => '作成';
  String get report => '通報';
  String get logout => 'ログアウト';
  String get relogin => 'ログインし直す';
  String get add => '追加';
  String get dontShowAgain => '今後表示しない';
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
  String get circles => 'サークルがないよ\n新しいサークルを探してみよう！';
  String get followers => 'まだフォロワーがいないよ';
  String get following => 'まだ誰もフォローしていないよ';
  String get adminReviewEmpty => '審査待ちの投稿はありません';
}

/// サークル関連メッセージ
class _CircleMessages {
  const _CircleMessages();

  String get navLabel => 'サークル';
  String get joinRequestTitle => '参加申請';
  String get joinRequestMessage => 'このサークルは招待制です。\nオーナーに参加申請を送信しますか？';
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

  // メンバー管理
  String get subOwnerAssignTitle => '副オーナーを任命';
  String get subOwnerRemoveTitle => '副オーナーを解任';
  String subOwnerAssignConfirm(String name) => '$name さんを副オーナーに任命しますか？';
  String subOwnerAssignDescription(String name) =>
      '$name さんを副オーナーに任命しますか？\n\n副オーナーはピン留めや参加承認などの権限を持ちます。';
  String subOwnerRemoveConfirm(String name) => '$name さんの副オーナー権限を解除しますか？';
  String subOwnerAssigned(String name) => '$name さんを副オーナーに任命しました';
  String subOwnerRemoved(String name) => '$name さんの副オーナー権限を解除しました';
  String get subOwnerAssignFailed => '任命に失敗しました';
  String get subOwnerRemoveFailed => '解任に失敗しました';
  String get subOwnerAssignAction => '任命する';
  String get subOwnerRemoveAction => '解任する';

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
  String get circleFullLabel => '満員です';
  String get requestPendingLabel => '申請中';

  // サークル一覧画面
  String get listTitle => 'サークル';
  String get searchHint => 'サークルを検索';
  String get tabAll => 'みんなの';
  String get tabJoined => '参加中';
  String get searchNotFound => '見つかりませんでした';
  String get searchError => '検索中にエラーが発生しました';
  String get createLimitExceeded => 'サークルの作成上限（30個）に達しています';
  String get imageUploadFailedButCreated => 'サークルは作成されましたが、画像のアップロードに失敗しました。サークル設定から画像を再設定できます。';
  String get imageUploadFailedButUpdated => 'サークル情報は更新されましたが、画像のアップロードに失敗しました。再度お試しください。';
  String get searchJoinedTruncated => '参加中のサークルが多いため、一部のサークルが表示されていない可能性があります';
  String get listError => 'エラーが発生しました';
  String get emptyTitle => 'まだサークルがないよ';
  String get emptyDescription => '最初のサークルを作ってみよう！';
  String get createCircle => 'サークルを作る';
  String get emptyJoined => '参加中のサークルがありません';
  String get emptyGeneric => 'サークルがありません';
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
  String get loadMoreButton => 'もっと見る';
  String get circleFullError => 'このサークルは満員のため、参加できません';
  String get joinedLimitError => '参加できるサークル数の上限に達しています';
  String get trialBannerTitle => '初回サークル体験中';
  String get trialBannerDescription =>
      'この体験では閲覧のみ可能です（作成・参加はできません）。画面遷移またはアプリ終了で体験は終了し、再度閲覧できません。';
  String get trialChecking => 'サークル機能の利用可否を確認中...';
}

/// ホーム関連メッセージ
class _HomeMessages {
  const _HomeMessages();

  String get navLabel => 'ホーム';
  String get tabRecommended => 'おすすめ';
  String get tabFollowing => 'フォロー中';
  String get nativeAdLabel => '広告';
  String get nativeAdLoading => '広告を読み込み中...';
  String get timelineLoading => 'みんなの投稿を読み込み中...';
  String get emptyPostsTitle => 'まだ投稿がないよ';
  String get emptyPostsDescription => '最初の投稿をしてみよう！';
  String get emptyFollowingTitle => 'まだ誰もフォローしていないよ';
  String get emptyFollowingDescription => '「おすすめ」タブで気になる人を\n見つけてフォローしてみよう！';
}

/// オンボーディング関連メッセージ
class _OnboardingMessages {
  const _OnboardingMessages();

  String get skip => 'スキップ';
  String get next => '次へ';
  String get start => 'はじめる';
  String get alreadyHaveAccount => 'すでにアカウントをお持ちの方';

  String get page1Title => 'ようこそ、ほめっぷへ';
  String get page1Description => 'ほめっぷに来てくれてありがとう！\nほめっぷは世界一優しいSNSを目指しているよ！';
  String get page2Title => 'たくさん褒められよう';
  String get page2Description => 'ほめっぷではあなたの投稿に\nAIや仲間から温かい言葉が届くよ😊';
  String get page3Title => 'あなたの安心できる場所';
  String get page3Description => 'ほめっぷでは発言内容をAIが審査しているから\n安心して使ってね！';
}

class _TutorialMessages {
  const _TutorialMessages();

  // Step 0: ホーム画面
  String get welcomeHome =>
      '**ほめっぷへ来てくれてありがとう！**\nまずは公開範囲を設定しよう🌟\n下の「マイページ」をタップしてね';

  // Step 1: マイページ（設定アイコン）
  String get tapSettings => '次は右上の設定アイコン⚙️をタップしてね';

  // Step 2: 設定画面（公開範囲カードへスクロール）
  String get scrollToPrivacy => 'ここが「公開範囲」の設定だよ！\nまずはここをタップして開いてみてね';

  // Step 3: AIモード説明
  String get explainAI => 'AIだけが見れるモードだよ!\n人間には見えないから安心して投稿できる！\nAIからコメントやリアクションが届くよ😊';

  // Step 4: ミックスモード説明
  String get explainMix => 'AIも人間も両方見れるモードだよ！\nAIからもコメントやリアクションが届くよ💕';

  // Step 5: 人間モード説明
  String get explainHuman => '人間だけが見れるモードだよ！\n投稿に慣れたらこのモードに挑戦しよう！';

  // Step 6: 完了
  String get complete =>
      'これで公開範囲の説明はおしまい！\n画面操作出来るようになったら、希望のモードをタップしてね🎉\n**あとからいつでも設定は変えられるから安心してね！**\n\n※AIのコメントは自動生成のため、\n内容が不正確な場合もありますのでご了承ください。';
  String get completeAction => 'わかった！';
  String get selectModeRequired => 'モードを1つ選んでね';

  // Home explanation
  String get homeOverview => 'ここはホーム画面だよ！\nみんなの投稿がここに表示されるよ😊';
  String get homeLongPress => 'カード長押しでリアクションスタンプが押せるよ！かわいいスタンプをいっぱい押そう🎉';
  String get bottomNavHomeGuide => 'ここがホーム画面だよ！\n投稿だけでなく通知の確認もここからできるよ🔔';
  String get bottomNavCircleGuide =>
      'ここがサークル機能だよ！\n**この機能はサブスク限定だよ**\n1回だけ見れるけど、**他の画面に行っちゃうと体験は終了**して、[[danger:サークル画面を開けなくなっちゃうから注意してね！]]';
  String get bottomNavPostGuide => '真ん中のボタンから投稿を作成できるよ！\n今日の気持ちや出来事を投稿してみよう💕';
  String get bottomNavStampGuide => 'ここがスタンプ画面だよ！\n返信コメントでいいねをもらうとスタンプを押せるよ🎉';
  String get bottomNavMyPageGuide => 'ここがマイページだよ！\nプロフィール編集や設定はここからできるよ';

  // Circle tutorial (Phase 5)
  String get circleOverviewGuide =>
      'ここがサークル画面だよ！\n興味のあるサークルを探したり、参加中サークルを確認できるよ😊';
  String get circleFabGuide => '下の真ん中ボタンからサークルを作成できるよ！\n気の合う仲間のサークルを作ってみよう✨';

  // Profile tutorial (Phase 6)
  String get profileOverviewGuide => 'ここがマイページだよ！\n自分の活動や投稿をまとめて確認できるよ😊';
  String get profileVirtueGuide =>
      'ここが徳ポイントだよ！\nタップすると履歴も確認できるから、どんな行動で増減したか見てみよう✨\n徳ポイントはアイテムの購入などに使えるよ！🎉';
  String get profileFavoritesGuide =>
      'ここがお気に入りタブだよ！\n過去の投稿をお気に入り登録すると、登録した投稿をまとめて見返せるよ⭐';

  // Post detail explanation (Phase 2)
  String get postDetailOverview => 'ここは投稿詳細画面だよ！\nあなたの投稿についたコメントを確認できるよ😊';
  String get postDetailAiCommentNote =>
      'AIからのコメントもここに表示されるよ！\n\n※AIのコメントは自動生成のため、内容が不正確な場合があります。あたたかい気持ちでお楽しみください。';
  String get postDetailLongPressComment =>
      '他の人のコメントを長押しすると\n投稿主として「いいね！」を返せるよ❤\nいいコメントがあったらいいね！してあげてね😊';

  // Create post explanation (Phase 4)
  String get postCreateStep1 => '投稿したい内容の入力が終わったら\n「投稿する」ボタンから投稿できるよ！';
  String get postCreateStep2 =>
      '**投稿内容はシステムとAIの審査が入る**から、\n実際に[[danger:投稿されるまで少し時間がかかる]]ことがあるよ。ごめんね！';
  String get postCreateStep3 =>
      '**AI審査はたまに間違えちゃうこともあるよ！**\n問題ない内容でもブロックされる場合は、言い方を変えてみてね😊';

  // Stamp sheet explanation (Phase 3)
  String get stampOverview => 'ここはスタンプ画面だよ！\n返信コメントでいいね！をもらうと、ここでスタンプを押せるよ🎉';
  String get stampInitialSheetSelection =>
      '最初にスタンプシートを1つ選ぼう！\nシートはスタンプが埋まるまで変更できないよ。';
  String get stampInitialSheetSelectionGuide =>
      'まずはここをタップして最初のシートを選ぼう！\n[[danger:シートはスタンプが埋まるまで変更できないよ。]]';
  String get stampLongPressSheet => 'まずはシートを長押しして\nスタンプバーを開いてみよう！';
  String get stampCatalogGuide => 'ここからスタンプシート一覧を開けるよ！\n購入できるデザインもあるよ😊';
  String get stampCollectionGuide => 'ここはコレクションだよ！\n過去スタンプで埋めたシートを確認できるよ！';
  String get stampUndoGuide => 'ここから最新のスタンプを取り消せるよ！';

  // 共通
  String get nextAction => '次へ';

  String get phase1Confirm => 'この設定で始める';
}

/// 通知関連メッセージ
class _NotificationMessages {
  const _NotificationMessages();

  String get title => '通知';
  String get markAllRead => '全て既読にする';
  String get empty => 'まだ通知はありません';
  String get tabTimeline => 'TL';
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
  String get screenshotHelp => 'バグ報告の場合は画面のスクリーンショットを添付すると解決が早くなります';
  String get attachImage => '画像を添付';
  String get messageHint => 'メッセージを入力...';
  String get imageOnlyMessage => '（画像を添付しました）';
}

/// 認証関連メッセージ
class _AuthMessages {
  const _AuthMessages();

  // ログイン
  String get loginEmailOrPasswordInvalid => 'メールアドレスかパスワードが間違っているよ、確認してね';
  String get loginUserNotFound => 'このメールアドレスは登録されていないみたい🔍';
  String get loginWrongPassword => 'パスワードが違うみたい🔐';
  String get loginInvalidEmail => 'メールアドレスの形式を確認してね📧';
  String get loginTooManyRequests => 'ちょっと休憩してからまた試してね⏰';
  String get loginTitle => 'おかえりなさい';
  String get loginSubtitle => 'また会えてうれしいな✨';
  String get loginEmailLabel => 'メールアドレス';
  String get loginEmailHint => 'example@email.com';
  String get loginEmailRequired => 'メールアドレスを入力してね';
  String get loginPasswordLabel => 'パスワード';
  String get loginPasswordHint => 'パスワードを入力';
  String get loginPasswordRequired => 'パスワードを入力してね';
  String get loginSubmit => 'ログイン';
  String get loginNoAccount => 'はじめてですか？';
  String get loginCreateAccount => '新規登録';
  String get loginForgotPassword => 'パスワードを忘れた？';
  String get passwordResetTitle => 'パスワードをリセット';
  String get passwordResetEmailLabel => 'メールアドレス';
  String get passwordResetEmailHint => 'example@email.com';
  String get passwordResetEmailRequired => 'メールアドレスを入力してね';
  String get passwordResetInvalidEmail => '正しいメールアドレスを入力してね';
  String get passwordResetUserNotFound => 'このメールアドレスは登録されていないみたい🔍';
  String get passwordResetSend => '送信する';
  String get passwordResetSent => 'パスワードリセットメールを送信したよ📩';

  // 登録
  String get registerEmailAlreadyInUse => 'このメールアドレスはすでに使われているみたい📧';
  String get registerWeakPassword => 'もう少し強いパスワードにしてね🔐';
  String get registerInvalidEmail => 'メールアドレスの形式を確認してね📧';

  // 新規登録 UI
  String get registerTitle => 'アカウント作成';
  String get registerSubtitle => '一緒に素敵な時間を過ごそう✨';
  String get registerAvatarTab => 'アバター';
  String get registerIconTab => 'アイコン';
  String get registerEmailLabel => 'メールアドレス';
  String get registerEmailHint => 'example@email.com';
  String get registerEmailRequired => 'メールアドレスを入力してね';
  String get registerEmailInvalid => '正しいメールアドレスを入力してね';
  String get registerPasswordLabel => 'パスワード';
  String get registerPasswordHint => '6文字以上';
  String get registerPasswordRequired => 'パスワードを入力してね';
  String get registerPasswordTooShort => '6文字以上にしてね';
  String get registerPasswordConfirmLabel => 'パスワード（確認）';
  String get registerPasswordConfirmHint => 'もう一度入力';
  String get registerPasswordMismatch => 'パスワードが一致しないよ';
  String get registerSubmit => 'アカウント作成';
  String get registerHaveAccount => '登録済みですか？';
  String get registerLogin => 'ログイン';
  String get registerNameSelectTitle => 'なまえを選ぼう';
  String get registerNamePrefix => '前半';
  String get registerNameSuffix => '後半';
  String get registerNameNote => '※登録後も設定から変更できます';

  // メール認証
  String get verifyTitle => '認証メールを送信しました';
  String verifySentTo(String email) => email;
  String get verifySentToPrefix => '送信先: ';
  String get verifyNoEmail => '確認メールの送信先が取得できませんでした。登録をやり直してください。';
  String get verifyStep1 => '1. お使いのメールアプリを開く';
  String get verifyStep2 => '2. ほめっぷ運営からのメールを確認';
  String get verifyStep3 => '3. メール内のURLをタップして\n認証を完了してください';
  String get verifySpamHint => '※メールが届かない場合は、迷惑メールフォルダも確認してね';
  String verifyResendCountdown(int seconds) => '再送まであと$seconds秒';
  String get verifyResendReady => '再送できます';
  String get verifyResendAction => '再送する';
  String get verifyRestart => '登録をやり直す';
  String get verifyCheckAction => '認証できたらここをタップ';
  String get verifyResent => '認証メールを再送しました';
  String get verifyGenericError => 'ごめんね、うまくいかなかったみたい。もう一度試してみてね';
  String get verifyRequiresRecentLogin => '安全のため、もう一度ログインしてから変更してね';
}

/// 管理者関連メッセージ
class _AdminMessages {
  const _AdminMessages();

  // AI操作
  String get aiInitInProgress => 'AIアカウントを初期化中...';
  String get aiInitCompleted => 'AIアカウントを作成しました！🤖';
  String get aiGenerateInProgress => 'AI投稿を生成中...（少し時間がかかります）';
  String get aiGenerateCompletedDefault => '完了しました';

  // 通報/審査
  String get postApproved => '投稿を承認しました';
  String get postDeleted => '投稿を削除しました';
  String get commentDeleted => 'コメントを削除しました';
  String get approveFailed => '承認に失敗しました';
  String get deleteFailed => '削除に失敗しました';
  String get deletePostTitle => '投稿を削除';
  String get deleteCommentTitle => 'コメントを削除';
  String get deletePostMessage => 'この投稿を削除しますか？\nこの操作は取り消せません。';
  String get deletePostWithNotifyMessage => 'この投稿を削除しますか？\n投稿者に通知が送信されます。';
  String get deleteCommentWithNotifyMessage =>
      'このコメントを削除しますか？\nコメント投稿者に通知が送信されます。';
  String reportBatchResolved(int count) => '$count件の通報を処理しました';
  String get falseReportDismissed => '虚偽判定しました';
  String get reportResolved => '問題なしとして処理しました';
  String get reportProcessFailed => '処理に失敗しました';

  // 問い合わせ
  String get inquiryReplySent => '返信を送信しました';
  String get inquiryReplyFailed => '送信に失敗しました';
  String inquiryStatusChanged(String label) => 'ステータスを「$label」に変更しました';
  String inquiryStatusChangedAndLogged(String label) =>
      'ステータスを「$label」に変更し、スプレッドシートに記録しました';
  String get inquiryStatusChangeFailed => '変更に失敗しました';
  String get inquiryResolveTitle => 'ステータスを「解決済み」に変更';
  String get inquiryResolveRecord => 'スプレッドシートに記録する';
  String get inquiryResolveConfirm => '解決済みにする';

  // BAN異議申し立て
  String get appealCloseTitle => '対応完了';
  String get appealCloseMessage => 'このチャット履歴を削除しますか？\n削除後は復元できません。';
  String get appealClosed => 'チャット履歴を削除しました';
  String get appealCloseFailed => '削除に失敗しました';
  String get appealSendFailed => '送信に失敗しました';
  String get appealLoginRequired => 'ログインしていません';
  String appealPermanentNotice(String scheduledDeletionDate) =>
      'アカウントは永久停止されています。\n解除の申し立てはここから管理者へ連絡できます。\n$scheduledDeletionDateまでに解除されない場合、アプリデータは自動削除され、復旧できません。';
  String get appealTemporaryNotice =>
      'アカウントは一時的に制限されています。\n解除の申し立てや詳細はここから管理者へ連絡できます。';
  String get appealIntroTitle => '異議申し立て・お問い合わせ';
  String get appealIntroDescription =>
      '管理者にメッセージを送信して、\nBANの解除や詳細について問い合わせることができます。';

  // その他
  String get idCopied => 'IDをコピーしました';
}

/// プロフィール関連メッセージ
class _ProfileMessages {
  const _ProfileMessages();

  String get navLabel => 'マイページ';
  // 設定画面
  String get settingsTitle => '設定';
  String get premiumTitle => 'プレミアム';
  String get premiumSubtitle => 'サブスク加入で特典を解放';
  String get premiumFeatureTitle => '特典';
  String get premiumFeatureEpic => 'Epicアイテム解放';
  String get premiumFeatureAds => '広告表示OFF';
  String get premiumFeatureCircles => 'サークル機能解放';
  String get premiumFeatureProfileImage => 'プロフィール画像設定機能解放';
  String get premiumFeatureHeaderImage => 'プロフィールヘッダー画像設定機能解放';
  String get premiumPriceLabel => '/月';
  String get premiumProcessing => '購入処理中...';
  String get premiumProcessingWait => '少々お待ちください';
  String get premiumNotice => '反映まで数十秒かかる場合があります';
  String get premiumSubscribed => '加入済み';
  String get premiumManage => '定期購入を管理';
  String get premiumComingSoon => '準備中';

  String get profileEditTitle => 'プロフィール編集';
  String get profileVisualLabel => 'アイコン設定';
  String get profileImageModeLabel => '画像設定';
  String get tapToEditAvatar => 'タップして編集';
  String get tapToChangeImage => 'タップして変更';
  String get profileImageCropTitle => '画像を調整';
  String get profileImageRequired => '画像を選択してください';
  String get profileImageSubscriptionTitle => 'サブスク限定';
  String get profileImageSubscriptionMessage => 'この機能はサブスク課金限定の機能だよ';
  String get profileImageUnlockAction => '画像アイコン機能解放';
  String get profileHeaderUnlockAction => '画像ヘッダー機能解放';
  String get circleSubscriptionTitle => 'サブスク限定';
  String get circleSubscriptionMessage => 'この機能はサブスク課金限定の機能だよ';
  String get circleUnlockAction => 'サークル機能解放';
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
  String get milestonesTitle => 'ストリーク達成時';
  String get milestonesSubtitle => '連続達成（マイルストーン）した時に自動で投稿します';
  String get privacyTitle => '公開範囲';
  String privacyCurrent(String label) => '現在: $label';
  String get privacyInfo => '次回以降の投稿から適用されます\n過去の投稿は変わりません';
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
  String get aboutVersion => 'バージョン 1.0.0';
  String get aboutTagline => '安心して使えるSNS';
  String get aboutDescription => 'ほめっぷは、あなたの日常に「ほめられる」体験を届けるSNSです。';
  String get aboutFeaturesTitle => '主な機能';
  String get aboutFeaturePost => '・公開範囲を選んで安心して投稿';
  String get aboutFeatureStamp => '・スタンプとリアクションで気持ちを伝える';
  String get aboutFeatureAvatar => '・名前パーツとアバターで自分らしさを表現';
  String get aboutFeatureSubscription => '・プレミアム加入でEpicアイテム解放';
  String get aboutAiTitle => 'AIについて';
  String get aboutAiDescription =>
      'ほめっぷでは、公開範囲が「AIモード」または「ミックス」の場合、AIが自動でコメントやリアクションを届けます。';
  String get aboutAiNote =>
      '※AIのコメントは自動生成のため、内容が不正確な場合があります。あたたかい気持ちでお楽しみください。';
  String get aboutContactTitle => 'お問い合わせ';
  String get aboutContactBody => '不具合報告・ご要望は設定の「問い合わせ・要望」から送信できます。';
  String get aboutCopyright => 'Copyright (c) 2026 ほめっぷ';
  String get legalLoading => '読み込み中...';
  String get legalLoadFailed => 'ドキュメントを読み込めませんでした';
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

/// スタンプシート関連メッセージ
class _StampMessages {
  const _StampMessages();

  String get navLabel => 'スタンプ';
  String get title => 'スタンプシート';
  String creditsLabel(int count) => 'お礼スタンプ: $count';
  String get noSheets => 'スタンプシートがありません';
  String get selectStamp => 'スタンプを選択';
  String get slotTapHint => 'シートを長押ししてスタンプを押してください';
  String get sheetLocked => 'このシートは未解放です';
  String get stampLocked => 'このスタンプは未解放です';
  String get creditNotEnough => 'お礼スタンプが足りません';

  String get sheetFull => 'このシートはすべて埋まっています';

  String get applied => 'スタンプを押しました';

  String get replaced => 'スタンプを上書きしました';

  String get thanksAction => 'いいね！する';

  String get thanksSending => 'いいね！しています...';
  String get thanksSent => 'いいね！しました';
  String get thanksReceived => 'いいね！されたよ';
  String get thanksGiven => 'お礼スタンプを1個獲得しました';
  String get thanksAlreadyGiven => 'このコメントには既に付与済みです';
  String get postOwnerOnly => '投稿主のみ実行できます';
  String get designSelect => 'デザイン閲覧';
  String get designCatalogTitle => 'シート一覧';
  String get chooseNextSheetTitle => '次のシートを選択';
  String get chooseNextSheetFabLabel => '次を選ぶ';
  String get chooseFirstSheetTitle => '最初のシートを選択';
  String get sheetCompleted => 'シート完成！';
  String get chooseNextSheetBody => '次のページに使うシートを選んでください';
  String get chooseNextSheetRequired => '次のシートを選択してください';
  String sheetRarityLabel(String rarity) => 'レア度: $rarity';
  String get owned => '所持済み';
  String get selectAction => '選択する';
  String pageLabel(int current, int total) => '$current / $total';
  String get firstSheetPrompt => 'スタンプを押すシートを選んでください';
  String get undoAction => '取り消し';
  String get undoDone => '最新のスタンプを取り消しました';
  String get undoUnavailable => '取り消せるスタンプがありません';
  String get sheetConfigNotReady => 'スタンプシート設定を同期中です。少し待ってからもう一度お試しください。';
  String get archiveTitle => 'コレクション';
  String get archiveEmpty => 'まだアーカイブはありません';
  String archiveItemTitle(String sheetId) => 'シート: $sheetId';
  String archiveCompletedAt(String value) => '$value 完成 🎉';
  String get archivePreviewUnavailable => 'このシートのプレビューを表示できません';
}

/// 徳ポイント関連メッセージ
class _VirtueMessages {
  const _VirtueMessages();

  String get shortLabel => '徳';
  String get warningLabel => '⚠️ 注意';
  String get title => '徳ポイント';
  String get description => '徳ポイントは、ほめっぷでの行いを表す指標だよ☺️';
  String get guidelines =>
      '• ポジティブな投稿で徳が上がるよ\n'
      '• ネガティブな発言をすると下がるよ\n'
      '• 0になると投稿できなくなるよ';
  String get lowWarning => '徳ポイントが少なくなっているよ。ポジティブな投稿を心がけてね！';
  String get historyTitle => '履歴';
  String get historyEmpty => 'まだ履歴がないよ';
  String get historyLoadFailed => '履歴を読み込めませんでした';
}
