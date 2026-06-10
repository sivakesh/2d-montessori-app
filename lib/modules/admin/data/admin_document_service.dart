import '../../documents/data/document_service.dart';

class AdminDocumentService extends DocumentService {
  AdminDocumentService({
    super.firestore,
    super.storage,
    super.imagePicker,
  });
}
