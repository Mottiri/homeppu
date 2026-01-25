import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/services/inquiry_service.dart';
import '../../../../shared/services/media_service.dart';

/// 新規問い合わせフォーム画面
class InquiryFormScreen extends ConsumerStatefulWidget {
  const InquiryFormScreen({super.key});

  @override
  ConsumerState<InquiryFormScreen> createState() => _InquiryFormScreenState();
}

class _InquiryFormScreenState extends ConsumerState<InquiryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _contentController = TextEditingController();

  InquiryCategory _selectedCategory = InquiryCategory.other;
  File? _selectedImage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      String? imageUrl;

      // 画像をアップロード
      if (_selectedImage != null) {
        final mediaService = MediaService();
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId == null) {
          throw Exception(AppMessages.error.unauthorized);
        }
        imageUrl = await mediaService.uploadInquiryImage(
          _selectedImage!,
          userId: userId,
        );
      }

      // 問い合わせを作成
      final inquiryService = InquiryService();
      await inquiryService.createInquiry(
        category: _selectedCategory,
        subject: _subjectController.text.trim(),
        content: _contentController.text.trim(),
        imageUrl: imageUrl,
      );

      if (mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.success.inquirySent);
        context.pop();
      }
    } catch (e) {
      debugPrint('InquiryFormScreen submit failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.inquiry.formTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Text(AppMessages.inquiry.send),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // カテゴリ選択
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMessages.inquiry.categoryLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: InquiryCategory.values.map((category) {
                          final isSelected = _selectedCategory == category;
                          return ChoiceChip(
                            label: Text(category.label),
                            selected: isSelected,
                            showCheckmark: false, // チェックマークを非表示にして配置ズレを防止
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedCategory = category);
                              }
                            },
                            selectedColor: AppColors.primaryLight,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 件名
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMessages.inquiry.subjectLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _subjectController,
                        decoration: InputDecoration(
                          hintText: AppMessages.inquiry.subjectHint,
                        ),
                        maxLength: 100,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return AppMessages.inquiry.subjectRequired;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 内容
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMessages.inquiry.contentLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _contentController,
                        decoration: InputDecoration(
                          hintText: AppMessages.inquiry.contentHint,
                        ),
                        maxLines: 6,
                        maxLength: 1000,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return AppMessages.inquiry.contentRequired;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // スクリーンショット添付
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMessages.inquiry.screenshotOptional,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppMessages.inquiry.screenshotHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedImage != null)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _selectedImage!,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                onPressed: _removeImage,
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(AppMessages.inquiry.attachImage),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
