// AY-IMPLEMENT-02-B architecture/regression coverage (task §16): proves the
// additive `Class.academicYearId` migration is exactly that — additive —
// and touches nothing else. Two guarantees are checked end-to-end through
// the real ClassFormDialog (not just the service layer):
//
// 1. Saving a Class (create or edit) through the dialog never reads,
//    writes, or otherwise alters a single field of Attendance, Leave,
//    Fees, Finance, Calendar, or StudentEnrollment data — every one of
//    those collections' seeded documents comes out byte-for-byte identical.
// 2. The *only* new field ClassFormDialog's save ever introduces onto an
//    existing Class document is `academicYearId` — every other field it
//    already writes (name/section/academicYear/capacity/teacherName/
//    description/isActive/approvalStatus/updatedAt) already existed before
//    this task; nothing new was added to the Class schema beyond the one
//    field this task was scoped to add.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/classes/ui/class_form_dialog.dart';

const _untouchedCollections = <String>[
  'students',
  'attendance',
  'staff_leave_requests',
  'fee_structures',
  'student_fee_assignments',
  'fee_transactions',
  'finance_income',
  'finance_ledger',
  'school_calendar_events',
  'student_enrollments',
];

Future<Map<String, Map<String, dynamic>>> _seedFixtures(FakeFirebaseFirestore firestore) async {
  final fixtures = <String, Map<String, dynamic>>{
    'students': {
      'name': 'Abdul Kareem',
      'admissionNo': 'ADM-001',
      'classId': 'class-1',
      'isActive': true,
    },
    'attendance': {
      'entityType': 'student',
      'entityId': 'student-1',
      'date': '2026-08-25',
      'status': 'present',
    },
    'staff_leave_requests': {
      'requesterId': 'staff-1',
      'requesterRole': 'staff',
      'leaveType': 'Sick Leave',
      'status': 'Approved',
    },
    'fee_structures': {
      'name': 'Term Fee',
      'academicYear': '2026-2027',
      'totalAmount': 5000,
      'isActive': true,
    },
    'student_fee_assignments': {
      'studentId': 'student-1',
      'classId': 'class-1',
      'academicYear': '2026-2027',
      'status': 'unpaid',
    },
    'fee_transactions': {
      'assignmentId': 'assignment-1',
      'amount': 1000,
    },
    'finance_income': {
      'type': 'income',
      'category': 'Fees',
      'amount': 1000,
    },
    'finance_ledger': {
      'type': 'income',
      'amount': 1000,
    },
    'school_calendar_events': {
      'title': 'Sports Day',
      'audience': 'All',
      'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
    },
    'student_enrollments': {
      'schoolId': kDefaultSchoolId,
      'studentId': 'student-1',
      'academicYearId': 'ay-2026',
      'classId': 'class-1',
      'status': 'Active',
    },
  };

  for (final entry in fixtures.entries) {
    await firestore.collection(entry.key).doc('${entry.key}-fixture').set(entry.value);
  }
  return fixtures;
}

Future<void> _expectUntouched(
  FakeFirebaseFirestore firestore,
  Map<String, Map<String, dynamic>> fixtures,
) async {
  for (final collection in _untouchedCollections) {
    final snap = await firestore.collection(collection).get();
    expect(snap.docs, hasLength(1), reason: '$collection must gain no new/removed documents');
    expect(
      snap.docs.single.data(),
      equals(fixtures[collection]),
      reason: '$collection\'s existing document must be byte-for-byte unchanged',
    );
  }
}

Widget _pumpable(Widget child, {required FakeFirebaseFirestore firestore}) {
  return ProviderScope(
    overrides: [
      academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AY-IMPLEMENT-02-B — architecture regression: additive-only', () {
    testWidgets('Creating a Class (with the new academicYearId) leaves every other collection untouched', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final fixtures = await _seedFixtures(firestore);
      await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );

      await tester.pumpWidget(_pumpable(
        ClassFormDialog(service: ClassService(firestore: firestore)),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Class Name *'), 'Mont X');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      await _expectUntouched(firestore, fixtures);
    });

    testWidgets('Editing a Class to add academicYearId introduces exactly one new field on that document', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final fixtures = await _seedFixtures(firestore);
      await AcademicYearService(firestore: firestore).createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      // A pre-existing (legacy-shaped, pre-AY-IMPLEMENT-02-B) Class document
      // — every field ClassFormDialog already manages is already present,
      // matching a class that was last saved before this task.
      final classDoc = await firestore.collection('classes').add({
        'name': 'Mont 2',
        'section': 'A',
        'academicYear': '2026-2027',
        'capacity': 20,
        'teacherName': 'Ms. Priya',
        'description': '',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'createdBy': 'admin',
      });
      final beforeKeys = (await classDoc.get()).data()!.keys.toSet();

      await tester.pumpWidget(_pumpable(
        ClassFormDialog(
          classId: classDoc.id,
          initialData: {
            'name': 'Mont 2', 'section': 'A', 'academicYear': '2026-2027', 'capacity': 20,
            'teacherName': 'Ms. Priya', 'description': '', 'isActive': true, 'approvalStatus': 'Approved',
          },
          service: ClassService(firestore: firestore),
        ),
        firestore: firestore,
      ));
      await tester.pumpAndSettle();
      // No field edited — just an explicit Save, the only path that ever
      // upgrades a legacy Class to carry academicYearId.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final afterData = (await classDoc.get()).data()!;
      final newKeys = afterData.keys.toSet().difference(beforeKeys);
      expect(newKeys, {'academicYearId'}, reason: 'academicYearId must be the only field this migration ever newly introduces');
      expect(afterData['academicYear'], '2026-2027', reason: 'the legacy string is retained, never removed');

      await _expectUntouched(firestore, fixtures);
    });
  });
}
