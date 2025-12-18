import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/services/circle_service.dart';

class EditCircleScreen extends ConsumerStatefulWidget {
  final String circleId;
  final CircleModel circle;

  const EditCircleScreen({
    super.key,
    required this.circleId,
    required this.circle,
  });

  @override
  ConsumerState<EditCircleScreen> createState() => _EditCircleScreenState();
}

class _EditCircleScreenState extends ConsumerState<EditCircleScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _goalController;
  late TextEditingController _rulesController;

  late String _selectedCategory;
  late bool _isPublic;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.circle.name);
    _descriptionController = TextEditingController(
      text: widget.circle.description,
    );
    _goalController = TextEditingController(text: widget.circle.goal);
    _rulesController = TextEditingController(text: widget.circle.rules ?? '');
    _selectedCategory = widget.circle.category;
    _isPublic = widget.circle.isPublic;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final circleService = ref.read(circleServiceProvider);

      await circleService.updateCircle(widget.circleId, {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'goal': _goalController.text.trim(),
        'rules': _rulesController.text.trim().isEmpty
            ? null
            : _rulesController.text.trim(),
        'isPublic': _isPublic,
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('サークルを更新しました！')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = CircleService.categories
        .where((c) => c != '全て')
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('サークル編集'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveChanges,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // サークル名
            _buildSection(
              title: 'サークル名',
              child: TextFormField(
                controller: _nameController,
                decoration: _inputDecoration('サークル名を入力'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'サークル名を入力してください';
                  }
                  if (value.trim().length > 30) {
                    return '30文字以内で入力してください';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // 説明
            _buildSection(
              title: '説明',
              child: TextFormField(
                controller: _descriptionController,
                decoration: _inputDecoration('サークルの説明を入力'),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '説明を入力してください';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // カテゴリ
            _buildSection(
              title: 'カテゴリ',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((category) {
                  final isSelected = _selectedCategory == category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = category);
                      }
                    },
                    selectedColor: AppColors.primary.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.grey[700],
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // 目標
            _buildSection(
              title: '目標',
              child: TextFormField(
                controller: _goalController,
                decoration: _inputDecoration('サークルの目標（任意）'),
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 16),

            // ルール
            _buildSection(
              title: 'サークルルール',
              subtitle: '参加時に同意を求めます（任意・500文字以内）',
              child: TextFormField(
                controller: _rulesController,
                decoration: _inputDecoration('サークルのルールを入力'),
                maxLines: 5,
                maxLength: 500,
                validator: (value) {
                  if (value != null && value.length > 500) {
                    return '500文字以内で入力してください';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // AIモードの場合は公開設定を非表示
            if (widget.circle.aiMode != CircleAIMode.aiOnly) ...[
              // 公開設定
              _buildSection(
                title: '公開設定',
                child: Column(
                  children: [
                    _buildRadioTile(
                      title: '公開',
                      subtitle: '誰でも参加できます',
                      value: true,
                      groupValue: _isPublic,
                      onChanged: (value) => setState(() => _isPublic = value!),
                    ),
                    _buildRadioTile(
                      title: '招待制',
                      subtitle: '管理者の承認が必要です',
                      value: false,
                      groupValue: _isPublic,
                      onChanged: (value) => setState(() => _isPublic = value!),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required bool value,
    required bool groupValue,
    required ValueChanged<bool?> onChanged,
  }) {
    return RadioListTile<bool>(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
    );
  }
}
