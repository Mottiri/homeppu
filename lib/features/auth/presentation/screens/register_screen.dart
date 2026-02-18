import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/avatar_assets.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/constants/name_parts_catalog.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/models/avatar_parts_model.dart';
import '../../../../shared/widgets/avatar_parts_widget.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/models/name_part_model.dart';
import '../widgets/auth_text_field.dart';

/// 新規登録画面
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

// 登録時に選択可能な名前パーツ（Commonのみ）
final _defaultPrefixes = NamePartsCatalog.commonPrefixes;
final _defaultSuffixes = NamePartsCatalog.commonSuffixes;

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  int _selectedAvatarIndex = 0;
  AvatarParts _selectedAvatarParts = AvatarAssets.defaultParts();
  bool _useAvatarParts = true;
  bool _isLoading = false;
  String? _errorMessage;

  // 名前パーツ
  late NamePartModel _selectedPrefix;
  late NamePartModel _selectedSuffix;

  @override
  void initState() {
    super.initState();
    // ランダムに初期選択
    _selectedPrefix =
        _defaultPrefixes[DateTime.now().millisecond % _defaultPrefixes.length];
    _selectedSuffix =
        _defaultSuffixes[DateTime.now().second % _defaultSuffixes.length];
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String get _displayName => '${_selectedPrefix.text}${_selectedSuffix.text}';

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
        displayName: _displayName,
        avatarIndex: _selectedAvatarIndex,
        avatarParts: _useAvatarParts ? _selectedAvatarParts : null,
        profileVisualMode: _useAvatarParts ? 'avatar' : 'icon',
        namePrefix: _selectedPrefix.id,
        nameSuffix: _selectedSuffix.id,
      );
      // 登録成功 → ルーターがリダイレクト
    } catch (e) {
      debugPrint('RegisterScreen: Error during registration: $e');
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
      return AppMessages.auth.registerEmailAlreadyInUse;
    } else if (error.contains('weak-password')) {
      return AppMessages.auth.registerWeakPassword;
    } else if (error.contains('invalid-email')) {
      return AppMessages.auth.registerInvalidEmail;
    }
    return AppMessages.error.general;
  }

  bool get _hasEmailError =>
      _errorMessage == AppMessages.auth.registerEmailAlreadyInUse ||
      _errorMessage == AppMessages.auth.registerInvalidEmail;

  String? get _emailErrorMessage => _hasEmailError ? _errorMessage : null;

  Future<void> _openAvatarEdit() async {
    final result = await context.push<AvatarParts>(
      '/avatar-edit',
      extra: _selectedAvatarParts,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedAvatarParts = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
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
                    AppMessages.auth.registerTitle,
                    style: Theme.of(context).textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppMessages.auth.registerSubtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // アバター選択
                  Row(
                    children: [
                      Expanded(
                        child: _AvatarModeButton(
                          label: AppMessages.auth.registerAvatarTab,
                          isSelected: _useAvatarParts,
                          onTap: () => setState(() => _useAvatarParts = true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AvatarModeButton(
                          label: AppMessages.auth.registerIconTab,
                          isSelected: !_useAvatarParts,
                          onTap: () => setState(() => _useAvatarParts = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_useAvatarParts)
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _openAvatarEdit,
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                AvatarPartsWidget(
                                  parts: _selectedAvatarParts,
                                  size: 96,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppMessages.profile.tapToEditAvatar,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
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
                  if (_errorMessage != null && !_hasEmailError) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
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

                  // 名前パーツ選択
                  _buildNamePartsSelector(),
                  const SizedBox(height: 16),

                  // メールアドレス
                  AuthTextField(
                    controller: _emailController,
                    label: AppMessages.auth.registerEmailLabel,
                    hint: AppMessages.auth.registerEmailHint,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppMessages.auth.registerEmailRequired;
                      }
                      if (!value.contains('@')) {
                        return AppMessages.auth.registerEmailInvalid;
                      }
                      return null;
                    },
                  ),
                  if (_emailErrorMessage != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _emailErrorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // パスワード
                  AuthTextField(
                    controller: _passwordController,
                    label: AppMessages.auth.registerPasswordLabel,
                    hint: AppMessages.auth.registerPasswordHint,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppMessages.auth.registerPasswordRequired;
                      }
                      if (value.length < 6) {
                        return AppMessages.auth.registerPasswordTooShort;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // パスワード確認
                  AuthTextField(
                    controller: _confirmPasswordController,
                    label: AppMessages.auth.registerPasswordConfirmLabel,
                    hint: AppMessages.auth.registerPasswordConfirmHint,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return AppMessages.auth.registerPasswordMismatch;
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
                          : Text(AppMessages.auth.registerSubmit),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ログインリンク
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppMessages.auth.registerHaveAccount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(AppMessages.auth.registerLogin),
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

  Widget _buildNamePartsSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppMessages.auth.registerNameSelectTitle,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // プレビュー
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 16),

          // 前半パーツ選択
          Text(
            AppMessages.auth.registerNamePrefix,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _defaultPrefixes.map((part) {
              final isSelected = _selectedPrefix.id == part.id;
              return GestureDetector(
                onTap: () => setState(() => _selectedPrefix = part),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    part.text,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // 後半パーツ選択
          Text(
            AppMessages.auth.registerNameSuffix,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _defaultSuffixes.map((part) {
              final isSelected = _selectedSuffix.id == part.id;
              return GestureDetector(
                onTap: () => setState(() => _selectedSuffix = part),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    part.text,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
          Text(
            AppMessages.auth.registerNameNote,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _AvatarModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AvatarModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.textTertiary,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
