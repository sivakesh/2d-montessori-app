// AY-IMPLEMENT-03 Phase 8 architecture regression coverage (items 31-37).
//
// This task's explicit constraint is that Attendance, Leave, Calendar,
// Finance (general), and Mood Check-ins are "date-derived" (AY-AUDIT-02
// classification B) and must NEVER receive an `academicYearId` field —
// Academic Year context for these is always resolved at query time from
// AcademicYearModel.startDate/endDate against each record's own date
// field, never stored on the record itself. This file proves that
// invariant by exercising every *ForAcademicYear reporting method added in
// this task against realistic fixtures and then asserting the underlying
// documents were never mutated at all (read-only queries), so none of them
// could possibly have gained an `academicYearId` key.
//
// It also proves the explicitly-scoped, legitimately academicYearId-bearing
// collections from earlier tasks (StudentEnrollment, Class, Fees,
// AcademicYears themselves) are completely unaffected by this task's new
// code — their documents are byte-for-byte identical before and after.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';

/// The 9 collections this task must never add `academicYearId` to.
const _dateDerivedCollections = <String>[
  'attendance',
  'staff_leave_requests',
  'school_calendar_events',
  'finance_income',
  'finance_expenses',
  'finance_ledger',
  'finance_invoices',
  'staff_salary_payments',
  'mood_checkins',
];

/// Collections that legitimately already carry `academicYearId` from prior
/// tasks (StudentEnrollment/Class/Fees/AcademicYears themselves) — this
/// task must leave every document in them completely untouched.
const _preExistingYearScopedCollections = <String>[
  'student_enrollments',
  'classes',
  'fee_structures',
  'student_fee_assignments',
  'academic_years',
];

Future<Map<String, Map<String, Map<String, dynamic>>>> _snapshotAll(
  FakeFirebaseFirestore firestore,
  List<String> collections,
) async {
  final snapshot = <String, Map<String, Map<String, dynamic>>>{};
  for (final name in collections) {
    final docs = await firestore.collection(name).get();
    snapshot[name] = {for (final d in docs.docs) d.id: Map<String, dynamic>.from(d.data())};
  }
  return snapshot;
}

Future<void> _seedDateDerivedFixtures(FakeFirebaseFirestore firestore) async {
  await firestore.collection('attendance').doc('att1').set({
    'entityType': 'student',
    'entityId': 's1',
    'date': '2026-12-25',
    'status': 'present',
  });
  await firestore.collection('staff_leave_requests').doc('leave1').set({
    'requesterId': 'r1',
    'requesterRole': 'staff',
    'subjectType': 'staff',
    'leaveType': 'sick',
    'startDate': DateTime(2026, 12, 25),
    'endDate': DateTime(2026, 12, 26),
    'reason': 'test',
    'status': 'pending',
  });
  await firestore.collection('school_calendar_events').doc('event1').set({
    'title': 'Holiday',
    'date': DateTime(2026, 12, 25),
    'status': 'published',
    'audience': 'Public',
  });
  await firestore.collection('finance_income').doc('income1').set({
    'amount': 100,
    'incomeDate': DateTime(2026, 12, 25),
    'isDeleted': false,
  });
  await firestore.collection('finance_expenses').doc('expense1').set({
    'amount': 200,
    'expenseDate': DateTime(2026, 12, 25),
  });
  await firestore.collection('finance_ledger').doc('ledger1').set({
    'amount': 300,
    'transactionDate': DateTime(2026, 12, 25),
  });
  await firestore.collection('finance_invoices').doc('invoice1').set({
    'type': 'expense',
    'amount': 400,
    'invoiceDate': DateTime(2026, 12, 25),
  });
  await firestore.collection('staff_salary_payments').doc('salary1').set({
    'staffUserId': 'u1',
    'amount': 500,
    'paymentDate': DateTime(2026, 12, 25),
  });
  await firestore.collection('mood_checkins').doc('mood1').set({
    'entityType': 'student',
    'entityId': 's1',
    'checkInAt': Timestamp.fromDate(DateTime(2026, 12, 25, 10, 0)),
  });
}

