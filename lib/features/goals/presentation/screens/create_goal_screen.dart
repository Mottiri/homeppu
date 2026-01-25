import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/mixins/loading_state_mixin.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/widgets/reminder_setting_widget.dart';
import '../../../../shared/models/goal_model.dart';
import '../../../../shared/providers/goal_provider.dart';

class CreateGoalScreen extends ConsumerStatefulWidget {
  final GoalModel? goal;
  const CreateGoalScreen({super.key, this.goal});

  @override
  ConsumerState<CreateGoalScreen> createState() => _CreateGoalScreenState();
}

class _CreateGoalScreenState extends ConsumerState<CreateGoalScreen>
    with LoadingStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _deadline;
  int _selectedColorValue = 0xFFFF8A80; // Default: AppColors.primary
  List<Map<String, dynamic>> _reminders = [];

  final List<Map<String, dynamic>> _colorOptions = [
    {'color': 0xFFFF8A80, 'name': 'コーラル'},
    {'color': 0xFFFFAB91, 'name': 'ピーチ'},
    {'color': 0xFF81C784, 'name': 'グリーン'},
    {'color': 0xFF64B5F6, 'name': 'ブルー'},
    {'color': 0xFFB39DDB, 'name': 'パープル'},
    {'color': 0xFFF48FB1, 'name': 'ピンク'},
    {'color': 0xFF4DB6AC, 'name': 'ティール'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.goal != null) {
      _titleController.text = widget.goal!.title;
      _descriptionController.text = widget.goal!.description ?? '';
      _deadline = widget.goal!.deadline;
      _selectedColorValue = widget.goal!.colorValue;
      _reminders = List.from(widget.goal!.reminders);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveGoal() async {
    if (!_formKey.currentState!.validate()) return;

    await runWithLoading(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ログインが必要です');

      final goalService = ref.read(goalServiceProvider);

      if (widget.goal != null) {
        // 更新モード
        final updatedGoal = widget.goal!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          deadline: _deadline,
          colorValue: _selectedColorValue,
          updatedAt: DateTime.now(),
          reminders: _reminders,
        );
        await goalService.updateGoal(updatedGoal);
      } else {
        // 新規作成モード
        final newGoal = GoalModel(
          id: const Uuid().v4(),
          userId: user.uid,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          deadline: _deadline,
          colorValue: _selectedColorValue,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          reminders: _reminders,
        );
        await goalService.createGoal(newGoal);
      }

      if (mounted) {
        context.pop();
        SnackBarHelper.showSuccess(
          context,
          widget.goal != null
              ? AppMessages.success.goalUpdated
              : AppMessages.success.goalCreated,
        );
      }
    }).catchError((e) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('Goal save failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = Color(_selectedColorValue);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.goal != null ? '目標を編集' : '新しい目標'),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, size: 20),
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // プレビューカード
            _buildPreviewCard(selectedColor),

            const SizedBox(height: 24),

            // タイトル入力セクション
            _buildSectionCard(
              icon: Icons.edit_rounded,
              iconColor: selectedColor,
              title: 'タイトル',
              child: TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: '達成したい目標を入力',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(fontSize: 16),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'タイトルを入力してください';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: 16),

            // 詳細入力セクション
            _buildSectionCard(
              icon: Icons.notes_rounded,
              iconColor: AppColors.textSecondary,
              title: '詳細・意気込み（任意）',
              child: TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: '具体的な数値目標や、達成したらやりたいことなど',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: 16),

            // カラー選択セクション
            _buildSectionCard(
              icon: Icons.palette_rounded,
              iconColor: selectedColor,
              title: 'テーマカラー',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _colorOptions.map((option) {
                    final colorValue = option['color'] as int;
                    final isSelected = _selectedColorValue == colorValue;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedColorValue = colorValue),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Color(colorValue),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: AppColors.textPrimary,
                                  width: 3,
                                )
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Color(
                                      colorValue,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 24,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 期限設定セクション
            _buildSectionCard(
              icon: Icons.event_rounded,
              iconColor: _deadline != null ? selectedColor : AppColors.textHint,
              title: '期限を設定（任意）',
              child: Column(
                children: [
                  InkWell(
                    onTap: _selectDeadline,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _deadline == null
                                ? Text(
                                    '期限を選択してモチベーションUP！',
                                    style: TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 14,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat(
                                          'yyyy年M月d日 H:mm',
                                        ).format(_deadline!),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: selectedColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'あと${_deadline!.difference(DateTime.now()).inDays}日',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          if (_deadline != null)
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: AppColors.textHint,
                              ),
                              onPressed: () => setState(() => _deadline = null),
                            )
                          else
                            Icon(
                              Icons.calendar_today_rounded,
                              color: AppColors.textHint,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_deadline != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ReminderSettingWidget(
                        reminders: _reminders,
                        onChanged: (reminders) {
                          setState(() => _reminders = reminders);
                        },
                        isGoal: true,
                      ),
                    ),
                  ] else ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 18,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '期限を設定すると事前通知が可能になります',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 保存ボタン
            _buildSaveButton(selectedColor),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(Color color) {
    final title = _titleController.text.isEmpty
        ? '目標タイトル'
        : _titleController.text;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // アイコン
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.flag_rounded, size: 32, color: color),
          ),
          const SizedBox(height: 16),
          // タイトル
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          if (_descriptionController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _descriptionController.text,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_deadline != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('M/d').format(_deadline!)} まで',
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildSaveButton(Color color) {
    return GestureDetector(
      onTap: isLoading ? null : _saveGoal,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color,
              color.withBlue(((color.b * 255).round() + 30).clamp(0, 255)),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.goal != null ? '変更を保存する' : 'この目標で始める',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _selectDeadline() async {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? today,
      firstDate: todayMidnight,
      lastDate: todayMidnight.add(const Duration(days: 3650)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(_selectedColorValue),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      // 時間選択ダイアログ
      if (!mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: _deadline != null
            ? TimeOfDay.fromDateTime(_deadline!)
            : TimeOfDay.fromDateTime(today),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Color(_selectedColorValue),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: AppColors.textPrimary,
              ),
            ),
            child: child!,
          );
        },
      );
      if (pickedTime != null) {
        setState(() {
          _deadline = DateTime(
            picked.year,
            picked.month,
            picked.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }
}
