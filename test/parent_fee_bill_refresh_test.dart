// Parent Dashboard Phase 0.2 follow-up (docs/parent_access_security.md
// §3a): the parent-safe fee-bill copies follow Fee Bill Issuance. After a
// bill issue or cancellation has committed, FeeBillService calls its
// after-change hook (registered by the Parent module), which re-derives
// that student's `parent_fee_bills` copies from the original bills. A
// refused or failed bill operation calls nothing; a failed refresh never
// affects the bill operation, is recorded, and is repaired by a retry or
// the Parent access rebuild. Also: the per-student copy writes (each copy
// written on its own) keep successful copies when another fails, and a
// repeated refresh writes nothing.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
// whenCalling: fake_cloud_firestore's failure injection (a dev dependency of
// it, not of the app), as in website_publish_guards_test.dart.
// ignore: depend_on_referenced_packages
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
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

const father = '9000000001';
const guardian = '9000000003';

const school = FeeBillSchool(name: '2D Eduvance Montessori', addressLines: ['12, Lake View Road'], contactLines: ['Phone: 044 1234 5678']);

FeeBillLine line(String month, int rupees) => FeeBillLine(billingMonth: month, description: 'Monthly tuition fee', grossPaise: rupees * 100);

/// Every original record (anything that is not a parent copy or a parent
/// copy failure record), with each bill's audit history.
Future<Map<String, Object?>> originals(FakeFirebaseFirestore db) async {
  final out = <String, Object?>{};
  for (final c in ['fee_issued_bills', 'fee_bill_allocations', 'fee_receipts', 'fee_transactions', 'student_fee_assignments', 'students', 'finance_income', 'finance_ledger', 'finance_accounts']) {
    for (final d in (await db.collection(c).get()).docs) {
      out['$c/${d.id}'] = d.data();
      if (c == 'fee_issued_bills') {
        for (final a in (await d.reference.collection('audit').get()).docs) {
          out['$c/${d.id}/audit/${a.id}'] = a.data();
        }
      }
    }
  }
  return out;
}

/// Refuses every call on `parent_fee_bills` while [denyCopies] (an outage
/// or a security-rules refusal while refreshing).
class _DenyingFirestore extends BufferedTransactionFirestore {
  bool denyCopies = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (denyCopies && collectionPath == ParentFeeBillFields.collection) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Injected refusal');
    }
    return super.collection(collectionPath);
  }
}

