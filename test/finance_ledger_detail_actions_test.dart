// Finance -> Ledger transaction details: the actions offered for each kind
// of transaction, all through the existing workflows.
// - Fee Collection income: "Open in Fees" (that exact collection's Edit
//   Collection dialog in Fees) and "Void Fee Collection" (the Fees void);
//   never Finance's Edit, which can't change it.
// - Income entered in Finance: Edit (the Edit Income dialog, which saves)
//   and Void.
// - Cancelled entries: no action.
// - Expense invoice payments: Reverse payment; direct expenses and salary
//   payments: none.
// Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_dialog.dart';
import 'package:montessori_app/modules/finance/models/finance_expense_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_income_dialog.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

DateTime _today() => DateTime(2026, 11, 6, 10);

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late FeeService fees;
  late String cashId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
    await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('students').doc('s1').set({'name': 'Adhira D', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true});
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1', 'studentName': 'Adhira D', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
      'feeStructureId': 'structure-1', 'feeStructureName': 'Core Fees', 'academicYear': '2026-2027',
      'totalFee': 20000, 'discountAmount': 0, 'payableAmount': 20000, 'paidAmount': 0, 'balanceAmount': 20000, 'status': 'unpaid',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<String> collectFee({double amount = 4500}) async => (await fees.collectFee(
        assignmentId: 'a1', amount: amount, paymentDate: DateTime(2026, 11, 2), paymentMode: 'cash', referenceNo: 'FEE-1', remarks: '',
      ))
          .id;

  Future<String> manualIncome() async {
    final cat = (await finance.watchCategories().first).firstWhere((c) => c.name == 'Other Income');
    return finance.createIncome(FinanceIncomeModel(
      id: '', title: 'Hall rental', categoryId: cat.id, categoryName: 'Other Income', programType: 'other',
      studentId: '', studentName: '', classId: '', className: '', amount: 3000, incomeDate: DateTime(2026, 11, 3),
      paymentMode: 'cash', accountId: cashId, accountName: 'Cash', referenceNo: 'HR-1', remarks: '', attachmentUrls: const [],
      ledgerEntryId: '', createdAt: DateTime(2026, 11, 3), updatedAt: DateTime(2026, 11, 3), createdBy: 'admin',
    ));
  }

  Future<Map<String, dynamic>> doc(String path) async => (await firestore.doc(path).get()).data()!;
  Future<String> ledgerOfIncome(String incomeId) async => (await doc('finance_income/$incomeId'))['ledgerEntryId'] as String;
  Future<String> feeIncomeId(String receiptId) async =>
      (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single.id;

  Future<void> pumpLedger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees, clock: _today))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> openRow(WidgetTester tester, String title) async {
    await tap(tester, find.ancestor(of: find.text(title), matching: find.byType(LedgerEntryCard)).first);
    expect(key('ledger-detail'), findsOneWidget);
  }

  void expectActions(List<String> present) {
    for (final a in ['edit', 'void', 'reverse', 'open-in-fees']) {
      expect(key('ledger-detail-$a'), present.contains(a) ? findsOneWidget : findsNothing, reason: a);
    }
  }

  testWidgets('Fee Collection income: Open in Fees and Void Fee Collection, no Edit; Open in Fees opens that exact collection', (tester) async {
    await collectFee(amount: 1200); // another collection, so the right one must be picked
    final receiptId = await collectFee();
    await pumpLedger(tester);
    final titles = [for (final c in tester.widgetList<LedgerEntryCard>(find.byType(LedgerEntryCard))) c.entry];
    final entry = titles.firstWhere((e) => e.amount == 4500);
    await tap(tester, find.byKey(Key('ledger-entry-${entry.id}')));
    expectActions(['void', 'open-in-fees']);
    expect(key('ledger-detail-fees-note'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.ancestor(of: find.text('Open in Fees'), matching: find.byType(OutlinedButton))).onPressed, isNotNull);

    await tap(tester, key('ledger-detail-open-in-fees'));
    expect(key('ledger-detail'), findsNothing);
    expect(find.byType(AdminFeesScreen), findsOneWidget);
    expect(tester.widget<AdminFeesScreen>(find.byType(AdminFeesScreen)).openReceiptId, receiptId);
    final dialog = tester.widget<FeeCollectionDialog>(find.byType(FeeCollectionDialog));
    expect(dialog.receipt!.id, receiptId, reason: 'the original collection, in the Fees edit dialog');
    expect(dialog.receipt!.amount, 4500);
    expect(dialog.assignment.id, 'a1');
    // Nothing was written by opening it.
    expect((await doc('fee_receipts/$receiptId'))['amount'], 4500);
  });

  testWidgets('Fee Collection income: Void Fee Collection still runs the Fees void (receipt, income, ledger together)', (tester) async {
    final receiptId = await collectFee();
    final incomeId = await feeIncomeId(receiptId);
    final ledgerId = await ledgerOfIncome(incomeId);
    await pumpLedger(tester);
    await tap(tester, find.byKey(Key('ledger-entry-$ledgerId')));
    await tap(tester, key('ledger-detail-void'));
    expect(find.text('Void Fee Collection'), findsWidgets, reason: 'the existing confirmation');
    await tap(tester, find.widgetWithText(FilledButton, 'Void'));
    expect((await doc('fee_receipts/$receiptId'))['isDeleted'], isTrue);
    expect((await doc('finance_income/$incomeId'))['isDeleted'], isTrue);
    expect((await doc('finance_ledger/$ledgerId'))['status'], 'cancelled');
    expect((await doc('student_fee_assignments/a1'))['balanceAmount'], 20000);

    // Cancelled now: shown on request, with no action.
    await tap(tester, key('ledger-show-cancelled'));
    await tap(tester, find.byKey(Key('ledger-entry-$ledgerId')));
    expect(key('ledger-detail-cancelled'), findsOneWidget);
    expectActions(const []);
    expect(key('ledger-detail-fees-note'), findsNothing);
  });

  testWidgets('a fee collection that no longer exists: Fees says so instead of opening something else', (tester) async {
    final receiptId = await collectFee();
    await firestore.collection('fee_receipts').doc(receiptId).delete();
    final ledgerId = await ledgerOfIncome(await feeIncomeId(receiptId));
    await pumpLedger(tester);
    await tap(tester, find.byKey(Key('ledger-entry-$ledgerId')));
    await tap(tester, key('ledger-detail-open-in-fees'));
    expect(find.byType(FeeCollectionDialog), findsNothing);
    expect(find.text('The fee collection for this transaction could not be found, or it has been voided.'), findsOneWidget);
  });

  testWidgets('income entered in Finance: Edit opens the Edit Income dialog and saves; Void; no Open in Fees', (tester) async {
    final incomeId = await manualIncome();
    final ledgerId = await ledgerOfIncome(incomeId);
    await pumpLedger(tester);
    await openRow(tester, 'Hall rental');
    expectActions(['edit', 'void']);
    expect(key('ledger-detail-fees-note'), findsNothing);

    await tap(tester, key('ledger-detail-edit'));
    expect(find.byType(AddIncomeDialog), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '3500');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.byType(AddIncomeDialog), findsNothing);
    expect((await doc('finance_income/$incomeId'))['amount'], 3500);
    expect((await doc('finance_ledger/$ledgerId'))['amount'], 3500, reason: 'its ledger entry follows, no new entry');
    expect((await firestore.collection('finance_ledger').get()).docs, hasLength(1));
    expect((await finance.watchDashboardSummary().first).cashBalance, 3500);

    await openRow(tester, 'Hall rental');
    await tap(tester, key('ledger-detail-void'));
    expect(find.text('Void Income Entry'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Void'));
    expect((await doc('finance_ledger/$ledgerId'))['status'], 'cancelled');
    await tap(tester, key('ledger-show-cancelled'));
    await openRow(tester, 'Hall rental');
    expectActions(const []);
  });

  testWidgets('expenses: an invoice payment offers Reverse payment (which still works); direct expenses and salary payments offer nothing', (tester) async {
    final invoiceId = await finance.createExpenseInvoice({'partyName': 'Acme', 'totalAmount': 800, 'amount': 800, 'invoiceNo': 'EXP-7', 'invoiceDate': DateTime(2026, 11, 1)});
    final paymentId = (await finance.payInvoice(invoiceId: invoiceId, invoiceType: 'expense', amount: 800, paidDate: DateTime(2026, 11, 4), paymentMode: 'cash', referenceNo: 'R', remarks: ''))!;
    final ledgerId = await ledgerOfIncome(paymentId);
    final salaryInvoice = await finance.createSalaryInvoice({'partyName': 'Teacher A', 'totalAmount': 900, 'amount': 900, 'invoiceNo': 'SAL-1', 'invoiceDate': DateTime(2026, 11, 1)});
    await finance.payInvoice(invoiceId: salaryInvoice, invoiceType: 'salary', amount: 900, paidDate: DateTime(2026, 11, 5), paymentMode: 'cash', referenceNo: '', remarks: '');
    await finance.createExpense(FinanceExpenseModel.fromMap('', {
      'title': 'Stationery', 'categoryId': 'c', 'categoryName': 'Supplies', 'vendorName': 'Corner Shop', 'amount': 90,
      'expenseDate': DateTime(2026, 11, 2), 'paymentMode': 'cash', 'accountId': cashId, 'accountName': 'Cash', 'createdAt': DateTime(2026, 11, 2),
    }));
    await pumpLedger(tester);

    await openRow(tester, 'Salary Payment - Teacher A');
    expectActions(const []);
    await tap(tester, key('ledger-detail-close'));
    await openRow(tester, 'Stationery');
    expectActions(const []);
    await tap(tester, key('ledger-detail-close'));

    await tap(tester, find.byKey(Key('ledger-entry-$ledgerId')));
    expectActions(['reverse']);
    await tap(tester, key('ledger-detail-reverse'));
    await tester.enterText(find.byType(TextField).last, 'Recorded twice');
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(FilledButton, 'Reverse Payment'));
    expect((await doc('finance_ledger/$ledgerId'))['status'], 'cancelled');
    expect((await doc('finance_invoices/$invoiceId'))['paidAmount'], 0);
  });
}
