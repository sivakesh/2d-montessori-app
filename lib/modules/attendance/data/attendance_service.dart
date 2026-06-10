import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class AttendanceService {
  AttendanceService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? imagePicker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final ImagePicker _imagePicker;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('attendance');
  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String _dateKey() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
  }

  Future<Map<String, dynamic>> getTodayAttendance({
    required String entityType,
  }) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
    // ignore: avoid_print
    print('Fetching attendance for: $dateKey');

    final snapshot = await _firestore
        .collection('attendance')
        .where('entityType', isEqualTo: entityType)
        .where('date', isEqualTo: dateKey)
        .get();

    final Map<String, dynamic> map = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      map[data['entityId']] = data;
    }

    return map;
  }

  Future<Map<String, Map<String, dynamic>>> getTodayAttendanceMap() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
    final snapshot = await _attendance.where('date', isEqualTo: dateKey).get();
    final Map<String, Map<String, dynamic>> map = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final entityType = data['entityType']?.toString() ?? '';
      final entityId = data['entityId']?.toString() ?? '';
      if (entityType.isEmpty || entityId.isEmpty) continue;
      map['${entityType}_$entityId'] = data;
    }

    return map;
  }

  Future<int> getStudentCount({List<String> classIds = const []}) async {
    Query<Map<String, dynamic>> query = _students.where(
      'isActive',
      isEqualTo: true,
    );

    if (classIds.isEmpty) {
      final snapshot = await query.get();
      return snapshot.docs.length;
    }

    final snapshots = await Future.wait(
      classIds.map(
        (classId) => query.where('classId', isEqualTo: classId).get(),
      ),
    );

    final seen = <String>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        seen.add(doc.id);
      }
    }
    return seen.length;
  }

  Future<int> getStaffCount() async {
    final snapshot = await _users.where('isActive', isEqualTo: true).get();
    final staff = snapshot.docs.where((doc) {
      final role = doc.data()['role']?.toString() ?? 'parent';
      // ignore: avoid_print
      print(role);
      return role.toLowerCase() != 'student';
    }).toList();
    return staff.length;
  }

  Future<AttendanceOverview> getAttendanceOverview({
    List<String> classIds = const [],
  }) async {
    final studentCount = await getStudentCount(classIds: classIds);
    final staffCount = await getStaffCount();
    final dateKey = _dateKey();
    final snapshot = await _attendance.where('date', isEqualTo: dateKey).get();
    final presentIds = snapshot.docs
        .where(
          (doc) =>
              (doc.data()['status']?.toString() ?? '').toLowerCase() ==
              'present',
        )
        .map((doc) => doc.data()['entityId']?.toString() ?? '')
        .where((entityId) => entityId.isNotEmpty)
        .toSet();
    final presentCount = presentIds.length;
    final totalCount = studentCount + staffCount;
    final absentCount = (totalCount - presentCount).clamp(0, totalCount);

    return AttendanceOverview(
      studentCount: studentCount,
      staffCount: staffCount,
      totalCount: totalCount,
      presentCount: presentCount,
      absentCount: absentCount,
    );
  }

  String _attendanceId(String date, String entityType, String entityId) =>
      '${date}_${entityType}_$entityId';

  String _environmentTag() => kReleaseMode ? 'prod' : 'dev';

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> filterByClasses({
    required List<String> classIds,
  }) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
    final snapshot = await _attendance
        .where('date', isEqualTo: dateKey)
        .orderBy('createdAt', descending: true)
        .get();

    if (classIds.isEmpty) {
      return snapshot.docs;
    }

    return snapshot.docs.where((doc) {
      final data = doc.data();
      final entityType = data['entityType']?.toString();
      if (entityType == 'staff') return true;
      final classId = data['classId']?.toString();
      return classIds.contains(classId);
    }).toList();
  }

  Future<String> uploadImage({
    required dynamic image,
    required String path,
  }) async {
    try {
      // ignore: avoid_print
      print('Uploading image...');
      final ref = _storage.ref().child(path);

      UploadTask uploadTask;

      if (kIsWeb) {
        uploadTask = ref.putData(image as Uint8List);
      } else {
        uploadTask = ref.putFile(image as File);
      }

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      // ignore: avoid_print
      print('Upload successful');
      return url;
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('Firebase upload error: $e');
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('Upload error: $e');
      rethrow;
    }
  }

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
    final path =
        'attendance_photos/${entityType == 'student' ? 'students' : 'staff'}/$date/$entityId.jpg';

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      return uploadImage(image: bytes, path: path);
    } else {
      final file = File(picked.path);
      return uploadImage(image: file, path: path);
    }
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
    required String status,
  }) async {
    final date = _dateKey();
    final environment = _environmentTag();
    final id = environment == 'dev'
        ? '${date}_${entityType}_${entityId}_${DateTime.now().microsecondsSinceEpoch}'
        : _attendanceId(date, entityType, entityId);
    final docRef = _attendance.doc(id);

    // ignore: avoid_print
    print('Saving attendance...');
    await docRef.set({
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId,
      'date': date,
      'photoUrl': photoUrl,
      'markedBy': markedBy,
      'status': status,
      'environment': environment,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // ignore: avoid_print
    print('Attendance saved');
  }

  Future<void> updateAttendanceStatus({
    required String entityId,
    required String date,
    required String status,
    required String entityType,
  }) async {
    if (kReleaseMode) {
      await _attendance.doc(_attendanceId(date, entityType, entityId)).set({
        'status': status,
        'date': date,
        'entityType': entityType,
        'entityId': entityId,
        'environment': 'prod',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    await _attendance.doc(_attendanceId(date, entityType, entityId)).set({
      'status': status,
      'date': date,
      'entityType': entityType,
      'entityId': entityId,
      'environment': 'dev',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      'environment': _environmentTag(),
    });
  }

  Future<bool> hasMarkedToday(String userId) async {
    final date = _dateKey();
    final staffDoc = await _attendance
        .doc(_attendanceId(date, 'staff', userId))
        .get();
    final studentDoc = await _attendance
        .doc(_attendanceId(date, 'student', userId))
        .get();
    return staffDoc.exists || studentDoc.exists;
  }

  Future<void> markStudentAttendance({
    required String studentId,
    required String studentName,
    required String classId,
    required String markedBy,
    String? photoUrl,
    String status = 'present',
  }) async {
    await _markAttendance(
      entityType: 'student',
      entityId: studentId,
      entityName: studentName,
      classId: classId,
      markedBy: markedBy,
      photoUrl: photoUrl ?? '',
      status: status,
    );
  }

  Future<void> markStaffAttendance({
    required String staffId,
    required String staffName,
    required String markedBy,
    String? photoUrl,
    String status = 'present',
  }) async {
    await _markAttendance(
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      classId: '',
      markedBy: markedBy,
      photoUrl: photoUrl ?? '',
      status: status,
    );
  }
}

class AttendanceOverview {
  const AttendanceOverview({
    required this.studentCount,
    required this.staffCount,
    required this.totalCount,
    required this.presentCount,
    required this.absentCount,
  });

  final int studentCount;
  final int staffCount;
  final int totalCount;
  final int presentCount;
  final int absentCount;
}

// Firestore rules suggestion:
// attendance: authenticated users
// students: authenticated users
// classes: authenticated users