Future<void> _seedPreExistingYearScopedFixtures(FakeFirebaseFirestore firestore, String academicYearId) async {
  await firestore.collection('student_enrollments').doc('enr1').set({
    'studentId': 's1',
    'academicYearId': academicYearId,
    'classId': 'c1',
    'status': 'active',
  });
  await firestore.collection('classes').doc('c1').set({
    'name': 'Mont 1',
    'academicYearId': academicYearId,
    'isActive': true,
  });
  await firestore.collection('fee_structures').doc('fs1').set({
    'name': 'Standard',
    'academicYearId': academicYearId,
  });
  await firestore.collection('student_fee_assignments').doc('fa1').set({
    'studentId': 's1',
    'academicYearId': academicYearId,
    'totalFee': 10000,
  });
}

void main() {
  group('AY-IMPLEMENT-03 Phase 8: date-derived collections never receive academicYearId', () {
    test('31-35. Attendance/Leave/Calendar/Finance/Mood documents are never mutated by any *ForAcademicYear reporting call', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedDateDerivedFixtures(firestore);

      final ayService = AcademicYearService(firestore: firestore);
      final id = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 3, 30),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      final range = AcademicYearDateRange.fromAcademicYear(year!);

      final before = await _snapshotAll(firestore, _dateDerivedCollections);

      // Exercise every reporting method this task added, across every
      // date-derived module, against the very fixtures seeded above.
      await AttendanceService(firestore: firestore, storage: MockFirebaseStorage())
          .getAttendanceForAcademicYear(range);
      await LeaveService(firestore: firestore).getStaffRequestsForAcademicYear(range);
      await LeaveService(firestore: firestore).getStudentRequestsForAcademicYear(range);
      await CalendarService(firestore: firestore).getEventsForAcademicYear(range);
      final finance = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
      await finance.getIncomeForAcademicYear(range);
      await finance.getExpensesForAcademicYear(range);
      await finance.getLedgerForAcademicYear(range);
      await finance.getInvoicesForAcademicYear(range);
      await finance.getSalaryPaymentsForAcademicYear(range);
      await MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage())
          .getMoodCheckinsForAcademicYear(range);

      final after = await _snapshotAll(firestore, _dateDerivedCollections);

      expect(after, equals(before),
          reason: 'no *ForAcademicYear reporting call may write to any date-derived collection');

      for (final name in _dateDerivedCollections) {
        for (final entry in after[name]!.entries) {
          expect(entry.value.containsKey('academicYearId'), isFalse,
              reason: '$name/${entry.key} must never gain an academicYearId field');
        }
      }
    });

    test('36. StudentEnrollment, Class, Fees, and AcademicYears documents are completely unaffected by this task\'s reporting calls', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedDateDerivedFixtures(firestore);

      final ayService = AcademicYearService(firestore: firestore);
      final id = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 3, 30),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      await _seedPreExistingYearScopedFixtures(firestore, id);
      final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      final range = AcademicYearDateRange.fromAcademicYear(year!);

      final allYearScoped = [..._preExistingYearScopedCollections];
      final before = await _snapshotAll(firestore, allYearScoped);

      await AttendanceService(firestore: firestore, storage: MockFirebaseStorage())
          .getAttendanceForAcademicYear(range);
      await LeaveService(firestore: firestore).getStaffRequestsForAcademicYear(range);
      await CalendarService(firestore: firestore).getEventsForAcademicYear(range);
      final finance = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
      await finance.getIncomeForAcademicYear(range);
      await finance.getExpensesForAcademicYear(range);
      await MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage())
          .getMoodCheckinsForAcademicYear(range);

      final after = await _snapshotAll(firestore, allYearScoped);

      expect(after, equals(before));
    });

    test('37. AcademicYearDateRange itself never writes to Firestore — it is a pure in-memory value object', () async {
      final firestore = FakeFirebaseFirestore();
      final ayService = AcademicYearService(firestore: firestore);
      final id = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 3, 30),
        createdBy: 'admin-1',
      );
      final beforeCount = (await firestore.collection('academic_years').get()).docs.length;

      final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
      final range = AcademicYearDateRange.fromAcademicYear(year!);
      range.contains(DateTime(2026, 12, 25));
      // ignore: unnecessary_statements
      range.queryUpperBound;

      final afterCount = (await firestore.collection('academic_years').get()).docs.length;
      expect(afterCount, beforeCount);
    });
  });
}
