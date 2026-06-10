class AdminStudentModel {
  AdminStudentModel({
    required this.id,
    required this.name,
    required this.admissionNo,
    required this.classId,
    required this.gender,
    required this.dateOfBirth,
    required this.bloodGroup,
    required this.fatherName,
    required this.motherName,
    required this.phone,
    required this.address,
    required this.profileImage,
    required this.isActive,
    required this.isApproved,
  });

  final String id;
  final String name;
  final String admissionNo;
  final String classId;
  final String gender;
  final String dateOfBirth;
  final String bloodGroup;
  final String fatherName;
  final String motherName;
  final String phone;
  final String address;
  final String profileImage;
  final bool isActive;
  final bool isApproved;

  factory AdminStudentModel.fromMap(String id, Map<String, dynamic> data) {
    return AdminStudentModel(
      id: id,
      name: data['name']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      gender: data['gender']?.toString() ?? '',
      dateOfBirth: data['dateOfBirth']?.toString() ?? '',
      bloodGroup: data['bloodGroup']?.toString() ?? '',
      fatherName: data['fatherName']?.toString() ?? '',
      motherName: data['motherName']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      profileImage: data['profileImage']?.toString() ?? '',
      isActive: data['isActive'] == true,
      isApproved: data['isApproved'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'admissionNo': admissionNo,
      'classId': classId,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'bloodGroup': bloodGroup,
      'fatherName': fatherName,
      'motherName': motherName,
      'phone': phone,
      'address': address,
      'profileImage': profileImage,
      'isActive': isActive,
      'isApproved': isApproved,
    };
  }
}
