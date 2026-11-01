// Traceability of the Cancelled / Voided Transactions list:
// - Every counted row shows its source, type, Finance Record ID, payment
//   reference ("Reference not recorded" when absent — never a document id),
//   linked receipt/invoice number + id + status, ledger entry id + status.
// - Fee collections show the receipt number (read from fee_receipts) and
//   the Collection ID separately; invoice payments show the invoice number.
// - A counted record whose linked receipt/invoice is missing is marked
//   NEEDS REVIEW (still counted); unclear records are listed, not counted.
// - Count and amount equal the rows listed; balances are unchanged;
//   lookup failures never show a total.
// - Type filter (All / Income / Expenses / Salary) narrows only the rows
//   shown and the count/amount beneath them; traceability details and the
//   "Needs review — not counted" section stay visible.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/models/finance_cancelled_transactions_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

class _ControlledFinanceService extends FinanceService {
  _ControlledFinanceService(BufferedTransactionFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());
  Stream<FinanceCancelledTransactionsSummary>? replacement;

  @override
  Stream<FinanceCancelledTransactionsSummary> watchCancelledTransactions() =>
      replacement ?? super.watchCancelledTransactions();
}

void main() {
  late BufferedTransactionFirestore firestore;
  late _ControlledFinanceService finance;
  late FeeService fees;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    finance = _ControlledFinanceService(firestore);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage(), financeService: finance);
    await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('students').doc('s1').set({'name': 'Student A', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true});
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1', 'studentName': 'Student A', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
      'feeStructureId': 'structure-1', 'feeStructureName': 'Core Fees', 'academicYear': '2026-2027',
      'totalFee': 50000, 'discountAmount': 0, 'payableAmount': 50000, 'paidAmount': 0, 'balanceAmount': 50000,
      'status': 'unpaid', 'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Future<String> cashId() async =>
      (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;

  Future<String> manualIncome(double amount, {String title = 'Test Income', String referenceNo = ''}) async =>
      finance.createIncome(FinanceIncomeModel(
        id: '', title: title, categoryId: 'c', categoryName: 'Other Income', programType: 'other',
        studentId: '', studentName: '', classId: '', className: '', amount: amount,
        incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: await cashId(), accountName: 'Cash',
        referenceNo: referenceNo, remarks: '', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
      ));

  Future<String> collect(double amount, {String referenceNo = ''}) async => (await fees.collectFee(
        assignmentId: 'a1', amount: amount, paymentDate: DateTime(2026, 8, 2), paymentMode: 'cash', referenceNo: referenceNo, remarks: '',
      )).id;

  Future<({String invoiceId, String paymentId})> invoicePayment(double amount, {String type = 'expense', String invoiceNo = 'INV-00010020'}) async {
    final payload = {'partyName': 'Party', 'categoryName': 'Rent', 'invoiceNo': invoiceNo, 'totalAmount': amount, 'amount': amount};
    final invoiceId = type == 'salary' ? await finance.createSalaryInvoice(payload) : await finance.createExpenseInvoice(payload);
    final paymentId = (await finance.payInvoice(
      invoiceId: invoiceId, invoiceType: type, amount: amount, paidDate: DateTime(2026, 8, 3),
      paymentMode: 'cash', referenceNo: '', remarks: '',
    ))!;
    return (invoiceId: invoiceId, paymentId: paymentId);
  }

  Future<Map<String, dynamic>> doc(String path) async => (await firestore.doc(path).get()).data()!;
  Future<FinanceCancelledTransactionsSummary> summary() => finance.watchCancelledTransactions().first;
  FinanceCancelledTransaction byId(FinanceCancelledTransactionsSummary s, String id) => s.transactions.singleWhere((t) => t.id == id);

  Future<void> openList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: find.text('Cancelled / Voided Transactions'), matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
  }

  /// The dialog block for the row titled [heading].
  Finder rowBlock(String heading) => find.ancestor(of: find.text(heading), matching: find.byType(Column)).first;
  Finder inRow(String heading, String text) => find.descendant(of: rowBlock(heading), matching: find.text(text));

  testWidgets('1. manual income with no reference shows "Reference not recorded" and its Record ID', (tester) async {
    final id = await manualIncome(4000);
    await finance.voidIncome(id);
    final t = byId(await summary(), id);
    expect(t.sourceLabel, 'Finance → Income');
    expect(t.reference, '');
    expect(t.linkedDocumentLabel, '');
    expect(t.reviewNote, '');
    expect(t.ledgerStatus, 'cancelled');

    await openList(tester);
    const heading = 'Manual income • Test Income';
    expect(inRow(heading, 'Finance → Income'), findsOneWidget);
    expect(inRow(heading, 'Reference not recorded'), findsOneWidget);
    expect(inRow(heading, 'Record ID'), findsOneWidget);
    expect(inRow(heading, id), findsOneWidget);
    expect(find.text('NEEDS REVIEW'), findsNothing);
  });

  testWidgets('2. fee collection: receipt number, generated Collection ID and Finance record ID shown separately', (tester) async {
    final receiptId = await collect(10000);
    await fees.voidReceipt(receiptId);
    final receiptNo = (await doc('fee_receipts/$receiptId'))['receiptNo'] as String;
    final incomeId = (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single.id;
    final t = byId(await summary(), incomeId);
    expect(t.sourceLabel, 'Fees');
    expect(t.linkedDocumentLabel, 'Receipt');
    expect(t.linkedDocumentNumber, receiptNo);
    expect(t.linkedDocumentId, receiptId);
    expect(t.linkedDocumentStatus, 'Voided');
    expect(t.reference, '', reason: 'the collection id is no longer used as a reference');
    expect(t.reviewNote, '');

    await openList(tester);
    final heading = 'Fee collection • ${t.title}';
    expect(inRow(heading, receiptNo), findsOneWidget);
    expect(inRow(heading, 'Collection ID'), findsOneWidget);
    expect(inRow(heading, receiptId), findsOneWidget);
    expect(inRow(heading, 'Finance record ID'), findsOneWidget);
    expect(inRow(heading, incomeId), findsOneWidget);
    expect(inRow(heading, 'Reference not recorded'), findsOneWidget);
    expect(inRow(heading, 'Voided'), findsNWidgets(2)); // receipt status + Finance status
  });

  test('3. expense and salary reversals show their invoice reference', () async {
    final expense = await invoicePayment(2000, invoiceNo: 'INV-00010013');
    await finance.reverseExpenseInvoicePayment(paymentId: expense.paymentId, reason: 'Recorded by mistake');
    // No app workflow reverses salary payments; a record in that state is seeded.
    final salary = await invoicePayment(5000, type: 'salary', invoiceNo: 'INV-00010014');
    final salaryLedger = (await doc('finance_income/${salary.paymentId}'))['ledgerEntryId'] as String;
    await firestore.doc('finance_income/${salary.paymentId}').update({'isDeleted': true});
    await firestore.doc('finance_ledger/$salaryLedger').update({'status': 'cancelled'});
    // An older payment record without invoiceNo: read from the invoice.
    final legacy = await invoicePayment(700, invoiceNo: 'INV-00010015');
    final legacyLedger = (await doc('finance_income/${legacy.paymentId}'))['ledgerEntryId'] as String;
    await firestore.doc('finance_income/${legacy.paymentId}').update({'isDeleted': true, 'invoiceNo': FieldValue.delete()});
    await firestore.doc('finance_ledger/$legacyLedger').update({'status': 'cancelled'});

    final s = await summary();
    final e = byId(s, expense.paymentId);
    expect(e.sourceLabel, 'Finance → Expenses');
    expect(e.linkedDocumentLabel, 'Invoice');
    expect(e.linkedDocumentNumber, 'INV-00010013');
    expect(e.linkedDocumentId, expense.invoiceId);
    expect(e.reason, 'Recorded by mistake');
    expect(e.statusLabel, 'Reversed');
    final sal = byId(s, salary.paymentId);
    expect(sal.sourceLabel, 'Finance → Salary');
    expect(sal.linkedDocumentNumber, 'INV-00010014');
    expect(byId(s, legacy.paymentId).linkedDocumentNumber, 'INV-00010015');
    expect(s.transactions.every((t) => t.reviewNote.isEmpty), isTrue);
  });

  testWidgets('4. missing reference vs missing source record', (tester) async {
    await finance.voidIncome(await manualIncome(2000, title: 'Test 2'));
    final receiptId = await collect(1500, referenceNo: 'UPI-778');
    await fees.voidReceipt(receiptId);
    await firestore.doc('fee_receipts/$receiptId').delete(); // linked source record now missing
    final s = await summary();
    expect(s.count, 2, reason: 'a missing linked receipt is flagged, not dropped');
    final fee = s.transactions.singleWhere((t) => t.sourceLabel == 'Fees');
    expect(fee.linkedDocumentFound, isFalse);
    expect(fee.reviewNote, 'The linked Fee Collection receipt record was not found');
    expect(fee.reference, 'UPI-778');
    final manual = s.transactions.singleWhere((t) => t.sourceLabel == 'Finance → Income');
    expect(manual.reviewNote, '');

    await openList(tester);
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
    final heading = 'Fee collection • ${fee.title}';
    expect(inRow(heading, 'Receipt record not found'), findsOneWidget);
    expect(inRow(heading, 'UPI-778'), findsOneWidget);
    expect(inRow(heading, receiptId), findsOneWidget);
    expect(find.descendant(of: rowBlock(heading), matching: find.textContaining('Still counted')), findsOneWidget);
    expect(inRow('Manual income • Test 2', 'Reference not recorded'), findsOneWidget);
  });

  test('5. duplicate fee links and extra ledger lines do not inflate count or amount', () async {
    final first = await collect(10000);
    await fees.voidReceipt(first);
    await fees.voidReceipt(await collect(3000));
    // A second Finance entry pointing at the first collection.
    final linked = (await firestore.collection('finance_income').where('sourceId', isEqualTo: first).get()).docs.single;
    await firestore.collection('finance_income').add({...linked.data(), 'ledgerEntryId': ''});
    // A stray cancelled ledger line mirroring nothing.
    await firestore.collection('finance_ledger').add({'entryType': 'income', 'amount': 10000, 'status': 'cancelled', 'title': 'Copy'});

    final s = await summary();
    expect(s.count, 1);
    expect(s.originalAmount, 3000);
    expect(s.exclusions.map((e) => e.reason), containsAll([
      'More than one Finance entry is linked to the same Fee Collection',
      'Cancelled ledger entry with no linked Finance income record',
    ]));
    expect(s.exclusions.singleWhere((e) => e.collection == 'finance_ledger').title, 'Copy');
  });

  test('6. active transactions are excluded', () async {
    await manualIncome(1000);
    await collect(4500);
    await invoicePayment(2000);
    final s = await summary();
    expect(s.count, 0);
    expect(s.originalAmount, 0);
    expect(s.exclusions, isEmpty);
  });

  testWidgets('7. count and amount reconcile to the rows listed', (tester) async {
    await finance.voidIncome(await manualIncome(2000, title: 'Test 2'));
    await finance.voidIncome(await manualIncome(4000));
    await fees.voidReceipt(await collect(10000));
    final p = await invoicePayment(2000, invoiceNo: 'INV-00010013');
    await finance.reverseExpenseInvoicePayment(paymentId: p.paymentId, reason: 'Mistake');
    final s = await summary();
    expect(s.count, 4);
    expect(s.originalAmount, 18000);
    expect(s.transactions.fold<double>(0, (a, t) => a + t.amount), s.originalAmount);
    expect(s.transactions.map((t) => t.id).toSet(), hasLength(s.count));

    await openList(tester);
    expect(find.text('Original amount'), findsNWidgets(4));
    expect(find.text('Counted: 4 transactions, ₹18000 in total — the sum of the amounts listed above.'), findsOneWidget);
  });

  test('8. Net Movement, Closing Balance and account balances are unchanged', () async {
    await manualIncome(1000);
    await finance.voidIncome(await manualIncome(500));
    await fees.voidReceipt(await collect(4500));
    final before = await finance.watchDashboardSummary().first;
    final cancelled = await summary();
    final after = await finance.watchDashboardSummary().first;
    expect(cancelled.originalAmount, 5000);
    for (final s in [before, after]) {
      expect(s.netBalance, 1000);
      expect(s.closingBalance, 1000);
      expect(s.cashBalance, 1000);
      expect(s.bankBalance, 0);
      expect(s.upiBalance, 0);
    }
    expect(((await doc('finance_accounts/${await cashId()}'))['currentBalance'] as num).toDouble(), 1000);
  });

  testWidgets('9. a lookup failure, even after a valid result, never shows a total', (tester) async {
    final controller = StreamController<FinanceCancelledTransactionsSummary>();
    addTearDown(controller.close);
    finance.replacement = controller.stream;
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
    await tester.pumpAndSettle();
    final card = find.ancestor(of: find.text('Cancelled / Voided Transactions'), matching: find.byType(InkWell)).first;

    controller.add(const FinanceCancelledTransactionsSummary(transactions: [
      FinanceCancelledTransaction(
        id: 'x', sourceLabel: 'Finance → Income', typeLabel: 'Manual income', title: 'T', reference: '',
        originalDate: null, cancelledAt: null, amount: 160000, reason: '', statusLabel: 'Voided',
      ),
    ], exclusions: []));
    await tester.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.text('₹160000')), findsOneWidget);

    controller.addError(Exception('fee_receipts lookup failed'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.textContaining("Couldn't load cancelled transactions")), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('₹160000')), findsNothing);
    expect(find.descendant(of: card, matching: find.text('1')), findsNothing);
    // Not openable while failed.
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Cancelled / Voided Transactions'), findsOneWidget);
  });

  group('type filter', () {
    Finder filterChip(String label) => find.descendant(
          of: find.byKey(const Key('cancelled-type-filter')),
          matching: find.widgetWithText(ChoiceChip, label),
        );
    Future<void> selectFilter(WidgetTester tester, String label) async {
      await tester.tap(filterChip(label));
      await tester.pumpAndSettle();
    }

    int rows(String typeLabel) => find.textContaining('$typeLabel • ').evaluate().length;

    late String expensePaymentId;
    late String receiptId;

    Future<void> seedAllTypes() async {
      await finance.voidIncome(await manualIncome(2000, title: 'Test 2'));
      await finance.voidIncome(await manualIncome(4000));
      receiptId = await collect(10000);
      await fees.voidReceipt(receiptId);
      final expense = await invoicePayment(2000, invoiceNo: 'INV-00010013');
      expensePaymentId = expense.paymentId;
      await finance.reverseExpenseInvoicePayment(paymentId: expense.paymentId, reason: 'Recorded by mistake');
      // No app workflow reverses salary payments; a record in that state is seeded.
      final salary = await invoicePayment(5000, type: 'salary', invoiceNo: 'INV-00010014');
      final salaryLedger = (await doc('finance_income/${salary.paymentId}'))['ledgerEntryId'] as String;
      await firestore.doc('finance_income/${salary.paymentId}').update({'isDeleted': true});
      await firestore.doc('finance_ledger/$salaryLedger').update({'status': 'cancelled'});
    }

    testWidgets('All shows every transaction; Income, Expenses and Salary show only their types', (tester) async {
      await seedAllTypes();
      final s = await summary();
      expect(s.count, 5);
      expect(s.originalAmount, 23000);
      await openList(tester);

      expect(tester.widget<ChoiceChip>(filterChip('All')).selected, isTrue);
      expect([rows('Manual income'), rows('Fee collection'), rows('Expense payment'), rows('Salary payment')], [2, 1, 1, 1]);
      expect(find.text('Counted: 5 transactions, ₹23000 in total — the sum of the amounts listed above.'), findsOneWidget);

      await selectFilter(tester, 'Income');
      expect(tester.widget<ChoiceChip>(filterChip('Income')).selected, isTrue);
      expect([rows('Manual income'), rows('Fee collection'), rows('Expense payment'), rows('Salary payment')], [2, 1, 0, 0]);
      expect(find.text('Original amount'), findsNWidgets(3));
      expect(
        find.text('Income: 3 transactions, ₹16000 in total — the sum of the amounts listed above. All types: 5, ₹23000.'),
        findsOneWidget,
      );

      await selectFilter(tester, 'Expenses');
      expect([rows('Manual income'), rows('Fee collection'), rows('Expense payment'), rows('Salary payment')], [0, 0, 1, 0]);
      expect(
        find.text('Expenses: 1 transaction, ₹2000 in total — the sum of the amounts listed above. All types: 5, ₹23000.'),
        findsOneWidget,
      );

      await selectFilter(tester, 'Salary');
      expect([rows('Manual income'), rows('Fee collection'), rows('Expense payment'), rows('Salary payment')], [0, 0, 0, 1]);
      expect(
        find.text('Salary: 1 transaction, ₹5000 in total — the sum of the amounts listed above. All types: 5, ₹23000.'),
        findsOneWidget,
      );

      await selectFilter(tester, 'All');
      expect([rows('Manual income'), rows('Fee collection'), rows('Expense payment'), rows('Salary payment')], [2, 1, 1, 1]);
      expect(find.text('Counted: 5 transactions, ₹23000 in total — the sum of the amounts listed above.'), findsOneWidget);
      // The underlying summary is untouched by filtering.
      expect((await summary()).count, 5);
    });

    testWidgets('each row keeps its heading, a type chip, sourceLabel and all traceability details when filtered', (tester) async {
      await seedAllTypes();
      final receiptNo = (await doc('fee_receipts/$receiptId'))['receiptNo'] as String;
      final expenseLedger = (await doc('finance_income/$expensePaymentId'))['ledgerEntryId'] as String;
      await openList(tester);

      await selectFilter(tester, 'Expenses');
      const heading = 'Expense payment • Expense Payment - Party';
      for (final text in [
        'EXPENSES', 'Finance → Expenses', 'INV-00010013', 'Invoice ID', 'Invoice status', 'Reference not recorded',
        'Record ID', expensePaymentId, '$expenseLedger (cancelled)', 'Original date', 'Cancelled on', '₹2000',
        'Recorded by mistake', 'Reversed',
      ]) {
        expect(inRow(heading, text), findsOneWidget, reason: text);
      }

      await selectFilter(tester, 'Income');
      final feeHeading = find.textContaining('Fee collection • ').evaluate().single.widget as Text;
      for (final text in ['INCOME', 'Fees', receiptNo, 'Collection ID', receiptId, 'Finance record ID', 'Receipt status']) {
        expect(inRow(feeHeading.data!, text), findsOneWidget, reason: text);
      }
      expect(inRow('Manual income • Test 2', 'INCOME'), findsOneWidget);
      expect(inRow('Manual income • Test 2', 'Finance → Income'), findsOneWidget);

      await selectFilter(tester, 'Salary');
      expect(inRow('Salary payment • Salary Payment - Party', 'SALARY'), findsOneWidget);
      expect(inRow('Salary payment • Salary Payment - Party', 'Finance → Salary'), findsOneWidget);
      expect(inRow('Salary payment • Salary Payment - Party', 'INV-00010014'), findsOneWidget);
    });

    testWidgets('a counted record needing review stays visible with its note under its filter', (tester) async {
      final receipt = await collect(1500);
      await fees.voidReceipt(receipt);
      await firestore.doc('fee_receipts/$receipt').delete();
      await openList(tester);
      await selectFilter(tester, 'Income');
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
      expect(find.textContaining('Still counted'), findsOneWidget);
      await selectFilter(tester, 'Expenses');
      expect(find.text('NEEDS REVIEW'), findsNothing);
      expect(find.text('No cancelled or voided expense transactions.'), findsOneWidget);
    });
  });
}
