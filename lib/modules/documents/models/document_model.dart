class DocumentModel {
  DocumentModel({
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

  factory DocumentModel.fromMap(String id, Map<String, dynamic> data) {
    return DocumentModel(
      id: id,
      entityType: data['entityType']?.toString() ?? '',
      entityId: data['entityId']?.toString() ?? '',
      documentType: data['documentType']?.toString() ?? '',
      fileName: data['fileName']?.toString() ?? '',
      fileUrl: data['fileUrl']?.toString() ?? '',
      uploadedBy: data['uploadedBy']?.toString() ?? '',
      verified: data['verified'] == true,
    );
  }
}
