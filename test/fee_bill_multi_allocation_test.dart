// Fee Bill Issuance Phase 2: bills supported by several payments, payments
// supporting several bills, and partial allocations, through the allocation
// ledger (docs/fee_bill_issuance.md). Payments here are real collections
// (FeeService.collectFee: receipt + Fees transaction + Finance income);
// every test checks that bills never create or change them.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_pdf.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
import 'package:montessori_app/modules/fees/models/amount_in_words.dart';
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_fee_bill_refresh.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projections.dart';

import 'support/buffered_transaction_firestore.dart';

const school = FeeBillSchool(name: '2D Montessori', addressLines: ['12, Lake View Road'], contactLines: ['Phone: 044 1234 5678']);
const father = '9000000001', mother = '9000000002', guardian = '9000000003', otherFather = '9000000008';

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

FeeBillLine line(String month, int paise, {int adjustment = 0, String description = 'Monthly tuition fee'}) => FeeBillLine(
      billingMonth: month,
      description: description,
      grossPaise: paise,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment,
      adjustmentReason: adjustment > 0 ? 'Rounded to the amount paid' : '',
    );

/// ₹ as paise.
int rs(num rupees) => (rupees * 100).round();

void main() {
  late BufferedTransactionFirestore db;
  late FeeService fees;
  late FeeBillService bills;
  late String yearId;
  var request = 0;

  setUp(() async {
    registerParentFeeBillRefresh();
    db = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1'));
    final finance = FinanceService(firestore: db, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: db, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => DateTime(2026, 11, 5));
    bills = FeeBillService(firestore: db, auth: auth, clock: () => DateTime(2026, 11, 16, 10));
    yearId = await AcademicYearService(firestore: db).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await db.collection('fee_structures').doc('term').set({'name': 'Term Fees', 'totalAmount': 50000, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'components': []});
    await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name) in [('s1', 'Anu Raman'), ('s2', 'Bala Kumar')]) {
      await db.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    }
    final links = ParentLinkService(firestore: db);
    await links.saveLinksForStudent(studentId: 's1', parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi Raman', phone: father),
      ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena Raman', phone: mother),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
    await links.saveLinksForStudent(studentId: 's2', parents: const [ParentLinkEntry(userId: otherFather, relation: 'Father', name: 'Kumar', phone: otherFather)]);
    final access = ParentAccessService(firestore: db);
    await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  });

  tearDown(() {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
  });

  final assignments = <String, String>{};

  /// A real collection of ₹[rupees] from [student] on [date] (receipt,
  /// Fees transaction and Finance income, as Fees records it).
  Future<FeeReceiptModel> pay(num rupees, DateTime date, {String student = 's1'}) async {
    final key = '$student-${db.hashCode}';
    assignments[key] ??= (await fees.assignFee({
      'studentId': student, 'studentName': student == 's1' ? 'Anu Raman' : 'Bala Kumar', 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 50000, 'discountAmount': 0, 'payableAmount': 50000, 'paidAmount': 0, 'balanceAmount': 50000, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    // Receipt numbers are made from the clock's milliseconds.
    await Future<void>.delayed(const Duration(milliseconds: 3));
    return fees.collectFee(assignmentId: assignments[key]!, amount: rupees.toDouble(), paymentDate: date, paymentMode: 'cash', referenceNo: 'REF', remarks: '');
  }

  Future<List<FeeIssuedBill>> issue(List<FeeBillDraft> drafts, {String student = 's1', String? requestId}) => bills.issueAllocatedBills(
      requesterRole: 'admin', studentId: student, drafts: drafts, requestId: requestId ?? 'req-${request++}', school: school);

  FeeBillDraft draft(String month, int paise, Map<String, int> allocations, {int adjustment = 0}) =>
      FeeBillDraft(line: line(month, paise, adjustment: adjustment), allocations: allocations);

  Future<int> available(String receiptId) async {
    final r = (await bills.paymentBalancesForStudent('s1')).firstWhere((b) => b.payment.receiptId == receiptId);
    return r.availablePaise;
  }

  Future<Map<String, Map<String, dynamic>>> ledger() async => {for (final d in (await db.collection(FeeBillService.ledgerCollection).get()).docs) d.id: d.data()};
  Future<Map<String, Map<String, dynamic>>> reversals() async => {for (final d in (await db.collection(FeeBillService.reversalsCollection).get()).docs) d.id: d.data()};

  /// Every record bills must never change.
  Future<Map<String, Object?>> money() async => {
        for (final c in ['fee_receipts', 'fee_transactions', 'student_fee_assignments', 'finance_income', 'finance_ledger', 'finance_accounts', 'finance_expenses'])
          c: {for (final d in (await db.collection(c).get()).docs) d.id: d.data()},
      };

  /// Every Fee Bill Issuance record.
  Future<Map<String, Object?>> billRecords() async => {
        for (final c in [FeeBillService.billsCollection, FeeBillService.allocationsCollection, FeeBillService.ledgerCollection, FeeBillService.reversalsCollection, FeeBillService.requestsCollection])
          c: {for (final d in (await db.collection(c).get()).docs) d.id: d.data()},
      };

  String ref(FeeReceiptModel r, int n) => '${r.receiptNo}-${n.toString().padLeft(6, '0')}';

  group('A–D. payment-to-bill combinations', () {
    test('A. one payment → three bills (₹4,200 + ₹4,200 + ₹4,100 = ₹12,500), all referencing it', () async {
      final p = await pay(12500, DateTime(2026, 11, 5));
      final before = await money();
      final issued = await issue([
        draft('2026-09', rs(4200), {p.id: rs(4200)}),
        draft('2026-10', rs(4200), {p.id: rs(4200)}),
        draft('2026-11', rs(4200), {p.id: rs(4100)}, adjustment: rs(100)),
      ]);
      expect([for (final b in issued) b.billNo], [ref(p, 1), ref(p, 2), ref(p, 3)]);
      expect(issued.fold<int>(0, (s, b) => s + b.line.netPaise), rs(12500));
      for (final b in issued) {
        expect(b.allocations.single.receiptId, p.id);
        expect(b.allocations.single.allocatedPaise, b.line.netPaise);
        expect(b.isMultiPayment, isFalse);
      }
      expect(await available(p.id), 0);
      expect((await ledger()).length, 3);
      expect(await money(), before, reason: 'no payment, receipt, assignment or Finance record changed');
    });

    test('B. two payments (₹5,000 + ₹7,500) → one ₹12,500 bill keeping both references; numbered from the earliest', () async {
      final a = await pay(5000, DateTime(2026, 11, 10));
      final b = await pay(7500, DateTime(2026, 11, 12));
      // The map lists the later payment first: order doesn't decide the primary.
      final bill = (await issue([draft('2026-11', rs(12500), {b.id: rs(7500), a.id: rs(5000)})])).single;
      expect(bill.billNo, ref(a, 1), reason: 'the earliest payment\'s receipt number and sequence');
      expect(bill.payment.receiptId, a.id);
      expect([for (final x in bill.allocations) (x.receiptNo, x.allocatedPaise)], [(a.receiptNo, rs(5000)), (b.receiptNo, rs(7500))]);
      final stored = (await db.collection('fee_issued_bills').doc(bill.id).get()).data()!;
      expect(stored['receiptIds'], [a.id, b.id]);
      expect(stored['allocationSchema'], 2);
      expect((await bills.getAllocation(a.id))!.allocatedPaise, rs(5000));
      expect((await bills.getAllocation(b.id))!.allocatedPaise, rs(7500));
      expect((await bills.getAllocation(a.id))!.nextSequence, 2);
      expect((await bills.getAllocation(b.id))!.nextSequence, 1, reason: 'a supporting payment\'s own sequence is not used');
      final l = await ledger();
      expect(l.keys.toSet(), {FeeBillPaymentAllocation.idFor(bill.id, a.id), FeeBillPaymentAllocation.idFor(bill.id, b.id)});
      final entry = l[FeeBillPaymentAllocation.idFor(bill.id, b.id)]!;
      expect([entry['receiptNo'], entry['allocatedPaise'], entry['paymentAmountPaise'], entry['billNo'], entry['status'], entry['allocatedBy']],
          [b.receiptNo, rs(7500), rs(7500), bill.billNo, 'active', 'admin-1']);
      expect(entry['paymentDate'], isNotNull);
      expect(await bills.billsForPayment(b.id), [isA<FeeIssuedBill>().having((x) => x.id, 'id', bill.id)]);
    });

    test('C. two payments (₹8,000 + ₹7,000) → bills of ₹6,000, ₹5,000 (₹2,000 + ₹3,000) and ₹4,000', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(7000, DateTime(2026, 11, 3));
      final issued = await issue([
        draft('2026-09', rs(6000), {a.id: rs(6000)}),
        draft('2026-10', rs(5000), {a.id: rs(2000), b.id: rs(3000)}),
        draft('2026-11', rs(4000), {b.id: rs(4000)}),
      ]);
      expect([for (final x in issued) x.billNo], [ref(a, 1), ref(a, 2), ref(b, 1)]);
      expect([for (final x in issued) [for (final y in x.allocations) (y.receiptNo, y.allocatedPaise)]], [
        [(a.receiptNo, rs(6000))],
        [(a.receiptNo, rs(2000)), (b.receiptNo, rs(3000))],
        [(b.receiptNo, rs(4000))],
      ]);
      expect((await available(a.id), await available(b.id)), (0, 0));
      expect((await bills.getAllocation(a.id))!.bills, {issued[0].id: rs(6000), issued[1].id: rs(2000)});
      expect((await bills.getAllocation(b.id))!.bills, {issued[1].id: rs(3000), issued[2].id: rs(4000)});
      // Payment A appears on two bills; it is still one payment.
      expect((await bills.billsForPayment(a.id)).length, 2);
      expect((await db.collection('fee_receipts').get()).docs.length, 2);
    });

    test('D. partial allocation: ₹10,000 → ₹4,000 + ₹3,000 leaves ₹3,000 for a later bill', () async {
      final p = await pay(10000, DateTime(2026, 11, 5));
      await issue([draft('2026-09', rs(4000), {p.id: rs(4000)}), draft('2026-10', rs(3000), {p.id: rs(3000)})]);
      expect(await available(p.id), rs(3000));
      final report = await bills.allocationReport();
      expect((report.eligibleCollectedPaise, report.allocatedPaise, report.unallocatedPaise), (rs(10000), rs(7000), rs(3000)));
      await expectLater(issue([draft('2026-11', rs(3500), {p.id: rs(3500)})]), throwsA(predicate((e) => '$e'.contains('only ₹3,000.00 of this payment'))));
      final later = (await issue([draft('2026-11', rs(3000), {p.id: rs(3000)})])).single;
      expect(later.billNo, ref(p, 3));
      expect(await available(p.id), 0);
    });

    test('primary payment: the earliest by date; with equal dates the lowest receipt number', () async {
      final late_ = await pay(1000, DateTime(2026, 11, 20));
      final early = await pay(1000, DateTime(2026, 11, 2)); // collected later, dated earlier
      expect((await issue([draft('2026-09', rs(2000), {late_.id: rs(1000), early.id: rs(1000)})])).single.billNo, ref(early, 1));
      final x = await pay(1000, DateTime(2026, 11, 25));
      final y = await pay(1000, DateTime(2026, 11, 25));
      expect(x.receiptNo.compareTo(y.receiptNo), lessThan(0));
      expect((await issue([draft('2026-10', rs(2000), {y.id: rs(1000), x.id: rs(1000)})])).single.billNo, ref(x, 1));
    });
  });

  group('financial integrity', () {
    test('no allocation above the payment, and no total above it across bills; nothing written when refused', () async {
      final a = await pay(5000, DateTime(2026, 11, 1));
      final b = await pay(2000, DateTime(2026, 11, 2));
      final before = await billRecords();
      await expectLater(issue([draft('2026-09', rs(6000), {a.id: rs(5500), b.id: rs(500)})]),
          throwsA(predicate((e) => '$e'.contains('use ₹5,500.00 of receipt ${a.receiptNo}') && '$e'.contains('only ₹5,000.00'))));
      await expectLater(
          issue([draft('2026-09', rs(4000), {a.id: rs(3000), b.id: rs(1000)}), draft('2026-10', rs(3000), {a.id: rs(2500), b.id: rs(500)})]),
          throwsA(predicate((e) => '$e'.contains('₹5,500.00 of receipt ${a.receiptNo}'))));
      expect(await billRecords(), before);
    });

    test('a bill\'s net must equal its allocations; no negative, empty or over-limit allocations (refused before any transaction)', () async {
      final a = await pay(5000, DateTime(2026, 11, 1));
      final b = await pay(5000, DateTime(2026, 11, 2));
      final attempts = db.attempts;
      Future<void> refused(List<FeeBillDraft> d, String message) =>
          expectLater(issue(d), throwsA(predicate((e) => '$e'.contains(message), message)));
      await refused([draft('2026-09', rs(4000), {a.id: rs(2000), b.id: rs(1000)})], 'total ₹3,000.00, but its net bill amount is ₹4,000.00');
      await refused([draft('2026-09', rs(4000), {a.id: rs(5000), b.id: -rs(1000)})], 'cannot be negative');
      await refused([draft('2026-09', rs(4000), {a.id: 0, b.id: 0})], 'choose the payment(s)');
      await refused([draft('2026-09', rs(4000), {})], 'choose the payment(s)');
      await refused([draft('2026-09', rs(4000), {for (var i = 0; i < 7; i++) 'r$i': rs(4000) ~/ 7 + (i == 0 ? rs(4000) % 7 : 0)})], 'at most 6');
      await refused([for (var m = 1; m <= 13; m++) draft('2026-${m.clamp(1, 12).toString().padLeft(2, '0')}', 100, {a.id: 100})], 'At most 12 bills');
      await refused([draft('2026-09', rs(100), {a.id: 0}, adjustment: rs(100))], 'net bill amount must be more than ₹0');
      expect(db.attempts, attempts, reason: 'no transaction was opened');
      expect((await db.collection('fee_issued_bills').get()).docs, isEmpty);
    });

    test('the bill-only adjustment stays separate: gross ₹4,200, adjustment ₹100, net and allocation ₹4,100', () async {
      final p = await pay(4100, DateTime(2026, 11, 5));
      final bill = (await issue([draft('2026-11', rs(4200), {p.id: rs(4100)}, adjustment: rs(100))])).single;
      expect((bill.line.grossPaise, bill.line.adjustmentPaise, bill.line.netPaise, bill.allocatedPaise), (rs(4200), rs(100), rs(4100), rs(4100)));
      expect((await ledger()).values.single['allocatedPaise'], rs(4100));
      expect((await bills.getAllocation(p.id))!.allocatedPaise, rs(4100));
      final t = FeeBillTotals.of([bill]);
      expect((t.adjustmentPaise, t.netPaise, t.allocatedPaise), (rs(100), rs(4100), rs(4100)));
    });

    test('whole paise, no rounding: ₹10,000 as ₹3,333.33 + ₹3,333.33 + ₹3,333.34', () async {
      final p = await pay(10000, DateTime(2026, 11, 5));
      final parts = [parseRupees('3333.33')!, parseRupees('3333.33')!, parseRupees('3333.34')!];
      expect(parts, [333333, 333333, 333334]);
      await issue([for (final (i, v) in parts.indexed) draft('2026-0${i + 1}', v, {p.id: v})]);
      expect((await bills.getAllocation(p.id))!.allocatedPaise, 1000000);
      expect(await available(p.id), 0);
    });

    test('another student\'s payment, a voided payment, or one whose Fees transaction is missing, voided or different is refused and listed why', () async {
      final mine = await pay(5000, DateTime(2026, 11, 1));
      final theirs = await pay(5000, DateTime(2026, 11, 2), student: 's2');
      await expectLater(issue([draft('2026-09', rs(6000), {mine.id: rs(3000), theirs.id: rs(3000)})]),
          throwsA(predicate((e) => '$e'.contains(FeeBillService.otherStudentMessage))));

      Future<FeeReceiptModel> tampered(void Function(Map<String, dynamic> tx) change) async {
        final r = await pay(1000, DateTime(2026, 11, 3));
        final tx = (await db.collection('fee_transactions').doc(r.transactionId).get()).data()!;
        change(tx);
        await db.collection('fee_transactions').doc(r.transactionId).set(tx);
        return r;
      }

      final noTx = await pay(1000, DateTime(2026, 11, 3));
      await db.collection('fee_transactions').doc(noTx.transactionId).delete();
      final voidedTx = await tampered((t) => t['isDeleted'] = true);
      final otherAmount = await tampered((t) => t['amount'] = 999);
      final otherStudent = await tampered((t) => t['studentId'] = 's2');
      final noLink = await pay(1000, DateTime(2026, 11, 3));
      await db.collection('fee_receipts').doc(noLink.id).update({'transactionId': ''});
      final voided = await pay(1000, DateTime(2026, 11, 4));
      await fees.voidReceipt(voided.id);

      final cases = {
        noTx.id: FeeBillService.transactionMissingMessage(noTx.receiptNo),
        voidedTx.id: FeeBillService.transactionVoidedMessage(voidedTx.receiptNo),
        otherAmount.id: FeeBillService.transactionMismatchMessage(otherAmount.receiptNo, 'amount'),
        otherStudent.id: FeeBillService.transactionMismatchMessage(otherStudent.receiptNo, 'student'),
        noLink.id: FeeBillService.noTransactionMessage(noLink.receiptNo),
        voided.id: FeeBillService.voidedMessage,
      };
      final before = await billRecords();
      for (final e in cases.entries) {
        await expectLater(issue([draft('2026-09', rs(1000), {e.key: rs(1000)})]), throwsA(predicate((x) => '$x'.contains(e.value), e.value)));
        await expectLater(issue([draft('2026-09', rs(2000), {mine.id: rs(1000), e.key: rs(1000)})]), throwsA(predicate((x) => '$x'.contains(e.value), e.value)));
      }
      expect(await billRecords(), before);
      final listed = {for (final b in await bills.paymentBalancesForStudent('s1')) b.payment.receiptId: b};
      for (final e in cases.entries) {
        expect(listed[e.key]!.ineligibleReason, e.value);
        expect(listed[e.key]!.availablePaise, 0);
      }
      expect(listed[mine.id]!.eligible, isTrue);
    });

    test('issuing and cancelling never change payments, receipts, transactions, fee balances or Finance, and create no Finance entries', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(7000, DateTime(2026, 11, 3));
      final before = await money();
      final issued = await issue([draft('2026-09', rs(6000), {a.id: rs(6000)}), draft('2026-10', rs(9000), {a.id: rs(2000), b.id: rs(7000)})]);
      await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Wrong month', replacement: line('2026-11', rs(9000)));
      await bills.recordReprint(requesterRole: 'admin', billId: issued[0].id);
      expect(await money(), before);
    });
  });

  group('concurrency and recovery', () {
    test('two administrators allocating the same remaining ₹6,000 of ₹10,000: one succeeds, the other is refused', () async {
      final p = await pay(10000, DateTime(2026, 11, 5));
      final results = await Future.wait([
        issue([draft('2026-09', rs(6000), {p.id: rs(6000)})]).then<Object>((v) => v, onError: (Object e) => e),
        issue([draft('2026-10', rs(6000), {p.id: rs(6000)})]).then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<List<FeeIssuedBill>>().length, 1);
      expect(results.whereType<StateError>().single.message, contains('only ₹4,000.00 of this payment'));
      expect((await bills.getAllocation(p.id))!.allocatedPaise, rs(6000));
      expect((await ledger()).length, 1);
    });

    test('concurrent multi-payment issues that both fit both succeed, with distinct references and exact totals', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(8000, DateTime(2026, 11, 2));
      final results = await Future.wait([
        issue([draft('2026-09', rs(7000), {a.id: rs(4000), b.id: rs(3000)})]),
        issue([draft('2026-10', rs(9000), {a.id: rs(4000), b.id: rs(5000)})]),
      ]);
      expect({for (final r in results) r.single.billNo}, {ref(a, 1), ref(a, 2)});
      expect((await available(a.id), await available(b.id)), (0, 0));
      expect((await bills.getAllocation(a.id))!.isConsistent, isTrue);
    });

    test('a failed commit leaves no bill, allocation, ledger entry or request', () async {
      final a = await pay(5000, DateTime(2026, 11, 1));
      final b = await pay(5000, DateTime(2026, 11, 2));
      final before = await billRecords();
      db.failCommitWhen = (path) => path.startsWith(FeeBillService.ledgerCollection);
      await expectLater(issue([draft('2026-09', rs(8000), {a.id: rs(5000), b.id: rs(3000)})]), throwsA(isA<Exception>()));
      db.failCommitWhen = null;
      expect(await billRecords(), before);
      expect(await available(a.id), rs(5000));
    });

    test('a retried request returns the same bills: no duplicate bills or allocations', () async {
      final a = await pay(5000, DateTime(2026, 11, 1));
      final b = await pay(5000, DateTime(2026, 11, 2));
      final d = [draft('2026-09', rs(8000), {a.id: rs(5000), b.id: rs(3000)})];
      final first = await issue(d, requestId: 'same');
      final again = await issue(d, requestId: 'same');
      expect([for (final x in again) x.id], [for (final x in first) x.id]);
      expect((await db.collection('fee_issued_bills').get()).docs.length, 1);
      expect((await ledger()).length, 2);
      expect(await available(b.id), rs(2000));
      final r = (await db.collection(FeeBillService.requestsCollection).doc('same').get()).data()!;
      expect(r['billIds'], [first.single.id]);
    });

    test('cancelling releases only that bill\'s allocations, with reversal records; the history is kept', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(7000, DateTime(2026, 11, 3));
      final issued = await issue([
        draft('2026-09', rs(6000), {a.id: rs(6000)}),
        draft('2026-10', rs(5000), {a.id: rs(2000), b.id: rs(3000)}),
        draft('2026-11', rs(4000), {b.id: rs(4000)}),
      ]);
      final snapshot = (await db.collection('fee_issued_bills').doc(issued[1].id).get()).data()!;
      await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Wrong amount');
      expect((await available(a.id), await available(b.id)), (rs(2000), rs(3000)));
      expect((await bills.getAllocation(a.id))!.bills, {issued[0].id: rs(6000)});
      expect((await bills.getAllocation(b.id))!.bills, {issued[2].id: rs(4000)});
      final l = await ledger();
      final released = {for (final e in l.entries) if (e.value['status'] == 'released') e.key};
      expect(released, {FeeBillPaymentAllocation.idFor(issued[1].id, a.id), FeeBillPaymentAllocation.idFor(issued[1].id, b.id)});
      expect(l.length, 4, reason: 'no allocation history is deleted');
      for (final id in released) {
        expect(l[id]!['reversalId'], id);
        expect(l[id]!['allocatedPaise'], isNotNull, reason: 'the entry\'s details are kept');
      }
      final rev = await reversals();
      expect(rev.keys.toSet(), released);
      expect(rev[FeeBillPaymentAllocation.idFor(issued[1].id, b.id)]!['releasedPaise'], rs(3000));
      expect(rev.values.first['reason'], 'Wrong amount');
      final after = (await db.collection('fee_issued_bills').doc(issued[1].id).get()).data()!;
      expect(after['allocations'], snapshot['allocations'], reason: 'the bill\'s snapshot is unchanged');
      expect(after['status'], 'cancelled');
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'again'), throwsA(isA<StateError>()));
    });

    test('a replacement reuses the released amounts with a new reference and new allocations; its own allocations can differ', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(7000, DateTime(2026, 11, 3));
      final issued = await issue([draft('2026-09', rs(6000), {a.id: rs(6000)}), draft('2026-10', rs(5000), {a.id: rs(2000), b.id: rs(3000)})]);
      // Same net: the same allocations by default.
      final r1 = (await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Description', replacement: line('2026-10', rs(5000), description: 'October tuition')))!;
      expect(r1.billNo, ref(a, 3), reason: 'never reuses ${ref(a, 2)}');
      expect(r1.replacesBillId, issued[1].id);
      expect([for (final x in r1.allocations) x.allocatedPaise], [rs(2000), rs(3000)]);
      expect((await bills.getBill(issued[1].id))!.replacedByBillId, r1.id);
      // A different net: the allocations are given.
      final r2 = (await bills.cancelBill(
          requesterRole: 'admin', billId: r1.id, reason: 'Lower amount', replacement: line('2026-10', rs(4500)), replacementAllocations: {a.id: rs(2000), b.id: rs(2500)}))!;
      expect([for (final x in r2.allocations) x.allocatedPaise], [rs(2000), rs(2500)]);
      expect((await available(a.id), await available(b.id)), (0, rs(4500)));
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: r2.id, reason: 'x', replacement: line('2026-10', rs(4000))),
          throwsA(predicate((e) => '$e'.contains('Enter how much of each the replacement uses'))));
      await expectLater(
          bills.cancelBill(requesterRole: 'admin', billId: r2.id, reason: 'x', replacement: line('2026-10', rs(9500)), replacementAllocations: {a.id: rs(2000), b.id: rs(7500)}),
          throwsA(predicate((e) => '$e'.contains('of receipt ${b.receiptNo}'))));
      expect((await bills.getBill(r2.id))!.isCancelled, isFalse, reason: 'a refused replacement cancels nothing');
      expect((await ledger()).values.where((e) => e['status'] == 'active').length, 3);
    });

    test('a reprint writes no allocation', () async {
      final p = await pay(5000, DateTime(2026, 11, 1));
      final bill = (await issue([draft('2026-09', rs(5000), {p.id: rs(5000)})])).single;
      final before = {...await billRecords()}..remove(FeeBillService.billsCollection);
      await bills.recordReprint(requesterRole: 'admin', billId: bill.id);
      expect({...await billRecords()}..remove(FeeBillService.billsCollection), before);
    });
  });

  group('historical (pre-ledger) bills', () {
    /// Bill [b] as bills issued before the ledger were stored: no
    /// allocations, no ledger entry.
    Future<void> makeLegacy(FeeIssuedBill b) async {
      final ref = db.collection('fee_issued_bills').doc(b.id);
      final d = (await ref.get()).data()!..remove('allocations')..remove('receiptIds')..remove('allocationSchema');
      await ref.set(d);
      await db.collection(FeeBillService.ledgerCollection).doc(FeeBillPaymentAllocation.idFor(b.id, b.payment.receiptId)).delete();
    }

    test('read as one allocation of their net; the PDF is exactly as before', () async {
      final p = await pay(4100, DateTime(2026, 11, 5));
      final bill = (await issue([draft('2026-11', rs(4200), {p.id: rs(4100)}, adjustment: rs(100))])).single;
      final newText = pdfText(await FeeBillPdf.build((await bills.getBill(bill.id))!));
      await makeLegacy(bill);
      final legacy = (await bills.getBill(bill.id))!;
      expect(legacy.isLegacy, isTrue);
      expect([legacy.allocations.single.receiptId, legacy.allocations.single.allocatedPaise, legacy.allocations.single.legacy], [p.id, rs(4100), true]);
      final text = pdfText(await FeeBillPdf.build(legacy));
      expect(text, newText, reason: 'a one-payment bill prints the same with or without stored allocations');
      expect(text, isNot(contains(FeeBillPdf.allocationHeading)));
      expect(FeeBillPdf.billRows(legacy).last, ('Receipt Reference', p.receiptNo));
    });

    test('cancelling one records its allocation (already released) and a reversal, leaving its snapshot unchanged', () async {
      final p = await pay(8400, DateTime(2026, 11, 5));
      final issued = await issue([draft('2026-09', rs(4200), {p.id: rs(4200)}), draft('2026-10', rs(4200), {p.id: rs(4200)})]);
      await makeLegacy(issued[0]);
      final before = (await db.collection('fee_issued_bills').doc(issued[0].id).get()).data()!;
      await bills.cancelBill(requesterRole: 'admin', billId: issued[0].id, reason: 'Duplicate');
      final after = (await db.collection('fee_issued_bills').doc(issued[0].id).get()).data()!;
      // Only the cancellation is added: status, reason, who and when.
      for (final k in before.keys.where((k) => !{'status', 'updatedAt', 'updatedBy'}.contains(k))) {
        expect(after[k], before[k], reason: k);
      }
      expect(after['status'], 'cancelled');
      expect(after.containsKey('allocations'), isFalse);
      final id = FeeBillPaymentAllocation.idFor(issued[0].id, p.id);
      final entry = (await ledger())[id]!;
      expect([entry['legacy'], entry['status'], entry['allocatedPaise'], entry['reversalId']], [true, 'released', rs(4200), id]);
      expect((await reversals())[id]!['legacy'], isTrue);
      expect((await bills.getAllocation(p.id))!.bills, {issued[1].id: rs(4200)}, reason: 'the other bill is untouched');
      expect(await available(p.id), rs(4200));
    });
  });

  group('PDF', () {
    test('several payments: every receipt reference, a PAYMENT ALLOCATION table with dates and amounts, and the total', () async {
      final a = await pay(5000, DateTime(2026, 11, 10));
      final b = await pay(7500, DateTime(2026, 11, 12));
      final bill = (await issue([draft('2026-11', rs(12500), {a.id: rs(5000), b.id: rs(7500)})])).single;
      final text = pdfText(await FeeBillPdf.build(bill));
      for (final t in [
        'BILL DETAILS', 'Receipt Reference', '${a.receiptNo}, ${b.receiptNo}', FeeBillPdf.allocationHeading, 'Payment Reference', 'Payment Date', 'Allocated Amount',
        a.receiptNo, '10 Nov 2026', 'Rs. 5,000.00', b.receiptNo, '12 Nov 2026', 'Rs. 7,500.00', FeeBillPdf.allocationTotalLabel, 'Rs. 12,500.00',
        'Net Bill Amount', IndianAmount.words(rs(12500)), FeeBillPdf.footer,
      ]) {
        expect(text, contains(t), reason: t);
      }
      // The table sits between BILL DETAILS and the net amount.
      expect(text.indexOf(FeeBillPdf.allocationHeading), greaterThan(text.indexOf('BILL DETAILS')));
      expect(text.indexOf(FeeBillPdf.allocationHeading), lessThan(text.indexOf('Net Bill Amount')));
      expect(FeeBillPdf.fileName(bill), '${ref(a, 1)}.pdf');
    });

    test('partial allocations across bills: each bill\'s PDF shows only what it uses', () async {
      final a = await pay(8000, DateTime(2026, 11, 1));
      final b = await pay(7000, DateTime(2026, 11, 3));
      final issued = await issue([draft('2026-09', rs(6000), {a.id: rs(6000)}), draft('2026-10', rs(5000), {a.id: rs(2000), b.id: rs(3000)})]);
      final one = pdfText(await FeeBillPdf.build(issued[0]));
      expect(one, isNot(contains(FeeBillPdf.allocationHeading)));
      expect(FeeBillPdf.allocationRows(issued[1]), [(a.receiptNo, '01 Nov 2026', 'Rs. 2,000.00'), (b.receiptNo, '03 Nov 2026', 'Rs. 3,000.00')]);
      expect(pdfText(await FeeBillPdf.build(issued[1])), contains('Rs. 5,000.00'));
    });
  });

  group('Parent Dashboard', () {
    late FeeReceiptModel a, b;
    late FeeIssuedBill multi;

    setUp(() async {
      a = await pay(5000, DateTime(2026, 11, 10));
      b = await pay(7500, DateTime(2026, 11, 12));
      await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
      multi = (await issue([draft('2026-11', rs(12500), {a.id: rs(5000), b.id: rs(7500)})])).single;
    });

    ParentFileService files(String parent, List<(Uint8List, String)> saved) =>
        ParentFileService(parentUserId: parent, firestore: db, storage: MockFirebaseStorage(), save: (bytes, name) async => saved.add((bytes, name)));

    test('the parent copy lists the payments without receipt or allocation ids, and its PDF is the administrator\'s', () async {
      final copy = (await db.collection(ParentFeeBillFields.collection).doc(multi.id).get()).data()!;
      expect(copy['allocations'], [
        {'receiptNo': a.receiptNo, 'paymentDate': isNotNull, 'allocatedPaise': rs(5000)},
        {'receiptNo': b.receiptNo, 'paymentDate': isNotNull, 'allocatedPaise': rs(7500)},
      ]);
      expect(jsonEncode(copy['allocations'], toEncodable: (o) => '$o'), isNot(anyOf(contains(a.id), contains(b.id), contains('__'))));
      expect(copy['schemaVersion'], 3);
      final saved = <(Uint8List, String)>[];
      for (final parent in [father, mother]) {
        await files(parent, saved).downloadFeeBillById(multi.id);
        expect(saved.last.$2, '${multi.billNo}.pdf');
        expect(pdfText(saved.last.$1), pdfText(await FeeBillPdf.build((await bills.getBill(multi.id))!)), reason: parent);
      }
      final listed = (await files(father, saved).feeBillsForStudent('s1')).single;
      expect([for (final x in listed.allocations) (x.receiptNo, x.allocatedPaise)], [(a.receiptNo, rs(5000)), (b.receiptNo, rs(7500))]);
    });

    test('Guardian, another child\'s Father and cancelled bills: refused or hidden', () async {
      final saved = <(Uint8List, String)>[];
      for (final p in [guardian, otherFather]) {
        await expectLater(files(p, saved).downloadFeeBillById(multi.id), throwsA(isA<ParentFileAccessDenied>()), reason: p);
      }
      await bills.cancelBill(requesterRole: 'admin', billId: multi.id, reason: 'Wrong');
      await expectLater(files(father, saved).downloadFeeBillById(multi.id), throwsA(isA<ParentFileAccessDenied>()));
      expect(await files(father, saved).feeBillsForStudent('s1'), isEmpty);
      expect(saved, isEmpty);
    });
  });
}
