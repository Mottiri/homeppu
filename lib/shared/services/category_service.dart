import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/category_model.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  // カテゴリ一覧取得
  Future<List<CategoryModel>> getCategories() async {
    debugPrint('[CategoryService] getCategories called, userId=$_userId');
    if (_userId == null) {
      debugPrint('[CategoryService] userId is null, returning empty list');
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('categories')
          .orderBy('order')
          .get();

      debugPrint(
        '[CategoryService] Got ${snapshot.docs.length} categories from Firestore',
      );

      final categories = snapshot.docs
          .map((doc) => CategoryModel.fromFirestore(doc))
          .toList();

      for (final cat in categories) {
        debugPrint(
          '[CategoryService] Category: ${cat.name} (id=${cat.id}, order=${cat.order})',
        );
      }

      return categories;
    } catch (e) {
      debugPrint('[CategoryService] Error fetching categories: $e');
      return [];
    }
  }

  // カテゴリ追加
  Future<CategoryModel?> addCategory(String name) async {
    debugPrint(
      '[CategoryService] addCategory called, name=$name, userId=$_userId',
    );
    if (_userId == null) {
      debugPrint('[CategoryService] userId is null, returning null');
      return null;
    }

    try {
      // 現在の最大orderを取得して、末尾に追加
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('categories')
          .orderBy('order', descending: true)
          .limit(1)
          .get();

      int nextOrder = 0;
      if (snapshot.docs.isNotEmpty) {
        nextOrder = (snapshot.docs.first.data()['order'] as int) + 1;
      }
      debugPrint('[CategoryService] Next order: $nextOrder');

      final newCategoryRef = _firestore
          .collection('users')
          .doc(_userId)
          .collection('categories')
          .doc();

      final category = CategoryModel(
        id: newCategoryRef.id,
        userId: _userId!,
        name: name,
        order: nextOrder,
        createdAt: DateTime.now(),
      );

      await newCategoryRef.set(category.toMap());
      debugPrint(
        '[CategoryService] Category created successfully: ${category.id}',
      );
      return category;
    } catch (e) {
      debugPrint('[CategoryService] Error adding category: $e');
      return null;
    }
  }

  // カテゴリ更新
  Future<void> updateCategory(String categoryId, String name) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('categories')
          .doc(categoryId)
          .update({'name': name});
    } catch (e) {
      debugPrint('Error updating category: $e');
      rethrow;
    }
  }

  // カテゴリ削除
  Future<void> deleteCategory(String categoryId) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('categories')
          .doc(categoryId)
          .delete();

      // Note: このカテゴリに属するタスクの処理はどうするか？
      // 現状はタスクの表示側で categoryId が見つからない場合は「タスク」タブに表示するなどのフォールバックが必要
    } catch (e) {
      debugPrint('Error deleting category: $e');
      rethrow;
    }
  }
}
