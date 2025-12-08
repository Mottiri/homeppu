import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/models/name_part_model.dart';
import '../widgets/auth_text_field.dart';

/// 新規登録画面
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

// 登録時に選択可能な名前パーツ（ノーマルのみ）
final _defaultPrefixes = [
  NamePartModel(id: 'prefix_pre_01', text: 'がんばる', category: 'positive', rarity: 'normal', type: 'prefix', order: 1, unlocked: true),
  NamePartModel(id: 'prefix_pre_02', text: 'キラキラ', category: 'positive', rarity: 'normal', type: 'prefix', order: 2, unlocked: true),
  NamePartModel(id: 'prefix_pre_03', text: '全力', category: 'positive', rarity: 'normal', type: 'prefix', order: 3, unlocked: true),
  NamePartModel(id: 'prefix_pre_04', text: '輝く', category: 'positive', rarity: 'normal', type: 'prefix', order: 4, unlocked: true),
  NamePartModel(id: 'prefix_pre_05', text: '前向き', category: 'positive', rarity: 'normal', type: 'prefix', order: 5, unlocked: true),
  NamePartModel(id: 'prefix_pre_06', text: 'のんびり', category: 'relaxed', rarity: 'normal', type: 'prefix', order: 6, unlocked: true),
  NamePartModel(id: 'prefix_pre_07', text: 'まったり', category: 'relaxed', rarity: 'normal', type: 'prefix', order: 7, unlocked: true),
  NamePartModel(id: 'prefix_pre_08', text: 'ゆるふわ', category: 'relaxed', rarity: 'normal', type: 'prefix', order: 8, unlocked: true),
  NamePartModel(id: 'prefix_pre_11', text: 'コツコツ', category: 'effort', rarity: 'normal', type: 'prefix', order: 11, unlocked: true),
  NamePartModel(id: 'prefix_pre_12', text: 'もくもく', category: 'effort', rarity: 'normal', type: 'prefix', order: 12, unlocked: true),
];

final _defaultSuffixes = [
  NamePartModel(id: 'suffix_suf_01', text: '🐰うさぎ', category: 'animal', rarity: 'normal', type: 'suffix', order: 1, unlocked: true),
  NamePartModel(id: 'suffix_suf_02', text: '🐱ねこ', category: 'animal', rarity: 'normal', type: 'suffix', order: 2, unlocked: true),
  NamePartModel(id: 'suffix_suf_03', text: '🐶いぬ', category: 'animal', rarity: 'normal', type: 'suffix', order: 3, unlocked: true),
  NamePartModel(id: 'suffix_suf_04', text: '🐼パンダ', category: 'animal', rarity: 'normal', type: 'suffix', order: 4, unlocked: true),
  NamePartModel(id: 'suffix_suf_05', text: '🐻くま', category: 'animal', rarity: 'normal', type: 'suffix', order: 5, unlocked: true),
  NamePartModel(id: 'suffix_suf_07', text: '🌸さくら', category: 'nature', rarity: 'normal', type: 'suffix', order: 7, unlocked: true),
  NamePartModel(id: 'suffix_suf_08', text: '🌻ひまわり', category: 'nature', rarity: 'normal', type: 'suffix', order: 8, unlocked: true),
  NamePartModel(id: 'suffix_suf_09', text: '⭐ほし', category: 'nature', rarity: 'normal', type: 'suffix', order: 9, unlocked: true),
  NamePartModel(id: 'suffix_suf_12', text: '🍙おにぎり', category: 'food', rarity: 'normal', type: 'suffix', order: 12, unlocked: true),
  NamePartModel(id: 'suffix_suf_14', text: '🍮プリン', category: 'food', rarity: 'normal', type: 'suffix', order: 14, unlocked: true),
];

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  int _selectedAvatarIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;
  
  // 名前パーツ
  late NamePartModel _selectedPrefix;
  late NamePartModel _selectedSuffix;

  @override
  void initState() {
    super.initState();
    // ランダムに初期選択
    _selectedPrefix = _defaultPrefixes[DateTime.now().millisecond % _defaultPrefixes.length];
    _selectedSuffix = _defaultSuffixes[DateTime.now().second % _defaultSuffixes.length];
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
        namePrefix: _selectedPrefix.id,
        nameSuffix: _selectedSuffix.id,
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
                  
                  // 名前パーツ選択
                  _buildNamePartsSelector(),
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

  Widget _buildNamePartsSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'なまえを選ぼう',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // プレビュー
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 前半パーツ選択
          Text(
            '前半',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 16),
          
          // 後半パーツ選択
          Text(
            '後半',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 8),
          Text(
            '※登録後も設定から変更できます',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
