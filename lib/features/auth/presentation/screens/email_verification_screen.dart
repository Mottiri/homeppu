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
    with WidgetsBindingObserver {
  static const int _cooldownSeconds = 60;

  Timer? _timer;
  int _remainingSeconds = _cooldownSeconds;
  bool _isSending = false;
  String? _errorMessage;

  FirebaseAuth get _auth => ref.read(firebaseAuthProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
    _sendVerification(initial: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    final description = email.isNotEmpty
        ? AppMessages.auth.verifySentTo(email)
        : AppMessages.auth.verifyNoEmail;
    final countdownText = _remainingSeconds > 0
        ? AppMessages.auth.verifyResendCountdown(_remainingSeconds)
        : AppMessages.auth.verifyResendReady;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.mark_email_unread_rounded,
                    size: 72,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        countdownText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _canResend ? _sendVerification : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _canResend
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(AppMessages.auth.verifyResendAction),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final router = ref.read(appRouterProvider);
                        final authService = ref.read(authServiceProvider);
                        router.go('/register');
                        await authService.signOut();
                      },
                      child: Text(AppMessages.auth.verifyRestart),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _checkVerification,
                    child: Text(AppMessages.auth.verifyCheckAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
