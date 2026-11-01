// Finance -> Expenses and Salary: UI pagination (10/25/50 per page), the
// same controls and behaviour as Finance -> Income.
// - Only the current page's invoice cards are built, in the existing order
//   (newest first).
// - Outstanding / Paid / Total cards always cover the full list.
// - Previous/Next (disabled at the ends), "Showing x–y of n", "Page p of q";
//   back to the first page when the list changes or a page size makes the
//   current page invalid; no controls for an empty list.
// - Row actions (Pay; and Edit/Delete/Cancel on Expenses) work on later pages.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

class _Tab {
  const _Tab(this.label, this.type, this.prefix, this.totalLabel, this.emptyTitle);
  final String label; // ChoiceChip label
  final String type; // finance_invoices.type
  final String prefix; // invoice number prefix and control key prefix
  final String totalLabel;
  final String emptyTitle;
  String get keyPrefix => type;
}

const _tabs = [
  _Tab('Expenses', 'expense', 'EXP', 'Total Expenses', 'No expense invoices'),
  _Tab('Salary', 'salary', 'SAL', 'Total Salary', 'No salary invoices'),
];

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  for (final tab in _tabs) {
    String no(int n) => '${tab.prefix}-${n.toString().padLeft(2, '0')}';

    /// [count] unpaid invoices of this tab's type, oldest "-01" … newest
    /// last, ₹100 × n each, plus one invoice of the other type.
    Future<void> seed(int count, {int from = 1}) async {
      for (var n = from; n < from + count; n++) {
        await firestore.collection('finance_invoices').add({
          'type': tab.type, 'invoiceNo': no(n), 'partyName': 'Party ${n.toString().padLeft(2, '0')}',
          'categoryName': 'General', 'amount': n * 100, 'totalAmount': n * 100, 'paidAmount': 0,
          'balanceAmount': n * 100, 'status': 'unpaid', 'invoiceDate': DateTime(2026, 8, 1),
          'createdAt': DateTime(2026, 8, 1).add(Duration(minutes: n)),
        });
      }
    }

    Future<void> seedOtherType() => firestore.collection('finance_invoices').add({
          'type': tab.type == 'expense' ? 'salary' : 'expense', 'invoiceNo': 'OTHER-1', 'partyName': 'Other',
          'amount': 99999, 'totalAmount': 99999, 'paidAmount': 0, 'balanceAmount': 99999, 'status': 'unpaid',
          'createdAt': DateTime(2026, 9, 1),
        });

    Future<void> pumpTab(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, tab.label));
      await tester.pumpAndSettle();
    }

    List<String> shown(WidgetTester tester) => tester
        .widgetList<Text>(find.textContaining(RegExp('^${tab.prefix}-\\d\\d\$')))
        .map((t) => t.data!)
        .toList();
    List<String> range(int from, int to) => [for (var n = from; n >= to; n--) no(n)];

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
      await tapAndSettle(tester, find.byKey(Key('${tab.keyPrefix}-page-size')));
      await tester.tap(find.text('$size').last);
      await tester.pumpAndSettle();
    }

    void expectTotals(WidgetTester tester, {required String outstanding, required String paid, required String total}) {
      Finder card(String label) => find.ancestor(of: find.text(label), matching: find.byType(FinanceSummaryCard));
      expect(find.descendant(of: card('Outstanding'), matching: find.text(outstanding)), findsOneWidget);
      expect(find.descendant(of: card('Paid'), matching: find.text(paid)), findsOneWidget);
      expect(find.descendant(of: card(tab.totalLabel), matching: find.text(total)), findsOneWidget);
    }

    // ₹100 × 1..27
    void expectFullTotals(WidgetTester tester) =>
        expectTotals(tester, outstanding: '₹37800', paid: '₹0', total: '₹37800');

    group('${tab.label} pagination', () {
      testWidgets('1. first page: 10 newest, range and page count; other invoice types not shown', (tester) async {
        await seed(27);
        await seedOtherType();
        await pumpTab(tester);
        expect(shown(tester), range(27, 18));
        expect(find.text('Showing 1–10 of 27'), findsOneWidget);
        expect(find.text('Page 1 of 3'), findsOneWidget);
        expect(find.text('OTHER-1'), findsNothing);
        expect(find.byKey(Key('${tab.keyPrefix}-pagination')), findsOneWidget);
        expectFullTotals(tester);
      });

      testWidgets('2 + 4. Next/Previous with disabled ends; totals unchanged on every page', (tester) async {
        await seed(27);
        await pumpTab(tester);
        expect(enabled(tester, previous()), isFalse);
        expect(enabled(tester, next()), isTrue);

        await tapAndSettle(tester, next());
        expect(shown(tester), range(17, 8));
        expect(find.text('Showing 11–20 of 27'), findsOneWidget);
        expect(find.text('Page 2 of 3'), findsOneWidget);
        expect(enabled(tester, previous()), isTrue);
        expectFullTotals(tester);

        await tapAndSettle(tester, next());
        expect(shown(tester), range(7, 1));
        expect(find.text('Showing 21–27 of 27'), findsOneWidget);
        expect(enabled(tester, next()), isFalse);
        expectFullTotals(tester);

        await tapAndSettle(tester, previous());
        await tapAndSettle(tester, previous());
        expect(shown(tester), range(27, 18));
        expect(enabled(tester, previous()), isFalse);
        expectFullTotals(tester);
      });

      testWidgets('3. page sizes: a valid page is kept, an invalid one returns to page 1', (tester) async {
        await seed(27);
        await pumpTab(tester);
        await tapAndSettle(tester, next());

        await choosePageSize(tester, 25);
        expect(shown(tester), range(2, 1));
        expect(find.text('Showing 26–27 of 27'), findsOneWidget);
        expect(find.text('Page 2 of 2'), findsOneWidget);

        await choosePageSize(tester, 50);
        expect(shown(tester), range(27, 1));
        expect(find.text('Showing 1–27 of 27'), findsOneWidget);
        expect(find.text('Page 1 of 1'), findsOneWidget);
        expect(enabled(tester, previous()), isFalse);
        expect(enabled(tester, next()), isFalse);

        await choosePageSize(tester, 10);
        expect(shown(tester), range(27, 18));
        expectFullTotals(tester);
      });

      testWidgets('5. a change to the list returns to page 1', (tester) async {
        await seed(27);
        await pumpTab(tester);
        await tapAndSettle(tester, next());
        await tapAndSettle(tester, next());
        expect(find.text('Page 3 of 3'), findsOneWidget);

        await seed(1, from: 28);
        await tester.pumpAndSettle();
        expect(find.text('Showing 1–10 of 28'), findsOneWidget);
        expect(shown(tester), range(28, 19));
        expectTotals(tester, outstanding: '₹40600', paid: '₹0', total: '₹40600');
      });

      testWidgets('6. empty list: existing empty state, no pagination controls', (tester) async {
        await seedOtherType();
        await pumpTab(tester);
        expect(find.text(tab.emptyTitle), findsOneWidget);
        expect(find.byKey(Key('${tab.keyPrefix}-pagination')), findsNothing);
        expect(find.byTooltip('Next page'), findsNothing);
        expectTotals(tester, outstanding: '₹0', paid: '₹0', total: '₹0');
      });

      testWidgets('7. row actions remain available on a later page', (tester) async {
        await seed(12);
        await pumpTab(tester);
        await tapAndSettle(tester, next());
        expect(shown(tester), range(2, 1));
        expect(find.widgetWithText(FilledButton, 'Pay'), findsNWidgets(2));
        if (tab.type == 'expense') {
          expect(find.byTooltip('Edit'), findsNWidgets(2));
          expect(find.byTooltip('Delete'), findsNWidgets(2));
          expect(find.byTooltip('Cancel Invoice'), findsNWidgets(2));
        }

        await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Pay').last);
        expect(find.text('Pay Invoice - Party 01'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        // Invoice details (payment history / audit) still open from page 2.
        await tapAndSettle(tester, find.text(no(2)));
        expect(find.text('Payments'), findsOneWidget);
        expect(find.text('No payments recorded.'), findsOneWidget);
      });

      testWidgets('a payment on a later page keeps that page (list identity unchanged)', (tester) async {
        await seed(12);
        await pumpTab(tester);
        await tapAndSettle(tester, next());
        final id = (await firestore.collection('finance_invoices').where('invoiceNo', isEqualTo: no(1)).get()).docs.single.id;
        await service.payInvoice(
          invoiceId: id, invoiceType: tab.type, amount: 100, paidDate: DateTime(2026, 9, 1),
          paymentMode: 'cash', referenceNo: '', remarks: '',
        );
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 2'), findsOneWidget);
        expect(shown(tester), range(2, 1));
        // ₹100 × 1..12 = ₹7800; ₹100 now paid.
        expectTotals(tester, outstanding: '₹7700', paid: '₹100', total: '₹7800');
      });
    });
  }
}
