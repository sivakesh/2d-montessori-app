class AdminDocumentModel {
  AdminDocumentModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.documentType,
    required this.fileName,
    required this.fileUrl,
    required this.uploadedBy,
    required this.verified,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String documentType;
  final String fileName;
  final String fileUrl;
  final String uploadedBy;
  final bool verified;
}
