import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import '../models/admin_school_document.dart';
import '../../../../modules/documents/models/document_model.dart';

class AdminDocumentsService {
  AdminDocumentsService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FilePicker? filePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _filePicker = filePicker ?? FilePicker.platform;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FilePicker _filePicker;

  CollectionReference<Map<String, dynamic>> get _documents =>
      _firestore.collection('school_documents');

  CollectionReference<Map<String, dynamic>> get _legacyDocuments =>
      _firestore.collection('documents');

  Future<List<AdminSchoolDocument>> getSchoolDocuments() async {
    final snapshot = await _documents.orderBy('createdAt', descending: true).get();
    return snapshot.docs
        .map((doc) => AdminSchoolDocument.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<PlatformFile?> pickFile() async {
    final result = await _filePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  Future<Map<String, dynamic>?> uploadDocumentFile({
    required String documentId,
    required PlatformFile file,
  }) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('File bytes were not available for upload');
    }
    final safeName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final ref = _storage.ref().child('school_documents/$documentId/$safeName');
    final snapshot = await ref.putData(bytes);
    final url = await snapshot.ref.getDownloadURL();
    return {
      'fileUrl': url,
      'fileName': safeName,
      'fileSize': file.size,
      'mimeType': file.extension ?? '',
    };
  }

  Future<List<DocumentModel>> getDocuments(String studentId) async {
    final snapshot = await _legacyDocuments
        .where('entityType', isEqualTo: 'student')
        .where('entityId', isEqualTo: studentId)
        .get();
    return snapshot.docs.map((doc) => DocumentModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<DocumentModel?> uploadDocument({
    required String studentId,
    required String documentType,
  }) async {
    final result = await _filePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    final ref = _storage.ref().child(
      'documents/students/$studentId/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
    );
    final snap = await ref.putData(bytes);
    final url = await snap.ref.getDownloadURL();
    final doc = _legacyDocuments.doc();
    await doc.set({
      'entityType': 'student',
      'entityId': studentId,
      'documentType': documentType,
      'fileUrl': url,
      'fileName': file.name,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    return DocumentModel.fromMap(doc.id, {
      'entityType': 'student',
      'entityId': studentId,
      'documentType': documentType,
      'fileUrl': url,
      'fileName': file.name,
    });
  }

  Future<String> createDocument(Map<String, dynamic> data) async {
    final doc = _documents.doc();
    await doc.set(data);
    return doc.id;
  }

  Future<void> updateDocument(String documentId, Map<String, dynamic> data) async {
    await _documents.doc(documentId).set(data, SetOptions(merge: true));
  }

  Future<void> deleteDocument(String documentId, {String? fileUrl}) async {
    if (fileUrl != null && fileUrl.isNotEmpty) {
      try {
        final ref = _storage.refFromURL(fileUrl);
        await ref.delete();
      } catch (_) {}
    }
    await _documents.doc(documentId).delete();
  }

  Future<void> seedSampleDocuments() async {
    final existing = await _documents.get();
    final titles = existing.docs
        .map((d) => d.data()['title']?.toString().trim().toLowerCase() ?? '')
        .toSet();

    final samples = <Map<String, dynamic>>[
      {'title': 'Holiday List 2026-2027', 'documentType': 'Holiday List', 'category': 'General', 'appliesToAllClasses': true},
      {'title': 'Parent Handbook', 'documentType': 'Policy', 'category': 'Parent Communication', 'appliesToAllClasses': true},
      {'title': 'Fee Structure 2026-2027', 'documentType': 'Fee Structure', 'category': 'Finance', 'appliesToAllClasses': false},
      {'title': 'Academic Calendar 2026-2027', 'documentType': 'Academic Calendar', 'category': 'Academic', 'appliesToAllClasses': true},
      {'title': 'Safety Policy', 'documentType': 'Government Compliance', 'category': 'Safety', 'appliesToAllClasses': false},
    ];

    for (final sample in samples) {
      final key = sample['title'].toString().trim().toLowerCase();
      if (titles.contains(key)) continue;
      await _documents.add({
        ...sample,
        'fileName': '',
        'fileUrl': '',
        'fileSize': null,
        'mimeType': '',
        'academicYear': '2026-2027',
        'appliesToAllClasses': sample['appliesToAllClasses'] == true,
        'applicableClassIds': sample['appliesToAllClasses'] == true ? const [] : ['class-mont1'],
        'applicableClassNames': sample['appliesToAllClasses'] == true ? const [] : ['Mont 1'],
        'visibility': 'Parents',
        'status': 'Published',
        'description': '',
        'tags': const [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'uploadedBy': 'seed',
        'uploadedByName': 'System',
      });
    }
  }
}
