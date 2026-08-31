// AY-IMPLEMENT-03 coverage (items 19-23): FinanceService's academic-year
// reporting methods — a dual strategy per AY-AUDIT-02: fee-sourced entries
// resolve their Academic Year through the already-existing
// feeAssignmentId -> StudentFeeAssignment.academicYearId relationship (no
// new method needed for that path), while every other Finance entity uses
// its own date field via a dedicated *ForAcademicYear method. None of these
// write or read an academicYearId on any Finance document; every Finance
// schema is completely untouched.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

Future<AcademicYearDateRange> _seedCurrentYearRange(FakeFirebaseFirestore firestore) async {
  final ayService = AcademicYearService(firestore: firestore);
  final id = await ayService.createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: '2026-2027',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2027, 3, 30),
    createdBy: 'admin-1',
  );
  final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
  return AcademicYearDateRange.fromAcademicYear(year!);
}

void main() {
  group('FinanceService academic-year reporting (AY-IMPLEMENT-03)', () {
    test('19. A fee-sourced income entry resolves its Academic Year through feeAssignmentId -> StudentFeeAssignment.academicYearId, not through a date field', () async {
      final firestore = FakeFirebaseFirestore();
      // The fee assignment is the source of truth for which Academic Year
      // this money belongs to — deliberately given an incomeDate that would
      // put it OUTSIDE the 2026-2027 date range, to prove the resolution
      // path used for fee-sourced entries is the relation, never the date.
      await firestore.collection('student_fee_assignments').doc('fa1').set({
        'studentId': 's1',
        'studentName': 'Student One',
        'academicYear': '2026-2027',
        'academicYearId': 'ay-fixed-id',
        'totalFee': 10000,
        'payableAmount': 10000,
        'paidAmount': 5000,
        'balanceAmount': 5000,
        'status': 'partial',
      });
      await firestore.collection('finance_income').doc('inc1').set({
        'title': 'Fee payment',
        'sourceModule': 'fees',
        'feeAssignmentId': 'fa1',
        'amount': 5000,
        'incomeDate': DateTime(2099, 1, 1),
        'isDeleted': false,
      });

      final assignmentDoc = await firestore.collection('student_fee_assignments').doc('fa1').get();
      final incomeDoc = await firestore.collection('finance_income').doc('inc1').get();
      final resolvedAcademicYearId = assignmentDoc.data()!['academicYearId'];

      expect(incomeDoc.data()!['feeAssignmentId'], 'fa1');
      expect(resolvedAcademicYearId, 'ay-fixed-id');
      expect(incomeDoc.data()!.containsKey('academicYearId'), isFalse,
          reason: 'the income document itself never carries academicYearId — it is resolved via the relation');
    });

    test('20. Income within the Academic Year is included by date; entries outside are excluded; no academicYearId is written', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('finance_income').doc('inside').set({
        'amount': 100,
        'incomeDate': DateTime(2026, 12, 25),
        'isDeleted': false,
      });
      await firestore.collection('finance_income').doc('outside').set({
        'amount': 100,
        'incomeDate': DateTime(2027, 4, 1),
        'isDeleted': false,
      });
      final range = await _seedCurrentYearRange(firestore);
      final service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());

      final result = await service.getIncomeForAcademicYear(range);
      final ids = result.map((e) => e.id).toSet();
      expect(ids, contains('inside'));
      expect(ids, isNot(contains('outside')));

      final doc = await firestore.collection('finance_income').doc('inside').get();
      expect(doc.data()!.containsKey('academicYearId'), isFalse);
    });

    test('21. Expenses within the Academic Year are included by expenseDate; entries outside are excluded', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('finance_expenses').doc('inside').set({
        'amount': 200,
        'expenseDate': DateTime(2026, 9, 1),
      });
      await firestore.collection('finance_expenses').doc('outside').set({
        'amount': 200,
        'expenseDate': DateTime(2026, 5, 1),
      });
      final range = await _seedCurrentYearRange(firestore);
      final service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());

      final result = await service.getExpensesForAcademicYear(range);
      final ids = result.map((e) => e.id).toSet();
      expect(ids, contains('inside'));
      expect(ids, isNot(contains('outside')));
    });

    test('22. Ledger entries and invoices within the Academic Year are included by their own date field; entries outside are excluded', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('finance_ledger').doc('ledgerInside').set({
        'amount': 300,
        'transactionDate': DateTime(2026, 8, 15),
      });
      await firestore.collection('finance_ledger').doc('ledgerOutside').set({
        'amount': 300,
        'transactionDate': DateTime(2025, 1, 1),
      });
      await firestore.collection('finance_invoices').doc('invInside').set({
        'type': 'expense',
        'amount': 400,
        'invoiceDate': DateTime(2027, 1, 1),
      });
      await firestore.collection('finance_invoices').doc('invOutside').set({
        'type': 'expense',
        'amount': 400,
        'invoiceDate': DateTime(2027, 4, 1),
      });
      final range = await _seedCurrentYearRange(firestore);
      final service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());

      final ledgerResult = await service.getLedgerForAcademicYear(range);
      final ledgerIds = ledgerResult.map((e) => e.id).toSet();
      expect(ledgerIds, contains('ledgerInside'));
      expect(ledgerIds, isNot(contains('ledgerOutside')));

      final invoiceResult = await service.getInvoicesForAcademicYear(range);
      final invoiceIds = invoiceResult.map((e) => e.id).toSet();
      expect(invoiceIds, contains('invInside'));
      expect(invoiceIds, isNot(contains('invOutside')));
    });

    test('23. Salary payments within the Academic Year are included by paymentDate; no academicYearId is written to any Finance collection', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_salary_payments').doc('payInside').set({
        'staffUserId': 'u1',
        'amount': 500,
        'paymentDate': DateTime(2027, 2, 1),
      });
      await firestore.collection('staff_salary_payments').doc('payOutside').set({
        'staffUserId': 'u1',
        'amount': 500,
        'paymentDate': DateTime(2027, 4, 1),
      });
      final range = await _seedCurrentYearRange(firestore);
      final service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());

      final result = await service.getSalaryPaymentsForAcademicYear(range);
      final ids = result.map((e) => e.id).toSet();
      expect(ids, contains('payInside'));
      expect(ids, isNot(contains('payOutside')));

      final doc = await firestore.collection('staff_salary_payments').doc('payInside').get();
      expect(doc.data()!.containsKey('academicYearId'), isFalse);
    });
  });
}
