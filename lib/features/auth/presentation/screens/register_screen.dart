import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

/// 新規登録画面（3ステップ ウィザード形式）
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
  final _pageController = PageController();

  int _currentStep = 0;
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
    _pageController.dispose();
    super.dispose();
  }

  String get _displayName => '${_selectedPrefix.text}${_selectedSuffix.text}';

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    setState(() => _currentStep = step);
  }

  void _nextStep() {
    if (_currentStep < 2) {
      _goToStep(_currentStep + 1);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    } else {
      context.go('/onboarding');
    }
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
      extra: <String, dynamic>{
        'parts': _selectedAvatarParts,
        'allowedRarities': const <String>['common'],
      },
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
          child: Column(
            children: [
              // 戻るボタン + ステップインジケータ
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _previousStep,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: _StepIndicator(
                        currentStep: _currentStep,
                        totalSteps: 3,
                      ),
                    ),
                    const SizedBox(width: 48), // バランス用スペーサー
                  ],
                ),
              ),

              // ページビュー
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _currentStep = index);
                  },
                  children: [
                    _buildStep1Avatar(),
                    _buildStep2Name(),
                    _buildStep3Account(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Step 1: アバター選択
  // ============================================================
  Widget _buildStep1Avatar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            AppMessages.auth.registerStep1Title,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppMessages.auth.registerStep1Subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // アバター/アイコン モード切替
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
          const SizedBox(height: 24),

          // アバター表示
          if (_useAvatarParts)
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _openAvatarEdit,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        AvatarPartsWidget(
                          parts: _selectedAvatarParts,
                          size: 120,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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

          const SizedBox(height: 40),

          // 次へボタン
          _NextButton(onTap: _nextStep),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ============================================================
  // Step 2: 名前選択
  // ============================================================
  Widget _buildStep2Name() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            AppMessages.auth.registerStep2Title,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppMessages.auth.registerStep2Subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // アバター + 名前プレビュー
          _ProfilePreviewCard(
            useAvatarParts: _useAvatarParts,
            avatarParts: _selectedAvatarParts,
            avatarIndex: _selectedAvatarIndex,
            displayName: _displayName,
          ),

          const SizedBox(height: 24),

          // 名前パーツ選択
          _buildNamePartsSelector(),

          const SizedBox(height: 32),

          // 次へボタン
          _NextButton(onTap: _nextStep),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ============================================================
  // Step 3: アカウント情報
  // ============================================================
  Widget _buildStep3Account() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              AppMessages.auth.registerStep3Title,
              style: Theme.of(context).textTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppMessages.auth.registerStep3Subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // プレビューカード（小さめ）
            _ProfilePreviewCard(
              useAvatarParts: _useAvatarParts,
              avatarParts: _selectedAvatarParts,
              avatarIndex: _selectedAvatarIndex,
              displayName: _displayName,
              compact: true,
            ),

            const SizedBox(height: 24),

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
              const SizedBox(height: 16),
            ],

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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 4,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppMessages.auth.registerSubmit,
                            style: GoogleFonts.zenMaruGothic(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('🎉', style: TextStyle(fontSize: 18)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 16),

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
    );
  }

  // ============================================================
  // 名前パーツセレクター（Wrapベース・柔らかいデザイン）
  // ============================================================
  Widget _buildNamePartsSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 前半パーツ選択
          Text(
            AppMessages.auth.registerNamePrefix,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _defaultPrefixes.map((part) {
              final isSelected = _selectedPrefix.id == part.id;
              return _NamePartChip(
                text: part.text,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedPrefix = part),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // 後半パーツ選択
          Text(
            AppMessages.auth.registerNameSuffix,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: _defaultSuffixes.map((part) {
              final isSelected = _selectedSuffix.id == part.id;
              return _NamePartChip(
                text: part.text,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedSuffix = part),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          Text(
            AppMessages.auth.registerNameNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// サブウィジェット群
// ================================================================

/// ステップインジケータ
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final isActive = index == currentStep;
        final isCompleted = index < currentStep;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: isActive ? 32 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary
                    : isCompleted
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isCompleted
                  ? const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 10,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            if (index < totalSteps - 1) const SizedBox(width: 8),
          ],
        );
      }),
    );
  }
}

/// 次へボタン
class _NextButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppMessages.auth.registerNext,
              style: GoogleFonts.zenMaruGothic(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

/// プロフィールプレビューカード
class _ProfilePreviewCard extends StatelessWidget {
  final bool useAvatarParts;
  final AvatarParts avatarParts;
  final int avatarIndex;
  final String displayName;
  final bool compact;

  const _ProfilePreviewCard({
    required this.useAvatarParts,
    required this.avatarParts,
    required this.avatarIndex,
    required this.displayName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 56.0 : 72.0;
    final borderRadius = BorderRadius.circular(compact ? 16 : 20);
    final nameFontSize = compact ? 18.0 : 22.0;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF8F2),
            Color(0xFFFFEFE5),
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // アバター
          if (useAvatarParts)
            AvatarPartsWidget(
              parts: avatarParts,
              size: avatarSize,
              borderRadius: borderRadius,
            )
          else
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: borderRadius,
              ),
              child: Center(
                child: Text(
                  presetAvatars[avatarIndex.clamp(0, presetAvatars.length - 1)],
                  style: TextStyle(fontSize: avatarSize * 0.5),
                ),
              ),
            ),
          const SizedBox(width: 16),
          // 名前
          Flexible(
            child: Text(
              displayName,
              style: GoogleFonts.zenMaruGothic(
                fontSize: nameFontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 名前パーツチップ（柔らかい角丸ピル型）
class _NamePartChip extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const _NamePartChip({
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.textTertiary.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: GoogleFonts.zenMaruGothic(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
          child: Text(text),
        ),
      ),
    );
  }
}

/// アバターモード切替ボタン
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
