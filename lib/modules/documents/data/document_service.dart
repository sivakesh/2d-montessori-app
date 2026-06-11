// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/document_model.dart';

class DocumentService {
  DocumentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _documents =>
      _firestore.collection('documents');

  Future<Map<String, dynamic>?> uploadDocument() async {
    try {
      final uploadInput = FileUploadInputElement();
      uploadInput.accept = '*/*';
      uploadInput.click();

      await uploadInput.onChange.first;

      final file = uploadInput.files?.first;
      if (file == null) return null;

      final reader = FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final data = reader.result as Uint8List;
      final fileName = file.name;

      final storageRef = FirebaseStorage.instance.ref().child(
        'documents/${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      final uploadTask = storageRef.putData(data);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return <String, dynamic>{'url': downloadUrl, 'name': fileName};
    } catch (e) {
      // ignore: avoid_print
      print('DOCUMENT UPLOAD ERROR: $e');
      return null;
    }
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
