class AppUser {
  final String id;
  final String phone;
  final String? name;
  final String role;
  final bool isActive;

  AppUser({
    required this.id,
    required this.phone,
    this.name,
    required this.role,
    required this.isActive,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> data) {
    return AppUser(
      id: id,
      phone: data['phone'] ?? '',
      name: data['name'],
      role: data['role'] ?? 'parent',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phone': phone,
      'name': name,
      'role': role,
      'isActive': isActive,
      'createdAt': DateTime.now(),
    };
  }
}
