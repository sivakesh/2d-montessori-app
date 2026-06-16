import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/admin_student_model.dart';

class AdminStudentService {
  AdminStudentService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _classes =>
      _firestore.collection('classes');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudents() async {
    final snapshot = await _students.orderBy('createdAt', descending: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getClasses() async {
    final snapshot = await _classes.where('isActive', isEqualTo: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> searchParentUsers(
    String query,
  ) async {
    final snapshot = await _users.where('role', isEqualTo: 'parent').get();
    final lowerQuery = query.trim().toLowerCase();
    return snapshot.docs.where((doc) {
      if (lowerQuery.isEmpty) return true;
      final data = doc.data();
      final name = data['name']?.toString().toLowerCase() ?? '';
      final phone = data['phone']?.toString().toLowerCase() ?? '';
      return name.contains(lowerQuery) || phone.contains(lowerQuery);
    }).toList();
  }

  Future<bool> isAdmissionNoTaken(String admissionNo, {String? ignoreId}) async {
    final snapshot = await _students.where('admissionNo', isEqualTo: admissionNo).get();
    return snapshot.docs.any((doc) => doc.id != ignoreId);
  }

  Future<String> createStudent({
    required AdminStudentModel student,
    required String createdBy,
  }) async {
    final doc = _students.doc();
    await doc.set({
      ...student.toMap(),
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateStudent({
    required String studentId,
    required AdminStudentModel student,
  }) async {
    await _students.doc(studentId).set({
      ...student.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteStudent(String studentId) async {
    await _students.doc(studentId).delete();
  }

  Future<void> linkParentToStudent({
    required String studentId,
    required Map<String, dynamic> parentData,
  }) async {
    await _students.doc(studentId).set({
      'parentLinks': FieldValue.arrayUnion([
        {
          'userId': parentData['userId'],
          'relation': parentData['relation'],
          'name': parentData['name'],
        },
      ]),
    }, SetOptions(merge: true));
  }

  Future<void> removeParentLink({
    required String studentId,
    required String userId,
  }) async {
    final snapshot = await _students.doc(studentId).get();
    final links = (snapshot.data()?['parentLinks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    links.removeWhere((link) => link['userId']?.toString() == userId);
    await _students.doc(studentId).set({
      'parentLinks': links,
    }, SetOptions(merge: true));
  }

  Future<void> uploadStudentDocument({
    required String studentId,
    required String documentName,
  }) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final isImage = picked.mimeType?.startsWith('image/') ?? false;
    final extension = isImage ? 'jpg' : 'pdf';
    final ref = _storage.ref().child(
          'students/$studentId/${DateTime.now().millisecondsSinceEpoch}.$extension',
        );
    final Uint8List bytes = await picked.readAsBytes();
    final snap = await ref.putData(bytes);
    final url = await snap.ref.getDownloadURL();

    await _students.doc(studentId).set({
      'documents': FieldValue.arrayUnion([
        {
          'name': documentName,
          'url': url,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      ]),
    }, SetOptions(merge: true));
  }

  Future<void> removeStudentDocument({
    required String studentId,
    required String documentUrl,
  }) async {
    final snapshot = await _students.doc(studentId).get();
    final docs = (snapshot.data()?['documents'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    docs.removeWhere((doc) => doc['url']?.toString() == documentUrl);
    await _students.doc(studentId).set({
      'documents': docs,
    }, SetOptions(merge: true));
  }

  Future<void> seedSampleStudents() async {
    final classes = await getClasses();
    if (classes.isEmpty) return;

    final existing = await _students.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final seeds = [
      ('Aarav Sharma', 'ADM-001', 'Male'),
      ('Ananya Patel', 'ADM-002', 'Female'),
      ('Ishaan Verma', 'ADM-003', 'Male'),
    ];

    for (var i = 0; i < seeds.length; i++) {
      final seed = seeds[i];
      final student = AdminStudentModel(
        id: '',
        name: seed.$1,
        admissionNo: seed.$2,
        classId: classes[i % classes.length].id,
        dateOfBirth: '',
        gender: seed.$3,
        isActive: true,
        isApproved: true,
        createdAt: null,
        createdBy: null,
        parentLinks: const [],
        documents: const [],
      );
      await createStudent(student: student, createdBy: 'seed');
    }
  }
}
