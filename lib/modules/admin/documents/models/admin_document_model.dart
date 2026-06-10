class AdminDocumentModel {
  AdminDocumentModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.documentType,
    required this.fileUrl,
    required this.fileName,
    required this.uploadedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String documentType;
  final String fileUrl;
  final String fileName;
  final DateTime? uploadedAt;

  factory AdminDocumentModel.fromMap(String id, Map<String, dynamic> data) {
    return AdminDocumentModel(
      id: id,
      entityType: data['entityType']?.toString() ?? '',
      entityId: data['entityId']?.toString() ?? '',
      documentType: data['documentType']?.toString() ?? '',
      fileUrl: data['fileUrl']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? '',
      uploadedAt: null,
    );
  }
}
