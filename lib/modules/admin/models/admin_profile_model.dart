class AdminProfileStudentRef {
  const AdminProfileStudentRef({
    required this.studentId,
    required this.studentName,
    required this.classId,
  });

  final String studentId;
  final String studentName;
  final String classId;

  factory AdminProfileStudentRef.fromMap(Map<String, dynamic> map) {
    return AdminProfileStudentRef(
      studentId: map['studentId']?.toString() ?? '',
      studentName: map['studentName']?.toString() ?? '',
      classId: map['classId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'classId': classId,
      };
}

class AdminProfileDocumentRef {
  const AdminProfileDocumentRef({
    required this.documentId,
    required this.documentType,
    required this.fileUrl,
    this.fileName = '',
  });

  final String documentId;
  final String documentType;
  final String fileUrl;
  final String fileName;

  factory AdminProfileDocumentRef.fromMap(Map<String, dynamic> map) {
    return AdminProfileDocumentRef(
      documentId: map['documentId']?.toString() ?? '',
      documentType: map['documentType']?.toString() ?? '',
      fileUrl: map['fileUrl']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'documentId': documentId,
        'documentType': documentType,
        'fileUrl': fileUrl,
        'fileName': fileName,
      };
}

class AdminProfileModel {
  AdminProfileModel({
    required this.userId,
    required this.fullName,
    required this.dateOfBirth,
    required this.gender,
    required this.bloodGroup,
    required this.phone,
    required this.alternatePhone,
    required this.email,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.country,
    required this.pincode,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.occupation,
    required this.nationality,
    required this.profileImageUrl,
    required this.students,
    required this.documents,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String fullName;
  final String dateOfBirth;
  final String gender;
  final String bloodGroup;
  final String phone;
  final String alternatePhone;
  final String email;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String country;
  final String pincode;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String occupation;
  final String nationality;
  final String profileImageUrl;
  final List<AdminProfileStudentRef> students;
  final List<AdminProfileDocumentRef> documents;
  final String createdAt;
  final String updatedAt;

  factory AdminProfileModel.fromMap(String userId, Map<String, dynamic> map) {
    return AdminProfileModel(
      userId: userId,
      fullName: map['fullName']?.toString() ?? '',
      dateOfBirth: map['dateOfBirth']?.toString() ?? '',
      gender: map['gender']?.toString() ?? '',
      bloodGroup: map['bloodGroup']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      alternatePhone: map['alternatePhone']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      addressLine1: map['addressLine1']?.toString() ?? '',
      addressLine2: map['addressLine2']?.toString() ?? '',
      city: map['city']?.toString() ?? '',
      state: map['state']?.toString() ?? '',
      country: map['country']?.toString() ?? '',
      pincode: map['pincode']?.toString() ?? '',
      emergencyContactName: map['emergencyContactName']?.toString() ?? '',
      emergencyContactPhone: map['emergencyContactPhone']?.toString() ?? '',
      occupation: map['occupation']?.toString() ?? '',
      nationality: map['nationality']?.toString() ?? '',
      profileImageUrl: map['profileImageUrl']?.toString() ?? '',
      students: (map['students'] as List<dynamic>? ?? [])
          .map((e) => AdminProfileStudentRef.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      documents: (map['documents'] as List<dynamic>? ?? [])
          .map((e) => AdminProfileDocumentRef.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: map['createdAt']?.toString() ?? '',
      updatedAt: map['updatedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'fullName': fullName,
        'dateOfBirth': dateOfBirth,
        'gender': gender,
        'bloodGroup': bloodGroup,
        'phone': phone,
        'alternatePhone': alternatePhone,
        'email': email,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'city': city,
        'state': state,
        'country': country,
        'pincode': pincode,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'occupation': occupation,
        'nationality': nationality,
        'profileImageUrl': profileImageUrl,
        'students': students.map((e) => e.toMap()).toList(),
        'documents': documents.map((e) => e.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
