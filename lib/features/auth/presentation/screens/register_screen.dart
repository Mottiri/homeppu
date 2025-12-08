import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../widgets/auth_text_field.dart';

/// 新規登録画面
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  int _selectedAvatarIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
        avatarIndex: _selectedAvatarIndex,
      );
      // 登録成功 → ルーターがリダイレクト
    } catch (e) {
      print('RegisterScreen: Error during registration: $e');
      setState(() {
        _errorMessage = _getErrorMessage(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('email-already-in-use')) {
      return 'このメールアドレスはすでに使われているみたい📧';
    } else if (error.contains('weak-password')) {
      return 'もう少し強いパスワードにしてね🔐';
    } else if (error.contains('invalid-email')) {
      return 'メールアドレスの形式を確認してね📧';
    }
    return AppConstants.friendlyMessages['error_general']!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.warmGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 戻るボタン
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () => context.go('/onboarding'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // タイトル
                  Text(
                    'アカウント作成',
                    style: Theme.of(context).textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一緒に素敵な時間を過ごそう✨',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // アバター選択
                  Center(
                    child: AvatarSelector(
                      selectedIndex: _selectedAvatarIndex,
                      onSelected: (index) {
                        setState(() => _selectedAvatarIndex = index);
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // エラーメッセージ
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 表示名
                  AuthTextField(
                    controller: _displayNameController,
                    label: 'ニックネーム',
                    hint: 'みんなに呼ばれる名前',
                    prefixIcon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'ニックネームを入力してね';
                      }
                      if (value.length > AppConstants.maxDisplayNameLength) {
                        return '${AppConstants.maxDisplayNameLength}文字以内にしてね';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // メールアドレス
                  AuthTextField(
                    controller: _emailController,
                    label: 'メールアドレス',
                    hint: 'example@email.com',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'メールアドレスを入力してね';
                      }
                      if (!value.contains('@')) {
                        return '正しいメールアドレスを入力してね';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // パスワード
                  AuthTextField(
                    controller: _passwordController,
                    label: 'パスワード',
                    hint: '6文字以上',
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'パスワードを入力してね';
                      }
                      if (value.length < 6) {
                        return '6文字以上にしてね';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // パスワード確認
                  AuthTextField(
                    controller: _confirmPasswordController,
                    label: 'パスワード（確認）',
                    hint: 'もう一度入力',
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'パスワードが一致しないよ';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // 登録ボタン
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('アカウント作成'),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // ログインリンク
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'すでにアカウントをお持ち？',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('ログイン'),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


