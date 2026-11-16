// Fee Bill Issuance (docs/fee_bill_issuance.md): supplementary month-wise
// bills issued against an existing payment. A bill is a document, never a
// payment: these tests issue, adjust, cancel, reissue and reprint bills
// against a real collected payment and check that no payment, receipt,
// assignment or Finance record changes. Numbers refer to the task's list.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_details_dialog.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_issuance_page.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_pdf.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

/// The words a PDF made by the `pdf` package draws, in order.
String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final words = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      final content = latin1.decode(ZLibDecoder().convert(bytes.sublist(m.end, end)));
      for (final w in RegExp(r'\[\((.*?)\)\]TJ').allMatches(content)) {
        words.add(w.group(1)!.replaceAllMapped(RegExp(r'\\([()\\])'), (x) => x.group(1)!));
      }
    } catch (_) {}
  }
  return words.join(' ');
}

const school = FeeBillSchool(name: '2D Eduvance Montessori', addressLines: ['12, Lake View Road', 'Anna Nagar, Chennai, Tamil Nadu - 600040'], contactLines: ['Phone: 044 1234 5678']);

FeeBillLine line(String month, int rupees, {int adjustment = 0, String description = 'Monthly tuition fee', String reason = 'Rounded to the amount paid'}) => FeeBillLine(
      billingMonth: month,
      description: description,
      grossPaise: rupees * 100,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment * 100,
      adjustmentReason: adjustment > 0 ? reason : '',
    );

