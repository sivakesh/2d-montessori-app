import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/admin_student_model.dart';

class AdminStudentsService {
  AdminStudentsService({
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

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudents() async {
    final snapshot = await _students.orderBy('createdAt', descending: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getClasses() async {
    final snapshot = await _classes.where('isActive', isEqualTo: true).get();
    return snapshot.docs;
  }

  Future<String?> uploadProfileImage(String studentId) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final ref = _storage.ref().child('students/$studentId.jpg');
    final uploadTask = ref.putFile(File(picked.path));
    final snap = await uploadTask;
    return snap.ref.getDownloadURL();
  }

  Future<void> addStudent(AdminStudentModel student) async {
    final doc = _students.doc();
    await doc.set({
      ...student.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
}
