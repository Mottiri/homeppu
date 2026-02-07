import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/providers/auth_provider.dart';

/// メール認証待ち画面
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const int _cooldownSeconds = 60;

  Timer? _timer;
  int _remainingSeconds = _cooldownSeconds;
  bool _isSending = false;
  String? _errorMessage;

  // パルスアニメーション用
  late AnimationController _pulseController;
  late Animation<double> _pulseOpacity;
  late Animation<double> _pulseSize;

  FirebaseAuth get _auth => ref.read(firebaseAuthProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
    _sendVerification(initial: true);

    // パルスアニメーション初期化（より目立つ設定）
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // 透明度: 0.1 → 0.7 で大きく変化
    _pulseOpacity = Tween<double>(begin: 0.1, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // シャドウサイズ: 12 → 28 で拡大・縮小
    _pulseSize = Tween<double>(begin: 12, end: 28).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVerification();
    }
  }

  bool get _canResend => _remainingSeconds == 0 && !_isSending;

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remainingSeconds = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() => _remainingSeconds -= 1);
      }
    });
  }

  Future<void> _sendVerification({bool initial = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!initial) {
      setState(() {
        _isSending = true;
        _errorMessage = null;
      });
    }

    try {
      debugPrint(
        '[verify] sendEmailVerification start: uid=${user.uid}, email=${user.email}',
      );
      await user.sendEmailVerification();
      debugPrint('[verify] sendEmailVerification success: uid=${user.uid}');
      if (!initial && mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.auth.verifyResent);
      }
      if (!initial) {
        _startCooldown();
      }
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[verify] FirebaseAuthException: code=${e.code}, message=${e.message}',
      );
      setState(() {
        _errorMessage = AppMessages.auth.verifyGenericError;
      });
    } catch (e) {
      debugPrint('[verify] unexpected error: $e');
      setState(() {
        _errorMessage = AppMessages.auth.verifyGenericError;
      });
    } finally {
      if (!initial && mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _checkVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    await user.getIdToken(true);
    final refreshed = _auth.currentUser;
    if (refreshed?.emailVerified == true && mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // メールアイコン（アニメーション付き）
                  _buildEmailIcon(),
                  const SizedBox(height: 24),

                  // タイトル
                  Text(
                    AppMessages.auth.verifyTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // メールアドレス表示（ピル型）
                  if (email.isNotEmpty) _buildEmailPill(email),
                  if (email.isEmpty) _buildNoEmailWarning(),
                  const SizedBox(height: 24),

                  // 手順カード
                  _buildInstructionsCard(),
                  const SizedBox(height: 32),

                  // 主要アクションボタン
                  _buildPrimaryButton(),
                  const SizedBox(height: 16),

                  // 再送・やり直しボタン行
                  _buildSecondaryActions(),

                  // エラー表示
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    _buildErrorCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // 背景の円（パルスアニメーション）
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            // メールアイコン（シャドウがパルス - サイズと濃さが変化）
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: _pulseOpacity.value,
                    ),
                    blurRadius: _pulseSize.value,
                    spreadRadius: _pulseSize.value / 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.mark_email_unread_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            // チェックマークバッジ
            Positioned(
              right: 0,
              bottom: 0,
              child: Transform.translate(
                offset: const Offset(50, 0),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cheer,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmailPill(String email) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.email_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                email,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEmailWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppMessages.auth.verifyNoEmail,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepRow(AppMessages.auth.verifyStep1, 1),
          const SizedBox(height: 12),
          _buildStepRow(AppMessages.auth.verifyStep2, 2),
          const SizedBox(height: 12),
          _buildStepRow(AppMessages.auth.verifyStep3, 3, isHighlight: true),
        ],
      ),
    );
  }

  Widget _buildStepRow(String text, int step, {bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHighlight
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.backgroundSecondary,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isHighlight
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text.substring(3), // "1. " を除去
            style: TextStyle(
              fontSize: 14,
              color: isHighlight ? AppColors.primary : AppColors.textPrimary,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _checkVerification,
        child: Text(
          AppMessages.auth.verifyCheckAction,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSecondaryActions() {
    final countdownText = _remainingSeconds > 0
        ? '再送（$_remainingSeconds秒後）'
        : AppMessages.auth.verifyResendAction;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 再送ボタン
        TextButton.icon(
          onPressed: _canResend ? _sendVerification : null,
          icon: Icon(
            Icons.refresh_rounded,
            size: 18,
            color: _canResend
                ? AppColors.primary
                : AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          label: Text(
            countdownText,
            style: TextStyle(
              color: _canResend
                  ? AppColors.primary
                  : AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 1,
          height: 20,
          color: AppColors.textSecondary.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 8),
        // 登録やり直しボタン
        TextButton(
          onPressed: () async {
            final router = ref.read(appRouterProvider);
            final authService = ref.read(authServiceProvider);
            router.go('/register');
            await authService.signOut();
          },
          child: Text(
            AppMessages.auth.verifyRestart,
            style: const TextStyle(
              color: AppColors.textSecondary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