/// The example: September and October ₹4,200, November ₹4,200 less ₹100.
final example = [line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200, adjustment: 100)];

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late FeeBillService bills;
  late FeeReceiptModel receipt;
  late String assignmentId;
  var request = 0;
  String nextRequest() => 'req-${request++}';

  Future<List<FeeIssuedBill>> issue(List<FeeBillLine> lines, {String role = 'admin', String? receiptId, String studentId = 's1', String? requestId}) =>
      bills.issueBills(requesterRole: role, studentId: studentId, receiptId: receiptId ?? receipt.id, lines: lines, requestId: requestId ?? nextRequest(), school: school);

  /// Every record Fee Bill Issuance must never change, exactly as stored.
  Future<Map<String, Object?>> records() async => {
        for (final c in ['fee_receipts', 'fee_transactions', 'student_fee_assignments', 'fee_structures', 'students', 'classes', 'finance_income', 'finance_ledger', 'finance_accounts', 'finance_expenses', 'school_calendar_events'])
          c: {for (final d in (await firestore.collection(c).get()).docs) d.id: d.data()},
      };

  Future<FeeBillAllocation> allocation() async => (await bills.getAllocation(receipt.id))!;

  /// The Bill Reference of this payment's [n]th bill.
  String ref(int n) => '${receipt.receiptNo}-${n.toString().padLeft(6, '0')}';

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1', displayName: 'Test Admin'));
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => DateTime(2026, 11, 5));
    bills = FeeBillService(firestore: firestore, auth: auth, clock: () => DateTime(2026, 11, 16, 10));
    final yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await firestore.collection('fee_structures').doc('term').set({
      'name': 'Term Fees', 'description': 'Montessori Fee', 'totalAmount': 12500, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't', 'components': [],
    });
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
    await firestore.collection('students').doc('s1').set({'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    await firestore.collection('students').doc('s2').set({'name': 'Bala K', 'admissionNo': 'ADM-102', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    assignmentId = (await fees.assignFee({
      'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    // The one payment of ₹12,500, recorded in Fees and Finance as usual.
    receipt = await fees.collectFee(assignmentId: assignmentId, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-778899', remarks: '');
  });

  group('bill lines and amounts', () {
    test('rupees are parsed to whole paise exactly', () {
      expect(parseRupees('4200'), 420000);
      expect(parseRupees('4,200.5'), 420050);
      expect(parseRupees('0.07'), 7);
      for (final bad in ['', '-1', '4200.123', 'abc', '1e3']) {
        expect(parseRupees(bad), isNull, reason: bad);
      }
      expect(rupeesText(410000), '4100');
      expect(rupeesText(410050), '4100.50');
    });

    test('C. validation: adjustment non-negative, not above gross, with a type and reason; net never negative', () {
      expect(line('2026-11', 4200, adjustment: 100).error, isNull);
      expect(line('2026-11', 4200, adjustment: 100).netPaise, 410000);
      expect(line('2026-11', 4200, adjustment: 4200).netPaise, 0);
      expect(line('2026-11', 4200, adjustment: 4300).error, contains('cannot be more than the gross'));
      expect(const FeeBillLine(billingMonth: '2026-11', description: 'x', grossPaise: 100, adjustmentPaise: -1, adjustmentType: FeeBillAdjustmentType.other, adjustmentReason: 'r').error, contains('negative'));
      expect(line('2026-11', 4200, adjustment: 100, reason: ' ').error, contains('reason'));
      expect(const FeeBillLine(billingMonth: '2026-11', description: 'x', grossPaise: 100, adjustmentPaise: 10).error, contains('adjustment type'));
      expect(line('2026-13', 4200).error, contains('billing month'));
      expect(line('2026-11', 4200, description: ' ').error, contains('description'));
      expect(line('2026-11', 0).error, contains('more than'));
    });
  });

  group('issuing', () {
    test('1, 2. one ₹12,500 payment, three monthly bills: ₹12,600 gross less ₹100 bill-only adjustment = ₹12,500 net', () async {
      final issued = await issue(example);
      expect([for (final b in issued) b.billNo], [ref(1), ref(2), ref(3)]);
      expect([for (final b in issued) b.line.billingMonth], ['2026-09', '2026-10', '2026-11']);
      expect([for (final b in issued) b.line.netPaise], [420000, 420000, 410000]);
      final t = FeeBillTotals.of(await bills.getBills());
      expect((t.issued, t.grossPaise, t.adjustmentPaise, t.netPaise), (3, 1260000, 10000, 1250000));
      final a = await allocation();
      expect((a.paymentPaise, a.allocatedPaise, a.availableFor(a.paymentPaise)), (1250000, 1250000, 0), reason: 'fully allocated: net bills = the payment');
      for (final b in issued) {
        expect(b.payment.receiptId, receipt.id);
        expect(b.payment.receiptNo, receipt.receiptNo);
      }
      final stored = (await firestore.collection(FeeBillService.billsCollection).doc(issued.last.id).get()).data()!;
      expect(stored['adjustment'], {'type': 'discount', 'amountPaise': 10000, 'reason': 'Rounded to the amount paid', 'createdBy': 'admin-1', 'createdAt': isNotNull});
      expect(issued.last.id, '${kDefaultSchoolId}_${ref(3)}');
    });

    test('3, 4, 5. issuing, adjusting, cancelling, reissuing and reprinting change no assignment, payment, receipt or Finance record', () async {
      final before = await records();
      final assignment = await fees.getAssignmentById(assignmentId);
      final issued = await issue(example);
      await bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: 'Wrong amount', replacement: line('2026-11', 4100));
      await bills.recordReprint(requesterRole: 'admin', billId: issued.first.id);
      expect(await records(), before, reason: 'assignments (payable, paid, balance), fee transactions, receipts, structures, students, Finance income, ledger and accounts unchanged');
      final after = await fees.getAssignmentById(assignmentId);
      expect((after!.payableAmount, after.paidAmount, after.balanceAmount, after.discountAmount), (assignment!.payableAmount, assignment.paidAmount, assignment.balanceAmount, assignment.discountAmount));
      expect((await firestore.collection('finance_income').get()).docs, hasLength(1), reason: 'only the original collection’s income entry');
      expect((await firestore.collection('finance_ledger').get()).docs, hasLength(1));
      expect((await fees.getReceipts()).single.receiptNo, receipt.receiptNo, reason: 'no new receipt');
    });

    test('6. net bills can never exceed the payment; nothing is written when refused', () async {
      await expectLater(issue([line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200)]),
          throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('₹12,600.00'), contains('₹12,500.00')))));
      expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, isEmpty);
      expect(await bills.getAllocation(receipt.id), isNull);
      expect((await firestore.collection('system_counters').doc('fee_bills_$kDefaultSchoolId').get()).exists, isFalse, reason: 'no number used');
    });

    test('7. partial issuance shows the remaining unallocated amount; the rest can be billed later', () async {
      await issue([line('2026-09', 4200)]);
      var a = await allocation();
      expect(a.availableFor(a.paymentPaise), 830000);
      await expectLater(issue([line('2026-10', 8400)]), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('only ₹8,300.00'))));
      await issue([line('2026-10', 4200), line('2026-11', 4100)]);
      a = await allocation();
      expect(a.availableFor(a.paymentPaise), 0);
      expect([for (final b in await bills.getBills()) b.billNo]..sort(), [ref(1), ref(2), ref(3)], reason: 'consecutive numbers across issues');
    });

    test('8. duplicates: a repeated request returns the same bills; an active line for the same month and item is refused', () async {
      final first = await issue(example, requestId: 'press-1');
      final again = await issue(example, requestId: 'press-1');
      expect([for (final b in again) b.billNo], [for (final b in first) b.billNo]);
      expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, hasLength(3));
      await bills.cancelBill(requesterRole: 'admin', billId: first.first.id, reason: 'Test');
      await expectLater(issue([line('2026-10', 100)]), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('${ref(2)} has already been issued'))));
      await expectLater(issue([line('2026-09', 100), line('2026-09', 100, description: ' monthly  TUITION fee')]),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('same month and description'))));
      expect((await issue([line('2026-09', 4200)])).single.billNo, ref(4), reason: 'September may be billed again once its bill is cancelled');
    });

    test('9. a missing, voided, other-student or other-school payment is refused', () async {
      await expectLater(issue([line('2026-09', 100)], receiptId: 'nope'), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.notFoundMessage)));
      await expectLater(issue([line('2026-09', 100)], studentId: 's2'), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.otherStudentMessage)));
      await firestore.collection('fee_receipts').doc('other-school').set({...receipt.toMap(), 'schoolId': 'school-b'});
      await expectLater(issue([line('2026-09', 100)], receiptId: 'other-school'), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.otherSchoolMessage)));
      expect(await bills.paymentsForStudent('s1'), hasLength(1), reason: 'another school’s receipt is not offered');
      final otherSchoolBills = FeeBillService(firestore: firestore, auth: MockFirebaseAuth(signedIn: true), schoolId: 'school-b');
      await expectLater(
        otherSchoolBills.issueBills(requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, lines: [line('2026-09', 100)], requestId: 'x', school: school),
        throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.otherSchoolMessage)),
      );
      await fees.voidReceipt(receipt.id);
      await expectLater(issue([line('2026-09', 100)]), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.voidedMessage)));
      expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, isEmpty);
    });

    test('10. concurrent issuance can never use the same unallocated amount twice', () async {
      final results = await Future.wait([
        issue([line('2026-09', 8000)]).then<Object>((b) => b, onError: (Object e) => e),
        issue([line('2026-10', 8000)]).then<Object>((b) => b, onError: (Object e) => e),
      ]);
      expect(results.whereType<List<FeeIssuedBill>>(), hasLength(1));
      expect(results.whereType<StateError>().single.message, contains('only ₹4,500.00'));
      final a = await allocation();
      expect((a.allocatedPaise, a.bills.length), (800000, 1));
      expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, hasLength(1));
    });
  });

  group('Bill Reference', () {
    Future<String> otherReceipt(String id, String receiptNo, {double amount = 5000}) async {
      await firestore.collection('fee_receipts').doc(id).set({...receipt.toMap(), 'receiptNo': receiptNo, 'amount': amount, 'transactionId': 't-$id'});
      return id;
    }

    test('receipt number + six-digit sequence; usable receipt numbers only', () {
      expect(FeeBillService.billReference('REC-2026-1792729533955', 1), 'REC-2026-1792729533955-000001');
      expect(FeeBillService.billReference('REC-2026-1792729533955', 123456), 'REC-2026-1792729533955-123456');
      expect(FeeBillService.referenceBaseOf('REC-2026-1792729533955'), 'REC-2026-1792729533955');
      for (final bad in ['', ' ', 'REC 2026', 'REC/2026/1', 'REC-2026-1 ', ' REC-1', 'REC--1', '-REC', 'REC-', 'REC_1', 'रसीद-1', 'R' * 34]) {
        expect(FeeBillService.referenceBaseOf(bad), isNull, reason: bad);
      }
    });

    test('1, 2, 7. numbered separately for each payment and stored on the bill and in its history', () async {
      final first = await issue(example);
      final otherId = await otherReceipt('r2', 'REC-2026-2');
      final other = await issue([line('2026-12', 4200)], receiptId: otherId);
      expect([for (final b in first) b.billNo], [ref(1), ref(2), ref(3)]);
      expect(other.single.billNo, 'REC-2026-2-000001', reason: 'its own sequence');
      final stored = (await firestore.collection(FeeBillService.billsCollection).doc(first.last.id).get()).data()!;
      expect((stored['billNo'], first.last.id), (ref(3), '${kDefaultSchoolId}_${ref(3)}'));
      expect((await allocation()).nextSequence, 4);
      expect((await bills.history(first.last.id)).first['billNo'], ref(3));
      expect((await firestore.collection('system_counters').get()).docs, isEmpty, reason: 'no shared counter');
    });

    test('4, 5. never reused: after a cancellation, and for a replacement', () async {
      final issued = await issue([line('2026-09', 4200), line('2026-10', 4200)]);
      await bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: 'not needed');
      expect((await issue([line('2026-10', 4200)])).single.billNo, ref(3), reason: 'not ${ref(2)} again');
      final replacement = (await bills.cancelBill(requesterRole: 'admin', billId: issued.first.id, reason: 'amount', replacement: line('2026-09', 4100)))!;
      expect(replacement.billNo, ref(4));
      expect((await bills.history(issued.first.id)).last['replacedBy'], ref(4));
      expect((await allocation()).nextSequence, 5);
      expect((await bills.getBill(issued.last.id))!.billNo, ref(2), reason: 'the cancelled bill keeps its reference');
    });

    test('3. concurrent issues against one payment get distinct consecutive references; different payments don’t interfere', () async {
      final otherId = await otherReceipt('r2', 'REC-2026-2', amount: 9000);
      final results = await Future.wait([
        issue([line('2026-09', 4000)]),
        issue([line('2026-10', 4000)]),
        issue([line('2026-09', 4000)], receiptId: otherId),
        issue([line('2026-10', 4000)], receiptId: otherId),
      ]);
      expect({for (final r in results.take(2)) r.single.billNo}, {ref(1), ref(2)});
      expect({for (final r in results.skip(2)) r.single.billNo}, {'REC-2026-2-000001', 'REC-2026-2-000002'});
      expect((await allocation()).nextSequence, 3);
    });

    test('6. a reprint keeps the Bill Reference', () async {
      final b = (await issue([line('2026-09', 4200)])).single;
      final again = (await bills.getBill(b.id))!;
      await bills.recordReprint(requesterRole: 'admin', billId: b.id);
      expect(pdfText(await FeeBillPdf.build(again, reprintedAt: DateTime(2027))), allOf(contains('Bill Reference: ${ref(1)}'), contains('Receipt Reference ${receipt.receiptNo}')));
      expect((await bills.getBill(b.id))!.billNo, ref(1));
    });

    test('10. an unusable or shared receipt number is refused; nothing is written; receipt numbers are never changed', () async {
      for (final (id, no) in [('r-empty', ''), ('r-space', 'REC 2026 9'), ('r-slash', 'REC/2026/9'), ('r-long', 'R' * 40)]) {
        await otherReceipt(id, no);
        await expectLater(issue([line('2026-09', 100)], receiptId: id),
            throwsA(isA<StateError>().having((e) => e.message, 'message', contains("can't be used for Bill References"))), reason: no);
      }
      await otherReceipt('dup-a', 'REC-2026-7');
      await otherReceipt('dup-b', 'REC-2026-7');
      await expectLater(issue([line('2026-09', 100)], receiptId: 'dup-a'),
          throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.sharedReceiptNoMessage('REC-2026-7'))));
      expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, isEmpty);
      expect((await firestore.collection(FeeBillService.allocationsCollection).get()).docs, isEmpty);
      expect((await firestore.collection('fee_receipts').doc('r-space').get()).data()!['receiptNo'], 'REC 2026 9');
    });
  });

  group('cancellation, reissue and reprint', () {
    test('11, 14. cancelling keeps the bill, records who, when and why, and releases its net amount', () async {
      final issued = await issue(example);
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: '  '), throwsA(isA<StateError>()));
      final replacement = await bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: 'Parent asked for a different amount');
      expect(replacement, isNull);
      final cancelled = (await bills.getBill(issued.last.id))!;
      expect(cancelled.status, FeeBillStatus.cancelled);
      expect((cancelled.cancellationReason, cancelled.cancelledBy, cancelled.cancelledAt), ('Parent asked for a different amount', 'admin-1', DateTime(2026, 11, 16, 10)));
      expect((cancelled.billNo, cancelled.line.netPaise, cancelled.line.adjustmentPaise), (ref(3), 410000, 10000), reason: 'record preserved');
      final a = await allocation();
      expect((a.allocatedPaise, a.availableFor(a.paymentPaise), a.bills.containsKey(issued.last.id)), (840000, 410000, false));
      expect(FeeBillTotals.of(await bills.getBills()).cancelled, 1);
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: 'again'),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('already cancelled'))));
      final history = await bills.history(issued.last.id);
      expect([for (final h in history) h['action']], ['issued', 'cancelled']);
      expect(history.first, containsPair('adjustmentPaise', 10000));
      expect(history.first, containsPair('adjustmentType', 'discount'));
      expect(history.first, containsPair('adjustmentReason', 'Rounded to the amount paid'));
      expect(history.last, allOf(containsPair('reason', 'Parent asked for a different amount'), containsPair('releasedPaise', 410000), containsPair('by', 'admin-1')));
    });

    test('12. cancel and reissue: the replacement gets a new number and both are linked', () async {
      final issued = await issue(example);
      final replacement = (await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Item name', replacement: line('2026-10', 4200, description: 'Tuition fee (October)')))!;
      expect(replacement.billNo, ref(4));
      expect(replacement.replacesBillId, issued[1].id);
      expect((await bills.getBill(issued[1].id))!.replacedByBillId, replacement.id);
      final a = await allocation();
      expect(a.allocatedPaise, 1250000);
      expect(a.bills.keys.toSet(), {issued[0].id, issued[2].id, replacement.id});
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued[0].id, reason: 'x', replacement: line('2026-09', 4300)),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('only ₹4,200.00'))), reason: 'a replacement is checked against the payment too');
      expect((await bills.getBill(issued[0].id))!.isCancelled, isFalse, reason: 'refused as a whole');
    });

    test('a cancellation that would leave the allocation inconsistent is refused', () async {
      final issued = await issue(example);
      await firestore.collection(FeeBillService.allocationsCollection).doc(receipt.id).update({'allocatedPaise': 1});
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued.first.id, reason: 'x'),
          throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.inconsistentMessage)));
      await expectLater(issue([line('2026-12', 1)]), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeBillService.inconsistentMessage)));
      expect((await bills.getBill(issued.first.id))!.isCancelled, isFalse);
    });

    test('13. a reprint keeps the bill number and stored snapshot and is recorded in the history', () async {
      final issued = await issue(example);
      final storedBefore = (await firestore.collection(FeeBillService.billsCollection).doc(issued.last.id).get()).data();
      // School Settings changing later doesn't change an issued bill.
      await firestore.collection('school_settings').doc(kDefaultSchoolId).set({'name': 'Renamed School'});
      final b = (await bills.getBill(issued.last.id))!;
      final original = pdfText(await FeeBillPdf.build(b));
      final reprint = pdfText(await FeeBillPdf.build(b, reprintedAt: DateTime(2026, 12, 1)));
      await bills.recordReprint(requesterRole: 'admin', billId: b.id);
      expect(reprint, contains('Bill Reference: ${ref(3)}'));
      expect(reprint, contains('2D Eduvance Montessori'));
      expect(reprint, contains('Reprint generated on 01 Dec 2026'));
      expect(reprint.replaceAll(RegExp(r' ?Reprint generated on .*? unchanged\.'), ''), original, reason: 'otherwise the same document');
      expect((await firestore.collection(FeeBillService.billsCollection).doc(issued.last.id).get()).data(), storedBefore);
      expect([for (final h in await bills.history(b.id)) h['action']], ['issued', 'reprinted']);
    });

    test('15. only an administrator can issue, cancel or record a reprint', () async {
      for (final role in ['staff', 'teacher', 'parent', '']) {
        await expectLater(issue(example, role: role), throwsA(isA<UnauthorizedFeeBillException>()));
      }
      final issued = await issue(example);
      for (final role in ['staff', 'parent']) {
        await expectLater(bills.cancelBill(requesterRole: role, billId: issued.first.id, reason: 'x'), throwsA(isA<UnauthorizedFeeBillException>()));
        await expectLater(bills.recordReprint(requesterRole: role, billId: issued.first.id), throwsA(isA<UnauthorizedFeeBillException>()));
      }
      expect((await bills.getBill(issued.first.id))!.isCancelled, isFalse);
    });
  });

  group('16. PDF', () {
    test('one fee bill per month in the regenerated receipt’s layout, with the adjustment and the Receipt Reference', () async {
      final issued = await issue(example);
      final nov = pdfText(await FeeBillPdf.build(issued.last));
      for (final expected in [
        '2D Eduvance Montessori', '12, Lake View Road', 'Phone: 044 1234 5678',
        'FEE BILL', 'Bill Reference: ${ref(3)}', 'Issue Date: 02 Nov 2026',
        'Student Name Anu Raman', 'Admission No ADM-101', 'Class Mont 1',
        'Billing Month November 2026', 'Fee Particulars Monthly tuition fee', 'Gross Amount Rs. 4,200.00',
        'Bill-only Adjustment (Discount adjustment) - Rs. 100.00', 'Adjustment Reason Rounded to the amount paid',
        'Receipt Reference ${receipt.receiptNo}',
        'Net Bill Amount Rs. 4,100.00 Amount in Words: Rupees Four Thousand One Hundred Only',
        FeeBillPdf.footer,
      ]) {
        expect(nov, contains(expected));
      }
      for (final absent in [
        // 7, 8: no original payment date or reference; 16: no disclaimer.
        'Original Payment Date', 'Original Payment Reference', 'UPI-778899', '05 Nov 2026', 'Original Receipt No',
        'supplementary', 'official record of payment', 'not a separate payment receipt',
        'FEE PAYMENT RECEIPT', 'Amount Paid', 'CANCELLED', 'PREVIEW', 'Reprint', 'Rs. 12,500', 'GSTIN', 'GST Included', "'s Name",
      ]) {
        expect(nov, isNot(contains(absent)), reason: absent);
      }
      final sep = pdfText(await FeeBillPdf.build(issued.first));
      expect(sep, contains('Billing Month September 2026'));
      expect(sep, contains('Issue Date: 01 Sep 2026'));
      expect(sep, contains('Net Bill Amount Rs. 4,200.00'));
      expect(sep, isNot(contains('Adjustment')), reason: 'no adjustment row when there is none');
      expect(FeeBillPdf.fileName(issued.last), '${ref(3)}.pdf');
      final stored = (await firestore.collection(FeeBillService.billsCollection).doc(issued.last.id).get()).data()!;
      // The payment link stays in the record for traceability.
      expect(stored['receiptId'], receipt.id);
      expect((stored['payment'] as Map)['referenceNo'], 'UPI-778899');
      expect((stored['payment'] as Map)['paymentDate'], isNotNull);
    });

    test('a cancelled bill and an unissued preview are marked as not valid', () async {
      final issued = await issue(example);
      await bills.cancelBill(requesterRole: 'admin', billId: issued.first.id, reason: 'Duplicate request');
      expect(pdfText(await FeeBillPdf.build((await bills.getBill(issued.first.id))!)), allOf(contains('CANCELLED on 16 Nov 2026: Duplicate request'), contains('Bill Reference: ${ref(1)}')));
      final preview = pdfText(await FeeBillPdf.build(issued[1], preview: true));
      expect(preview, contains(FeeBillPdf.previewBanner));
      expect(preview, contains('Bill Reference: ${FeeBillPdf.pendingNumber}'));
    });
  });

  group('parent / guardian', () {
    Future<String> pdfFor(List<Map<String, String>> links) async {
      await firestore.collection('students').doc('s1').update({'parentLinks': links});
      final b = (await issue([line('2026-09', 4200)])).single;
      final text = pdfText(await FeeBillPdf.build((await bills.getBill(b.id))!));
      await bills.cancelBill(requesterRole: 'admin', billId: b.id, reason: 'test');
      return text;
    }

    test('1-4. father first, then mother, then guardian; no row when none is linked', () async {
      expect(await pdfFor([
        {'name': 'Lakshmi R', 'relation': 'Mother'},
        {'name': 'Raman K', 'relation': 'Father'},
      ]), contains("Father's Name Raman K"));
      expect(await pdfFor([
        {'name': 'Lakshmi R', 'relation': 'Mother'},
        {'name': 'Ravi S', 'relation': 'Guardian'},
      ]), allOf(contains("Mother's Name Lakshmi R"), isNot(contains('Ravi'))));
      expect(await pdfFor([
        {'name': 'Ravi S', 'relation': 'Other'},
      ]), contains("Guardian's Name Ravi S"));
      expect(await pdfFor([
        {'name': '', 'relation': 'Father'},
      ]), isNot(contains("'s Name")));
      expect(await pdfFor([]), isNot(contains("'s Name")));
    });

    test('the name is a snapshot: later changes to the student don’t alter an issued bill', () async {
      await firestore.collection('students').doc('s1').update({'parentLinks': [{'name': 'Raman K', 'relation': 'Father'}]});
      final b = (await issue([line('2026-09', 4200)])).single;
      await firestore.collection('students').doc('s1').update({'parentLinks': [{'name': 'Someone Else', 'relation': 'Father'}]});
      final stored = (await bills.getBill(b.id))!;
      expect((stored.parentRelation, stored.parentName), ('Father', 'Raman K'));
      expect(pdfText(await FeeBillPdf.build(stored, reprintedAt: DateTime(2027, 1, 5))), allOf(contains("Father's Name Raman K"), isNot(contains('Someone Else'))));
    });
  });

  group('GST', () {
    const gstin = '27AAPFU0939F1ZV';

    test('5, 6. Show GSTIN and Amount includes GST, as on the regenerated receipt; no GST is ever calculated', () async {
      for (final (show, includes) in [(false, false), (true, false), (false, true), (true, true)]) {
        final reason = 'show $show, includes $includes';
        final b = (await bills.issueBills(
          requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: nextRequest(),
          lines: [line('2026-09', 4200)], school: school.withGstin(show ? gstin : ''), amountIncludesGst: includes,
        )).single;
        final stored = (await bills.getBill(b.id))!;
        final t = pdfText(await FeeBillPdf.build(stored));
        expect(t.contains('GSTIN: $gstin'), show, reason: reason);
        if (show) expect(t.indexOf('GSTIN'), lessThan(t.indexOf('FEE BILL')), reason: 'in the header');
        expect(t.contains('Net Bill Amount Rs. 4,200.00 (GST Included)'), includes, reason: reason);
        expect(t.contains('GST Included'), includes, reason: reason);
        expect(stored.line.netPaise, 420000, reason: '$reason: the amount is never changed');
        expect(RegExp(r'Rs\. [0-9,]+\.[0-9]{2}').allMatches(t).map((m) => m.group(0)).toSet(), {'Rs. 4,200.00'}, reason: '$reason: no GST amount');
        await bills.cancelBill(requesterRole: 'admin', billId: b.id, reason: 'test');
      }
    });

    test('a replacement keeps the cancelled bill’s GST choices', () async {
      final b = (await bills.issueBills(
        requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: nextRequest(),
        lines: [line('2026-09', 4200)], school: school.withGstin(gstin), amountIncludesGst: true,
      )).single;
      final r = (await bills.cancelBill(requesterRole: 'admin', billId: b.id, reason: 'amount', replacement: line('2026-09', 4100)))!;
      final stored = (await bills.getBill(r.id))!;
      expect((stored.school.gstin, stored.amountIncludesGst), (gstin, true));
    });
  });

  group('issue date', () {
    Future<void> event(DateTime date, String type, {String status = 'Published'}) =>
        firestore.collection(FeeBillService.calendarCollection).add({'title': type, 'date': date, 'eventType': type, 'status': status, 'audience': 'Public'});

    test('10, 11. the first working day of the billing month, never the day issued; weekends skipped; across years', () async {
      expect(await bills.issueDateFor('2026-09'), DateTime(2026, 9, 1), reason: 'a Tuesday');
      expect(await bills.issueDateFor('2026-11'), DateTime(2026, 11, 2), reason: '1 November 2026 is a Sunday');
      expect(await bills.issueDateFor('2026-08'), DateTime(2026, 8, 3), reason: 'Saturday 1 and Sunday 2 August');
      expect(await bills.issueDateFor('2027-01'), DateTime(2027, 1, 1), reason: 'next year: a Friday');
      final issued = await issue([line('2026-09', 4200), line('2026-11', 4200), line('2027-01', 4100)]);
      expect([for (final b in issued) b.issueDate], [DateTime(2026, 9, 1), DateTime(2026, 11, 2), DateTime(2027, 1, 1)]);
      expect([for (final b in issued) b.issuedAt], everyElement(DateTime(2026, 11, 16, 10)), reason: 'when it was actually issued is kept separately');
    });

    test('12. published school holidays are skipped; a published Working Day counts; drafts and archived events are ignored', () async {
      await event(DateTime(2026, 9, 1), 'School Holiday');
      await event(DateTime(2026, 9, 2), 'School Holiday', status: 'Draft');
      await event(DateTime(2026, 8, 1), 'Working Day');
      await event(DateTime(2026, 10, 1), 'School Holiday', status: 'Archived');
      await event(DateTime(2027, 1, 1), 'School Holiday');
      await event(DateTime(2027, 1, 4), 'School Holiday');
      await event(DateTime(2027, 1, 4), 'Working Day');
      expect(await bills.issueDateFor('2026-09'), DateTime(2026, 9, 2));
      expect(await bills.issueDateFor('2026-08'), DateTime(2026, 8, 1), reason: 'a Saturday marked as a Working Day');
      expect(await bills.issueDateFor('2026-10'), DateTime(2026, 10, 1));
      expect(await bills.issueDateFor('2027-01'), DateTime(2027, 1, 5), reason: 'holiday on the 1st; the 4th is both, and the holiday wins');
    });

    test('13. reprinting keeps the stored issue date, even if the calendar changes later', () async {
      final b = (await issue([line('2026-09', 4200)])).single;
      await event(DateTime(2026, 9, 1), 'School Holiday');
      final stored = (await bills.getBill(b.id))!;
      expect(stored.issueDate, DateTime(2026, 9, 1));
      expect(pdfText(await FeeBillPdf.build(stored, reprintedAt: DateTime(2026, 12, 1))), contains('Issue Date: 01 Sep 2026'));
    });
  });

  group('class', () {
    test('14, 15. each bill keeps its own selected class; the student and receipt classes are unchanged; reprint keeps it', () async {
      final before = await records();
      final issued = await issue([
        FeeBillLine(billingMonth: '2026-09', description: 'Monthly tuition fee', grossPaise: 420000, className: 'Mont 2'),
        FeeBillLine(billingMonth: '2026-10', description: 'Monthly tuition fee', grossPaise: 420000, className: 'Mont 3'),
        line('2026-11', 4100),
      ]);
      expect([for (final b in issued) b.payment.className], ['Mont 2', 'Mont 3', 'Mont 1'], reason: 'no selection: the receipt’s class');
      expect(pdfText(await FeeBillPdf.build((await bills.getBill(issued[1].id))!)), contains('Class Mont 3'));
      await firestore.collection('classes').doc('c2').update({'name': 'Renamed'});
      expect(pdfText(await FeeBillPdf.build((await bills.getBill(issued[0].id))!, reprintedAt: DateTime(2027))), contains('Class Mont 2'));
      final after = await records();
      expect(after['students'], before['students']);
      expect(after['fee_receipts'], before['fee_receipts']);
    });
  });

  group('screens', () {
    Widget app(String role, Widget child) => ProviderScope(
          overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true))],
          child: MaterialApp(home: child),
        );

    Future<void> setView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> settle(WidgetTester tester, [int ms = 100]) async {
      await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await settle(tester);
    }

    FeeBillIssuancePage page(List<(Uint8List, String)> saved) => FeeBillIssuancePage(
          service: bills,
          loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': '2D Eduvance Montessori', 'address': '12, Lake View Road', 'phone': '044 1234 5678'}),
          loadLogo: (_) async => null,
          savePdf: (bytes, name) async => saved.add((bytes, name)),
          clock: () => DateTime(2026, 11, 16, 10),
        );

    testWidgets('UAT: an administrator issues the three bills for the ₹12,500 payment; nothing else changes', (tester) async {
      await setView(tester);
      final before = (await tester.runAsync(records))!;
      final saved = <(Uint8List, String)>[];
      await tester.pumpWidget(app('admin', page(saved)));
      await settle(tester);
      expect(find.byKey(const Key('fee-bills-empty')), findsOneWidget);
      await tap(tester, find.byKey(const Key('fee-bills-issue')));

      await tester.enterText(find.byKey(const Key('fee-bill-student-search')), 'anu');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-student-s1')));
      expect(find.textContaining('Not yet billed ₹12,500.00'), findsOneWidget);
      await tap(tester, find.byKey(Key('fee-bill-payment-${receipt.id}')));
      expect(find.byKey(const Key('fee-bill-payment-details')), findsOneWidget);
      expect(find.text('₹12,500.00'), findsWidgets);
      expect(find.text('UPI-778899'), findsOneWidget);

      // Three lines: September, October, November (₹100 bill-only adjustment).
      await tester.enterText(find.byKey(const Key('fee-bill-line-0-description')), 'Monthly tuition fee');
      await tester.enterText(find.byKey(const Key('fee-bill-line-0-gross')), '4200');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-line-0-month')));
      await tester.tap(find.text('September').last);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-add-line')));
      await tap(tester, find.byKey(const Key('fee-bill-add-line')));
      await tap(tester, find.byKey(const Key('fee-bill-line-2-adjustment-type')));
      await tester.tap(find.text('Discount adjustment').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('fee-bill-line-2-adjustment')), '100');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fee-bill-error')), findsOneWidget, reason: 'the reason is still missing');
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('fee-bill-review'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('fee-bill-line-2-reason')), 'Rounded to the amount paid');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('fee-bill-line-2-net'))).data, 'Net bill amount: ₹4,100.00');
      expect(tester.widget<Text>(find.byKey(const Key('fee-bill-summary-new'))).data, '₹12,500.00');
      expect(tester.widget<Text>(find.byKey(const Key('fee-bill-summary-remaining'))).data, '₹0.00');
      // October's bill for another class; the amounts include GST.
      await tap(tester, find.byKey(const Key('fee-bill-line-1-class')));
      await tester.tap(find.text('Mont 2').last);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-amount-includes-gst')));

      await tap(tester, find.byKey(const Key('fee-bill-review')));
      expect(find.byKey(const Key('fee-bill-preview')), findsOneWidget);
      expect(find.textContaining('November 2026 · Monthly tuition fee'), findsOneWidget);
      final nov = tester.widget<Text>(find.byKey(const Key('fee-bill-preview-details-2'))).data!;
      expect(nov, allOf(contains('Net ₹4,100.00 (GST Included)'), contains('Issue date 2 Nov 2026'), contains('Class Mont 1')));
      expect(tester.widget<Text>(find.byKey(const Key('fee-bill-preview-details-1'))).data, contains('Class Mont 2'));
      await tester.ensureVisible(find.byKey(const Key('fee-bill-preview-pdf-2')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('fee-bill-preview-pdf-2')));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();
      expect(pdfText(saved.single.$1), contains('PREVIEW - NOT ISSUED'));
      expect((await tester.runAsync(() => firestore.collection(FeeBillService.billsCollection).get()))!.docs, isEmpty, reason: 'a preview writes nothing');

      await tap(tester, find.byKey(const Key('fee-bill-issue')));
      expect(find.textContaining('3 separate bills totalling ₹12,500.00 net'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fee-bill-confirm-issue')));
      // The issue transaction completes on the real event loop.
      for (var i = 0; i < 20 && find.byKey(const Key('fee-bill-close')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      if (find.byKey(const Key('fee-bill-error')).evaluate().isNotEmpty) {
        fail('issue error: ${tester.widget<Text>(find.byKey(const Key('fee-bill-error'))).data}');
      }
      for (final n in [ref(1), ref(2), ref(3)]) {
        expect(find.byKey(Key('fee-bill-issued-$n')), findsOneWidget);
      }
      await tap(tester, find.byKey(const Key('fee-bill-close')));
      await settle(tester, 300);

      expect(find.byKey(Key('fee-bills-row-${ref(3)}')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('fee-bills-total-gross'))).data, '₹12,600.00');
      expect(tester.widget<Text>(find.byKey(const Key('fee-bills-total-adjustment'))).data, '₹100.00');
      expect(tester.widget<Text>(find.byKey(const Key('fee-bills-total-net'))).data, '₹12,500.00');
      final issued = (await tester.runAsync(bills.getBills))!;
      expect([for (final b in issued) (b.line.billingMonth, b.line.netPaise)]..sort((a, b) => a.$1.compareTo(b.$1)),
          [('2026-09', 420000), ('2026-10', 420000), ('2026-11', 410000)]);
      final byMonth = {for (final b in issued) b.line.billingMonth: b};
      expect([for (final m in ['2026-09', '2026-10', '2026-11']) byMonth[m]!.payment.className], ['Mont 1', 'Mont 2', 'Mont 1']);
      expect([for (final m in ['2026-09', '2026-10', '2026-11']) byMonth[m]!.issueDate], [DateTime(2026, 9, 1), DateTime(2026, 10, 1), DateTime(2026, 11, 2)]);
      expect(issued.every((b) => b.amountIncludesGst && b.school.gstin.isEmpty), isTrue);
      expect((await tester.runAsync(records))!, before, reason: 'the receipt, Fees records, balances and Finance are unchanged');
    });

    testWidgets('E, F. the bill details: download, original payment, history, and cancel and reissue with a new number', (tester) async {
      await setView(tester);
      final saved = <(Uint8List, String)>[];
      await tester.runAsync(() => issue(example));
      await tester.pumpWidget(app('admin', page(saved)));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('fee-bills-search')), ref(2));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('fee-bills-row-${ref(2)}')), findsOneWidget, reason: 'search by Bill Reference');
      expect(find.byKey(Key('fee-bills-row-${ref(1)}')), findsNothing);
      await tester.enterText(find.byKey(const Key('fee-bills-search')), 'November');
      await tester.pumpAndSettle();
      expect(find.byKey(Key('fee-bills-row-${ref(3)}')), findsOneWidget);
      expect(find.byKey(Key('fee-bills-row-${ref(1)}')), findsNothing);
      await tap(tester, find.byKey(Key('fee-bills-row-${ref(3)}')));
      expect(find.byType(FeeBillDetailsDialog), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('fee-bill-details-download')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('fee-bill-details-download')));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();
      expect(saved.single.$2, '${ref(3)}.pdf');
      await tap(tester, find.byKey(const Key('fee-bill-details-payment')));
      await settle(tester);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('₹12,500.00'), findsWidgets);
      await tap(tester, find.byKey(const Key('fee-bill-details-history')));
      await settle(tester);
      expect(find.textContaining('Issued ${ref(3)}: gross ₹4,200.00, discount adjustment ₹100.00 (Rounded to the amount paid), net ₹4,100.00'), findsOneWidget);

      await tap(tester, find.byKey(const Key('fee-bill-details-cancel')));
      await tap(tester, find.byKey(const Key('fee-bill-cancel-reissue')));
      await tester.enterText(find.byKey(const Key('fee-bill-reissue-adjustment')), '50');
      await tester.enterText(find.byKey(const Key('fee-bill-reissue-gross')), '4150');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-cancel-confirm')));
      expect(find.byKey(const Key('fee-bill-cancel-error')), findsOneWidget, reason: 'a reason is required');
      await tester.enterText(find.byKey(const Key('fee-bill-cancel-reason')), 'Parent asked for another amount');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('fee-bill-cancel-confirm')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.textContaining('cancelled and replaced by ${ref(4)}'), findsOneWidget);
      expect(find.textContaining('CANCELLED on 16 Nov 2026'), findsOneWidget);
      final replacement = (await tester.runAsync(() => bills.getBill('${kDefaultSchoolId}_${ref(4)}')))!;
      expect((replacement.line.grossPaise, replacement.line.adjustmentPaise, replacement.line.netPaise), (415000, 5000, 410000));
    });

    testWidgets('A. Fees has a Fee Bill Issuance entry', (tester) async {
      await setView(tester);
      await tester.pumpWidget(app('admin', AdminFeesScreen(service: fees)));
      await settle(tester);
      expect(find.byKey(const Key('fees-open-bill-issuance')), findsOneWidget);
      expect(find.text('Fee Bill Issuance'), findsOneWidget);
    });

    testWidgets('phone width: the page, the issue dialog and the bill details fit without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // One bill (with an adjustment), so the payment still has an amount to bill.
      await tester.runAsync(() => issue([example.last]));
      await tester.pumpWidget(app('admin', page([])));
      await settle(tester);
      await tap(tester, find.byKey(Key('fee-bills-row-${ref(1)}')));
      await tap(tester, find.byKey(const Key('fee-bill-details-history')));
      await tap(tester, find.byKey(const Key('fee-bill-details-close')));
      await tap(tester, find.byKey(const Key('fee-bills-issue')));
      await tester.enterText(find.byKey(const Key('fee-bill-student-search')), 'anu');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('fee-bill-student-s1')));
      await tap(tester, find.byKey(Key('fee-bill-payment-${receipt.id}')));
      await tap(tester, find.byKey(const Key('fee-bill-line-0-adjustment-type')));
      await tester.tap(find.text('Other adjustment').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fee-bill-line-0-reason')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('15. a staff user can view bills but has no Issue, Reprint or Cancel', (tester) async {
      await setView(tester);
      await tester.runAsync(() => issue(example));
      await tester.pumpWidget(app('staff', page([])));
      await settle(tester);
      expect(find.byKey(const Key('fee-bills-issue')), findsNothing);
      expect(find.text('Only an administrator can issue or cancel bills.'), findsOneWidget);
      await tap(tester, find.byKey(Key('fee-bills-row-${ref(1)}')));
      expect(find.byKey(const Key('fee-bill-details-cancel')), findsNothing);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('fee-bill-details-reprint'))).onPressed, isNull);
    });
  });
}
