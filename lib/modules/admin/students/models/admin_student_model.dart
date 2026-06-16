import 'package:cloud_firestore/cloud_firestore.dart';

class AdminStudentParentLink {
  AdminStudentParentLink({
    required this.userId,
    required this.name,
    required this.email,
    required this.relation,
  });

  final String userId;
  final String name;
  final String email;
  final String relation;

  factory AdminStudentParentLink.fromMap(Map<String, dynamic> data) {
    return AdminStudentParentLink(
      userId: data['userId']?.toString() ?? data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      relation: data['relation']?.toString() ?? 'Father',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'relation': relation,
    };
  }
}

class AdminStudentDocument {
  AdminStudentDocument({
    required this.name,
    required this.fileName,
    required this.url,
    this.uploadedAt,
  });

  final String name;
  final String fileName;
  final String url;
  final DateTime? uploadedAt;

  factory AdminStudentDocument.fromMap(Map<String, dynamic> data) {
    final rawUploadedAt = data['uploadedAt'];
    return AdminStudentDocument(
      name: data['name']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? '',
      url: data['url']?.toString() ?? '',
      uploadedAt: rawUploadedAt is Timestamp
          ? rawUploadedAt.toDate()
          : rawUploadedAt is DateTime
              ? rawUploadedAt
              : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'fileName': fileName,
      'url': url,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : FieldValue.serverTimestamp(),
    };
  }
}

class AdminStudentModel {
  AdminStudentModel({
    required this.id,
    required this.name,
    required this.admissionNo,
    required this.classId,
    required this.dateOfBirth,
    required this.gender,
    required this.isActive,
    required this.isApproved,
    required this.createdAt,
    required this.createdBy,
    required this.parentLinks,
    required this.documents,
    this.profileImageUrl = '',
  });

  final String id;
  final String name;
  final String admissionNo;
  final String classId;
  final dynamic dateOfBirth;
  final String gender;
  final bool isActive;
  final bool isApproved;
  final DateTime? createdAt;
  final String? createdBy;
  final List<AdminStudentParentLink> parentLinks;
  final List<AdminStudentDocument> documents;
  final String profileImageUrl;

  factory AdminStudentModel.fromMap(String id, Map<String, dynamic> data) {
    final rawDate = data['dateOfBirth'];
    final createdAt = data['createdAt'];
    return AdminStudentModel(
      id: id,
      name: data['name']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      dateOfBirth: rawDate,
      gender: data['gender']?.toString() ?? '',
      isActive: data['isActive'] == true,
      isApproved: data['isApproved'] == true,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : createdAt is DateTime
              ? createdAt
              : null,
      createdBy: data['createdBy']?.toString(),
      profileImageUrl: data['profileImageUrl']?.toString() ?? '',
      parentLinks: (data['parentLinks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AdminStudentParentLink.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      documents: (data['documents'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => AdminStudentDocument.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'admissionNo': admissionNo,
      'classId': classId,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
      'isActive': isActive,
      'isApproved': isApproved,
      'createdBy': createdBy,
      'profileImageUrl': profileImageUrl,
      'parentLinks': parentLinks.map((e) => e.toMap()).toList(),
      'documents': documents.map((e) => e.toMap()).toList(),
    };
  }
}
