import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/admin_document_model.dart';

class AdminDocumentsService {
  AdminDocumentsService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _documents =>
      _firestore.collection('documents');

  Future<List<AdminDocumentModel>> getDocuments(String studentId) async {
    final snapshot = await _documents
        .where('entityType', isEqualTo: 'student')
        .where('entityId', isEqualTo: studentId)
        .get();
    return snapshot.docs
        .map((doc) => AdminDocumentModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<AdminDocumentModel?> uploadDocument({
    required String studentId,
    required String documentType,
  }) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final fileName = picked.name;
    final ref = _storage.ref().child(
          'documents/students/$studentId/${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
    final snap = await ref.putFile(File(picked.path));
    final url = await snap.ref.getDownloadURL();
    final doc = _documents.doc();
    await doc.set({
      'entityType': 'student',
      'entityId': studentId,
      'documentType': documentType,
      'fileUrl': url,
      'fileName': fileName,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    return AdminDocumentModel(
      id: doc.id,
      entityType: 'student',
      entityId: studentId,
      documentType: documentType,
      fileUrl: url,
      fileName: fileName,
      uploadedAt: null,
    );
  }

  Future<void> deleteDocument(String documentId) async {
    await _documents.doc(documentId).delete();
  }
}
