import 'package:cloud_firestore/cloud_firestore.dart';

class AdminClassModel {
  AdminClassModel({
    required this.id,
    required this.name,
    required this.section,
    required this.academicYear,
    required this.capacity,
    required this.teacherId,
    required this.teacherName,
    required this.description,
    required this.isActive,
    required this.approvalStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String section;
  final String academicYear;
  final int? capacity;
  final String teacherId;
  final String teacherName;
  final String description;
  final bool isActive;
  final String approvalStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;

  factory AdminClassModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return AdminClassModel(
      id: id,
      name: data['name']?.toString() ?? '',
      section: data['section']?.toString() ?? '',
      academicYear: data['academicYear']?.toString() ?? '',
      capacity: int.tryParse(data['capacity']?.toString() ?? ''),
      teacherId: data['teacherId']?.toString() ?? '',
      teacherName: data['teacherName']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      isActive: data['isActive'] != false,
      approvalStatus: data['approvalStatus']?.toString() ??
          (data['isApproved'] == true ? 'Approved' : 'Pending Approval'),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'section': section,
      'academicYear': academicYear,
      'capacity': capacity,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'description': description,
      'isActive': isActive,
      'approvalStatus': approvalStatus,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
    };
  }
}
