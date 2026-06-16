import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceCategoryModel {
  FinanceCategoryModel({
    required this.id,
    required this.name,
    required this.type,
    required this.parentId,
    required this.isSystem,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type;
  final String? parentId;
  final bool isSystem;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FinanceCategoryModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    return FinanceCategoryModel(
      id: id,
      name: data['name']?.toString() ?? '',
      type: data['type']?.toString() ?? 'income',
      parentId: data['parentId']?.toString(),
      isSystem: data['isSystem'] == true,
      isActive: data['isActive'] != false,
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type,
        'parentId': parentId,
        'isSystem': isSystem,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

