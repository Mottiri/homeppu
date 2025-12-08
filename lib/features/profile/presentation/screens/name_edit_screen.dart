import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/name_part_model.dart';
import '../../../../shared/services/name_parts_service.dart';
import '../../../../shared/providers/auth_provider.dart';

/// 名前編集画面
class NameEditScreen extends ConsumerStatefulWidget {
  const NameEditScreen({super.key});

  @override
  ConsumerState<NameEditScreen> createState() => _NameEditScreenState();
}

class _NameEditScreenState extends ConsumerState<NameEditScreen> {
  final _namePartsService = NamePartsService();
  
  bool _isLoading = true;
  String? _error;
  
  List<NamePartModel> _prefixes = [];
  List<NamePartModel> _suffixes = [];
  
  String? _selectedPrefixId;
  String? _selectedSuffixId;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNameParts();
  }

  Future<void> _loadNameParts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final result = await _namePartsService.getNameParts();
      
      setState(() {
        _prefixes = result.prefixes;
        _suffixes = result.suffixes;
        _selectedPrefixId = result.currentPrefixId;
        _selectedSuffixId = result.currentSuffixId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'パーツの読み込みに失敗しました';
        _isLoading = false;
      });
    }
  }

  String get _previewName {
    final prefix = _prefixes.firstWhere(
      (p) => p.id == _selectedPrefixId,
      orElse: () => NamePartModel(id: '', text: '???', category: '', rarity: 'normal', type: 'prefix', order: 0),
    );
    final suffix = _suffixes.firstWhere(
      (s) => s.id == _selectedSuffixId,
      orElse: () => NamePartModel(id: '', text: '???', category: '', rarity: 'normal', type: 'suffix', order: 0),
    );
    return '${prefix.text}${suffix.text}';
  }

  Future<void> _saveName() async {
    if (_selectedPrefixId == null || _selectedSuffixId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パーツを選択してください')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final result = await _namePartsService.updateUserName(
        prefixId: _selectedPrefixId!,
        suffixId: _selectedSuffixId!,
      );

      if (result.success) {
        // ユーザー情報を更新
        ref.invalidate(currentUserProvider);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message)),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '名前の変更に失敗しました';
        if (e.toString().contains('月1回まで')) {
          errorMessage = '名前の変更は月1回までです。来月まで待ってね！';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('名前を変更'),
        actions: [
          if (!_isLoading && _selectedPrefixId != null && _selectedSuffixId != null)
            TextButton(
              onPressed: _isSaving ? null : _saveName,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadNameParts,
                        child: const Text('再読み込み'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // プレビュー
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Column(
                        children: [
                          const Text(
                            'プレビュー',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _previewName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 注意事項
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.amber.withOpacity(0.2),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '名前の変更は月1回までです',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // パーツ選択
                    Expanded(
                      child: DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(
                              tabs: [
                                Tab(text: '前半（形容詞）'),
                                Tab(text: '後半（名詞）'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildPartsList(_prefixes, true),
                                  _buildPartsList(_suffixes, false),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPartsList(List<NamePartModel> parts, bool isPrefix) {
    // カテゴリでグループ化
    final Map<String, List<NamePartModel>> grouped = {};
    for (final part in parts) {
      grouped.putIfAbsent(part.category, () => []).add(part);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final category = grouped.keys.elementAt(index);
        final categoryParts = grouped[category]!;
        final firstPart = categoryParts.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                firstPart.categoryDisplayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categoryParts.map((part) {
                final isSelected = isPrefix
                    ? _selectedPrefixId == part.id
                    : _selectedSuffixId == part.id;
                final isLocked = !part.unlocked;

                return _buildPartChip(part, isSelected, isLocked, isPrefix);
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPartChip(NamePartModel part, bool isSelected, bool isLocked, bool isPrefix) {
    return GestureDetector(
      onTap: isLocked
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('「${part.text}」は${part.rarityDisplayName}パーツです。徳ポイントショップでアンロックできます。'),
                ),
              );
            }
          : () {
              setState(() {
                if (isPrefix) {
                  _selectedPrefixId = part.id;
                } else {
                  _selectedSuffixId = part.id;
                }
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : isLocked
                  ? Colors.grey[200]
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : part.rarity != 'normal'
                    ? Color(part.rarityColor)
                    : Colors.grey[300]!,
            width: part.rarity != 'normal' ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocked) ...[
              Icon(Icons.lock, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
            ],
            Text(
              part.text,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isLocked
                        ? Colors.grey[500]
                        : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (part.rarity != 'normal' && !isLocked) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(part.rarityColor).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  part.rarityDisplayName,
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(part.rarityColor),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

