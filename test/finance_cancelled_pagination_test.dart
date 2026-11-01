// Finance Dashboard -> Cancelled / Voided Transactions dialog: UI pagination
// of the counted rows (10/25/50 per page), with the same controls as the
// Finance tabs.
// - Only the current page's rows are built, in the summary's order.
// - The "Counted"/filter count and original-amount line always covers the
//   complete filtered list, never just the page.
// - Back to page 1 when the type filter changes (even if it shows the same
//   rows) or the page becomes invalid; the page size is kept.
// - "Needs review — not counted" exclusions are not paginated: shown in
//   full under every filter and on every page, as before.
// - No controls when the (filtered) list is empty; controls wrap at 360px.
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
  Stream<FinanceCancelledTransactionsSummary> watchCancelledTransactions() => replacement ?? super.watchCancelledTransactions();
}

String _title(int n) => 'Txn ${n.toString().padLeft(2, '0')}';

/// Rows 1..15 income (odd manual, even fee), 16..22 expenses, 23..27
/// salary; amount ₹100 × n; row 14 needs review (still counted).
String _typeOf(int n) => n <= 15
    ? (n.isOdd ? 'Manual income' : 'Fee collection')
    : n <= 22
        ? 'Expense payment'
        : 'Salary payment';

FinanceCancelledTransaction _txn(int n, {String? type}) => FinanceCancelledTransaction(
      id: 'income-$n',
      sourceLabel: 'Source $n',
      typeLabel: type ?? _typeOf(n),
      title: _title(n),
      reference: 'R-$n',
      originalDate: DateTime(2026, 8, 1),
      cancelledAt: DateTime(2026, 9, 1),
      amount: n * 100.0,
      reason: 'Reason $n',
      statusLabel: 'Voided',
      ledgerId: 'ledger-$n',
      ledgerStatus: 'cancelled',
      reviewNote: n == 14 ? 'Its linked receipt is missing' : '',
    );