void main() {
  late _DenyingFirestore db;
  late FeeService fees;
  late FeeBillService bills;
  late FeeReceiptModel receipt;
  late ParentProjectionService copies;

  /// Calls of the after-change hook, and whether a refresh ran in each.
  late List<String> hookCalls;

  /// While true, writing the copy of a matching bill fails (an outage
  /// while refreshing).
  var failCopyWrites = false;

  var request = 0;
  String nextRequest() => 'req-${request++}';
  String billId(int n) => FeeIssuedBill.idFor(kDefaultSchoolId, '${receipt.receiptNo}-${n.toString().padLeft(6, '0')}');

  Future<List<FeeIssuedBill>> issue(List<FeeBillLine> lines, {String? requestId}) =>
      bills.issueBills(requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, lines: lines, requestId: requestId ?? nextRequest(), school: school);

  Future<Map<String, Map<String, dynamic>>> billCopies() async => {for (final d in (await db.collection(ParentFeeBillFields.collection).get()).docs) d.id: d.data()};
  Future<Map<String, dynamic>?> original(String id) async => (await db.collection('fee_issued_bills').doc(id).get()).data();
  Future<List<ParentProjectionFailure>> failures() => copies.failures(requesterRole: 'admin');

  /// Makes the copy writes of bills [ids] fail while [failCopyWrites].
  void failCopiesOf(List<String> ids) {
    for (final id in ids) {
      whenCalling(Invocation.method(#set, [predicate<Object?>((_) => failCopyWrites)]))
          .on(db.collection(ParentFeeBillFields.collection).doc(id))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Injected copy write failure'));
    }
  }

  setUp(() async {
    failCopyWrites = false;
    hookCalls = [];
    db = _DenyingFirestore();
    copies = ParentProjectionService(firestore: db);
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1', displayName: 'Test Admin'));
    final finance = FinanceService(firestore: db, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: db, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => DateTime(2026, 11, 5));
    // The production hook (refreshParentFeeBills), counted, and checked to
    // write no original record.
    bills = FeeBillService(firestore: db, auth: auth, clock: () => DateTime(2026, 11, 16, 10), afterChange: (firestore, studentId) async {
      final before = await originals(db);
      await refreshParentFeeBills(firestore, studentId);
      expect(await originals(db), before, reason: 'the refresh writes parent copies only');
      hookCalls.add(studentId);
    });
    final yearId = await AcademicYearService(firestore: db).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await db.collection('fee_structures').doc('term').set({
      'name': 'Term Fees', 'totalAmount': 12500, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't', 'components': [],
    });
    await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await db.collection('students').doc('s1').set({'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    await ParentLinkService(firestore: db).saveLinksForStudent(studentId: 's1', parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
    final access = ParentAccessService(firestore: db);
    await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
    final assignmentId = (await fees.assignFee({
      'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    receipt = await fees.collectFee(assignmentId: assignmentId, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-1', remarks: '');
  });

  tearDown(() => FeeBillService.defaultAfterChange = null);

  group('fee bill issue and cancellation refresh the parent copies', () {
    test('a successful issue writes one parent-safe copy per bill, as the original produces it; Father sees them, Guardian cannot', () async {
      expect(await billCopies(), isEmpty);
      final issued = await issue([line('2026-09', 4200), line('2026-10', 4200)]);
      expect(hookCalls, ['s1'], reason: 'once, after the transaction committed');
      final stored = await billCopies();
      expect(stored.keys.toSet(), {for (final b in issued) b.id});
      for (final b in issued) {
        final expected = parentFeeBill(b.id, (await original(b.id))!)!;
        expect({...stored[b.id]!}..remove('syncedAt'), expected);
        expect(stored[b.id]!.toString(), isNot(anyOf(contains('admin-1'), contains('req-'))), reason: 'no admin ids or request ids');
      }
      expect(await failures(), isEmpty);
      expect((await copies.health(requesterRole: 'admin')).firstWhere((h) => h.kind == ParentProjectionKind.feeBills).isCurrent, isTrue);

      final fatherBills = await ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');
      expect([for (final b in fatherBills) b.billNo]..sort(), [for (final b in issued) b.billNo]..sort());
      expect([for (final b in fatherBills) b.line.netPaise], [420000, 420000]);
      await expectLater(ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1'), throwsA(isA<ParentFileAccessDenied>()));
    });

    test('numbering, allocation and the returned bills are those of the issue itself', () async {
      final issued = await issue([line('2026-09', 4200)], requestId: 'same-request');
      expect(issued.single.id, billId(1));
      final alloc = (await bills.getAllocation(receipt.id))!;
      expect([alloc.nextSequence, alloc.allocatedPaise, alloc.version], [2, 420000, 1]);
      // The same request again: the same bills, nothing new, copies unchanged.
      final syncedAt = (await billCopies())[billId(1)]!['syncedAt'];
      final again = await issue([line('2026-09', 4200)], requestId: 'same-request');
      expect([for (final b in again) b.id], [billId(1)]);
      expect((await billCopies()).keys, [billId(1)]);
      expect((await billCopies())[billId(1)]!['syncedAt'], syncedAt, reason: 'an unchanged copy is not rewritten');
      expect((await bills.getAllocation(receipt.id))!.nextSequence, 2);
    });

    test('a successful cancellation removes the parent copy; a replacement gets its own copy with no link to the cancelled bill', () async {
      final issued = await issue([line('2026-09', 4200), line('2026-10', 4200)]);
      hookCalls.clear();
      await bills.cancelBill(requesterRole: 'admin', billId: issued.first.id, reason: 'Not needed');
      expect(hookCalls, ['s1']);
      var stored = await billCopies();
      expect(stored.keys, [issued.last.id], reason: 'parents never see a cancelled bill');
      expect((await original(issued.first.id))!['status'], FeeBillStatus.cancelled.key, reason: 'administrators keep it, with its history');

      final replacement = (await bills.cancelBill(requesterRole: 'admin', billId: issued.last.id, reason: 'Amount', replacement: line('2026-10', 4100)))!;
      expect(replacement.id, billId(3), reason: 'a cancelled number is never reused');
      stored = await billCopies();
      expect(stored.keys, [replacement.id]);
      expect(stored[replacement.id]!['netPaise'], 410000);
      expect(stored[replacement.id]!.containsKey('replacesBillId'), isFalse);
      expect(stored[replacement.id]!.toString(), isNot(anyOf(contains(issued.first.billNo), contains(issued.last.billNo))));
      expect({...stored[replacement.id]!}..remove('syncedAt'), parentFeeBill(replacement.id, (await original(replacement.id))!));
      expect(await failures(), isEmpty);
    });

    test('a failed issue (refused, or its commit failed) writes no bill and no copy, and calls no refresh', () async {
      final before = await originals(db);
      await expectLater(issue([line('2026-09', 20000)]), throwsA(isA<StateError>()), reason: 'more than the payment');
      db.failCommitWhen = (path) => path.startsWith('fee_bill_allocations/');
      await expectLater(issue([line('2026-09', 4200)]), throwsA(isA<FirebaseException>()));
      db.failCommitWhen = null;
      expect(hookCalls, isEmpty);
      expect(await billCopies(), isEmpty);
      expect(await failures(), isEmpty);
      expect(await originals(db), before);
    });

    test('a failed cancellation (refused, or its commit failed) leaves the bill and its copy as issued, and calls no refresh', () async {
      final issued = await issue([line('2026-09', 4200)]);
      hookCalls.clear();
      final copyBefore = (await billCopies())[issued.single.id];
      final before = await originals(db);
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued.single.id, reason: '  '), throwsA(isA<StateError>()));
      db.failCommitWhen = (path) => path.startsWith('fee_issued_bills/');
      await expectLater(bills.cancelBill(requesterRole: 'admin', billId: issued.single.id, reason: 'Wrong'), throwsA(isA<FirebaseException>()));
      db.failCommitWhen = null;
      expect(hookCalls, isEmpty);
      expect(await originals(db), before);
      expect((await billCopies())[issued.single.id], copyBefore);
      expect(copyBefore!['status'], FeeBillStatus.issued.key);
    });

    test('a failed refresh never fails the issue: it is recorded, shown by health, and repaired by a retry', () async {
      failCopiesOf([billId(1)]);
      failCopyWrites = true;
      final issued = await issue([line('2026-09', 4200)]);
      expect(issued.single.id, billId(1), reason: 'the issue succeeded and returned its bill');
      expect((await original(billId(1)))!['status'], FeeBillStatus.issued.key);
      expect(await billCopies(), isEmpty);
      final recorded = await failures();
      expect([for (final f in recorded) (f.scope, f.sourceId)], [('feeBills', billId(1))]);
      expect(recorded.single.error, contains('Injected copy write failure'));
      final health = (await copies.health(requesterRole: 'admin')).firstWhere((h) => h.kind == ParentProjectionKind.feeBills);
      expect([health.missing, health.isCurrent], [1, false]);

      // Retried while the outage lasts: still not claimed as success.
      expect(await copies.syncFeeBillsQuietly('s1'), isFalse);
      expect((await failures()).single.attempts, 2);

      // The outage is over: the next refresh repairs it and clears the record.
      failCopyWrites = false;
      expect(await copies.syncFeeBillsQuietly('s1'), isTrue);
      expect({...(await billCopies())[billId(1)]!}..remove('syncedAt'), parentFeeBill(billId(1), (await original(billId(1)))!));
      expect(await failures(), isEmpty);
      // Idempotent: again, nothing is rewritten.
      final syncedAt = (await billCopies())[billId(1)]!['syncedAt'];
      expect(await copies.syncFeeBillsQuietly('s1'), isTrue);
      expect((await billCopies())[billId(1)]!['syncedAt'], syncedAt);
    });

    test('a failed cancellation refresh is repaired by the Parent access rebuild; running it again changes nothing', () async {
      final issued = await issue([line('2026-09', 4200)]);
      db.denyCopies = true;
      await bills.cancelBill(requesterRole: 'admin', billId: issued.single.id, reason: 'Duplicate');
      db.denyCopies = false;
      expect((await original(issued.single.id))!['status'], FeeBillStatus.cancelled.key, reason: 'the cancellation stands');
      expect((await billCopies()).keys, [issued.single.id], reason: 'the stale copy could not be removed');
      final recorded = await failures();
      expect([for (final f in recorded) (f.scope, f.sourceId)], [('bills', 's1')]);
      expect(recorded.single.error, startsWith('permission-denied'));
      expect((await copies.health(requesterRole: 'admin')).firstWhere((h) => h.kind == ParentProjectionKind.feeBills).orphaned, 1);
      // Until the copy is removed it still reads "issued" (it was written
      // before the cancellation), so the parent would still see the bill:
      // the failure is recorded, Check reports it, and the rebuild below
      // (or the next fees/bill refresh of the student) removes it.

      final rebuilt = await copies.syncAll(requesterRole: 'admin');
      expect(rebuilt.removed[ParentProjectionKind.feeBills], 1);
      expect(rebuilt.totalFailed, 0);
      expect(await billCopies(), isEmpty);
      expect(await failures(), isEmpty);
      final again = await copies.syncAll(requesterRole: 'admin');
      expect(again.totalWritten, 0);
      expect(again.totalRemoved, 0);
      expect((await copies.health(requesterRole: 'admin')).every((h) => h.isCurrent), isTrue);
    });

    test('a hook that throws never affects the committed operation', () async {
      final throwing = FeeBillService(firestore: db, auth: MockFirebaseAuth(signedIn: true), afterChange: (_, _) async => throw StateError('hook down'));
      final issued = await throwing.issueBills(requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, lines: [line('2026-09', 4200)], requestId: nextRequest(), school: school);
      expect(issued.single.id, billId(1));
      expect(await throwing.cancelBill(requesterRole: 'admin', billId: issued.single.id, reason: 'x'), isNull);
      expect((await original(billId(1)))!['status'], FeeBillStatus.cancelled.key);
    });

    test('production wiring: registerParentFeeBillRefresh makes every FeeBillService refresh the copies', () async {
      expect(FeeBillService.defaultAfterChange, isNull, reason: 'tests and other callers are unaffected unless registered');
      registerParentFeeBillRefresh();
      expect(FeeBillService.defaultAfterChange, same(refreshParentFeeBills));
      final plain = FeeBillService(firestore: db, auth: MockFirebaseAuth(signedIn: true));
      final issued = await plain.issueBills(requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, lines: [line('2026-09', 4200)], requestId: nextRequest(), school: school);
      expect((await billCopies()).keys, [issued.single.id]);
    });
  });

  group('per-student copy writes', () {
    test('one copy failing never discards the others; only the failing one is recorded, and a retry repairs it', () async {
      // Two bills; the copy of the second can't be written.
      failCopiesOf([billId(2)]);
      failCopyWrites = true;
      await issue([line('2026-09', 4200), line('2026-10', 4200)]);
      expect((await billCopies()).keys, [billId(1)], reason: 'the first copy was written and kept');
      expect([for (final f in await failures()) f.sourceId], [billId(2)]);
      failCopyWrites = false;
      expect(await copies.syncFeesQuietly('s1'), isTrue, reason: 'the fees refresh covers the bills too');
      expect((await billCopies()).keys.toSet(), {billId(1), billId(2)});
      expect(await failures(), isEmpty);
    });

    test('a bulk refresh of many students writes only copies that differ: a repeat writes none', () async {
      for (var i = 0; i < 30; i++) {
        await db.collection('student_fee_assignments').doc('bulk-$i').set({
          'studentId': 'b$i', 'studentName': 'B$i', 'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYear': '2026-2027',
          'totalFee': 1000, 'discountAmount': 0, 'payableAmount': 1000, 'paidAmount': 0, 'balanceAmount': 1000, 'status': 'unpaid',
        });
      }
      final ids = [for (var i = 0; i < 30; i++) 'b$i'];
      expect(await copies.syncFeesForStudentsQuietly(ids), isTrue);
      Future<Map<String, Object?>> stamps() async => {
            for (final d in (await db.collection(ParentFeeAssignmentFields.collection).get()).docs) d.id: d.data()['syncedAt'],
          };
      final first = await stamps();
      expect(first.keys.where((k) => k.startsWith('bulk-')).length, 30);
      expect(await copies.syncFeesForStudentsQuietly(ids), isTrue);
      expect(await stamps(), first, reason: 'nothing rewritten');
      expect(await failures(), isEmpty);
    });
  });
}
