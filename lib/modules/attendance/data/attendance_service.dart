import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class AttendanceService {
  AttendanceService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('attendance');

  String _dateKey() {
    final now = DateTime.now().toLocal();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _attendanceId(String date, String entityType, String entityId) =>
      '${date}_${entityType}_$entityId';

  Future<String?> captureAndUploadPhoto({
    required String entityType,
    required String entityId,
  }) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 800,
    );
    if (picked == null) return null;

    final date = _dateKey();
    final ref = _storage
        .ref()
        .child('attendance_photos')
        .child(entityType == 'student' ? 'students' : 'staff')
        .child(date)
        .child('$entityId.jpg');

    await ref.putFile(File(picked.path));
    return ref.getDownloadURL();
  }

  Future<bool> hasAttendanceForDate({
    required String entityType,
    required String entityId,
    required String date,
  }) async {
    final id = _attendanceId(date, entityType, entityId);
    final doc = await _attendance.doc(id).get();
    return doc.exists;
  }

  Future<void> _markAttendance({
    required String entityType,
    required String entityId,
    required String entityName,
    required String classId,
    required String markedBy,
    required String photoUrl,
  }) async {
    final date = _dateKey();
    final id = _attendanceId(date, entityType, entityId);
    final docRef = _attendance.doc(id);
    final existing = await docRef.get();
    if (existing.exists) {
      throw StateError('Attendance already marked for today.');
    }

    await docRef.set({
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId,
      'date': date,
      'photoUrl': photoUrl,
      'markedBy': markedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAttendance({
    required String userId,
    required String name,
    required String role,
  }) async {
    final date = _dateKey();
    final entityType = role == 'staff' ? 'staff' : 'student';
    final id = _attendanceId(date, entityType, userId);
    final docRef = _attendance.doc(id);
    final existing = await docRef.get();
    if (existing.exists) {
      throw StateError('Attendance already marked today.');
    }

    await docRef.set({
      'entityType': entityType,
      'entityId': userId,
      'entityName': name,
      'classId': '',
      'date': date,
      'photoUrl': '',
      'markedBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'present',
      'name': name,
      'role': role,
    });
  }

  Future<bool> hasMarkedToday(String userId) async {
    final date = _dateKey();
    final staffDoc = await _attendance.doc(_attendanceId(date, 'staff', userId)).get();
    final studentDoc = await _attendance.doc(_attendanceId(date, 'student', userId)).get();
    return staffDoc.exists || studentDoc.exists;
  }

  Future<void> markStudentAttendance({
    required String studentId,
    required String studentName,
    required String classId,
    required String markedBy,
    String? photoUrl,
  }) async {
    photoUrl ??= await captureAndUploadPhoto(
      entityType: 'student',
      entityId: studentId,
    );
    if (photoUrl == null) {
      throw StateError('Photo is required.');
    }
    await _markAttendance(
      entityType: 'student',
      entityId: studentId,
      entityName: studentName,
      classId: classId,
      markedBy: markedBy,
      photoUrl: photoUrl,
    );
  }

  Future<void> markStaffAttendance({
    required String staffId,
    required String staffName,
    required String markedBy,
    String? photoUrl,
  }) async {
    photoUrl ??= await captureAndUploadPhoto(
      entityType: 'staff',
      entityId: staffId,
    );
    if (photoUrl == null) {
      throw StateError('Photo is required.');
    }
    await _markAttendance(
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      classId: '',
      markedBy: markedBy,
      photoUrl: photoUrl,
    );
  }
}

// Firestore rules suggestion:
// attendance: authenticated users
// students: authenticated users
// classes: authenticated users
