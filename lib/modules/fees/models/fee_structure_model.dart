import 'package:cloud_firestore/cloud_firestore.dart';
import 'fee_component_model.dart';

class FeeStructureModel {
  FeeStructureModel({
    required this.id,
    required this.name,
    required this.description,
    required this.components,
    required this.totalAmount,
    required this.academicYear,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String description;
  final List<FeeComponentModel> components;
  final double totalAmount;
  final String academicYear;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;

  factory FeeStructureModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic value) => value is Timestamp ? value.toDate() : value is DateTime ? value : null;
    final components = (data['components'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => FeeComponentModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return FeeStructureModel(
      id: id,
      name: data['name']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      components: components,
      totalAmount: double.tryParse(data['totalAmount']?.toString() ?? '') ?? 0,
      academicYear: data['academicYear']?.toString() ?? '',
      isActive: data['isActive'] != false,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'components': components.map((e) => e.toMap()).toList(),
        'totalAmount': totalAmount,
        'academicYear': academicYear,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };
}
