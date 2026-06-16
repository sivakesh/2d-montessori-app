import 'package:cloud_firestore/cloud_firestore.dart';

class AdminSchoolDocument {
  AdminSchoolDocument({
    required this.id,
    required this.title,
    required this.documentType,
    required this.category,
    required this.fileName,
    required this.fileUrl,
    required this.fileSize,
    required this.mimeType,
    required this.academicYear,
    required this.appliesToAllClasses,
    required this.applicableClassIds,
    required this.applicableClassNames,
    required this.visibility,
    required this.status,
    required this.issueDate,
    required this.expiryDate,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.description,
    required this.tags,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String documentType;
  final String category;
  final String fileName;
  final String fileUrl;
  final int? fileSize;
  final String mimeType;
  final String academicYear;
  final bool appliesToAllClasses;
  final List<String> applicableClassIds;
  final List<String> applicableClassNames;
  final String visibility;
  final String status;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String uploadedBy;
  final String uploadedByName;
  final String description;
  final List<String> tags;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminSchoolDocument.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      return null;
    }

    List<String> parseList(dynamic value) =>
        (value as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

    return AdminSchoolDocument(
      id: id,
      title: data['title']?.toString() ?? '',
      documentType: data['documentType']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? '',
      fileUrl: data['fileUrl']?.toString() ?? '',
      fileSize: int.tryParse(data['fileSize']?.toString() ?? ''),
      mimeType: data['mimeType']?.toString() ?? '',
      academicYear: data['academicYear']?.toString() ?? '',
      appliesToAllClasses: data['appliesToAllClasses'] == true,
      applicableClassIds: parseList(data['applicableClassIds']),
      applicableClassNames: parseList(data['applicableClassNames']),
      visibility: data['visibility']?.toString() ?? 'Admin Only',
      status: data['status']?.toString() ?? 'Draft',
      issueDate: parseDate(data['issueDate']),
      expiryDate: parseDate(data['expiryDate']),
      uploadedBy: data['uploadedBy']?.toString() ?? '',
      uploadedByName: data['uploadedByName']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      tags: parseList(data['tags']),
      isActive: data['isActive'] != false,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'documentType': documentType,
      'category': category,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'academicYear': academicYear,
      'appliesToAllClasses': appliesToAllClasses,
      'applicableClassIds': applicableClassIds,
      'applicableClassNames': applicableClassNames,
      'visibility': visibility,
      'status': status,
      'issueDate': issueDate,
      'expiryDate': expiryDate,
      'uploadedBy': uploadedBy,
      'uploadedByName': uploadedByName,
      'description': description,
      'tags': tags,
      'isActive': isActive,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  AdminSchoolDocument copyWith({
    String? title,
    String? documentType,
    String? category,
    String? fileName,
    String? fileUrl,
    int? fileSize,
    String? mimeType,
    String? academicYear,
    bool? appliesToAllClasses,
    List<String>? applicableClassIds,
    List<String>? applicableClassNames,
    String? visibility,
    String? status,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? uploadedBy,
    String? uploadedByName,
    String? description,
    List<String>? tags,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdminSchoolDocument(
      id: id,
      title: title ?? this.title,
      documentType: documentType ?? this.documentType,
      category: category ?? this.category,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      academicYear: academicYear ?? this.academicYear,
      appliesToAllClasses: appliesToAllClasses ?? this.appliesToAllClasses,
      applicableClassIds: applicableClassIds ?? this.applicableClassIds,
      applicableClassNames: applicableClassNames ?? this.applicableClassNames,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedByName: uploadedByName ?? this.uploadedByName,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
