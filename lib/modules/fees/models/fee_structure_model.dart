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
    required this.academicYearId,
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

  /// Legacy free-text year label, kept for backward compatibility during
  /// the FEES-AY-IMPLEMENT-01 additive migration — see [academicYearId]'s
  /// doc comment for which one is authoritative.
  final String academicYear;

  /// Canonical FK to `AcademicYearModel.id`. Empty (`''`) means this
  /// FeeStructure predates this field (a legacy document) or hasn't been
  /// re-saved since. Never invented on read — a legacy document with no
  /// `academicYearId` in Firestore loads with this as `''`, not a
  /// guessed/matched id; matching only ever happens in UI resolution code,
  /// never silently inside this model. Whenever non-empty, this — not
  /// [academicYear] — is the authoritative relationship.
  final String academicYearId;
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
      academicYearId: data['academicYearId']?.toString() ?? '',
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
        'academicYearId': academicYearId,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };
}
