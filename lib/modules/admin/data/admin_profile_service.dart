import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_profile_model.dart';

class AdminProfileService {
  AdminProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('profiles');
  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _documents =>
      _firestore.collection('documents');

  Stream<DocumentSnapshot<Map<String, dynamic>>> getProfile(String userId) {
    return _profiles.doc(userId).snapshots();
  }

  Future<AdminProfileModel?> fetchProfile(String userId) async {
    final doc = await _profiles.doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return AdminProfileModel.fromMap(doc.id, doc.data()!);
  }

  Future<void> upsertProfile(AdminProfileModel profile) async {
    await _profiles.doc(profile.userId).set(profile.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteProfile(String userId) async {
    await _profiles.doc(userId).delete();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllStudents() async {
    final snapshot = await _students.orderBy('name').get();
    return snapshot.docs;
  }

  Future<void> linkStudent({
    required String userId,
    required String studentId,
    required String studentName,
    required String classId,
  }) async {
    final doc = await _profiles.doc(userId).get();
    final profile = doc.data() ?? <String, dynamic>{};
    final students = List<Map<String, dynamic>>.from(profile['students'] as List<dynamic>? ?? const []);
    final updated = students.where((e) => e['studentId']?.toString() != studentId).toList();
    updated.add({
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
    });
    await _profiles.doc(userId).set({
      'userId': userId,
      'students': updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unlinkStudent({
    required String userId,
    required String studentId,
  }) async {
    final doc = await _profiles.doc(userId).get();
    final profile = doc.data() ?? <String, dynamic>{};
    final students = List<Map<String, dynamic>>.from(profile['students'] as List<dynamic>? ?? const []);
    students.removeWhere((e) => e['studentId']?.toString() == studentId);
    await _profiles.doc(userId).set({
      'userId': userId,
      'students': students,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> addDocumentReference({
    required String userId,
    required String documentType,
    required String fileUrl,
    String fileName = '',
  }) async {
    final doc = _documents.doc();
    await doc.set({
      'entityType': 'profile',
      'entityId': userId,
      'documentType': documentType,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    await _profiles.doc(userId).set({
      'userId': userId,
      'documents': FieldValue.arrayUnion([
        {
          'documentId': doc.id,
          'documentType': documentType,
          'fileUrl': fileUrl,
          'fileName': fileName,
        }
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return doc.id;
  }

  Future<void> deleteDocumentReference({
    required String userId,
    required String documentId,
  }) async {
    await _documents.doc(documentId).delete();
    final doc = await _profiles.doc(userId).get();
    final profile = doc.data() ?? <String, dynamic>{};
    final documents = List<Map<String, dynamic>>.from(profile['documents'] as List<dynamic>? ?? const []);
    documents.removeWhere((e) => e['documentId']?.toString() == documentId);
    await _profiles.doc(userId).set({
      'userId': userId,
      'documents': documents,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
