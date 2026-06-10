import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/document_model.dart';
import '../../attendance/data/attendance_service.dart';

class DocumentService {
  DocumentService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _documents =>
      _firestore.collection('documents');

  Future<DocumentModel?> uploadDocument({
    required String entityType,
    required String entityId,
    required String documentType,
    required String uploadedBy,
  }) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final fileName = picked.name;
    final file = File(picked.path);
    final url = await AttendanceService(
      firestore: _firestore,
      storage: _storage,
      imagePicker: _imagePicker,
    ).uploadImage(
      image: file,
      path: 'documents/$entityType/$entityId/$fileName',
    );
    final docRef = _documents.doc();
    await docRef.set({
      'id': docRef.id,
      'entityType': entityType,
      'entityId': entityId,
      'documentType': documentType,
      'fileName': fileName,
      'fileUrl': url,
      'uploadedBy': uploadedBy,
      'uploadedAt': FieldValue.serverTimestamp(),
      'verified': false,
    });
    return DocumentModel(
      id: docRef.id,
      entityType: entityType,
      entityId: entityId,
      documentType: documentType,
      fileName: fileName,
      fileUrl: url,
      uploadedBy: uploadedBy,
      verified: false,
    );
  }

  Future<List<DocumentModel>> getDocuments({
    required String entityType,
    required String entityId,
  }) async {
    final snapshot = await _documents
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .get();
    return snapshot.docs
        .map((doc) => DocumentModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> deleteDocument(String documentId) async {
    await _documents.doc(documentId).delete();
  }
}
