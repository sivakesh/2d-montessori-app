// Regression coverage for the Parent Attendance History view (Phase C).
// Uses a fake-Firestore-backed AttendanceService (injected via the
// test-only `attendanceService` parameter) to drive the widget end to end:
// summary chips reuse computeAttendanceSummary, the empty state shows for a
// child with no real records (Test 5), and switching from Child A to Child
// B never leaves stale data on screen (Test 4).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_attendance_history_view.dart';

Future<void> _openHistory(
  WidgetTester tester, {
  required AttendanceService service,
  required String studentId,
  String studentName = 'Child',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showChildAttendanceHistory(
              context,
              studentId: studentId,
              studentName: studentName,
              attendanceService: service,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

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

  group('Attendance History — summary and list', () {
    testWidgets('Test 5 — a child with no attendance records shows the empty state, not a 30-row list', (
      tester,
    ) async {
      await _openHistory(tester, service: service, studentId: 'child-new');

      expect(find.text('No attendance records yet for this child.'), findsOneWidget);
      expect(find.text('Present: 0'), findsOneWidget);
      expect(find.text('Absent: 0'), findsOneWidget);
    });

    testWidgets('shows Present/Absent counts reusing the existing attendance-summary calculation', (
      tester,
    ) async {
      final today = dateKey(DateTime.now());
      await firestore.collection('attendance').doc('${today}_student_child-a').set({
        'entityType': 'student',
        'entityId': 'child-a',
        'date': today,
        'status': 'present',
      });

      await _openHistory(tester, service: service, studentId: 'child-a');

      expect(find.text('Present: 1'), findsOneWidget);
      expect(find.text('Absent: 0'), findsOneWidget);
      expect(find.text('No attendance records yet for this child.'), findsNothing);
    });
  });

  group('Attendance History — Test 4: switching children never leaves stale data', () {
    testWidgets('Child A\'s present record does not leak into Child B\'s history', (tester) async {
      final today = dateKey(DateTime.now());
      await firestore.collection('attendance').doc('${today}_student_child-a').set({
        'entityType': 'student',
        'entityId': 'child-a',
        'date': today,
        'status': 'present',
      });
      // Child B has no attendance record at all.

      await _openHistory(tester, service: service, studentId: 'child-a', studentName: 'Child A');
      expect(find.text('Present: 1'), findsOneWidget);

      // Simulate the Dashboard's child switch: close this dialog and reopen
      // the same view for the newly selected child.
      Navigator.of(tester.element(find.text('Present: 1'))).pop();
      await tester.pumpAndSettle();

      await _openHistory(tester, service: service, studentId: 'child-b', studentName: 'Child B');
      expect(find.text('Present: 0'), findsOneWidget);
      expect(find.text('No attendance records yet for this child.'), findsOneWidget);
    });
  });

  group('Attendance History — responsive behavior', () {
    for (final size in [
      const Size(390, 844),
      const Size(400, 775),
      const Size(412, 915),
      const Size(768, 1024),
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        final today = dateKey(DateTime.now());
        await firestore.collection('attendance').doc('${today}_student_child-a').set({
          'entityType': 'student',
          'entityId': 'child-a',
          'date': today,
          'status': 'present',
          'updatedAt': DateTime.now(),
        });

        await _openHistory(tester, service: service, studentId: 'child-a');

        expect(tester.takeException(), isNull);
      });
    }
  });
}
