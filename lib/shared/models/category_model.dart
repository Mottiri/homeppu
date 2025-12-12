import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryModel {
  final String id;
  final String userId;
  final String name;
  final int order;
  final DateTime createdAt;

  CategoryModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.order,
    required this.createdAt,
  });

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      order: data['order'] ?? 0,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : DateTime.parse(data['createdAt'].toString()))
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'order': order,
      'createdAt': createdAt,
    };
  }

  CategoryModel copyWith({
    String? id,
    String? userId,
    String? name,
    int? order,
    DateTime? createdAt,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
