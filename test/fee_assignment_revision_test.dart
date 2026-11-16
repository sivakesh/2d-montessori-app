// Revising the fee amount of an existing assignment (FeeRevision,
// FeeService.reviseAssignmentFee), unpaid, partially or fully paid: collected
// is kept, payable / outstanding / status follow, an excess over the revised
// payable is held as a credit (no refund is invented), a student discount is
// recalculated from its own terms and never doubled; receipts, fee
// transactions and Finance entries are never touched; the revision and its
// audit record are written in one transaction against the assignment as it
// was reviewed. Editing a fee structure alone never changes an assignment.
// Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_amount_revision.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_discount.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_details_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late FeeService fees;
  late String yearId;
  final today = DateTime(2026, 8, 1);

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1', displayName: 'Test Admin'));
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => today);
    yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await firestore.collection('fee_structures').doc('term').set({
      'name': 'Term Fees', 'description': '', 'totalAmount': 40000, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't',
      'components': [
        FeeComponentModel(name: 'Tuition', amount: 30000, frequency: 'term', isOptional: false).toMap(),
        FeeComponentModel(name: 'Materials', amount: 10000, frequency: 'term', isOptional: false).toMap(),
      ],
    });
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name) in [('s1', 'Anu'), ('s2', 'Bala'), ('s3', 'Chitra')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    }
  });

  CollectionReference<Map<String, dynamic>> col(String c) => firestore.collection(c);
  Future<Map<String, dynamic>> doc(String id) async => (await col('student_fee_assignments').doc(id).get()).data()!;
  Future<StudentFeeAssignmentModel> model(String id) async => StudentFeeAssignmentModel.fromMap(id, await doc(id));

  Future<String> assign({String student = 's1', double total = 40000, double discount = 0}) async => (await fees.assignFee({
        'studentId': student, 'studentName': student == 's1' ? 'Anu' : student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': 0, 'balanceAmount': total - discount, 'status': 'unpaid',
        'dueDate': DateTime(2026, 9, 10),
      }))!;

  Future<void> collect(String id, double amount, DateTime date, {String mode = 'cash', String ref = ''}) =>
      fees.collectFee(assignmentId: id, amount: amount, paymentDate: date, paymentMode: mode, referenceNo: ref, remarks: '');

  /// Every receipt, fee transaction and Finance entry, exactly as stored.
  Future<Map<String, Object?>> money() async => {
        for (final c in ['fee_receipts', 'fee_transactions', 'finance_income', 'finance_ledger', 'finance_expenses'])
          c: {for (final d in (await col(c).get()).docs) d.id: d.data()},
      };

  Future<FeeAmountRevision> revise(String id, double total, {double? manual, String reason = 'Fee structure revised for 2026-27', String source = FeeRevision.entered, double? structureAmount}) async =>
      fees.reviseAssignmentFee(expected: await model(id), totalFee: total, manualDiscount: manual, reason: reason, source: source, structureAmount: structureAmount);

  List<Object?> figures(Map<String, dynamic> a) => [a['totalFee'], a['discountAmount'], a['payableAmount'], a['paidAmount'], a['balanceAmount'], a['status']];

  // ------------------------------------------------------------ the rules
  group('payments and balances (examples A–D)', () {
    test('1. an unpaid assignment: payable and outstanding follow', () async {
      final id = await assign();
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 0, 52000, 0, 52000, 'unpaid']);
    });

    test('2 (A). partially paid ₹20,000, ₹40,000 → ₹52,000: ₹32,000 outstanding', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1));
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 0, 52000, 20000, 32000, 'partial']);
    });

    test('3 (B). fully paid ₹40,000, revised to ₹52,000: ₹12,000 outstanding again, partial; it can be collected', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1));
      await collect(id, 20000, DateTime(2026, 7, 15));
      expect((await doc(id))['status'], 'paid');
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 0, 52000, 40000, 12000, 'partial']);
      await collect(id, 12000, DateTime(2026, 8, 1));
      expect(figures(await doc(id)), [52000, 0, 52000, 52000, 0, 'paid']);
    });

    test('4 (C). partially paid ₹20,000, revised down to ₹15,000: nothing outstanding, ₹5,000 excess identified, nothing refunded', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1));
      final before = await money();
      final rev = await revise(id, 15000);
      expect(figures(await doc(id)), [15000, 0, 15000, 20000, 0, 'paid']);
      expect((await model(id)).excessCollected, 5000);
      expect(rev.excess, 5000);
      expect(await money(), before, reason: 'no refund or other transaction is invented');
    });

    test('5 (D). fully paid ₹40,000, revised down to ₹35,000: ₹5,000 excess; voiding a receipt later recalculates it', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1));
      await collect(id, 20000, DateTime(2026, 7, 15));
      await revise(id, 35000);
      expect(figures(await doc(id)), [35000, 0, 35000, 40000, 0, 'paid']);
      expect((await model(id)).excessCollected, 5000);
      final receipts = (await col('fee_receipts').where('assignmentId', isEqualTo: id).get()).docs;
      await fees.voidReceipt(receipts.first.id);
      final after = await model(id);
      expect([after.paidAmount, after.balanceAmount, after.status, after.excessCollected], [20000, 15000, 'partial', 0], reason: 'derived, never stale');
    });

    test('the collected total is the recorded one, whatever the status said', () async {
      final id = await assign();
      await collect(id, 12345.5, DateTime(2026, 7, 1));
      // A status out of step with the amounts doesn't matter: collected does.
      await col('student_fee_assignments').doc(id).update({'status': 'paid'});
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 0, 52000, 12345.5, 39654.5, 'partial']);
    });
  });

  group('receipts and Finance', () {
    test('6, 7. receipts, fee transactions and Finance entries are byte-for-byte unchanged; no collection is added', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1), mode: 'upi', ref: 'UPI-1');
      await collect(id, 20000, DateTime(2026, 7, 15), mode: 'cheque', ref: 'CHQ-2');
      final before = await money();
      expect((before['fee_receipts']! as Map), hasLength(2));
      await revise(id, 52000);
      await revise(id, 38000);
      expect(await money(), before);
    });
  });

  group('discounts', () {
    test('10. a manual discount is kept (never applied twice), or replaced when given', () async {
      final id = await assign(discount: 2000);
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 2000, 50000, 0, 50000, 'unpaid']);
      await revise(id, 52000, manual: 3000);
      expect(figures(await doc(id)), [52000, 3000, 49000, 0, 49000, 'unpaid']);
      await expectLater(revise(id, 52000, manual: 60000), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('more than the fee amount'))));
    });

    Future<String> discounted(FeeDiscountType type, double value) async {
      await col('students').doc('s2').update({
        StudentFeeDiscount.field: {'id': 'd1', 'type': type.key, 'value': value, 'effectiveFrom': Timestamp.fromDate(DateTime(2026, 1, 1)), 'isActive': true, 'reason': 'Sibling'},
      });
      return assign(student: 's2');
    }

    test('10. a percentage student discount follows the revised fee from its own terms, once; allocation adds up', () async {
      final id = await discounted(FeeDiscountType.percentage, 10);
      final before = await model(id);
      expect([before.discountAmount, before.payableAmount], [4000, 36000]);
      await collect(id, 10000, DateTime(2026, 8, 1));
      // The student's own discount changes later: the snapshot's terms rule.
      await col('students').doc('s2').update({'${StudentFeeDiscount.field}.value': 50});
      await revise(id, 52000);
      final a = await model(id);
      expect([a.totalFee, a.discountAmount, a.payableAmount, a.paidAmount, a.balanceAmount], [52000, 5200, 46800, 10000, 36800]);
      final s = a.studentDiscount!;
      expect([s.configId, s.value, s.gross, s.amount, s.periodReference, s.source], ['d1', 10, 52000, 5200, before.studentDiscount!.periodReference, before.studentDiscount!.source]);
      expect(s.appliedAt, before.studentDiscount!.appliedAt, reason: 'when it was applied is kept');
      expect(s.allocation.fold<double>(0, (t, x) => t + x.discount), 5200);
      expect(a.manualDiscountAmount, 0, reason: 'the whole discount is the student discount: not doubled');
      await expectLater(revise(id, 52000, manual: 500), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('not combined'))));
    });

    test('10. a fixed student discount stays the same amount', () async {
      final id = await discounted(FeeDiscountType.fixed, 1500);
      await revise(id, 52000);
      expect(figures(await doc(id)), [52000, 1500, 50500, 0, 50500, 'unpaid']);
    });
  });

  group('integrity', () {
    test('11. a stale view can’t overwrite: a collection, another revision or an edit made meanwhile refuses it', () async {
      final id = await assign();
      final opened = await model(id);
      await collect(id, 5000, DateTime(2026, 7, 1));
      await expectLater(
        fees.reviseAssignmentFee(expected: opened, totalFee: 52000, reason: 'r'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', FeeRevision.concurrentMessage)),
      );
      final fresh = await model(id);
      await fees.reviseAssignmentFee(expected: fresh, totalFee: 52000, reason: 'first');
      await expectLater(fees.reviseAssignmentFee(expected: fresh, totalFee: 45000, reason: 'second, from the same view'), throwsA(isA<StateError>()));
      final edited = await model(id);
      await fees.updateAssignment(id, {'discountAmount': 1000.0});
      await expectLater(fees.reviseAssignmentFee(expected: edited, totalFee: 45000, reason: 'r'), throwsA(isA<StateError>()));
      expect(figures(await doc(id)), [52000, 1000, 51000, 5000, 46000, 'partial']);
      expect((await model(id)).revisions, hasLength(1));
    });

    test('11. two revisions at once from the same view: exactly one is saved', () async {
      final id = await assign();
      final opened = await model(id);
      final results = await Future.wait([
        fees.reviseAssignmentFee(expected: opened, totalFee: 52000, reason: 'a').then((_) => true, onError: (_) => false),
        fees.reviseAssignmentFee(expected: opened, totalFee: 45000, reason: 'b').then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((ok) => ok), hasLength(1));
      final a = await model(id);
      expect(a.revisions, hasLength(1));
      expect(a.feeRevision, 1);
      expect(a.totalFee, a.revisions.single.newTotalFee);
    });

    test('12. the audit record: before and after, collected, status, who, when, why and the source; appended in order', () async {
      final id = await assign(discount: 1000);
      await collect(id, 20000, DateTime(2026, 7, 1));
      await revise(id, 52000, source: FeeRevision.fromStructure, structureAmount: 52000, reason: '  Structure revised  ');
      await revise(id, 50000, manual: 0, reason: 'Corrected');
      final a = await model(id);
      expect(a.feeRevision, 2);
      final [first, second] = a.revisions;
      expect([first.revision, first.previousTotalFee, first.newTotalFee, first.previousDiscount, first.newDiscount, first.previousPayable, first.newPayable, first.collected, first.previousStatus, first.newStatus, first.excess],
          [1, 40000, 52000, 1000, 1000, 39000, 51000, 20000, 'partial', 'partial', 0]);
      expect([first.source, first.structureAmount, first.reason, first.revisedBy, first.revisedByName, first.revisedAt], [FeeRevision.fromStructure, 52000, 'Structure revised', 'admin-1', 'Test Admin', today]);
      expect([second.revision, second.previousTotalFee, second.newTotalFee, second.newDiscount, second.source, second.structureAmount], [2, 52000, 50000, 0, FeeRevision.entered, null]);
      expect(a.originalTotalFee, 40000);
      expect((await doc(id))['lastRevisedAt'], isA<Timestamp>());
    });

    test('13. a failed save writes nothing: commit failure, no reason, nothing changed, invalid amounts', () async {
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1));
      final before = {'a': await doc(id), ...await money()};
      firestore.failCommitWhen = (path) => path.contains('student_fee_assignments');
      await expectLater(revise(id, 52000), throwsA(anything));
      firestore.failCommitWhen = null;
      await expectLater(revise(id, 52000, reason: '   '), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.revisionReasonMessage)));
      await expectLater(revise(id, 40000), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.revisionUnchangedMessage)));
      await expectLater(revise(id, 0), throwsA(isA<StateError>()));
      await expectLater(revise(id, double.nan), throwsA(isA<StateError>()));
      await expectLater(revise(id, -5), throwsA(isA<StateError>()));
      expect({'a': await doc(id), ...await money()}, before);
    });

    test('14. an assignment stored before revisions existed reads and revises as usual; nothing is added until revised', () async {
      final ref = await col('student_fee_assignments').add({
        'studentId': 's3', 'studentName': 'Chitra', 'classId': 'c1', 'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYear': '2026-2027',
        'totalFee': 40000, 'discountAmount': 0, 'payableAmount': 40000, 'paidAmount': 40000, 'balanceAmount': 0, 'status': 'paid',
      });
      final legacy = await model(ref.id);
      expect([legacy.feeRevision, legacy.revisions, legacy.isRevised, legacy.originalTotalFee, legacy.excessCollected], [0, isEmpty, false, 40000, 0]);
      expect(legacy.toMap().keys, isNot(contains(FeeRevision.historyField)));
      expect(legacy.toMap().keys, isNot(contains(FeeRevision.revisionField)));
      await revise(ref.id, 52000);
      expect(figures(await doc(ref.id)), [52000, 0, 52000, 40000, 12000, 'partial']);
    });
  });

  group('fee structures', () {
    test('editing a fee structure alone changes no assignment; a revised one is never synced from it', () async {
      final unpaid = await assign();
      final paid = await assign(student: 's3');
      await collect(paid, 40000, DateTime(2026, 7, 1));
      final before = {unpaid: await doc(unpaid), paid: await doc(paid)};
      await fees.updateFeeStructure('term', {'totalAmount': 52000});
      expect({unpaid: await doc(unpaid), paid: await doc(paid)}, before);
      await revise(unpaid, 45000);
      final revised = await doc(unpaid);
      final sync = await fees.syncAssignmentsForFeeStructure(
        feeStructureId: 'term', feeStructureName: 'Term Fees', academicYearId: yearId, academicYear: '2026-2027', totalFee: 52000,
        assignmentScope: 'student', classIds: const [], studentIds: ['s1'],
      );
      expect(sync['skipped'], 1);
      expect(await doc(unpaid), revised, reason: 'the administrator’s revision stands');
    });
  });

  // ------------------------------------------------------------ screens
  group('Edit Assignment and Collection Details', () {
    Finder key(String k) => find.byKey(Key(k));
    String textOf(WidgetTester tester, Finder f) => tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text)).last).data!;
    String value(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    Future<void> pumpEdit(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = (await tester.runAsync(() => model(id)))!;
      // A fresh app each time (Save closes the dialog, popping its route).
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(assignment: a, service: fees))),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String k, String text) async {
      await tester.ensureVisible(key(k));
      await tester.enterText(find.descendant(of: key(k), matching: find.byType(TextField)), text);
      await tester.pumpAndSettle();
    }

    Future<String> paidInTwo() async {
      await fees.updateFeeStructure('term', {'totalAmount': 52000});
      final id = await assign();
      await collect(id, 20000, DateTime(2026, 7, 1), mode: 'upi', ref: 'UPI-1');
      await collect(id, 20000, DateTime(2026, 7, 15), mode: 'cheque', ref: 'CHQ-2');
      return id;
    }

    testWidgets('8, 9. ₹40,000 fully paid, the structure now ₹52,000: revised from the dialog; Collection Details shows ₹52,000 / ₹40,000 / ₹12,000 and both payments unchanged', (tester) async {
      final id = (await tester.runAsync(paidInTwo))!;
      final before = (await tester.runAsync(money))!;
      await pumpEdit(tester, id);
      // The saved amount, not the structure's: nothing changes unless revised.
      expect(tester.widget<TextField>(find.descendant(of: key('fee-assignment-total-fee'), matching: find.byType(TextField))).controller!.text, '40000');
      expect(value(tester, 'fee-assignment-original-fee'), 'Saved fee amount: ₹40000');
      expect(value(tester, 'fee-assignment-revision-collected'), '₹40000');
      expect(value(tester, 'fee-assignment-revision-outstanding'), '₹0');
      expect(key('fee-assignment-revision-receipts-note'), findsOneWidget);
      expect(key('fee-assignment-revision-reason'), findsNothing, reason: 'not a revision yet');

      await tap(tester, key('fee-assignment-use-structure'));
      expect(value(tester, 'fee-assignment-revision-payable'), '₹52000');
      expect(value(tester, 'fee-assignment-revision-outstanding'), '₹12000', reason: 'recalculated at once');
      // A reason is required.
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text(FeeService.revisionReasonMessage), findsOneWidget);
      expect((await tester.runAsync(() => doc(id)))!['totalFee'], 40000);
      await type(tester, 'fee-assignment-revision-reason', 'Fee structure revised');
      // Confirmation first; Cancel saves nothing.
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(key('fee-revision-confirm'), findsOneWidget);
      expect(find.textContaining('not changed'), findsWidgets);
      await tap(tester, key('fee-revision-confirm-cancel'));
      expect((await tester.runAsync(() => doc(id)))!['totalFee'], 40000);
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      await tap(tester, key('fee-revision-confirm-ok'));

      final a = (await tester.runAsync(() => model(id)))!;
      expect([a.totalFee, a.payableAmount, a.paidAmount, a.balanceAmount, a.status], [52000, 52000, 40000, 12000, 'partial']);
      expect([a.revisions.single.source, a.revisions.single.structureAmount, a.revisions.single.reason], [FeeRevision.fromStructure, 52000, 'Fee structure revised']);
      expect((await tester.runAsync(money))!, before, reason: 'receipts and Finance unchanged');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeeCollectionDetailsDialog(assignment: a, service: fees))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(textOf(tester, key('collection-details-original-fee')), '₹40,000');
      expect(textOf(tester, key('collection-details-total-fee')), '₹52,000');
      expect(textOf(tester, key('collection-details-payable')), '₹52,000');
      expect(textOf(tester, key('collection-details-paid')), '₹40,000');
      expect(textOf(tester, key('collection-details-balance')), '₹12,000');
      expect(key('collection-details-excess'), findsNothing);
      expect(key('collection-details-revision-1'), findsOneWidget);
      expect(find.descendant(of: key('collection-details-revision-1'), matching: find.textContaining('Fee structure revised')), findsOneWidget);
      // The two payments, exactly as recorded.
      expect(value(tester, 'collection-details-receipts-total'), '2 payments: 2 completed, totalling ₹40,000.');
      for (final r in ((before['fee_receipts']! as Map).values)) {
        expect(find.textContaining((r as Map)['receiptNo'] as String), findsOneWidget);
      }
      expect(find.textContaining('UPI-1'), findsOneWidget);
      expect(find.textContaining('CHQ-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('revised below what was collected: the excess is warned of in the dialog and shown in Collection Details', (tester) async {
      final id = (await tester.runAsync(paidInTwo))!;
      await pumpEdit(tester, id);
      await type(tester, 'fee-assignment-total-fee', '35000');
      expect(value(tester, 'fee-assignment-revision-outstanding'), '₹0');
      expect(key('fee-assignment-revision-excess'), findsOneWidget);
      expect(value(tester, 'fee-assignment-revision-excess'), contains('₹5000 already collected is more than the revised payable'));
      await type(tester, 'fee-assignment-revision-reason', 'Concession agreed');
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      await tap(tester, key('fee-revision-confirm-ok'));
      final a = (await tester.runAsync(() => model(id)))!;
      expect([a.payableAmount, a.paidAmount, a.balanceAmount, a.excessCollected], [35000, 40000, 0, 5000]);
      expect(a.revisions.single.source, FeeRevision.entered);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeeCollectionDetailsDialog(assignment: a, service: fees))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(textOf(tester, key('collection-details-excess')), '₹5,000');
      expect(key('collection-details-excess-note'), findsOneWidget);
      expect(textOf(tester, key('collection-details-balance')), '₹0');
    });

    testWidgets('1. an unpaid assignment: revised without a confirmation step; only the due date edited is not a revision', (tester) async {
      final id = (await tester.runAsync(() async {
        await fees.updateFeeStructure('term', {'totalAmount': 52000});
        return assign();
      }))!;
      await pumpEdit(tester, id);
      expect(key('fee-assignment-revision-receipts-note'), findsNothing);
      await type(tester, 'fee-assignment-total-fee', '41000');
      await type(tester, 'fee-assignment-revision-reason', 'Correction');
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(key('fee-revision-confirm'), findsNothing);
      expect(figures((await tester.runAsync(() => doc(id)))!), [41000, 0, 41000, 0, 41000, 'unpaid']);

      // An edit that doesn't touch the amount keeps it (never the structure's ₹52,000).
      final other = (await tester.runAsync(() => assign(student: 's3')))!;
      await pumpEdit(tester, other);
      await tester.ensureVisible(key('fee-due-date-pick'));
      await tester.tap(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      final saved = (await tester.runAsync(() => model(other)))!;
      expect([saved.totalFee, saved.dueDate, saved.revisions], [40000, DateTime(2026, 9, 20), isEmpty]);
    });
  });
}
