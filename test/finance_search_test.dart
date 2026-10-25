// Finance -> Income / Expenses / Salary / Ledger: free-text search above
// each list (display only).
// - Trimmed, case-insensitive substring match over the model's own fields:
//   Income: title, remarks, category, reference, payer (studentName).
//   Expenses: vendor, invoice no., category, description, status (stored
//   value and its label). Salary: staff name, invoice no., description,
//   status. Ledger: title, description, category, vendor (subCategoryName),
//   reference, account.
// - Updates while typing; Clear restores the full list; a query that
//   matches nothing shows "No … match "query".".
// - Pagination applies to the results: range and page count are for the
//   matches, a query change returns to page 1, and the page size is kept.
// - Summary cards (Total Income / Transactions, Outstanding / Paid /
//   Total, Ledger inflow / outflow / net / closing) stay over the full data.
// - Row actions and row details are unchanged on searched rows.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

String _two(int n) => n.toString().padLeft(2, '0');

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  Future<void> pumpTab(WidgetTester tester, String label) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, label));
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
  Finder next() => find.byTooltip('Next page');
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<IconButton>(find.ancestor(of: button, matching: find.byType(IconButton))).onPressed != null;

  void expectCard(String label, String value) => expect(
        find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(FinanceSummaryCard)), matching: find.text(value)),
        findsOneWidget,
        reason: '$label card',
      );

  List<String> texts(WidgetTester tester, RegExp pattern) => tester.widgetList<Text>(find.textContaining(pattern)).map((t) => t.data!).toList();

  // ---------------------------------------------------------------- Income
  group('Income', () {
    String title(int n) => 'Income ${_two(n)}';

    /// 27 manual entries, newest last (listed newest first), ₹100 × n;
    /// every 3rd is "Donations"; one remark and one payer; plus an invoice
    /// payment the tab never shows.
    Future<void> seed() async {
      for (var n = 1; n <= 27; n++) {
        await firestore.collection('finance_income').add({
          'title': title(n), 'amount': n * 100, 'programType': 'other', 'sourceModule': 'finance',
          'categoryName': n % 3 == 0 ? 'Donations' : 'Other Income', 'accountName': 'Cash', 'paymentMode': 'cash',
          'referenceNo': 'REF-${_two(n)}', 'remarks': n == 5 ? 'Annual Day sponsorship' : '',
          'studentName': n == 7 ? 'Student Seven' : '',
          'incomeDate': DateTime(2026, 8, 1), 'createdAt': DateTime(2026, 8, 1).add(Duration(minutes: n)),
        });
      }
      await firestore.collection('finance_income').add({
        'title': 'Expense Payment - Vendor', 'amount': 99999, 'programType': 'invoice', 'sourceModule': 'invoice',
        'createdAt': DateTime(2026, 9, 1),
      });
    }

    List<String> shown(WidgetTester tester) => texts(tester, RegExp(r'^Income \d\d$'));
    List<String> titles(Iterable<int> ns) => [for (final n in ns) title(n)];
    void expectTotals() {
      expectCard('Total Income', '₹37800');
      expectCard('Transactions', '27');
    }

    testWidgets('1 + 6. case-insensitive match on title, remarks, category, reference and payer; totals unchanged', (tester) async {
      await seed();
      await pumpTab(tester, 'Income');
      expect(find.text('Showing 1–10 of 27'), findsOneWidget);

      await search(tester, 'income', 'DONATIONS');
      expect(shown(tester), titles([27, 24, 21, 18, 15, 12, 9, 6, 3]));
      expect(find.text('Showing 1–9 of 9'), findsOneWidget);
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expectTotals();

      await search(tester, 'income', 'annual day');
      expect(shown(tester), titles([5]));
      await search(tester, 'income', 'student SEVEN');
      expect(shown(tester), titles([7]));
      await search(tester, 'income', 'Ref-12');
      expect(shown(tester), titles([12]));
      await search(tester, 'income', 'income 2');
      expect(shown(tester), titles([27, 26, 25, 24, 23, 22, 21, 20]));
      expectTotals();
    });

    testWidgets('2 + 5. trims the query; no-match message; Clear restores the full list', (tester) async {
      await seed();
      await pumpTab(tester, 'Income');
      await search(tester, 'income', '   ref-07   ');
      expect(shown(tester), titles([7]));

      await search(tester, 'income', 'vendor'); // the invoice payment is never listed
      expect(shown(tester), isEmpty);
      expect(find.text('No income transactions match "vendor".'), findsOneWidget);
      expect(find.byKey(const Key('income-pagination')), findsNothing);
      expectTotals();

      await clear(tester, 'income');
      expect(tester.widget<TextField>(find.byKey(const Key('income-search'))).controller!.text, '');
      expect(find.byKey(const Key('income-search-clear')), findsNothing);
      expect(shown(tester), titles([27, 26, 25, 24, 23, 22, 21, 20, 19, 18]));
      expect(find.text('Showing 1–10 of 27'), findsOneWidget);
      expectTotals();
    });

    testWidgets('3 + 4. results are paged; a query change returns to page 1; page size kept', (tester) async {
      await seed();
      await pumpTab(tester, 'Income');
      await tapAndSettle(tester, next());
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await search(tester, 'income', 'other income'); // 18 entries
      expect(find.text('Showing 1–10 of 18'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tapAndSettle(tester, next());
      expect(find.text('Showing 11–18 of 18'), findsOneWidget);
      expect(enabled(tester, next()), isFalse);

      // Same matches, different query: still back to page 1.
      await search(tester, 'income', 'other incom');
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await choosePageSize(tester, 'income', 25);
      expect(find.text('Showing 1–18 of 18'), findsOneWidget);
      await search(tester, 'income', 'donations');
      expect(pageSize(tester, 'income'), 25);
      expect(find.text('Showing 1–9 of 9'), findsOneWidget);
      await clear(tester, 'income');
      expect(pageSize(tester, 'income'), 25);
      expect(find.text('Showing 1–25 of 27'), findsOneWidget);
      expectTotals();
    });

    testWidgets('7. Edit and Void still work on a searched row; the query survives data updates', (tester) async {
      await seed();
      await pumpTab(tester, 'Income');
      await search(tester, 'income', 'ref-07');
      expect(find.byTooltip('Edit'), findsOneWidget);
      await tapAndSettle(tester, find.byTooltip('Void'));
      expect(find.text('Void Income Entry'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(shown(tester), titles([7]));

      await firestore.collection('finance_income').add({
        'title': title(28), 'amount': 2800, 'programType': 'other', 'categoryName': 'Other Income',
        'referenceNo': 'REF-28', 'createdAt': DateTime(2026, 8, 2),
      });
      await tester.pumpAndSettle();
      expect(shown(tester), titles([7]), reason: 'the search stays applied');
      expectCard('Total Income', '₹40600');
      expectCard('Transactions', '28');
    });
  });

  // ------------------------------------------------------ Expenses / Salary
  group('Expenses', () {
    String no(int n) => 'EXP-${_two(n)}';

    /// 27 expense invoices (newest last): even n "Acme Supplies", odd
    /// "Bright Cleaners"; every 3rd "Stationery"; 1–3 paid, 5 partial,
    /// 6 cancelled, the rest unpaid; ₹100 × n; plus a salary invoice.
    Future<Map<int, String>> seed() async {
      final ids = <int, String>{};
      for (var n = 1; n <= 27; n++) {
        final total = n * 100;
        final paid = n <= 3 ? total : n == 5 ? 200 : 0;
        final ref = await firestore.collection('finance_invoices').add({
          'type': 'expense', 'invoiceNo': no(n), 'partyId': '', 'partyName': n.isEven ? 'Acme Supplies' : 'Bright Cleaners',
          'categoryName': n % 3 == 0 ? 'Stationery' : 'General', 'description': n == 4 ? 'Printer toner' : '',
          'amount': total, 'taxAmount': 0, 'totalAmount': total, 'paidAmount': paid, 'balanceAmount': total - paid,
          'status': n <= 3 ? 'paid' : n == 5 ? 'partial' : n == 6 ? 'cancelled' : 'unpaid',
          'invoiceDate': DateTime(2026, 8, 1), 'createdAt': DateTime(2026, 8, 1).add(Duration(minutes: n)),
        });
        ids[n] = ref.id;
      }
      await firestore.collection('finance_invoices').add({
        'type': 'salary', 'invoiceNo': 'SAL-X', 'partyName': 'Acme Supplies', 'amount': 9999, 'totalAmount': 9999,
        'paidAmount': 0, 'balanceAmount': 9999, 'status': 'unpaid', 'createdAt': DateTime(2026, 9, 1),
      });
      return ids;
    }

    List<String> shown(WidgetTester tester) => texts(tester, RegExp(r'^EXP-\d\d$'));
    List<String> nos(Iterable<int> ns) => [for (final n in ns) no(n)];
    // Active (not cancelled): ₹37800 − ₹600; paid ₹600 + ₹200.
    void expectTotals({String outstanding = '₹36400', String paid = '₹800'}) {
      expectCard('Outstanding', outstanding);
      expectCard('Paid', paid);
      expectCard('Total Expenses', '₹37200');
    }

    testWidgets('1 + 6. vendor, invoice no., category, description and status; totals unchanged', (tester) async {
      await seed();
      await pumpTab(tester, 'Expenses');
      expectTotals();

      await search(tester, 'expense', 'ACME');
      expect(shown(tester), nos([26, 24, 22, 20, 18, 16, 14, 12, 10, 8]));
      expect(find.text('Showing 1–10 of 13'), findsOneWidget);
      expect(find.text('SAL-X'), findsNothing);
      expectTotals();

      await search(tester, 'expense', 'exp-04');
      expect(shown(tester), nos([4]));
      await search(tester, 'expense', 'printer TONER');
      expect(shown(tester), nos([4]));
      await search(tester, 'expense', 'stationery');
      expect(shown(tester), nos([27, 24, 21, 18, 15, 12, 9, 6, 3]));
      await search(tester, 'expense', 'partially paid'); // status label
      expect(shown(tester), nos([5]));
      await search(tester, 'expense', 'Cancelled'); // stored status
      expect(shown(tester), nos([6]));
      expect(find.text('CANCELLED'), findsOneWidget, reason: 'status chip unchanged');
      expectTotals();
    });

    testWidgets('2 + 3 + 4 + 5. trim, paging of results, reset on query change, page size kept, no-match, Clear', (tester) async {
      await seed();
      await pumpTab(tester, 'Expenses');
      await tapAndSettle(tester, next());
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await search(tester, 'expense', '  acme  ');
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tapAndSettle(tester, next());
      expect(shown(tester), nos([6, 4, 2]));
      expect(find.text('Showing 11–13 of 13'), findsOneWidget);
      await search(tester, 'expense', 'acme supplies'); // same matches, new query
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await choosePageSize(tester, 'expense', 25);
      expect(find.text('Showing 1–13 of 13'), findsOneWidget);
      await search(tester, 'expense', 'nothing like this');
      expect(find.text('No expense invoices match "nothing like this".'), findsOneWidget);
      expect(find.byKey(const Key('expense-pagination')), findsNothing);
      expectTotals();

      await clear(tester, 'expense');
      expect(pageSize(tester, 'expense'), 25);
      expect(find.text('Showing 1–25 of 27'), findsOneWidget);
      expectTotals();
    });

    testWidgets('7. Pay / Edit / Delete / Cancel and details on a searched row; a payment keeps the search', (tester) async {
      final ids = await seed();
      await pumpTab(tester, 'Expenses');
      await search(tester, 'expense', 'exp-04');
      expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.byTooltip('Cancel Invoice'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Pay'));
      expect(find.text('Pay Invoice - Acme Supplies'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.byTooltip('Edit'));
      expect(find.text('Edit Expense Invoice'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));

      await tapAndSettle(tester, find.text(no(4)));
      expect(find.text('Payments'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close').last);
      await tester.pumpAndSettle();

      await service.payInvoice(
        invoiceId: ids[4]!, invoiceType: 'expense', amount: 100, paidDate: DateTime(2026, 9, 1),
        paymentMode: 'cash', referenceNo: '', remarks: '',
      );
      await tester.pumpAndSettle();
      expect(shown(tester), nos([4]), reason: 'the search stays applied');
      expect(find.text('PARTIALLY PAID'), findsOneWidget);
      expectTotals(outstanding: '₹36300', paid: '₹900');
    });
  });

  group('Salary', () {
    String no(int n) => 'SAL-${_two(n)}';

    /// 12 salary invoices (newest last): staff "Staff nn" except 3
    /// "Malani D"; 2 has a description; 1 paid, the rest unpaid.
    Future<void> seed() async {
      for (var n = 1; n <= 12; n++) {
        final total = n * 1000;
        await firestore.collection('finance_invoices').add({
          'type': 'salary', 'invoiceNo': no(n), 'partyId': 'staff-$n', 'partyName': n == 3 ? 'Malani D' : 'Staff ${_two(n)}',
          'categoryName': 'Staff Salary', 'description': n == 2 ? 'September salary' : '',
          'amount': total, 'totalAmount': total, 'paidAmount': n == 1 ? total : 0, 'balanceAmount': n == 1 ? 0 : total,
          'status': n == 1 ? 'paid' : 'unpaid',
          'invoiceDate': DateTime(2026, 8, 1), 'createdAt': DateTime(2026, 8, 1).add(Duration(minutes: n)),
        });
      }
    }

    List<String> shown(WidgetTester tester) => texts(tester, RegExp(r'^SAL-\d\d$'));
    List<String> nos(Iterable<int> ns) => [for (final n in ns) no(n)];
    void expectTotals() {
      expectCard('Outstanding', '₹77000');
      expectCard('Paid', '₹1000');
      expectCard('Total Salary', '₹78000');
    }

    testWidgets('1–6. staff, invoice no., description and status; paging, reset, page size, no-match, Clear; totals unchanged', (tester) async {
      await seed();
      await pumpTab(tester, 'Salary');
      await search(tester, 'salary', 'MALANI');
      expect(shown(tester), nos([3]));
      await search(tester, 'salary', 'sal-1');
      expect(shown(tester), nos([12, 11, 10]));
      await search(tester, 'salary', ' september ');
      expect(shown(tester), nos([2]));
      expectTotals();

      await search(tester, 'salary', 'unpaid'); // 11 invoices
      expect(find.text('Showing 1–10 of 11'), findsOneWidget);
      await tapAndSettle(tester, next());
      expect(shown(tester), nos([2]));
      await search(tester, 'salary', 'unpai'); // same matches, new query
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await choosePageSize(tester, 'salary', 50);
      expect(find.text('Showing 1–11 of 11'), findsOneWidget);

      await search(tester, 'salary', 'zzz');
      expect(find.text('No salary invoices match "zzz".'), findsOneWidget);
      expectTotals();
      await clear(tester, 'salary');
      expect(pageSize(tester, 'salary'), 50);
      expect(find.text('Showing 1–12 of 12'), findsOneWidget);
    });

    testWidgets('7. Pay is still available on a searched row', (tester) async {
      await seed();
      await pumpTab(tester, 'Salary');
      await search(tester, 'salary', 'malani');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Pay'));
      expect(find.text('Pay Invoice - Malani D'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(shown(tester), nos([3]));
    });
  });

  // ---------------------------------------------------------------- Ledger
  group('Ledger', () {
    late String cashId;
    String title(int n) => 'Entry ${_two(n)}';

    /// As the ledger pagination test: odd n income, even n expense, ₹100 × n
    /// on Cash, entry 3 cancelled; every 3rd "Fees"; entry 5 has a
    /// description, entry 8 a vendor; even n shown on account "Main Cash".
    Future<void> seed() async {
      cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
      for (var n = 1; n <= 27; n++) {
        await firestore.collection('finance_ledger').add({
          'entryType': n.isOdd ? 'income' : 'expense', 'amount': n * 100, 'accountId': cashId,
          'accountName': n.isEven ? 'Main Cash' : 'Cash', 'categoryName': n % 3 == 0 ? 'Fees' : 'General',
          'subCategoryName': n == 8 ? 'Acme Supplies' : '', 'status': n == 3 ? 'cancelled' : 'confirmed',
          'title': title(n), 'description': n == 5 ? 'Annual day' : '', 'referenceNo': 'R-${_two(n)}',
          'transactionDate': DateTime(2026, 9, 1), 'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: n)),
        });
      }
    }

    List<String> shown(WidgetTester tester) => tester
        .widgetList<Text>(find.descendant(of: find.byType(LedgerEntryCard), matching: find.textContaining(RegExp(r'^Entry \d\d$'))))
        .map((t) => t.data!)
        .toList();
    List<String> titles(Iterable<int> ns) => [for (final n in ns) title(n)];
    void expectFigures() {
      expectCard('Total Inflow', '₹19300');
      expectCard('Total Outflow', '₹18200');
      expectCard('Net Movement', '₹1100');
      expectCard('Closing Balance', '₹1100');
    }

    testWidgets('1 + 6. title, description, category, vendor, reference and account; figures unchanged', (tester) async {
      await seed();
      await pumpTab(tester, 'Ledger');
      expectFigures();

      await search(tester, 'ledger', 'FEES');
      expect(shown(tester), titles([27, 24, 21, 18, 15, 12, 9, 6, 3]));
      expectFigures();
      await search(tester, 'ledger', 'annual DAY');
      expect(shown(tester), titles([5]));
      await search(tester, 'ledger', 'acme');
      expect(shown(tester), titles([8]));
      await search(tester, 'ledger', 'r-11');
      expect(shown(tester), titles([11]));
      await search(tester, 'ledger', 'main cash');
      expect(find.text('Showing 1–10 of 13'), findsOneWidget);
      await search(tester, 'ledger', 'entry 03');
      final row = find.ancestor(of: find.text(title(3)), matching: find.byType(LedgerEntryCard));
      expect(find.descendant(of: row, matching: find.text('cancelled')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Ref: R-03')), findsOneWidget);
      expectFigures();
    });

    testWidgets('2 + 3 + 4 + 5. trim, paging, reset on query change, page size kept, no-match, Clear', (tester) async {
      await seed();
      await pumpTab(tester, 'Ledger');
      await tapAndSettle(tester, next());
      await tapAndSettle(tester, next());
      expect(find.text('Page 3 of 3'), findsOneWidget);

      await search(tester, 'ledger', '   general  '); // 18 entries
      expect(find.text('Showing 1–10 of 18'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tapAndSettle(tester, next());
      expect(find.text('Showing 11–18 of 18'), findsOneWidget);
      await search(tester, 'ledger', 'genera'); // same matches, new query
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await choosePageSize(tester, 'ledger', 25);
      await search(tester, 'ledger', 'no such entry');
      expect(find.text('No transactions match "no such entry".'), findsOneWidget);
      expect(find.byKey(const Key('ledger-pagination')), findsNothing);
      expectFigures();

      await clear(tester, 'ledger');
      expect(pageSize(tester, 'ledger'), 25);
      expect(find.text('Showing 1–25 of 27'), findsOneWidget);
      expectFigures();
    });
  });

  testWidgets('empty tabs keep their existing empty states and show no search box', (tester) async {
    await pumpTab(tester, 'Income');
    expect(find.text('No income yet'), findsOneWidget);
    expect(find.byKey(const Key('income-search')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('No expense invoices'), findsOneWidget);
    expect(find.byKey(const Key('expense-search')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.byKey(const Key('ledger-search')), findsNothing);
  });
}
