// Finance -> Ledger: UI pagination of the Transactions list (10/25/50 per
// page), the same controls and behaviour as Income/Expenses/Salary.
// - Only the current page's LedgerEntryCards are built, in the existing
//   watchLedger() order (newest createdAt first).
// - Total Inflow / Total Outflow / Net Movement (confirmed entries) and the
//   Closing Balance / account cards always cover the complete ledger.
// - Previous/Next (disabled at the ends), "Showing x–y of n", "Page p of q";
//   back to page 1 when entries are added/removed/reordered or the page
//   becomes invalid; no controls for an empty ledger.
// - Ledger rows have no actions in this tab (LedgerEntryCard's optional
//   onCancel isn't passed); their status/reference/remarks still render on
//   later pages.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;
  late String cashId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
    cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
  });

  String title(int n) => 'Entry ${n.toString().padLeft(2, '0')}';

  /// Entry n (oldest 1 … newest last): odd n income, even n expense,
  /// ₹100 × n, on the Cash account; entry 3 is cancelled.
  Future<Map<int, String>> seed(int count, {int from = 1}) async {
    final ids = <int, String>{};
    for (var n = from; n < from + count; n++) {
      final ref = await firestore.collection('finance_ledger').add({
        'entryType': n.isOdd ? 'income' : 'expense',
        'amount': n * 100,
        'accountId': cashId,
        'accountName': 'Cash',
        'categoryName': 'General',
        'status': n == 3 ? 'cancelled' : 'confirmed',
        'title': title(n),
        'description': 'Note $n',
        'referenceNo': 'R-$n',
        'transactionDate': DateTime(2026, 9, 1),
        'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: n)),
      });
      ids[n] = ref.id;
    }
    return ids;
  }

  Future<void> pumpLedger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ledger'));
    await tester.pumpAndSettle();
  }

  List<String> shown(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(of: find.byType(LedgerEntryCard), matching: find.textContaining(RegExp(r'^Entry \d\d$'))))
      .map((t) => t.data!)
      .toList();
  List<String> range(int from, int to) => [for (var n = from; n >= to; n--) title(n)];

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder next() => find.byTooltip('Next page');
  Finder previous() => find.byTooltip('Previous page');
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<IconButton>(find.ancestor(of: button, matching: find.byType(IconButton))).onPressed != null;

  Future<void> choosePageSize(WidgetTester tester, int size) async {
    await tapAndSettle(tester, find.byKey(const Key('ledger-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  void expectFigures(WidgetTester tester, {required String inflow, required String outflow, required String net, required String closing}) {
    Finder card(String label) => find.ancestor(of: find.text(label), matching: find.byType(FinanceSummaryCard));
    expect(find.descendant(of: card('Total Inflow'), matching: find.text(inflow)), findsOneWidget);
    expect(find.descendant(of: card('Total Outflow'), matching: find.text(outflow)), findsOneWidget);
    expect(find.descendant(of: card('Net Movement'), matching: find.text(net)), findsOneWidget);
    expect(find.descendant(of: card('Closing Balance'), matching: find.text(closing)), findsOneWidget);
  }

  // Entries 1..27: inflow = odd n except cancelled 3 = (196 − 3) × 100;
  // outflow = even n = 182 × 100; net = closing = ₹1100.
  void expectFullFigures(WidgetTester tester) =>
      expectFigures(tester, inflow: '₹19300', outflow: '₹18200', net: '₹1100', closing: '₹1100');

  testWidgets('1. first page: 10 newest in watchLedger order, range and page count', (tester) async {
    await seed(27);
    await pumpLedger(tester);
    expect(shown(tester), range(27, 18));
    expect(find.byType(LedgerEntryCard), findsNWidgets(10));
    expect(find.text('Showing 1–10 of 27'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expectFullFigures(tester);
  });

  testWidgets('2 + 4. Next/Previous with disabled ends; inflow, outflow, net and closing unchanged on every page', (tester) async {
    await seed(27);
    await pumpLedger(tester);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isTrue);

    await tapAndSettle(tester, next());
    expect(shown(tester), range(17, 8));
    expect(find.text('Showing 11–20 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expectFullFigures(tester);

    await tapAndSettle(tester, next());
    expect(shown(tester), range(7, 1));
    expect(find.text('Showing 21–27 of 27'), findsOneWidget);
    expect(enabled(tester, next()), isFalse);
    expectFullFigures(tester);

    await tapAndSettle(tester, previous());
    await tapAndSettle(tester, previous());
    expect(shown(tester), range(27, 18));
    expect(enabled(tester, previous()), isFalse);
    expectFullFigures(tester);
  });

  testWidgets('3. page sizes: a valid page is kept, an invalid one returns to page 1', (tester) async {
    await seed(27);
    await pumpLedger(tester);
    await tapAndSettle(tester, next());

    await choosePageSize(tester, 25);
    expect(shown(tester), range(2, 1));
    expect(find.text('Showing 26–27 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await choosePageSize(tester, 50);
    expect(shown(tester), range(27, 1));
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isFalse);

    await choosePageSize(tester, 10);
    expect(shown(tester), range(27, 18));
    expectFullFigures(tester);
  });

  testWidgets('5a. adding an entry returns to page 1; figures update', (tester) async {
    await seed(27);
    await pumpLedger(tester);
    await tapAndSettle(tester, next());
    await tapAndSettle(tester, next());
    expect(find.text('Page 3 of 3'), findsOneWidget);

    await seed(1, from: 28); // expense ₹2800
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–10 of 28'), findsOneWidget);
    expect(shown(tester), range(28, 19));
    expectFigures(tester, inflow: '₹19300', outflow: '₹21000', net: '₹-1700', closing: '₹-1700');
  });

  testWidgets('5b. removing an entry returns to page 1; a status-only change keeps the page', (tester) async {
    final ids = await seed(27);
    await pumpLedger(tester);
    await tapAndSettle(tester, next());

    // Cancelling an entry changes its status, not the list: page kept.
    await firestore.doc('finance_ledger/${ids[10]}').update({'status': 'cancelled'});
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expectFigures(tester, inflow: '₹19300', outflow: '₹17200', net: '₹2100', closing: '₹2100');

    await firestore.doc('finance_ledger/${ids[27]}').delete();
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–10 of 26'), findsOneWidget);
    expect(shown(tester), range(26, 17));
  });

  testWidgets('5c. reordering entries returns to page 1', (tester) async {
    final ids = await seed(27);
    await pumpLedger(tester);
    await tapAndSettle(tester, next());
    await firestore.doc('finance_ledger/${ids[1]}').update({'createdAt': DateTime(2026, 12, 1)}); // oldest -> newest
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(shown(tester).first, title(1));
  });

  testWidgets('6. empty ledger: existing empty state, no pagination controls', (tester) async {
    await pumpLedger(tester);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.byKey(const Key('ledger-pagination')), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);
    expectFigures(tester, inflow: '₹0', outflow: '₹0', net: '₹0', closing: '₹0');
  });

  testWidgets('7. later-page rows render their status, reference and remarks (no row actions in this tab)', (tester) async {
    await seed(27);
    await pumpLedger(tester);
    await tapAndSettle(tester, next());
    await tapAndSettle(tester, next());
    final row = find.ancestor(of: find.text(title(3)), matching: find.byType(LedgerEntryCard));
    expect(find.descendant(of: row, matching: find.text('cancelled')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Ref: R-3')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Note 3')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Cancel')), findsNothing);
    expect(tester.widget<LedgerEntryCard>(row).onCancel, isNull);
  });
}
