class AdminUserModel {
  AdminUserModel({
    required this.id,
    required this.phone,
    required this.role,
    required this.isActive,
    this.name,
  });

  final String id;
  final String phone;
  final String role;
  final bool isActive;
  final String? name;

  factory AdminUserModel.fromMap(String id, Map<String, dynamic> data) {
    return AdminUserModel(
      id: id,
      phone: data['phone']?.toString() ?? '',
      role: data['role']?.toString() ?? 'parent',
      isActive: data['isActive'] == true,
      name: data['name']?.toString(),
    );
  }
}
