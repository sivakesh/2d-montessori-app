class AdminClassModel {
  AdminClassModel({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory AdminClassModel.fromMap(String id, Map<String, dynamic> data) {
    return AdminClassModel(
      id: id,
      name: data['name']?.toString() ?? '',
    );
  }
}
