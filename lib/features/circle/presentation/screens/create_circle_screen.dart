import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/services/media_service.dart';

class CreateCircleScreen extends ConsumerStatefulWidget {
  const CreateCircleScreen({super.key});

  @override
  ConsumerState<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends ConsumerState<CreateCircleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _goalController = TextEditingController();
  final _rulesController = TextEditingController();

  String _selectedCategory = 'その他';
  CircleAIMode _aiMode = CircleAIMode.mix;
  bool _isPublic = true;
  bool _isLoading = false;

  // 画像設定
  File? _iconImage;
  File? _coverImage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isIcon}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked != null) {
      // クロッピング
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: isIcon
            ? const CropAspectRatio(ratioX: 1, ratioY: 1)
            : const CropAspectRatio(ratioX: 16, ratioY: 9),
        compressQuality: 85,
        maxWidth: isIcon ? 512 : 1920,
        maxHeight: isIcon ? 512 : 1080,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isIcon ? 'アイコンを調整' : 'ヘッダーを調整',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: isIcon ? 'アイコンを調整' : 'ヘッダーを調整',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          if (isIcon) {
            _iconImage = File(croppedFile.path);
          } else {
            _coverImage = File(croppedFile.path);
          }
        });
      }
    }
  }

  Future<void> _createCircle() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final circleService = ref.read(circleServiceProvider);
      final mediaService = MediaService();

      // サークルを先に作成（IDを取得するため）
      final circleId = await circleService.createCircle(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        ownerId: currentUser.uid,
        aiMode: _aiMode,
        goal: _goalController.text.trim(),
        isPublic: _isPublic,
        rules: _rulesController.text.trim().isNotEmpty
            ? _rulesController.text.trim()
            : null,
      );

      // 画像をアップロード
      String? iconUrl;
      String? coverUrl;

      if (_iconImage != null) {
        iconUrl = await mediaService.uploadCircleImage(
          filePath: _iconImage!.path,
          circleId: circleId,
          imageType: 'icon',
        );
      }

      if (_coverImage != null) {
        coverUrl = await mediaService.uploadCircleImage(
          filePath: _coverImage!.path,
          circleId: circleId,
          imageType: 'cover',
        );
      }

      // 画像 URLを更新
      if (iconUrl != null || coverUrl != null) {
        await circleService.updateCircle(circleId, {
          if (iconUrl != null) 'iconImageUrl': iconUrl,
          if (coverUrl != null) 'coverImageUrl': coverUrl,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('サークルを作成しました！🎉')));
        context.pop();
        context.push('/circle/$circleId');
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
    // CircleServiceからカテゴリを取得（「全て」を除く）
    final categories = CircleService.categories
        .where((c) => c != '全て')
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('サークルを作成'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // アイコン・ヘッダー画像
              _buildSection(
                title: 'サークル画像（任意）',
                subtitle: 'アイコンとヘッダーをカスタマイズ',
                child: Row(
                  children: [
                    // アイコン
                    Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: () => _pickImage(isIcon: true),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[200],
                                  border: Border.all(color: Colors.grey[300]!),
                                  image: _iconImage != null
                                      ? DecorationImage(
                                          image: FileImage(_iconImage!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _iconImage == null
                                    ? Icon(
                                        Icons.camera_alt,
                                        color: Colors.grey[400],
                                      )
                                    : null,
                              ),
                            ),
                            if (_iconImage != null)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _iconImage = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'アイコン',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // ヘッダー
                    Expanded(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: () => _pickImage(isIcon: false),
                                child: Container(
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey[200],
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                    image: _coverImage != null
                                        ? DecorationImage(
                                            image: FileImage(_coverImage!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _coverImage == null
                                      ? Center(
                                          child: Icon(
                                            Icons.panorama,
                                            color: Colors.grey[400],
                                            size: 32,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              if (_coverImage != null)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _coverImage = null),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ヘッダー',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // サークル名
              _buildSection(
                title: 'サークル名',
                child: TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration(hintText: '例：朝活チャレンジ'),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'サークル名を入力してください' : null,
                ),
              ),

              // 説明
              _buildSection(
                title: '説明',
                child: TextFormField(
                  controller: _descriptionController,
                  decoration: _inputDecoration(hintText: 'どのような活動をするサークルですか？'),
                  maxLines: 3,
                  validator: (value) =>
                      value?.isEmpty ?? true ? '説明を入力してください' : null,
                ),
              ),

              // 目標
              _buildSection(
                title: '共通の目標（任意）',
                child: TextFormField(
                  controller: _goalController,
                  decoration: _inputDecoration(hintText: '例：毎日1回投稿する'),
                  // バリデーションなし（任意）
                ),
              ),

              // カテゴリ
              _buildSection(
                title: 'カテゴリ',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      items: categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCategory = val!),
                    ),
                  ),
                ),
              ),

              // AIモード
              _buildSection(
                title: 'AI参加モード',
                subtitle: _getAIModeDescription(),
                child: SegmentedButton<CircleAIMode>(
                  segments: const [
                    ButtonSegment(
                      value: CircleAIMode.aiOnly,
                      label: Text('AIのみ'),
                      icon: Icon(Icons.smart_toy, size: 18),
                    ),
                    ButtonSegment(
                      value: CircleAIMode.mix,
                      label: Text('ミックス'),
                      icon: Icon(Icons.people_alt, size: 18),
                    ),
                    ButtonSegment(
                      value: CircleAIMode.humanOnly,
                      label: Text('人間のみ'),
                      icon: Icon(Icons.person, size: 18),
                    ),
                  ],
                  selected: {_aiMode},
                  onSelectionChanged: (Set<CircleAIMode> newSelection) {
                    setState(() {
                      _aiMode = newSelection.first;
                      // AIモード選択時は自動で非公開に
                      if (_aiMode == CircleAIMode.aiOnly) {
                        _isPublic = false;
                      }
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primary.withOpacity(0.1);
                      }
                      return Colors.white;
                    }),
                  ),
                ),
              ),

              // 公開設定
              // 公開設定（AIモード時は非表示・自動で非公開）
              if (_aiMode != CircleAIMode.aiOnly)
                _buildSection(
                  title: '公開設定',
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildRadioTile(
                          title: '公開',
                          subtitle: '誰でも参加できます',
                          value: true,
                          groupValue: _isPublic,
                          onChanged: (val) => setState(() => _isPublic = val!),
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildRadioTile(
                          title: '招待制',
                          subtitle: '参加には管理者の承認が必要です',
                          value: false,
                          groupValue: _isPublic,
                          onChanged: (val) => setState(() => _isPublic = val!),
                        ),
                      ],
                    ),
                  ),
                ),

              // サークルルール（任意）
              _buildSection(
                title: 'サークルルール（任意）',
                subtitle: 'メンバーに守ってほしいルールがあれば記載してください',
                child: TextFormField(
                  controller: _rulesController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: '例：みんなで励まし合って楽しく頑張りましょう🎉',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 作成ボタン
              ElevatedButton(
                onPressed: _isLoading ? null : _createCircle,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
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
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline),
                          SizedBox(width: 8),
                          Text(
                            'サークルを作成',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String _getAIModeDescription() {
    switch (_aiMode) {
      case CircleAIMode.aiOnly:
        return 'あなた専用のAIパートナーたちがサポートします';
      case CircleAIMode.mix:
        return '人間とAIが協力して目標を目指します';
      case CircleAIMode.humanOnly:
        return '人間同士で励まし合います';
    }
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required bool value,
    required bool groupValue,
    required ValueChanged<bool?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : Colors.grey[400],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
