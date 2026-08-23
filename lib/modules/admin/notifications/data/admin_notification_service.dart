import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/admin_notification_model.dart';

class AdminNotificationService {
  AdminNotificationService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FilePicker? filePicker,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _filePicker = filePicker ?? FilePicker.platform;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FilePicker _filePicker;
  CollectionReference<Map<String, dynamic>> get _notifications => _firestore.collection('school_notifications');
  CollectionReference<Map<String, dynamic>> get _classes => _firestore.collection('classes');
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  Future<List<AdminNotificationModel>> getNotifications() async {
    final snap = await _notifications.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => AdminNotificationModel.fromMap(d.id, d.data())).toList();
  }

  /// Published notifications for one consumer audience ('Parents' or
  /// 'Staff'), for the read-only Parent/Staff notification feeds. `audience`
  /// is matched against both the requested audience and 'Public' — a
  /// Public-audience notification is meant to reach every authenticated
  /// consumer, and since Parents/Staff each fetch their own audience-scoped
  /// slice, without this a Public notification would never match either
  /// slice's equality filter and would silently never appear anywhere
  /// outside Admin. Still a single field filter (`whereIn`) — no
  /// `orderBy` — so this doesn't need a composite index beyond what
  /// [getNotifications] already relies on; `status` and sort order are
  /// applied client-side on the already-narrow result, the same way
  /// [AttendanceService.filterByClasses] narrows by one field server-side
  /// and refines further in Dart. Per-student/per-staff targeting
  /// (`applicableStudentIds`/`applicableStaffIds`) is intentionally left to
  /// the caller, since only it knows which specific student/staff ids are
  /// relevant.
  Future<List<AdminNotificationModel>> getNotificationsForAudience(
    String audience,
  ) async {
    final snap = await _notifications
        .where('audience', whereIn: [audience, 'Public'])
        .get();
    final items = snap.docs
        .map((d) => AdminNotificationModel.fromMap(d.id, d.data()))
        .where((n) => n.status == 'Published')
        .toList();
    items.sort((a, b) {
      final aDate = a.publishDate ?? a.createdAt ?? DateTime(2000);
      final bDate = b.publishDate ?? b.createdAt ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return items;
  }

  Future<PlatformFile?> pickAttachment() async {
    final res = await _filePicker.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return null;
    return res.files.first;
  }

  Future<Map<String, dynamic>?> uploadAttachment({required String notificationId, required PlatformFile file}) async {
    final bytes = file.bytes;
    if (bytes == null) return null;
    final safeName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final ref = _storage.ref().child('school_notifications/$notificationId/$safeName');
    final snap = await ref.putData(bytes);
    final url = await snap.ref.getDownloadURL();
    return {
      'attachmentName': safeName,
      'attachmentUrl': url,
      'attachmentSize': file.size,
      'attachmentMimeType': file.extension ?? '',
    };
  }

  Future<String> createNotification(Map<String, dynamic> data) async {
    final doc = _notifications.doc();
    final payload = {
      ...data,
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    debugPrint('Writing notification to Firestore: ${doc.path}');
    await doc.set(payload);
    debugPrint('Firestore write complete: ${doc.id}');
    return doc.id;
  }

  Future<void> updateNotification(String id, Map<String, dynamic> data) async {
    debugPrint('Updating notification: school_notifications/$id');
    await _notifications.doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Firestore update complete: $id');
  }

  Future<void> deleteNotification(String id, {String? attachmentUrl}) async {
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(attachmentUrl).delete();
      } catch (_) {}
    }
    await _notifications.doc(id).delete();
  }

  Future<void> publishNotification(String id) async {
    await _notifications.doc(id).set({
      'status': 'Published',
      'sentAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> archiveNotification(String id) async {
    await _notifications.doc(id).set({
      'status': 'Archived',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveClasses() async {
    final snap = await _classes.where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveStudents({String? classId}) async {
    Query<Map<String, dynamic>> q = _students.where('isActive', isEqualTo: true);
    if (classId != null && classId.isNotEmpty) q = q.where('classId', isEqualTo: classId);
    final snap = await q.get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStaffUsers() async {
    final snap = await _users.where('role', whereIn: ['staff', 'admin']).get();
    return snap.docs;
  }

  Future<void> seedSampleNotifications() async {
    final existing = await _notifications.get();
    final titles = existing.docs.map((e) => e.data()['title']?.toString().trim().toLowerCase() ?? '').toSet();
    final samples = <Map<String, dynamic>>[
      {
        'title': 'Holiday Notice - Gandhi Jayanti',
        'message': 'School will remain closed on the upcoming holiday.',
        'notificationType': 'Holiday Notice',
        'category': 'General',
        'priority': 'Normal',
        'audience': 'Parents',
        'visibility': 'Parents',
        'status': 'Published',
        'academicYear': '2026-2027',
        'publishDate': DateTime(2026, 10, 1),
        'isPinned': true,
        'requiresAcknowledgement': false,
        'appliesToAllClasses': true,
        'applicableClassIds': const [],
        'applicableClassNames': const [],
        'appliesToAllStudents': true,
        'applicableStudentIds': const [],
        'applicableStudentNames': const [],
        'appliesToAllStaff': true,
        'applicableStaffIds': const [],
        'applicableStaffNames': const [],
        'isPublic': false,
      },
      {
        'title': 'Fee Reminder - Term 1',
        'message': 'Please complete the term fee payment before the due date.',
        'notificationType': 'Fee Reminder',
        'category': 'Finance',
        'priority': 'High',
        'audience': 'Parents',
        'visibility': 'Parents',
        'status': 'Draft',
        'academicYear': '2026-2027',
        'publishDate': DateTime(2026, 8, 15),
        'requiresAcknowledgement': true,
        'appliesToAllClasses': false,
        'applicableClassIds': const ['class-mont1'],
        'applicableClassNames': const ['Mont 1'],
        'appliesToAllStudents': false,
        'applicableStudentIds': const [],
        'applicableStudentNames': const [],
        'appliesToAllStaff': true,
        'applicableStaffIds': const [],
        'applicableStaffNames': const [],
        'isPublic': false,
      },
      {
        'title': 'Staff Meeting Reminder',
        'message': 'Monthly staff meeting is scheduled for Friday.',
        'notificationType': 'Staff Notice',
        'category': 'HR/Staff',
        'priority': 'Normal',
        'audience': 'Staff',
        'visibility': 'Staff',
        'status': 'Scheduled',
        'academicYear': '2026-2027',
        'publishDate': DateTime(2026, 8, 10),
        'appliesToAllClasses': false,
        'applicableClassIds': const [],
        'applicableClassNames': const [],
        'appliesToAllStudents': false,
        'applicableStudentIds': const [],
        'applicableStudentNames': const [],
        'appliesToAllStaff': false,
        'applicableStaffIds': const [],
        'applicableStaffNames': const [],
        'isPublic': false,
      },
    ];

    for (final sample in samples) {
      final key = sample['title'].toString().trim().toLowerCase();
      if (titles.contains(key)) continue;
      await _notifications.add({
        ...sample,
        'category': sample['category'] ?? 'General',
        'message': sample['message'] ?? '',
        'attachmentName': '',
        'attachmentUrl': '',
        'attachmentSize': null,
        'attachmentMimeType': '',
        'createdBy': 'seed',
        'createdByName': 'System',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
