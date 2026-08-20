// Exercises AttendanceService against an in-memory Firestore
// (fake_cloud_firestore) and Storage (firebase_storage_mocks) to cover the
// reliability behaviors this change relies on:
// - Re-marking Present for the same entity/date never creates a second
//   attendance document (the deterministic doc-ID strategy holds).
// - Marking Absent clears photoUrl and best-effort deletes any photo left
//   over from a prior Present for that same entity/date.
// - deleteAttendancePhoto only ever targets the exact entity/date it is
//   given, and never throws when there is nothing to delete.
//
// The camera/image_picker step itself (captureAndUploadPhoto's
// ImagePicker.pickImage call) is intentionally not exercised here — it
// requires a platform channel, and the failure/cancellation handling that
// depends on it lives in attendance_screen.dart's orchestration, not in
// this service.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/attendance/data/attendance_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late AttendanceService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    service = AttendanceService(firestore: firestore, storage: storage);
  });

  String photoPath(String entityType, String entityId, String date) =>
      'attendance_photos/${entityType == 'student' ? 'students' : 'staff'}/$date/$entityId.jpg';

  test('marking Present twice for the same entity/date does not duplicate the record', () async {
    await service.markPresent(
      entityType: 'student',
      entityId: 'student-1',
      entityName: 'Aarav',
      markedBy: 'staff-1',
      photoUrl: 'https://example.com/photo-1.jpg',
      classId: 'class-1',
    );
    await service.markPresent(
      entityType: 'student',
      entityId: 'student-1',
      entityName: 'Aarav',
      markedBy: 'staff-1',
      photoUrl: 'https://example.com/photo-2.jpg',
      classId: 'class-1',
    );

    final snapshot = await firestore.collection('attendance').get();
    expect(snapshot.docs, hasLength(1));
    expect(snapshot.docs.single.data()['status'], 'present');
    expect(snapshot.docs.single.data()['photoUrl'], 'https://example.com/photo-2.jpg');
  });

  test('marking Absent clears photoUrl and deletes a prior Present photo for that day', () async {
    final date = service.dateKeyFor(DateTime.now());
    final path = photoPath('student', 'student-1', date);
    await storage.ref().child(path).putData(Uint8ListStub.bytes);

    await service.markPresent(
      entityType: 'student',
      entityId: 'student-1',
      entityName: 'Aarav',
      markedBy: 'staff-1',
      photoUrl: 'https://example.com/photo.jpg',
      classId: 'class-1',
    );

    await service.markAbsent(
      entityType: 'student',
      entityId: 'student-1',
      entityName: 'Aarav',
      markedBy: 'staff-1',
      classId: 'class-1',
    );

    final snapshot = await firestore.collection('attendance').get();
    expect(snapshot.docs, hasLength(1));
    expect(snapshot.docs.single.data()['status'], 'absent');
    expect(snapshot.docs.single.data()['photoUrl'], '');

    expect(
      () => storage.ref().child(path).getDownloadURL(),
      throwsA(isA<Exception>()),
    );
  });

  test('deleteAttendancePhoto does not throw when no photo exists for that entity/date', () async {
    await expectLater(
      service.deleteAttendancePhoto(
        entityType: 'staff',
        entityId: 'staff-404',
        date: '2026-01-01',
      ),
      completes,
    );
  });

  test('deleteAttendancePhoto only removes the targeted entity/date, leaving others intact', () async {
    final targetPath = photoPath('student', 'student-1', '2026-01-01');
    final otherPath = photoPath('student', 'student-2', '2026-01-01');
    await storage.ref().child(targetPath).putData(Uint8ListStub.bytes);
    await storage.ref().child(otherPath).putData(Uint8ListStub.bytes);

    await service.deleteAttendancePhoto(
      entityType: 'student',
      entityId: 'student-1',
      date: '2026-01-01',
    );

    expect(
      () => storage.ref().child(targetPath).getDownloadURL(),
      throwsA(isA<Exception>()),
    );
    // The untouched entity's photo must still resolve.
    final otherUrl = await storage.ref().child(otherPath).getDownloadURL();
    expect(otherUrl, isNotEmpty);
  });
}

/// A tiny reusable byte payload for Storage mock uploads in this file —
/// avoids repeating a literal at each call site.
class Uint8ListStub {
  static final bytes = Uint8List.fromList([1, 2, 3]);
}