const _exclusions = [
  FinanceCancellationExclusion(id: 'odd-1', title: 'Unclear A', reason: 'its ledger entry is still active'),
  FinanceCancellationExclusion(id: 'odd-2', title: 'Unclear B', reason: 'it has no amount', collection: 'finance_ledger'),
];

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
    await firestore.collection('students').doc('s1').set({'name': 'Student One', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true});
    await firestore.collection('student_fee_assignments').doc('a1').set({
      'studentId': 's1', 'studentName': 'Student One', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
      'feeStructureId': 'structure-1', 'feeStructureName': 'Core Fees', 'academicYear': '2026-2027',
      'totalFee': 20000, 'discountAmount': 0, 'payableAmount': 20000, 'paidAmount': 0, 'balanceAmount': 20000,
      'status': 'unpaid', 'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  });

  void useSummary(List<FinanceCancelledTransaction> transactions, {List<FinanceCancellationExclusion> exclusions = _exclusions}) =>
      finance.replacement = Stream.value(FinanceCancelledTransactionsSummary(transactions: transactions, exclusions: exclusions)).asBroadcastStream();
  List<FinanceCancelledTransaction> seeded([int count = 27]) => [for (var n = 1; n <= count; n++) _txn(n)];

  Future<void> openList(WidgetTester tester, {Size size = const Size(1400, 3000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
    await tester.pumpAndSettle();
    // The Dashboard itself renders without overflow at every width tested
    // (the Recent Transactions header used to overflow at 360px).
    expect(tester.takeException(), isNull);
    final card = find.ancestor(of: find.text('Cancelled / Voided Transactions'), matching: find.byType(InkWell)).first;
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  Finder pagination() => find.byKey(const Key('cancelled-pagination'));
  Finder next() => find.descendant(of: pagination(), matching: find.byTooltip('Next page'));
  Finder previous() => find.descendant(of: pagination(), matching: find.byTooltip('Previous page'));
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<IconButton>(find.ancestor(of: button, matching: find.byType(IconButton))).onPressed != null;

  List<String> shown(WidgetTester tester) => tester
      .widgetList<Text>(find.textContaining(RegExp(r' • Txn \d\d$')))
      .map((t) => t.data!.split(' • ').last)
      .toList();
  List<String> titles(Iterable<int> ns) => [for (final n in ns) _title(n)];
  Iterable<int> span(int from, int to) => [for (var n = from; n <= to; n++) n];

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choosePageSize(WidgetTester tester, int size) async {
    await tapAndSettle(tester, find.byKey(const Key('cancelled-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.descendant(of: find.byKey(const Key('cancelled-type-filter')), matching: find.widgetWithText(ChoiceChip, label));
  Future<void> filter(WidgetTester tester, String label) => tapAndSettle(tester, chip(label));

  const allLine = 'Counted: 27 transactions, ₹37800 in total — the sum of the amounts listed on all pages.';

  testWidgets('1. first page: 10 rows in summary order, range and page count; only that page is built', (tester) async {
    useSummary(seeded());
    await openList(tester);
    expect(shown(tester), titles(span(1, 10)));
    expect(find.text('Showing 1–10 of 27'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('Original amount'), findsNWidgets(10));
    expect(find.text(allLine), findsOneWidget);
  });

  testWidgets('2 + 5. Next/Previous with disabled ends; count and amount stay over the full list', (tester) async {
    useSummary(seeded());
    await openList(tester);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isTrue);

    await tapAndSettle(tester, next());
    expect(shown(tester), titles(span(11, 20)));
    expect(find.text('Showing 11–20 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text(allLine), findsOneWidget);

    await tapAndSettle(tester, next());
    expect(shown(tester), titles(span(21, 27)));
    expect(find.text('Showing 21–27 of 27'), findsOneWidget);
    expect(enabled(tester, next()), isFalse);
    expect(find.text(allLine), findsOneWidget);

    await tapAndSettle(tester, previous());
    await tapAndSettle(tester, previous());
    expect(shown(tester), titles(span(1, 10)));
    expect(enabled(tester, previous()), isFalse);
    expect(find.text(allLine), findsOneWidget);
  });

  testWidgets('3. page sizes: a valid page is kept, an invalid one returns to page 1', (tester) async {
    useSummary(seeded());
    await openList(tester);
    await tapAndSettle(tester, next());

    await choosePageSize(tester, 25);
    expect(shown(tester), titles(span(26, 27)));
    expect(find.text('Showing 26–27 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await choosePageSize(tester, 50);
    expect(shown(tester), titles(span(1, 27)));
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isFalse);

    await choosePageSize(tester, 10);
    expect(shown(tester), titles(span(1, 10)));
    expect(find.text(allLine), findsOneWidget);
  });

  testWidgets('4 + 5. changing the filter returns to page 1 with that filter\'s full count and amount', (tester) async {
    useSummary(seeded());
    await openList(tester);
    await tapAndSettle(tester, next());
    await tapAndSettle(tester, next());

    await filter(tester, 'Income');
    expect(shown(tester), titles(span(1, 10)));
    expect(find.text('Showing 1–10 of 15'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Income: 15 transactions, ₹12000 in total — the sum of the amounts listed on all pages. All types: 27, ₹37800.'), findsOneWidget);

    await tapAndSettle(tester, next());
    expect(shown(tester), titles(span(11, 15)));
    expect(find.text('Income: 15 transactions, ₹12000 in total — the sum of the amounts listed on all pages. All types: 27, ₹37800.'), findsOneWidget);

    await filter(tester, 'Expenses');
    expect(shown(tester), titles(span(16, 22)));
    expect(find.text('Showing 1–7 of 7'), findsOneWidget);
    expect(find.text('Expenses: 7 transactions, ₹13300 in total — the sum of the amounts listed above. All types: 27, ₹37800.'), findsOneWidget);

    await filter(tester, 'Salary');
    expect(shown(tester), titles(span(23, 27)));
    expect(find.text('Salary: 5 transactions, ₹12500 in total — the sum of the amounts listed above. All types: 27, ₹37800.'), findsOneWidget);

    await filter(tester, 'All');
    expect(shown(tester), titles(span(1, 10)));
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text(allLine), findsOneWidget);
  });

  testWidgets('4b. a filter change resets the page even when it shows the same rows; page size is kept', (tester) async {
    useSummary([for (var n = 1; n <= 27; n++) _txn(n, type: 'Manual income')]);
    await openList(tester);
    await choosePageSize(tester, 25);
    await tapAndSettle(tester, next());
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await filter(tester, 'Income'); // same 27 rows
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Showing 1–25 of 27'), findsOneWidget);
  });

  testWidgets('6. needs-review: exclusions listed in full on every page and filter, not counted; a counted row keeps its note', (tester) async {
    useSummary(seeded());
    await openList(tester);
    void expectExclusions() {
      expect(find.text('Needs review — not counted'), findsOneWidget);
      expect(find.text('Unclear A: its ledger entry is still active. Record ID odd-1 (finance_income).'), findsOneWidget);
      expect(find.text('Unclear B: it has no amount. Record ID odd-2 (finance_ledger).'), findsOneWidget);
    }

    expectExclusions();
    expect(find.text('NEEDS REVIEW'), findsNothing); // row 14 is on page 2
    await tapAndSettle(tester, next());
    expectExclusions();
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
    expect(find.text('Its linked receipt is missing. Still counted: the voided Finance record is what totals used.'), findsOneWidget);
    expect(find.text(allLine), findsOneWidget, reason: 'exclusions are never counted');
    await tapAndSettle(tester, next());
    expectExclusions();

    for (final label in ['Income', 'Expenses', 'Salary']) {
      await filter(tester, label);
      expectExclusions();
      expect(find.text('Shown under every filter: their type or link is unclear.'), findsOneWidget);
    }
    await filter(tester, 'Income');
    await tapAndSettle(tester, next());
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
  });

  testWidgets('7. empty results: existing messages, no pagination controls, exclusions still shown', (tester) async {
    useSummary(const []);
    await openList(tester);
    expect(find.text('No cancelled or voided transactions.'), findsOneWidget);
    expect(pagination(), findsNothing);
    expect(find.text('Needs review — not counted'), findsOneWidget);
  });

  testWidgets('7b. a filter with no rows shows its message and no controls', (tester) async {
    useSummary(seeded(15)); // income only
    await openList(tester);
    expect(pagination(), findsOneWidget);
    await filter(tester, 'Salary');
    expect(find.text('No cancelled or voided salary transactions.'), findsOneWidget);
    expect(pagination(), findsNothing);
    expect(find.textContaining('transactions, ₹'), findsNothing);
    await filter(tester, 'All');
    expect(find.text('Showing 1–10 of 15'), findsOneWidget);
  });

  testWidgets('8. narrow screen: controls wrap within 360px, no new overflow, navigation works', (tester) async {
    useSummary(seeded());
    await openList(tester, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(pagination());
    await tester.pumpAndSettle();
    final rect = tester.getRect(pagination());
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(tester.getRect(find.byKey(const Key('cancelled-type-filter'))).right, lessThanOrEqualTo(360));

    await tapAndSettle(tester, next());
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await choosePageSize(tester, 25);
    await filter(tester, 'Expenses');
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('9. real cancellations: traceability and type classification across pages', () {
    Future<String> cashId() async =>
        (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;

    Future<String> manualIncome(String title) async => finance.createIncome(FinanceIncomeModel(
          id: '', title: title, categoryId: 'c', categoryName: 'Other Income', programType: 'other',
          studentId: '', studentName: '', classId: '', className: '', amount: 100,
          incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: await cashId(), accountName: 'Cash',
          referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
          createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
        ));

    testWidgets('a fee receipt and its ledger line count once; every row keeps its details on its page', (tester) async {
      late String receiptId, receiptNo, feeIncomeId, invoiceId, paymentId;
      await tester.runAsync(() async {
        for (var n = 1; n <= 11; n++) {
          await finance.voidIncome(await manualIncome(_title(n)));
        }
        receiptId = (await fees.collectFee(
          assignmentId: 'a1', amount: 10000, paymentDate: DateTime(2026, 8, 2), paymentMode: 'cash', referenceNo: '', remarks: '',
        )).id;
        await fees.voidReceipt(receiptId);
        receiptNo = (await firestore.doc('fee_receipts/$receiptId').get()).data()!['receiptNo'] as String;
        feeIncomeId = (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single.id;
        final payload = {'partyName': 'Party', 'categoryName': 'Rent', 'invoiceNo': 'INV-00010020', 'totalAmount': 2000, 'amount': 2000};
        invoiceId = await finance.createExpenseInvoice(payload);
        paymentId = (await finance.payInvoice(
          invoiceId: invoiceId, invoiceType: 'expense', amount: 2000, paidDate: DateTime(2026, 8, 3),
          paymentMode: 'cash', referenceNo: '', remarks: '',
        ))!;
        await finance.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Recorded by mistake');
      });
      final before = await tester.runAsync(() => finance.watchCancelledTransactions().first);
      expect(before!.count, 13);

      await openList(tester);
      // 11 × ₹100 + ₹10000 fee + ₹2000 expense, counted once each.
      const line = 'Counted: 13 transactions, ₹13100 in total — the sum of the amounts listed on all pages.';
      expect(find.text(line), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      final headings = <String>[];
      var sawFee = false, sawExpense = false;
      for (var page = 1; page <= 2; page++) {
        headings.addAll(tester.widgetList<Text>(find.textContaining(' • ')).map((t) => t.data!).where((h) => RegExp(r'^(Manual income|Fee collection|Expense payment) • ').hasMatch(h)));
        if (find.text(receiptNo).evaluate().isNotEmpty) {
          sawFee = true;
          expect(find.text('Collection ID'), findsOneWidget);
          expect(find.text(receiptId), findsOneWidget);
          expect(find.text('Finance record ID'), findsOneWidget);
          expect(find.text(feeIncomeId), findsOneWidget);
        }
        if (find.text('Invoice ID').evaluate().isNotEmpty) {
          sawExpense = true;
          expect(find.text(invoiceId), findsOneWidget);
          expect(find.text('INV-00010020'), findsOneWidget);
        }
        expect(find.text(line), findsOneWidget);
        if (page == 1) await tapAndSettle(tester, next());
      }
      expect(headings, hasLength(13));
      expect(headings.toSet(), hasLength(13), reason: 'no row repeated across pages');
      expect(headings.where((h) => h.startsWith('Fee collection • ')), hasLength(1), reason: 'receipt + ledger line count once');
      expect(headings.where((h) => h.startsWith('Expense payment • ')), hasLength(1));
      expect(headings.where((h) => h.startsWith('Manual income • ')), hasLength(11));
      expect(sawFee && sawExpense, isTrue);

      await filter(tester, 'Expenses');
      expect(find.text('Expenses: 1 transaction, ₹2000 in total — the sum of the amounts listed above. All types: 13, ₹13100.'), findsOneWidget);
      expect(find.descendant(of: find.ancestor(of: find.textContaining('Expense payment • '), matching: find.byType(Wrap)).first, matching: find.text('EXPENSES')), findsOneWidget);
      await filter(tester, 'Income');
      expect(find.text('Income: 12 transactions, ₹11100 in total — the sum of the amounts listed on all pages. All types: 13, ₹13100.'), findsOneWidget);
      expect(find.text('Showing 1–10 of 12'), findsOneWidget);
    });
  });
}
