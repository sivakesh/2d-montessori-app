// Regression coverage for AttendanceService.getAttendanceHistoryForEntity —
// the single-entity-scoped history query added for the Parent Attendance
// History view (Phase C). Reuses the exact same deterministic
// `{date}_{entityType}_{entityId}` document id every attendance write path
// already relies on, fetched via one `whereIn` query instead of a broad
// date-range scan across every entity. Covers Test 3 (only the requested
// child's records come back) and Test 5 (a child with no attendance history
// at all does not crash, and every day is reported as 'not_marked') from
// the Phase C plan.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/attendance/data/attendance_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AttendanceService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = AttendanceService(
      firestore: firestore,
      storage: MockFirebaseStorage(),
    );
  });

  String dateKey(DateTime d) => service.dateKeyFor(d);

  group('getAttendanceHistoryForEntity', () {
    test('Test 3 — only the requested child\'s records are returned, not another child\'s', () async {
      final today = dateKey(DateTime.now());
      await firestore.collection('attendance').doc('${today}_student_child-a').set({
        'entityType': 'student',
        'entityId': 'child-a',
        'date': today,
        'status': 'present',
      });
      await firestore.collection('attendance').doc('${today}_student_child-b').set({
        'entityType': 'student',
        'entityId': 'child-b',
        'date': today,
        'status': 'absent',
      });

      final result = await service.getAttendanceHistoryForEntity(
        entityType: 'student',
        entityId: 'child-a',
        days: 3,
      );

      final todaysRecord = result.firstWhere((r) => r['date'] == today);
      expect(todaysRecord['status'], 'present');
      // No record in the returned list should ever carry another entity's id.
      expect(
        result.every((r) => r['entityId'] == null || r['entityId'] == 'child-a'),
        isTrue,
      );
    });

    test('Test 5 — a child with no attendance history returns not_marked for every day, no crash', () async {
      final result = await service.getAttendanceHistoryForEntity(
        entityType: 'student',
        entityId: 'brand-new-child',
        days: 5,
      );

      expect(result, hasLength(5));
      expect(result.every((r) => r['status'] == 'not_marked'), isTrue);
    });

    test('a day with no record comes back as not_marked instead of being omitted', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await firestore.collection('attendance').doc('${dateKey(today)}_student_child-a').set({
        'entityType': 'student',
        'entityId': 'child-a',
        'date': dateKey(today),
        'status': 'present',
      });
      // No record seeded for yesterday.

      final result = await service.getAttendanceHistoryForEntity(
        entityType: 'student',
        entityId: 'child-a',
        days: 2,
      );

      expect(result, hasLength(2));
      final yesterdaysRecord = result.firstWhere((r) => r['date'] == dateKey(yesterday));
      expect(yesterdaysRecord['status'], 'not_marked');
    });

    test('result is capped to the requested number of days', () async {
      final result = await service.getAttendanceHistoryForEntity(
        entityType: 'student',
        entityId: 'child-a',
        days: 7,
      );

      expect(result, hasLength(7));
    });
  });
}
