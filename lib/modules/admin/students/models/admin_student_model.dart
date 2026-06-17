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
    required this.type,
    required this.name,
    required this.fileName,
    required this.url,
    required this.storagePath,
    required this.uploadedBy,
    this.uploadedAt,
  });

  final String type;
  final String name;
  final String fileName;
  final String url;
  final String storagePath;
  final String uploadedBy;
  final DateTime? uploadedAt;

  factory AdminStudentDocument.fromMap(Map<String, dynamic> data) {
    final rawUploadedAt = data['uploadedAt'];
    return AdminStudentDocument(
      type: data['type']?.toString() ?? data['documentType']?.toString() ?? '',
      name: data['name']?.toString() ?? data['fileName']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? data['name']?.toString() ?? '',
      url: data['url']?.toString() ?? '',
      storagePath: data['storagePath']?.toString() ?? '',
      uploadedBy: data['uploadedBy']?.toString() ?? 'admin',
      uploadedAt: rawUploadedAt is Timestamp
          ? rawUploadedAt.toDate()
          : rawUploadedAt is DateTime
              ? rawUploadedAt
              : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'name': name,
      'fileName': fileName,
      'url': url,
      'storagePath': storagePath,
      'uploadedBy': uploadedBy,
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
    required this.section,
    required this.rollNumber,
    required this.dateOfBirth,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.nationality,
    required this.motherTongue,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.pincode,
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
  final String section;
  final String rollNumber;
  final dynamic dateOfBirth;
  final int? age;
  final String gender;
  final String bloodGroup;
  final String nationality;
  final String motherTongue;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String pincode;
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
    final rawAge = data['age'];
    return AdminStudentModel(
      id: id,
      name: data['name']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      section: data['section']?.toString() ?? '',
      rollNumber: data['rollNumber']?.toString() ?? '',
      dateOfBirth: rawDate,
      age: rawAge is int
          ? rawAge
          : rawAge is num
              ? rawAge.toInt()
              : int.tryParse(rawAge?.toString() ?? ''),
      gender: data['gender']?.toString() ?? '',
      bloodGroup: data['bloodGroup']?.toString() ?? '',
      nationality: data['nationality']?.toString() ?? '',
      motherTongue: data['motherTongue']?.toString() ?? '',
      addressLine1: data['addressLine1']?.toString() ?? '',
      addressLine2: data['addressLine2']?.toString() ?? '',
      city: data['city']?.toString() ?? '',
      state: data['state']?.toString() ?? '',
      pincode: data['pincode']?.toString() ?? '',
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
      'section': section,
      'rollNumber': rollNumber,
      'dateOfBirth': dateOfBirth,
      'age': age,
      'gender': gender,
      'bloodGroup': bloodGroup,
      'nationality': nationality,
      'motherTongue': motherTongue,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'isActive': isActive,
      'isApproved': isApproved,
      'createdBy': createdBy,
      'profileImageUrl': profileImageUrl,
      'parentLinks': parentLinks.map((e) => e.toMap()).toList(),
      'documents': documents.map((e) => e.toMap()).toList(),
    };
  }
}
