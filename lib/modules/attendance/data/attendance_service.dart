import 'dart:io';

import 'package:flutter/foundation.dart';

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

  Future<Map<String, Map<String, dynamic>>> getAttendanceHistoryMap({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startKey = DateFormat('yyyy-MM-dd').format(startDate.toLocal());
    final endKey = DateFormat('yyyy-MM-dd').format(endDate.toLocal());
    final snapshot = await _attendance
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .get();
    final Map<String, Map<String, dynamic>> map = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final entityType = data['entityType']?.toString() ?? '';
      final entityId = data['entityId']?.toString() ?? '';
      final date = data['date']?.toString() ?? '';
      if (entityType.isEmpty || entityId.isEmpty || date.isEmpty) continue;
      map['${entityType}_${entityId}_$date'] = data;
    }

    return map;
  }

  String dateKeyFor(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date.toLocal());

  /// Direct-by-ID read of a single entity's attendance for one day (default
  /// today), reusing the same deterministic `{date}_{entityType}_{entityId}`
  /// document id every write path above already uses. Read-only — added for
  /// the Parent dashboard so it can look up one child's attendance without a
  /// broad query, and does not affect the write paths above.
  Future<Map<String, dynamic>?> getAttendanceForEntity({
    required String entityType,
    required String entityId,
    DateTime? date,
  }) async {
    final dateKey = dateKeyFor(date ?? DateTime.now());
    final doc = await _attendance
        .doc(_attendanceId(dateKey, entityType, entityId))
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// Read-only, single-entity attendance history for the last [days] days
  /// (today inclusive), for the Parent attendance history view. Reuses the
  /// exact same deterministic `{date}_{entityType}_{entityId}` document id
  /// every write path above already uses, so it can fetch exactly one
  /// entity's recent days in a single `whereIn` query instead of
  /// [getAttendanceHistoryMap]'s broad date-range scan across every entity
  /// (which would require filtering other students/staff back out in the
  /// UI). Capped at 30 — Firestore's `whereIn` clause limit — which also
  /// matches the "recent attendance" window a Parent view needs; days with
  /// no record come back as `status: 'not_marked'` rather than being
  /// omitted, so the caller always gets one entry per day.
  Future<List<Map<String, dynamic>>> getAttendanceHistoryForEntity({
    required String entityType,
    required String entityId,
    int days = 30,
  }) async {
    assert(days > 0 && days <= 30);
    final today = DateTime.now();
    final dateKeys = [
      for (var i = 0; i < days; i++)
        dateKeyFor(today.subtract(Duration(days: i))),
    ];
    final ids = [
      for (final dateKey in dateKeys)
        _attendanceId(dateKey, entityType, entityId),
    ];
    final snap = await _attendance
        .where(FieldPath.documentId, whereIn: ids)
        .get();
    final byId = {for (final doc in snap.docs) doc.id: doc.data()};

    return [
      for (var i = 0; i < dateKeys.length; i++)
        if (byId[ids[i]] != null)
          byId[ids[i]]!
        else
          {'date': dateKeys[i], 'status': 'not_marked'},
    ];
  }

  DateTime getAcademicYearStart(DateTime today) {
    if (today.month >= 6) {
      return DateTime(today.year, 6, 1);
    }
    return DateTime(today.year - 1, 6, 1);
  }

  Future<Map<String, Map<String, dynamic>>> getAttendanceByDate({
    required DateTime date,
  }) async {
    final dateKey = dateKeyFor(date);
    final snapshot = await _attendance.where('date', isEqualTo: dateKey).get();
    final map = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final entityType = data['entityType']?.toString() ?? '';
      final entityId = data['entityId']?.toString() ?? '';
      if (entityType.isEmpty || entityId.isEmpty) continue;
      map['${entityType}_$entityId'] = data;
    }
    return map;
  }

  Future<void> saveAdminAttendance({
    required String entityType,
    required String entityId,
    required String entityName,
    required String classId,
    required String status,
    required DateTime selectedDate,
    required String markedBy,
  }) async {
    final dateKey = dateKeyFor(selectedDate);
    final docId = _attendanceId(dateKey, entityType, entityId);
    final docRef = _attendance.doc(docId);
    final existing = await docRef.get();
    final isToday = dateKey == _dateKey();
    final data = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId,
      'date': dateKey,
      'attendanceDate': dateKey,
      'dateKey': dateKey.replaceAll('-', ''),
      'markedBy': markedBy,
      'markedByRole': 'admin',
      'source': 'admin',
      'isBackdated': !isToday,
      'status': status,
      'environment': _environmentTag(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  Future<void> clearAdminAttendance({
    required String entityType,
    required String entityId,
    required DateTime selectedDate,
  }) async {
    final dateKey = dateKeyFor(selectedDate);
    final docId = _attendanceId(dateKey, entityType, entityId);
    await _attendance.doc(docId).delete();
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
    const staffRoles = {'staff', 'teacher', 'admin_staff'};
    return snapshot.docs.where((doc) {
      final role = doc.data()['role']?.toString().trim().toLowerCase();
      if (role == null || role.isEmpty) return false;
      return staffRoles.contains(role);
    }).length;
  }

  Future<AttendanceOverview> getAttendanceOverview({
    List<String> classIds = const [],
  }) async {
    final studentCount = await getStudentCount(classIds: classIds);
    final staffCount = await getStaffCount();
    final dateKey = _dateKey();
    final snapshot = await _attendance.where('date', isEqualTo: dateKey).get();
    final presentCount = snapshot.docs.where((doc) {
      final data = doc.data();
      final status = (data['status']?.toString() ?? '').toLowerCase();
      final hasPhoto = (data['photoUrl']?.toString() ?? '').isNotEmpty;
      return status == 'present' || (status.isEmpty && hasPhoto);
    }).length;
    final totalCount = studentCount + staffCount;
    final absentCount = snapshot.docs.where((doc) {
      final status = (doc.data()['status']?.toString() ?? '').toLowerCase();
      return status == 'absent';
    }).length;

    return AttendanceOverview(
      studentCount: studentCount,
      staffCount: staffCount,
      totalCount: totalCount,
      presentCount: presentCount,
      absentCount: absentCount,
    );
  }

  Future<int> getNotMarkedCount({List<String> classIds = const []}) async {
    final overview = await getAttendanceOverview(classIds: classIds);
    return (overview.totalCount - overview.presentCount - overview.absentCount)
        .clamp(0, overview.totalCount);
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

  String _attendancePhotoPath(String entityType, String entityId, String date) =>
      'attendance_photos/${entityType == 'student' ? 'students' : 'staff'}/$date/$entityId.jpg';

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
    final path = _attendancePhotoPath(entityType, entityId, date);

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      return uploadImage(image: bytes, path: path);
    } else {
      final file = File(picked.path);
      return uploadImage(image: file, path: path);
    }
  }

  /// Best-effort delete of the deterministic attendance photo for one
  /// entity/date. Never throws — a missing file or a Storage failure is
  /// swallowed so callers can use this for cleanup without risking the
  /// attendance write it follows. Only ever targets the
  /// `attendance_photos/...` path; mood check-in photos live elsewhere and
  /// are untouched.
  Future<void> deleteAttendancePhoto({
    required String entityType,
    required String entityId,
    required String date,
  }) async {
    final path = _attendancePhotoPath(entityType, entityId, date);
    try {
      await _storage.ref().child(path).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      debugPrint('Could not delete attendance photo ($path): $e');
    } catch (e) {
      debugPrint('Could not delete attendance photo ($path): $e');
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

  Future<String> _markAttendance({
    required String entityType,
    required String entityId,
    required String entityName,
    required String classId,
    required String markedBy,
    required String photoUrl,
    required String status,
    String? role,
    String? phone,
    String? email,
  }) async {
    final date = _dateKey();
    final environment = _environmentTag();
    final id = _attendanceId(date, entityType, entityId);
    final docRef = _attendance.doc(id);

    debugPrint(
      'Saving attendance: staffId=$entityId, staffName=$entityName, docId=$id, status=$status',
    );
    final data = <String, dynamic>{
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
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (role != null) data['role'] = role;
    if (phone != null && phone.isNotEmpty) data['phone'] = phone;
    if (email != null && email.isNotEmpty) data['email'] = email;
    await docRef.set(data, SetOptions(merge: true));
    debugPrint('Attendance saved successfully: docId=$id');
    return id;
  }

  Future<void> updateAttendanceStatus({
    required String entityId,
    required String date,
    required String status,
    required String entityType,
  }) async {
    await _attendance.doc(_attendanceId(date, entityType, entityId)).set({
      'status': status,
      'date': date,
      'entityType': entityType,
      'entityId': entityId,
      'environment': _environmentTag(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAbsent({
    required String entityId,
    required String entityType,
    required String entityName,
    required String markedBy,
    String? classId,
    String? role,
    String? phone,
    String? email,
    String? photoUrl,
  }) async {
    final date = _dateKey();
    final id = _attendanceId(date, entityType, entityId);
    debugPrint(
      'Saving attendance: staffId=$entityId, staffName=$entityName, docId=$id, status=absent',
    );
    final data = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId ?? '',
      'date': date,
      'photoUrl': photoUrl ?? '',
      'markedBy': markedBy,
      'status': 'absent',
      'environment': _environmentTag(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (role != null) data['role'] = role;
    if (phone != null && phone.isNotEmpty) data['phone'] = phone;
    if (email != null && email.isNotEmpty) data['email'] = email;
    await _attendance.doc(id).set(data, SetOptions(merge: true));
    debugPrint('Attendance saved successfully: docId=$id');
    // Absent has no photo; clean up any photo left over from a prior
    // Present mark for this same entity/date so it doesn't linger as an
    // orphan now that the Firestore photoUrl has been cleared above.
    await deleteAttendancePhoto(entityType: entityType, entityId: entityId, date: date);
  }

  Future<String> markPresent({
    required String entityId,
    required String entityType,
    required String entityName,
    required String markedBy,
    required String photoUrl,
    String? classId,
    String? role,
    String? phone,
    String? email,
  }) async {
    final date = _dateKey();
    final id = _attendanceId(date, entityType, entityId);
    debugPrint(
      'Saving attendance: staffId=$entityId, staffName=$entityName, docId=$id, status=present',
    );
    final data = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'classId': classId ?? '',
      'date': date,
      'photoUrl': photoUrl,
      'markedBy': markedBy,
      'status': 'present',
      'environment': _environmentTag(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (role != null) data['role'] = role;
    if (phone != null && phone.isNotEmpty) data['phone'] = phone;
    if (email != null && email.isNotEmpty) data['email'] = email;
    await _attendance.doc(id).set(data, SetOptions(merge: true));
    debugPrint('Attendance saved successfully: docId=$id');
    return id;
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

  Future<String> markStudentAttendance({
    required String studentId,
    required String studentName,
    required String classId,
    required String markedBy,
    String? photoUrl,
    String status = 'present',
  }) async {
    return _markAttendance(
      entityType: 'student',
      entityId: studentId,
      entityName: studentName,
      classId: classId,
      markedBy: markedBy,
      photoUrl: photoUrl ?? '',
      status: status,
    );
  }

  Future<String> markStaffAttendance({
    required String staffId,
    required String staffName,
    required String markedBy,
    String? photoUrl,
    String status = 'present',
    String? role,
    String? phone,
    String? email,
  }) async {
    return _markAttendance(
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      classId: '',
      markedBy: markedBy,
      photoUrl: photoUrl ?? '',
      status: status,
      role: role,
      phone: phone,
      email: email,
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
