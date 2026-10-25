// Finance Dashboard -> "Cancelled / Voided Transactions" card
// (FinanceService.watchCancelledTransactions):
// - One count per voided finance_income record (manual income, Fee
//   Collection income, reversed expense/salary invoice payment) with its
//   own original amount; its cancelled ledger mirror and the voided fees
//   receipt are never counted again; retries add nothing.
// - Unclear records (status/link disagreements, duplicate fee links, no
//   amount, cancelled ledger lines with no income record) are listed as
//   "not counted", never silently included.
// - Loading/failure are shown explicitly, never as a zero; read-only;
//   active totals and balances are unchanged.
//
// Records are created and cancelled through the existing workflows where
// they exist; states those workflows can't produce are seeded directly.
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

/// Real service whose cancelled-transactions stream can be replaced.
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
    await firestore.collection('students').doc('s1').set({'name': 'Adhira D', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true});
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1', 'studentName': 'Adhira D', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
      'feeStructureId': 'structure-1', 'feeStructureName': 'Core Fees', 'academicYear': '2026-2027',
      'totalFee': 20000, 'discountAmount': 0, 'payableAmount': 20000, 'paidAmount': 0, 'balanceAmount': 20000,
      'status': 'unpaid', 'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Future<String> cashId() async =>
      (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;

  Future<String> manualIncome(double amount, {DateTime? date}) async => finance.createIncome(FinanceIncomeModel(
        id: '', title: 'Donation', categoryId: 'c', categoryName: 'Other Income', programType: 'other',
        studentId: '', studentName: '', classId: '', className: '', amount: amount,
        incomeDate: date ?? DateTime(2026, 8, 1), paymentMode: 'cash', accountId: await cashId(), accountName: 'Cash',
        referenceNo: 'DON-1', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
      ));

  Future<String> collect(double amount) async => (await fees.collectFee(
        assignmentId: 'a1', amount: amount, paymentDate: DateTime(2026, 8, 2), paymentMode: 'cash', referenceNo: 'REF-F', remarks: '',
      )).id;

  Future<String> expensePayment(double amount, {String type = 'expense'}) async {
    final payload = {
      'partyName': type == 'salary' ? 'Malani D' : 'Vendor', 'categoryName': 'Rent', 'invoiceNo': 'INV-0${type.length}',
      'totalAmount': amount, 'amount': amount,
    };
    final invoiceId = type == 'salary' ? await finance.createSalaryInvoice(payload) : await finance.createExpenseInvoice(payload);
    return (await finance.payInvoice(
      invoiceId: invoiceId, invoiceType: type, amount: amount, paidDate: DateTime(2026, 8, 3),
      paymentMode: 'cash', referenceNo: '', remarks: '',
    ))!;
  }

  Future<FinanceCancelledTransactionsSummary> summary() => finance.watchCancelledTransactions().first;

  Future<Map<String, Map<String, dynamic>?>> snapshotAll() async => {
        for (final c in ['finance_income', 'finance_ledger', 'finance_accounts', 'finance_invoices', 'fee_receipts', 'student_fee_assignments'])
          for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
      };

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
    await tester.pumpAndSettle();
  }

  Finder card() => find.ancestor(of: find.text('Cancelled / Voided Transactions'), matching: find.byType(InkWell)).first;
  Finder inCard(String text) => find.descendant(of: card(), matching: find.text(text));

  testWidgets('1. no cancellations: count 0 and ₹0', (tester) async {
    await manualIncome(1000); // active
    final s = await summary();
    expect(s.count, 0);
    expect(s.originalAmount, 0);
    expect(s.exclusions, isEmpty);

    await pumpDashboard(tester);
    expect(inCard('0'), findsOneWidget);
    expect(inCard('₹0'), findsOneWidget);
    expect(inCard('Cancelled count'), findsOneWidget);
    expect(inCard('Original amount cancelled'), findsOneWidget);
  });

  test('2. one voided manual income transaction', () async {
    final id = await manualIncome(1200);
    await finance.voidIncome(id);
    final s = await summary();
    expect(s.count, 1);
    expect(s.originalAmount, 1200);
    final t = s.transactions.single;
    expect(t.id, id);
    expect(t.typeLabel, 'Manual income');
    expect(t.statusLabel, 'Voided');
    expect(t.reference, 'DON-1');
    expect(t.originalDate, DateTime(2026, 8, 1));
    expect(t.cancelledAt, isNotNull);
  });

  test('3. a voided fee collection (receipt + Finance income + ledger) counts once', () async {
    final receiptId = await collect(4500);
    await fees.voidReceipt(receiptId);
    expect((await firestore.doc('fee_receipts/$receiptId').get()).data()!['isDeleted'], isTrue);
    final s = await summary();
    expect(s.count, 1);
    expect(s.originalAmount, 4500);
    expect(s.transactions.single.typeLabel, 'Fee collection');
    expect(s.transactions.single.reference, 'REF-F');
    expect(s.exclusions, isEmpty);
  });

  test('4. multiple distinct cancellations: count and total original amount', () async {
    await finance.voidIncome(await manualIncome(1000));
    await fees.voidReceipt(await collect(4500));
    await finance.reverseExpenseInvoicePayment(paymentId: await expensePayment(2000), reason: 'Entered twice');
    final s = await summary();
    expect(s.count, 3);
    expect(s.originalAmount, 7500);
    expect(s.transactions.map((t) => t.typeLabel).toSet(), {'Manual income', 'Fee collection', 'Expense payment'});
  });

  test('5. retried cancellation does not double-count', () async {
    final receiptId = await collect(4500);
    await fees.voidReceipt(receiptId);
    await expectLater(fees.voidReceipt(receiptId), throwsStateError);
    await finance.reverseFeeIncomeByCollectionId(receiptId);
    final manual = await manualIncome(800);
    await finance.voidIncome(manual);
    await expectLater(finance.voidIncome(manual), throwsStateError);
    final s = await summary();
    expect(s.count, 2);
    expect(s.originalAmount, 5300);
  });

  test('6. active transactions are excluded', () async {
    await manualIncome(1000);
    await collect(4500);
    await expensePayment(2000);
    await finance.voidIncome(await manualIncome(300));
    final s = await summary();
    expect(s.count, 1);
    expect(s.originalAmount, 300);
  });

  test('7. cancelled ledger lines are not separate transactions; unlinked ones are reported, not counted', () async {
    await finance.voidIncome(await manualIncome(1000));
    final cancelledLedger = (await firestore.collection('finance_ledger').where('status', isEqualTo: 'cancelled').get()).docs;
    expect(cancelledLedger, hasLength(1)); // the mirror of the voided income
    final orphan = await firestore.collection('finance_ledger').add({'entryType': 'income', 'amount': 50, 'status': 'confirmed', 'title': 'Imported line'});
    await finance.cancelLedgerEntry(orphan.id, reason: 'Duplicate import');

    final s = await summary();
    expect(s.count, 1);
    expect(s.originalAmount, 1000);
    expect(s.exclusions.single.id, orphan.id);
    expect(s.exclusions.single.reason, contains('no linked Finance income record'));
  });

  test('8. reversed expense payment (and a reversed salary payment record) are identified', () async {
    final expense = await expensePayment(2000);
    await finance.reverseExpenseInvoicePayment(paymentId: expense, reason: 'Recorded by mistake');
    // No app workflow reverses salary payments; a record in that state
    // (same fields as an expense reversal) is still identified.
    final salary = await expensePayment(5000, type: 'salary');
    final salaryLedger = (await firestore.doc('finance_income/$salary').get()).data()!['ledgerEntryId'] as String;
    await firestore.doc('finance_income/$salary').update({'isDeleted': true});
    await firestore.doc('finance_ledger/$salaryLedger').update({'status': 'cancelled'});

    final s = await summary();
    final byId = {for (final t in s.transactions) t.id: t};
    expect(byId[expense]!.typeLabel, 'Expense payment');
    expect(byId[expense]!.statusLabel, 'Reversed');
    expect(byId[expense]!.reason, 'Recorded by mistake');
    expect(byId[expense]!.amount, 2000);
    expect(byId[salary]!.typeLabel, 'Salary payment');
    expect(s.originalAmount, 7000);
  });

  testWidgets('9. missing cancellation date or reason shows "Not recorded", never an invented value', (tester) async {
    await firestore.collection('finance_income').add({
      'title': 'Old donation', 'amount': 650, 'sourceModule': 'finance', 'isDeleted': true, // no dates, no reason, no ledger
    });
    final s = await summary();
    expect(s.transactions.single.cancelledAt, isNull);
    expect(s.transactions.single.originalDate, isNull);
    expect(s.transactions.single.reason, '');

    await pumpDashboard(tester);
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(find.text('Manual income • Old donation'), findsOneWidget);
    final entry = find.ancestor(of: find.text('Manual income • Old donation'), matching: find.byType(Column)).first;
    expect(find.descendant(of: entry, matching: find.text('₹650')), findsOneWidget);
    expect(find.text('Not recorded'), findsNWidgets(3)); // original date, cancelled on, reason
    expect(find.text('Reference not recorded'), findsOneWidget);
    expect(find.text(s.transactions.single.id), findsOneWidget); // Record ID shown instead
    expect(find.text('Voided'), findsOneWidget);
  });

  testWidgets('10. a lookup failure is shown as an error, not as a zero', (tester) async {
    finance.replacement = Stream.error(Exception('unavailable'));
    await pumpDashboard(tester);
    expect(find.descendant(of: card(), matching: find.textContaining("Couldn't load cancelled transactions")), findsOneWidget);
    expect(inCard('0'), findsNothing);
    expect(inCard('₹0'), findsNothing);
  });

  testWidgets('10b. while loading, no zero is shown', (tester) async {
    final controller = StreamController<FinanceCancelledTransactionsSummary>();
    addTearDown(controller.close);
    finance.replacement = controller.stream;
    await pumpDashboard(tester);
    expect(inCard('Loading…'), findsOneWidget);
    expect(inCard('0'), findsNothing);
  });

  testWidgets('11. Net Movement and Closing Balance are unchanged by cancelled amounts', (tester) async {
    await manualIncome(1000);
    await finance.voidIncome(await manualIncome(500));
    await fees.voidReceipt(await collect(4500));
    final s = await finance.watchDashboardSummary().first;
    expect(s.totalIncome, 1000);
    expect(s.netBalance, 1000);
    expect(s.closingBalance, 1000);
    expect(s.cashBalance, 1000);
    expect((await summary()).originalAmount, 5000);

    await pumpDashboard(tester);
    final netMovement = find.ancestor(of: find.text('Net Movement'), matching: find.byType(Container)).first;
    expect(find.descendant(of: netMovement, matching: find.text('₹1000')), findsOneWidget);
    expect(find.text('Closing Balance ₹1000 = Cash ₹1000 + Bank ₹0 + UPI ₹0'), findsOneWidget);
    expect(inCard('₹5000'), findsOneWidget);
    expect(inCard('2'), findsOneWidget);
  });

  testWidgets('12. read-only: watching and opening the list changes no record', (tester) async {
    await finance.voidIncome(await manualIncome(500));
    await fees.voidReceipt(await collect(4500));
    final before = await snapshotAll();
    await pumpDashboard(tester);
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(find.text('Cancelled / Voided Transactions'), findsNWidgets(2)); // card + dialog title
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(await snapshotAll(), before);
  });

  test('ambiguous records are reported and not counted', () async {
    // Voided income whose ledger entry is still active.
    final a = await manualIncome(100);
    await firestore.doc('finance_income/$a').update({'isDeleted': true});
    // Active income whose ledger entry is cancelled.
    final b = await manualIncome(200);
    final bLedger = (await firestore.doc('finance_income/$b').get()).data()!['ledgerEntryId'] as String;
    await firestore.doc('finance_ledger/$bLedger').update({'status': 'cancelled'});
    // Two Finance entries linked to one Fee Collection, one voided.
    final receiptId = await collect(4500);
    final linked = (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single;
    await firestore.collection('finance_income').add({...linked.data(), 'isDeleted': true, 'ledgerEntryId': ''});
    // Voided with no stored amount.
    await firestore.collection('finance_income').add({'title': 'No amount', 'isDeleted': true});

    final s = await summary();
    expect(s.count, 0);
    expect(s.originalAmount, 0);
    expect(s.exclusions.map((e) => e.reason), containsAll([
      'Voided Finance entry, but its ledger entry is still active',
      'Active Finance entry, but its ledger entry is cancelled',
      'More than one Finance entry is linked to the same Fee Collection',
      'Original amount not recorded',
    ]));
  });

  testWidgets('the card reports unclear records and the list shows why', (tester) async {
    await finance.voidIncome(await manualIncome(300));
    final a = await manualIncome(100);
    await firestore.doc('finance_income/$a').update({'isDeleted': true});
    await pumpDashboard(tester);
    expect(inCard('1'), findsOneWidget);
    expect(inCard('₹300'), findsOneWidget);
    expect(find.descendant(of: card(), matching: find.text('1 record with an unclear status not counted')), findsOneWidget);
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(find.text('Needs review — not counted'), findsOneWidget);
    expect(find.textContaining('its ledger entry is still active'), findsOneWidget);
  });
}
