// AY-IMPLEMENT-02-B coverage: Parent Dashboard's one identified
// `Class.academicYear` consumer (see AY-IMPLEMENT-02-A §9) now resolves the
// displayed academic year through the canonical `Class.academicYearId` when
// present, falling back to the legacy free-text `academicYear` string for a
// Class that hasn't been migrated yet — never crashing, and never inventing
// a year, when neither is resolvable. This mirrors the DI/pump pattern
// already established in parent_dashboard_notification_targeting_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

Future<void> _seedChild(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String name,
  required String classId,
}) async {
  await firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'classId': classId,
    'section': 'A',
    'isActive': true,
  });
  await firestore.collection('user_student_links').add({
    'userId': 'parent-1',
    'studentId': id,
  });
}

Widget _buildDashboard(FakeFirebaseFirestore firestore) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(
          id: 'parent-1',
          phone: '9999999999',
          name: 'Test Parent',
          role: 'parent',
          isActive: true,
        ),
      ),
      academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
    ],
    child: MaterialApp(
      home: ParentDashboard(
        parentService: ParentService(firestore: firestore),
        attendanceService: AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
        feeService: FeeService(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
        notificationService: AdminNotificationService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
          filePicker: _UnusedFilePicker(),
        ),
        classService: ClassService(firestore: firestore),
        moodCheckinService: MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
        leaveService: LeaveService(firestore: firestore),
      ),
    ),
  );
}

Future<void> _openProfile(WidgetTester tester) async {
  final profileButton = find.widgetWithText(OutlinedButton, 'Profile');
  await tester.ensureVisible(profileButton);
  await tester.pumpAndSettle();
  await tester.tap(profileButton);
  await tester.pumpAndSettle();
}

void main() {
  group('Parent Dashboard — academic year resolution (AY-IMPLEMENT-02-B)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    testWidgets('22. Resolves the displayed year through Class.academicYearId, not the legacy string', (tester) async {
      final yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2',
        'isActive': true,
        // Deliberately disagreeing legacy text — proves the id, not the
        // string, drives what's displayed.
        'academicYear': '2099-2100',
        'academicYearId': yearId,
      });
      await _seedChild(firestore, id: 'student-1', name: 'Amenah Noor', classId: classDoc.id);

      await tester.pumpWidget(_buildDashboard(firestore));
      await tester.pumpAndSettle();
      await _openProfile(tester);

      expect(find.text('2026-2027'), findsOneWidget);
      expect(find.text('2099-2100'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('23. Legacy Class (no academicYearId) still displays its academicYear string', (tester) async {
      final classDoc = await firestore.collection('classes').add({
        'name': 'Pre Mont',
        'isActive': true,
        'academicYear': '2025-2026',
      });
      await _seedChild(firestore, id: 'student-1', name: 'Amenah Noor', classId: classDoc.id);

      await tester.pumpWidget(_buildDashboard(firestore));
      await tester.pumpAndSettle();
      await _openProfile(tester);

      expect(find.text('2025-2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('24. A Class with neither field never crashes and the Academic Year row is simply omitted', (tester) async {
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 3',
        'isActive': true,
      });
      await _seedChild(firestore, id: 'student-1', name: 'Amenah Noor', classId: classDoc.id);

      await tester.pumpWidget(_buildDashboard(firestore));
      await tester.pumpAndSettle();
      await _openProfile(tester);

      expect(find.text('Academic Year'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('24b. An academicYearId that resolves to nothing (deactivated/unknown year) never crashes', (tester) async {
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 4',
        'isActive': true,
        'academicYearId': 'does-not-exist',
      });
      await _seedChild(firestore, id: 'student-1', name: 'Amenah Noor', classId: classDoc.id);

      await tester.pumpWidget(_buildDashboard(firestore));
      await tester.pumpAndSettle();
      await _openProfile(tester);

      // No stored fallback string either, so the row is omitted rather than
      // showing an invented or blank value — never "Unresolved" leaking
      // into the parent-facing profile without a stored string to explain it.
      expect(find.text('Academic Year'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
