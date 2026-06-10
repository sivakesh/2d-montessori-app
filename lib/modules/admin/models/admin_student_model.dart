class AdminStudentModel {
  AdminStudentModel({
    required this.id,
    required this.name,
    required this.classId,
    required this.isActive,
    this.profileImage,
  });

  final String id;
  final String name;
  final String classId;
  final bool isActive;
  final String? profileImage;

  factory AdminStudentModel.fromMap(String id, Map<String, dynamic> data) {
    return AdminStudentModel(
      id: id,
      name: data['name']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      isActive: data['isActive'] == true,
      profileImage: data['profileImage']?.toString(),
    );
  }
}
