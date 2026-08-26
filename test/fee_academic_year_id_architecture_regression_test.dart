// FEES-AY-IMPLEMENT-01 architecture regression coverage (task Phase 15):
// proves the additive `academicYearId` field this task introduces lands
// only on `fee_structures` and `student_fee_assignments` — never on
// fee_transactions, fee_receipts, finance_income, finance_ledger, students,
// student_enrollments, classes, attendance, staff_leave_requests, or
// school_calendar_events. Exercises the real, end-to-end flow (create a Fee
// Structure with a canonical year, assign it to a student, collect a
// payment, void it) rather than just inspecting source code, so this is a
// genuine, machine-checked guarantee.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

// student_enrollments is deliberately excluded from this list: it already
// legitimately carries `academicYearId` from AY-01-R1, predating this task
// entirely — its own fixture document (seeded with that field already set)
// is instead proven byte-for-byte unchanged by `_expectFixturesUntouched`,
// which is the real guarantee this task must not write a *new* value there.
const _mustNeverGainAcademicYearId = <String>[
  'fee_transactions',
  'fee_receipts',
  'finance_income',
  'finance_ledger',
  'students',
  'classes',
  'attendance',
  'staff_leave_requests',
  'school_calendar_events',
];

Future<Map<String, Map<String, dynamic>>> _seedFixtures(FakeFirebaseFirestore firestore) async {
  final fixtures = <String, Map<String, dynamic>>{
    'students': {'name': 'Abdul Kareem', 'admissionNo': 'ADM-001', 'classId': 'class-1', 'isActive': true},
    'classes': {'name': 'Mont 2', 'section': 'B', 'academicYear': '2026-2027', 'isActive': true},
    'attendance': {'entityType': 'student', 'entityId': 'student-1', 'date': '2026-08-25', 'status': 'present'},
    'staff_leave_requests': {'requesterId': 'staff-1', 'requesterRole': 'staff', 'leaveType': 'Sick Leave', 'status': 'Approved'},
    'school_calendar_events': {'title': 'Sports Day', 'audience': 'All', 'date': Timestamp.fromDate(DateTime(2026, 9, 1))},
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

Future<void> _expectFixturesUntouched(
  FakeFirebaseFirestore firestore,
  Map<String, Map<String, dynamic>> fixtures,
) async {
  for (final entry in fixtures.entries) {
    final snap = await firestore.collection(entry.key).doc('${entry.key}-fixture').get();
    expect(snap.data(), equals(entry.value), reason: '${entry.key} fixture must be byte-for-byte unchanged');
  }
}

Future<void> _expectNoAcademicYearIdField(FakeFirebaseFirestore firestore, String collection) async {
  final snap = await firestore.collection(collection).get();
  for (final doc in snap.docs) {
    expect(
      doc.data().containsKey('academicYearId'),
      isFalse,
      reason: '$collection/${doc.id} must never gain an academicYearId field',
    );
  }
}

void main() {
  test('Only fee_structures and student_fee_assignments ever gain academicYearId — everything else is untouched', () async {
    final firestore = FakeFirebaseFirestore();
    final fixtures = await _seedFixtures(firestore);

    // Real, canonical Academic Year — same infrastructure every other
    // Academic-Year-aware module already reuses.
    final yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
      schoolId: kDefaultSchoolId,
      requesterRole: 'admin',
      name: '2026-2027',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 5, 31),
      createdBy: 'admin-1',
      setAsCurrent: true,
    );

    final financeService = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    // A Finance account is required for collectFee's income entry to post.
    await firestore.collection('finance_accounts').add({
      'name': 'Cash', 'type': 'cash', 'isActive': true, 'currentBalance': 0.0,
    });
    final feeService = FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
      financeService: financeService,
    );

    // Full end-to-end Fees flow, exactly as an admin would perform it
    // through the now-canonical-Academic-Year-aware dialogs.
    final structureId = await feeService.createFeeStructure({
      'name': 'Core Fees',
      'description': '',
      'components': [],
      'totalAmount': 20000,
      'academicYearId': yearId,
      'academicYear': '2026-2027',
      'isActive': true,
      'createdBy': 'admin',
    });

    final assignmentId = await feeService.assignFee({
      'studentId': 'student-1',
      'studentName': 'Abdul Kareem',
      'admissionNo': 'ADM-001',
      'classId': 'class-1',
      'className': 'Mont 2',
      'feeStructureId': structureId,
      'feeStructureName': 'Core Fees',
      'academicYearId': yearId,
      'academicYear': '2026-2027',
      'totalFee': 20000.0,
      'discountAmount': 0.0,
      'payableAmount': 20000.0,
      'paidAmount': 0.0,
      'balanceAmount': 20000.0,
      'status': 'unpaid',
    });
    expect(assignmentId, isNotNull);

    final receipt = await feeService.collectFee(
      assignmentId: assignmentId!,
      amount: 5000,
      paymentDate: DateTime(2026, 8, 1),
      paymentMode: 'cash',
      referenceNo: 'REF-1',
      remarks: '',
    );
    await feeService.voidReceipt(receipt.id);

    // 1. Every collection this task must never touch is byte-for-byte
    //    unchanged, and none of them ever gained an academicYearId field —
    //    including on the brand-new documents collectFee/voidReceipt
    //    themselves created (fee_transactions/fee_receipts/finance_income/
    //    finance_ledger), not just the pre-seeded fixtures.
    await _expectFixturesUntouched(firestore, fixtures);
    for (final collection in _mustNeverGainAcademicYearId) {
      await _expectNoAcademicYearIdField(firestore, collection);
    }

    // 2. The only two collections that DO carry the new field, correctly.
    final structureDoc = (await firestore.collection('fee_structures').doc(structureId).get()).data()!;
    expect(structureDoc['academicYearId'], yearId);
    final assignmentDoc = (await firestore.collection('student_fee_assignments').doc(assignmentId).get()).data()!;
    expect(assignmentDoc['academicYearId'], yearId);

    // 3. Sanity: fee_transactions/fee_receipts/finance_income were in fact
    //    created by this flow (proving the "never touch" assertion above
    //    is meaningful, not vacuously true from an empty collection).
    final txCount = (await firestore.collection('fee_transactions').get()).docs.length;
    final receiptCount = (await firestore.collection('fee_receipts').get()).docs.length;
    final incomeCount = (await firestore.collection('finance_income').get()).docs.length;
    expect(txCount, greaterThan(0));
    expect(receiptCount, greaterThan(0));
    expect(incomeCount, greaterThan(0));
  });
}
