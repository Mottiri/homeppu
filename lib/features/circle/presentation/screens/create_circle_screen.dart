import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/providers/auth_provider.dart';

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

  String _selectedCategory = 'その他';
  CircleAIMode _aiMode = CircleAIMode.mix;
  bool _isPublic = true;
  bool _isLoading = false;

  final List<String> _categories = ['学習', '仕事', '健康', '趣味', '生活', 'その他'];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _createCircle() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('circles').doc();

      final circle = CircleModel(
        id: docRef.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        ownerId: currentUser.uid,
        memberIds: [currentUser.uid],
        aiMode: _aiMode,
        isPublic: _isPublic,
        createdAt: DateTime.now(),
        goal: _goalController.text.trim(),
      );

      await docRef.set(circle.toFirestore());

      if (mounted) {
        context.pop(); // Close screen
        context.push('/circle/${circle.id}'); // Navigate to new circle
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('サークルを作成'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
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
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'サークル名',
                      hintText: '例：朝活チャレンジ',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'サークル名を入力してください' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: '説明',
                      hintText: 'どのような活動をするサークルですか？',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLines: 3,
                    validator: (value) =>
                        value?.isEmpty ?? true ? '説明を入力してください' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _goalController,
                    decoration: InputDecoration(
                      labelText: '共通の目標',
                      hintText: '例：毎日1回投稿する',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? '目標を入力してください' : null,
                  ),
                  const SizedBox(height: 24),

                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'カテゴリー',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedCategory = val!),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'AI参加モード',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<CircleAIMode>(
                    segments: const [
                      ButtonSegment(
                        value: CircleAIMode.aiOnly,
                        label: Text('AIのみ'),
                        icon: Icon(Icons.smart_toy),
                      ),
                      ButtonSegment(
                        value: CircleAIMode.mix,
                        label: Text('ミックス'),
                        icon: Icon(Icons.people_alt),
                      ),
                      ButtonSegment(
                        value: CircleAIMode.humanOnly,
                        label: Text('人間のみ'),
                        icon: Icon(Icons.person),
                      ),
                    ],
                    selected: {_aiMode},
                    onSelectionChanged: (Set<CircleAIMode> newSelection) {
                      setState(() {
                        _aiMode = newSelection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _aiMode == CircleAIMode.aiOnly
                        ? 'あなた専用のAIパートナーたちがサポートします'
                        : _aiMode == CircleAIMode.mix
                        ? '人間とAIが協力して目標を目指します'
                        : '人間同士で励まし合います',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _createCircle,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'サークルを作成',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
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
