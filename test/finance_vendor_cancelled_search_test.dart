// Free-text search (display only) in:
// - Finance -> Vendors: trimmed, case-insensitive substring match on name,
//   service type, phone and email, plus status matched as the whole word
//   "active" / "inactive" (so "active" doesn't also match inactive
//   vendors). Results keep the watchVendors() name order and are paged
//   with the shared 10/25/50 pager; a query change returns to page 1 and
//   the page size is kept.
// - Cancelled / Voided Transactions dialog: the same matching over each
//   row's displayed text (title, type and type group, source, reference,
//   receipt/invoice number and id, record id, ledger id, reason, status),
//   combined with the All/Income/Expenses/Salary filter. Count and amount
//   cover every matching counted row; "Needs review — not counted" stays
//   listed in full and uncounted whatever the search.
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

String _two(int n) => n.toString().padLeft(2, '0');

/// Rows 1..15 income (odd manual, even fee with a receipt), 16..22 expense
/// payments, 23..27 salary payments (both with an invoice); ₹100 × n;
/// row 14 needs review (still counted). Same layout as the pagination test.
FinanceCancelledTransaction _txn(int n) {
  final type = n <= 15
      ? (n.isOdd ? 'Manual income' : 'Fee collection')
      : n <= 22
          ? 'Expense payment'
          : 'Salary payment';
  final linked = type == 'Fee collection' ? 'Receipt' : type == 'Manual income' ? '' : 'Invoice';
  return FinanceCancelledTransaction(
    id: 'income-${_two(n)}',
    sourceLabel: 'Source $n',
    typeLabel: type,
    title: 'Txn ${_two(n)}',
    reference: 'R-${_two(n)}',
    originalDate: DateTime(2026, 8, 1),
    cancelledAt: DateTime(2026, 9, 1),
    amount: n * 100.0,
    reason: 'Reason ${_two(n)}',
    statusLabel: n >= 16 ? 'Reversed' : 'Voided',
    linkedDocumentLabel: linked,
    linkedDocumentId: linked.isEmpty ? '' : 'doc-${_two(n)}',
    linkedDocumentNumber: linked == 'Receipt' ? 'RCPT-${_two(n)}' : linked == 'Invoice' ? 'INV-${_two(n)}' : '',
    linkedDocumentFound: linked.isNotEmpty,
    ledgerId: 'ledger-${_two(n)}',
    ledgerStatus: 'cancelled',
    reviewNote: n == 14 ? 'Its linked receipt is missing' : '',
  );
}

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
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: finance, feeService: fees))));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String prefix, String text) async {
    await tester.enterText(find.byKey(Key('$prefix-search')), text);
    await tester.pumpAndSettle();
  }

  Future<void> clear(WidgetTester tester, String prefix) => tapAndSettle(tester, find.byKey(Key('$prefix-search-clear')));

  Future<void> choosePageSize(WidgetTester tester, String prefix, int size) async {
    await tapAndSettle(tester, find.byKey(Key('$prefix-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  int pageSize(WidgetTester tester, String prefix) => tester.widget<DropdownButton<int>>(find.byKey(Key('$prefix-page-size'))).value!;

  // --------------------------------------------------------------- Vendors
  group('Vendors', () {
    /// "Acme Supplies" (Stationery), "Bright Cleaners" (Housekeeping,
    /// inactive) and Supplier 01..24 (odd Catering / even Transport; every
    /// 4th inactive; own phone and email). Listed by name.
    Future<void> seed() async {
      Future<void> add(String name, String serviceType, {bool active = true, String phone = '', String email = ''}) =>
          firestore.collection('vendors').add({'name': name, 'serviceType': serviceType, 'isActive': active, 'phone': phone, 'email': email, 'address': ''});
      await add('Bright Cleaners', 'Housekeeping', active: false);
      await add('Acme Supplies', 'Stationery', phone: '9000000000');
      for (var n = 1; n <= 24; n++) {
        await add('Supplier ${_two(n)}', n.isOdd ? 'Catering' : 'Transport',
            active: n % 4 != 0, phone: '98000000${_two(n)}', email: 's${_two(n)}@example.com');
      }
    }

    Future<void> pumpVendors(WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Vendors'));
      await tester.pumpAndSettle();
    }

    List<String> shown(WidgetTester tester) => tester
        .widgetList<Text>(find.textContaining(RegExp(r'^(Acme Supplies|Bright Cleaners|Supplier \d\d)$')))
        .map((t) => t.data!)
        .toList();
    List<String> suppliers(Iterable<int> ns) => [for (final n in ns) 'Supplier ${_two(n)}'];

    testWidgets('name, service type, phone and email: case-insensitive and trimmed, in name order', (tester) async {
      await seed();
      await pumpVendors(tester);
      expect(shown(tester), ['Acme Supplies', 'Bright Cleaners', ...suppliers([1, 2, 3, 4, 5, 6, 7, 8])]);
      expect(find.text('Showing 1–10 of 26'), findsOneWidget);

      await search(tester, 'vendor', 'ACME');
      expect(shown(tester), ['Acme Supplies']);
      await search(tester, 'vendor', '   stationery  ');
      expect(shown(tester), ['Acme Supplies']);
      await search(tester, 'vendor', 'Supplier 1');
      expect(shown(tester), suppliers([10, 11, 12, 13, 14, 15, 16, 17, 18, 19]));
      await search(tester, 'vendor', 'catering');
      expect(shown(tester), suppliers([1, 3, 5, 7, 9, 11, 13, 15, 17, 19]));
      expect(find.text('Showing 1–10 of 12'), findsOneWidget);
      await search(tester, 'vendor', '9800000007');
      expect(shown(tester), suppliers([7]));
      await search(tester, 'vendor', 'S05@EXAMPLE');
      expect(shown(tester), suppliers([5]));
    });

    testWidgets('status: "inactive" and "active" match only that status; INACTIVE chips unchanged', (tester) async {
      await seed();
      await pumpVendors(tester);
      await search(tester, 'vendor', 'Inactive');
      expect(shown(tester), ['Bright Cleaners', ...suppliers([4, 8, 12, 16, 20, 24])]);
      expect(find.text('INACTIVE'), findsNWidgets(7));

      await search(tester, 'vendor', ' ACTIVE ');
      expect(find.text('Showing 1–10 of 19'), findsOneWidget);
      expect(find.text('INACTIVE'), findsNothing);
      expect(shown(tester), isNot(contains('Bright Cleaners')));
    });

    testWidgets('paging of results, reset on query change, page size kept, no-match and Clear', (tester) async {
      await seed();
      await pumpVendors(tester);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await search(tester, 'vendor', 'supplier'); // 24
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      await search(tester, 'vendor', 'upplier'); // same matches, new query
      expect(find.text('Page 1 of 3'), findsOneWidget);

      await choosePageSize(tester, 'vendor', 25);
      expect(find.text('Showing 1–24 of 24'), findsOneWidget);
      await search(tester, 'vendor', 'no such vendor');
      expect(find.text('No vendors match "no such vendor".'), findsOneWidget);
      expect(find.byKey(const Key('vendor-pagination')), findsNothing);

      await clear(tester, 'vendor');
      expect(pageSize(tester, 'vendor'), 25);
      expect(find.text('Showing 1–25 of 26'), findsOneWidget);
    });

    testWidgets('new vendors arrive with the search kept; the empty state and Add Vendor are unchanged', (tester) async {
      await pumpVendors(tester);
      expect(find.text('No vendors yet'), findsOneWidget);
      expect(find.text('Add Vendor'), findsWidgets);
      expect(find.byKey(const Key('vendor-search')), findsNothing);

      await seed();
      await tester.pumpAndSettle();
      await search(tester, 'vendor', 'acme');
      await firestore.collection('vendors').add({'name': 'Acme Traders', 'serviceType': '', 'isActive': true});
      await firestore.collection('vendors').add({'name': 'Zenith Foods', 'serviceType': '', 'isActive': true});
      await tester.pumpAndSettle();
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Acme Traders'), findsOneWidget);
      expect(find.text('Zenith Foods'), findsNothing);
    });
  });

  // --------------------------------------------- Cancelled / Voided dialog
  group('Cancelled / Voided Transactions', () {
    void useSummary(List<FinanceCancelledTransaction> transactions) => finance.replacement =
        Stream.value(FinanceCancelledTransactionsSummary(transactions: transactions, exclusions: _exclusions)).asBroadcastStream();
    List<FinanceCancelledTransaction> seeded() => [for (var n = 1; n <= 27; n++) _txn(n)];

    Future<void> openList(WidgetTester tester) async {
      await pumpScreen(tester);
      final card = find.ancestor(of: find.text('Cancelled / Voided Transactions'), matching: find.byType(InkWell)).first;
      await tapAndSettle(tester, card);
    }

    List<String> shown(WidgetTester tester) =>
        tester.widgetList<Text>(find.textContaining(RegExp(r' • Txn \d\d$'))).map((t) => t.data!.split(' • ').last).toList();
    List<String> txns(Iterable<int> ns) => [for (final n in ns) 'Txn ${_two(n)}'];
    Finder chip(String label) => find.descendant(of: find.byKey(const Key('cancelled-type-filter')), matching: find.widgetWithText(ChoiceChip, label));
    Future<void> filter(WidgetTester tester, String label) => tapAndSettle(tester, chip(label));

    void expectExclusions({bool searching = true}) {
      expect(find.text('Needs review — not counted'), findsOneWidget);
      expect(find.text('Unclear A: its ledger entry is still active. Record ID odd-1 (finance_income).'), findsOneWidget);
      expect(find.text('Unclear B: it has no amount. Record ID odd-2 (finance_ledger).'), findsOneWidget);
      if (searching) expect(find.text('Shown under every filter and search: their type or link is unclear.'), findsOneWidget);
    }

    testWidgets('case-insensitive, trimmed match on every displayed identifier and type', (tester) async {
      useSummary(seeded());
      await openList(tester);
      final cases = <String, List<int>>{
        '  r-07  ': [7], // reference
        'RCPT-12': [12], // receipt number
        'inv-18': [18], // invoice number
        'DOC-25': [25], // linked receipt/invoice id
        'income-03': [3], // record id
        'ledger-05': [5], // ledger entry id
        'reason 09': [9], // reason
        'txn 2': [20, 21, 22, 23, 24, 25, 26, 27], // title
        'salary payment': [23, 24, 25, 26, 27], // type label
        'expenses': [16, 17, 18, 19, 20, 21, 22], // type chip
        'source 4': [4], // source label
      };
      for (final entry in cases.entries) {
        await search(tester, 'cancelled', entry.key);
        expect(shown(tester), txns(entry.value), reason: 'query "${entry.key}"');
      }
      await search(tester, 'cancelled', 'reversed'); // status
      expect(find.text('Showing 1–10 of 12'), findsOneWidget);
    });

    testWidgets('count and amount cover every matching row; "All types" stays the full summary', (tester) async {
      useSummary(seeded());
      await openList(tester);
      expect(find.text('Counted: 27 transactions, ₹37800 in total — the sum of the amounts listed on all pages.'), findsOneWidget);

      await search(tester, 'cancelled', 'Salary Payment');
      expect(find.text('Matching: 5 transactions, ₹12500 in total — the sum of the amounts listed above. All types: 27, ₹37800.'), findsOneWidget);

      await search(tester, 'cancelled', 'txn');
      expect(find.text('Matching: 27 transactions, ₹37800 in total — the sum of the amounts listed on all pages. All types: 27, ₹37800.'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      expect(find.text('Matching: 27 transactions, ₹37800 in total — the sum of the amounts listed on all pages. All types: 27, ₹37800.'), findsOneWidget);

      await clear(tester, 'cancelled');
      expect(find.text('Counted: 27 transactions, ₹37800 in total — the sum of the amounts listed on all pages.'), findsOneWidget);
      expect(find.text('Shown under every filter: their type or link is unclear.'), findsNothing);
      expect(find.text('Shown under every filter and search: their type or link is unclear.'), findsNothing);
    });

    testWidgets('search combines with the type filters', (tester) async {
      useSummary(seeded());
      await openList(tester);
      await filter(tester, 'Income');
      await search(tester, 'cancelled', 'rcpt'); // fee collections 2..14
      expect(shown(tester), txns([2, 4, 6, 8, 10, 12, 14]));
      expect(find.text('Matching Income: 7 transactions, ₹5600 in total — the sum of the amounts listed above. All types: 27, ₹37800.'), findsOneWidget);

      await filter(tester, 'Expenses');
      expect(shown(tester), isEmpty);
      expect(find.text('No cancelled or voided expense transactions match "rcpt".'), findsOneWidget);
      expect(find.byKey(const Key('cancelled-pagination')), findsNothing);
      expectExclusions();

      await search(tester, 'cancelled', 'inv');
      expect(shown(tester), txns([16, 17, 18, 19, 20, 21, 22]));
      await filter(tester, 'Salary');
      expect(shown(tester), txns([23, 24, 25, 26, 27]));
      await filter(tester, 'All');
      expect(find.text('Showing 1–10 of 12'), findsOneWidget);
      expect(find.text('Matching: 12 transactions, ₹25800 in total — the sum of the amounts listed on all pages. All types: 27, ₹37800.'), findsOneWidget);

      await search(tester, 'cancelled', 'nothing here');
      expect(find.text('No cancelled or voided transactions match "nothing here".'), findsOneWidget);
    });

    testWidgets('page 1 on any query or filter change (even with the same rows); page size kept through no-match', (tester) async {
      useSummary(seeded());
      await openList(tester);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await search(tester, 'cancelled', 'txn'); // same 27 rows
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      await search(tester, 'cancelled', 'tx'); // same rows, new query
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Next page'));
      await filter(tester, 'Income');
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await choosePageSize(tester, 'cancelled', 25);
      await filter(tester, 'All');
      expect(find.text('Showing 1–25 of 27'), findsOneWidget);
      await search(tester, 'cancelled', 'zzz');
      expect(find.byKey(const Key('cancelled-pagination')), findsNothing);
      await clear(tester, 'cancelled');
      expect(pageSize(tester, 'cancelled'), 25);
      expect(find.text('Showing 1–25 of 27'), findsOneWidget);

      await filter(tester, 'Salary');
      await search(tester, 'cancelled', 'rcpt'); // no salary rows
      await filter(tester, 'All');
      expect(pageSize(tester, 'cancelled'), 25);
    });

    testWidgets('needs review: exclusions listed in full and never counted while searching; a counted review row keeps its note', (tester) async {
      useSummary(seeded());
      await openList(tester);
      expectExclusions(searching: false);

      await search(tester, 'cancelled', 'unclear'); // exclusion titles aren't counted rows
      expect(shown(tester), isEmpty);
      expect(find.text('No cancelled or voided transactions match "unclear".'), findsOneWidget);
      expectExclusions();

      await search(tester, 'cancelled', 'txn 14');
      expect(shown(tester), txns([14]));
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
      expect(find.text('Its linked receipt is missing. Still counted: the voided Finance record is what totals used.'), findsOneWidget);
      expect(find.text('Matching: 1 transaction, ₹1400 in total — the sum of the amounts listed above. All types: 27, ₹37800.'), findsOneWidget);
      expectExclusions();

      // Every traceability field of the matching row is still shown.
      for (final text in ['Source 14', 'Receipt', 'RCPT-14', 'Collection ID', 'doc-14', 'R-14', 'Finance record ID', 'income-14', 'ledger-14 (cancelled)', 'Reason 14', 'Voided', '₹1400']) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.text('FEE COLLECTION'), findsNothing);
      expect(find.text('INCOME'), findsOneWidget, reason: 'type chip');
    });

    testWidgets('no cancellations: original message and no search box', (tester) async {
      useSummary(const []);
      await openList(tester);
      expect(find.text('No cancelled or voided transactions.'), findsOneWidget);
      expect(find.byKey(const Key('cancelled-search')), findsNothing);
      expectExclusions(searching: false);
    });

    group('real cancellations', () {
      setUp(() async {
        await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
        await firestore.collection('students').doc('s1').set({'name': 'Student One', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'isActive': true});
        await firestore.collection('student_fee_assignments').doc('a1').set({
          'studentId': 's1', 'studentName': 'Student One', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
          'feeStructureId': 'structure-1', 'feeStructureName': 'Core Fees', 'academicYear': '2026-2027',
          'totalFee': 20000, 'discountAmount': 0, 'payableAmount': 20000, 'paidAmount': 0, 'balanceAmount': 20000,
          'status': 'unpaid', 'assignedAt': Timestamp.fromDate(DateTime(2026, 1, 1)), 'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        });
      });

      testWidgets('a fee receipt and its ledger line match once; vendor name and invoice number find the reversal', (tester) async {
        late String receiptId, receiptNo, feeIncomeId, invoiceId;
        await tester.runAsync(() async {
          final cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
          final manual = await finance.createIncome(FinanceIncomeModel(
            id: '', title: 'Donation Drive', categoryId: 'c', categoryName: 'Other Income', programType: 'other',
            studentId: '', studentName: '', classId: '', className: '', amount: 500,
            incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: cashId, accountName: 'Cash',
            referenceNo: 'DON-9', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
            createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
          ));
          await finance.voidIncome(manual);
          receiptId = (await fees.collectFee(
            assignmentId: 'a1', amount: 10000, paymentDate: DateTime(2026, 8, 2), paymentMode: 'cash', referenceNo: '', remarks: '',
          )).id;
          await fees.voidReceipt(receiptId);
          receiptNo = (await firestore.doc('fee_receipts/$receiptId').get()).data()!['receiptNo'] as String;
          feeIncomeId = (await firestore.collection('finance_income').where('sourceId', isEqualTo: receiptId).get()).docs.single.id;
          invoiceId = await finance.createExpenseInvoice(
              {'partyName': 'Acme Supplies', 'categoryName': 'Rent', 'invoiceNo': 'INV-00010020', 'totalAmount': 2000, 'amount': 2000});
          final paymentId = (await finance.payInvoice(
            invoiceId: invoiceId, invoiceType: 'expense', amount: 2000, paidDate: DateTime(2026, 8, 3),
            paymentMode: 'cash', referenceNo: '', remarks: '',
          ))!;
          await finance.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Recorded by mistake');
        });
        await openList(tester);
        expect(find.text('Counted: 3 transactions, ₹12500 in total — the sum of the amounts listed above.'), findsOneWidget);

        await search(tester, 'cancelled', receiptNo.toLowerCase());
        expect(find.textContaining('Fee collection • '), findsOneWidget);
        expect(find.textContaining(RegExp(r'^(Manual income|Fee collection|Expense payment) • ')), findsOneWidget,
            reason: 'receipt and its ledger line are one row');
        expect(find.text('Matching: 1 transaction, ₹10000 in total — the sum of the amounts listed above. All types: 3, ₹12500.'), findsOneWidget);
        expect(find.text(receiptId), findsOneWidget);
        expect(find.text(feeIncomeId), findsOneWidget);

        await search(tester, 'cancelled', feeIncomeId);
        expect(find.textContaining('Fee collection • '), findsOneWidget);

        await search(tester, 'cancelled', 'acme supplies');
        expect(find.text('Expense payment • Expense Payment - Acme Supplies'), findsOneWidget);
        await search(tester, 'cancelled', 'INV-00010020');
        expect(find.text('Expense payment • Expense Payment - Acme Supplies'), findsOneWidget);
        expect(find.text(invoiceId), findsOneWidget);
        expect(find.text('Recorded by mistake'), findsOneWidget);

        await search(tester, 'cancelled', 'don-9');
        expect(find.text('Manual income • Donation Drive'), findsOneWidget);
      });
    });
  });
}
