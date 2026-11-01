// Finance -> Income: UI pagination (10/25/50 per page).
// - Only the current page's income cards are built, in the existing order
//   (newest first) and with the existing invoice-payment filter.
// - Total Income and Transactions always cover the full filtered list.
// - Previous/Next, the "Showing x–y of n" range and page sizes; the view
//   returns to the first page when the list changes or a page size makes
//   the current page invalid.
// - Edit/Void actions and the empty state are unchanged.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  String title(int n) => 'Income ${n.toString().padLeft(2, '0')}';

  /// [count] manual income entries, "Income 01" oldest … newest last,
  /// ₹100 × n each, plus one invoice payment the tab must not show.
  Future<void> seed(int count) async {
    for (var n = 1; n <= count; n++) {
      await firestore.collection('finance_income').add({
        'title': title(n), 'amount': n * 100, 'programType': 'other', 'sourceModule': 'finance',
        'categoryName': 'Other Income', 'accountName': 'Cash', 'paymentMode': 'cash',
        'incomeDate': DateTime(2026, 8, 1), 'createdAt': DateTime(2026, 8, 1).add(Duration(minutes: n)),
      });
    }
    await firestore.collection('finance_income').add({
      'title': 'Expense Payment - Vendor', 'amount': 99999, 'programType': 'invoice', 'sourceModule': 'invoice',
      'createdAt': DateTime(2026, 9, 1),
    });
  }

  Future<void> pumpIncome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
    await tester.pumpAndSettle();
  }

  /// Titles of the income cards currently built, top to bottom.
  List<String> shownTitles(WidgetTester tester) => tester
      .widgetList<Text>(find.textContaining(RegExp(r'^Income \d\d$')))
      .map((t) => t.data!)
      .toList();

  List<String> titles(int from, int to) => [for (var n = from; n >= to; n--) title(n)];

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
    await tapAndSettle(tester, find.byKey(const Key('income-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  void expectTotals(WidgetTester tester, {required String total, required String count}) {
    Finder card(String label) => find.ancestor(of: find.text(label), matching: find.byType(FinanceSummaryCard));
    expect(find.descendant(of: card('Total Income'), matching: find.text(total)), findsOneWidget);
    expect(find.descendant(of: card('Transactions'), matching: find.text(count)), findsOneWidget);
  }

  // Sum of ₹100 × 1..27.
  const fullTotal = '₹37800';

  testWidgets('first page: 10 newest entries, range, totals for the full list, invoice payments excluded', (tester) async {
    await seed(27);
    await pumpIncome(tester);

    expect(shownTitles(tester), titles(27, 18));
    expect(find.text('Showing 1–10 of 27'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isTrue);
    expectTotals(tester, total: fullTotal, count: '27');
    expect(find.text('Expense Payment - Vendor'), findsNothing);
  });

  testWidgets('Next/Previous move between pages; totals never change', (tester) async {
    await seed(27);
    await pumpIncome(tester);

    await tapAndSettle(tester, next());
    expect(shownTitles(tester), titles(17, 8));
    expect(find.text('Showing 11–20 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expectTotals(tester, total: fullTotal, count: '27');

    await tapAndSettle(tester, next());
    expect(shownTitles(tester), titles(7, 1));
    expect(find.text('Showing 21–27 of 27'), findsOneWidget);
    expect(enabled(tester, next()), isFalse);
    expectTotals(tester, total: fullTotal, count: '27');

    await tapAndSettle(tester, previous());
    expect(find.text('Showing 11–20 of 27'), findsOneWidget);
    await tapAndSettle(tester, previous());
    expect(shownTitles(tester), titles(27, 18));
    expect(enabled(tester, previous()), isFalse);
    expectTotals(tester, total: fullTotal, count: '27');
  });

  testWidgets('page size: a still-valid page is kept, an invalid one returns to the first page', (tester) async {
    await seed(27);
    await pumpIncome(tester);
    await tapAndSettle(tester, next()); // page 2 at 10 per page

    await choosePageSize(tester, 25); // page 2 at 25 per page still exists
    expect(shownTitles(tester), titles(2, 1));
    expect(find.text('Showing 26–27 of 27'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await choosePageSize(tester, 50); // only one page now
    expect(shownTitles(tester), titles(27, 1));
    expect(find.text('Showing 1–27 of 27'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(enabled(tester, previous()), isFalse);
    expect(enabled(tester, next()), isFalse);

    await choosePageSize(tester, 10);
    expect(shownTitles(tester), titles(27, 18));
    expectTotals(tester, total: fullTotal, count: '27');
  });

  testWidgets('a change to the income list returns to the first page', (tester) async {
    await seed(27);
    await pumpIncome(tester);
    await tapAndSettle(tester, next());
    await tapAndSettle(tester, next());
    expect(find.text('Page 3 of 3'), findsOneWidget);

    await firestore.collection('finance_income').add({
      'title': 'Income 28', 'amount': 2800, 'programType': 'other', 'sourceModule': 'finance',
      'createdAt': DateTime(2026, 8, 2),
    });
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–10 of 28'), findsOneWidget);
    expect(shownTitles(tester), titles(28, 19));
    expectTotals(tester, total: '₹40600', count: '28');
  });

  testWidgets('Edit and Void stay available on every page', (tester) async {
    await seed(12);
    await pumpIncome(tester);
    expect(find.byTooltip('Edit'), findsNWidgets(10));
    expect(find.byTooltip('Void'), findsNWidgets(10));

    await tapAndSettle(tester, next());
    expect(shownTitles(tester), titles(2, 1));
    expect(find.byTooltip('Edit'), findsNWidgets(2));
    await tapAndSettle(tester, find.byTooltip('Void').first);
    expect(find.text('Void Income Entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('a short list shows one page; an empty list keeps the empty state with no pagination', (tester) async {
    await seed(3);
    await pumpIncome(tester);
    expect(shownTitles(tester), titles(3, 1));
    expect(find.text('Showing 1–3 of 3'), findsOneWidget);
    expect(enabled(tester, next()), isFalse);

    await firestore.collection('finance_income').get().then((s) async {
      for (final d in s.docs) {
        await d.reference.delete();
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('No income yet'), findsOneWidget);
    expect(find.byKey(const Key('income-pagination')), findsNothing);
    expectTotals(tester, total: '₹0', count: '0');
  });
}
