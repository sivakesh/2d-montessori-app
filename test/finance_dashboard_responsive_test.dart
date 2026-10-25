// Finance Dashboard: the "Recent Transactions / View all" header row.
// Its title used to be a non-flexible Text in a Row next to the View all
// button, so on narrow screens their combined width exceeded the Row and it
// overflowed (134px at 360px wide in tests, still overflowing up to ~480px).
// The title is now Expanded: it wraps when space is short, and View all keeps
// its natural size at the right edge.
// - No framework exception at 320–480px (with transactions listed) or at
//   desktop width; nothing here clears or ignores exceptions.
// - Both stay visible and inside the screen; View all still opens the Ledger.
// - Desktop: title and View all on one line, View all at the right.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
    final cashId = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single.id;
    for (var n = 1; n <= 6; n++) {
      await firestore.collection('finance_ledger').add({
        'entryType': n.isOdd ? 'income' : 'expense', 'amount': n * 100, 'accountId': cashId, 'accountName': 'Cash',
        'categoryName': 'General', 'status': 'confirmed', 'title': 'Entry $n', 'referenceNo': 'R-$n',
        'transactionDate': DateTime(2026, 9, 1), 'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: n)),
      });
    }
  });

  Future<void> pumpDashboard(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
  }

  Finder title() => find.text('Recent Transactions');
  Finder viewAll() => find.widgetWithText(TextButton, 'View all');

  void expectInside(WidgetTester tester, Finder finder, double width) {
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(rect.width, greaterThan(0));
  }

  for (final width in [320.0, 360.0, 412.0, 480.0]) {
    testWidgets('1 + 2. ${width.toInt()}px: no overflow; title and View all visible, inside the screen', (tester) async {
      await pumpDashboard(tester, width);
      expect(tester.takeException(), isNull);
      expect(title(), findsOneWidget);
      expect(viewAll(), findsOneWidget);
      await tester.ensureVisible(viewAll());
      await tester.pumpAndSettle();
      expectInside(tester, title(), width);
      expectInside(tester, viewAll(), width);
      expect(tester.getRect(viewAll()).left, greaterThanOrEqualTo(tester.getRect(title()).right),
          reason: 'View all sits beside the title, not over it');
      expect(find.byType(LedgerEntryCard), findsNWidgets(5), reason: 'the 5 most recent rows still show');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('2 + 4. 360px: View all is tappable and opens the full Ledger list', (tester) async {
    await pumpDashboard(tester, 360);
    await tester.ensureVisible(viewAll());
    await tester.pumpAndSettle();
    await tester.tap(viewAll()); // warns if something else would receive the tap
    await tester.pumpAndSettle();
    expect(find.text('A complete record of every income and expense transaction'), findsOneWidget);
    expect(find.text('Showing 1–6 of 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3 + 4. desktop: title and View all on one line, View all at the right edge; navigation works', (tester) async {
    await pumpDashboard(tester, 1400);
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(title());
    final buttonRect = tester.getRect(viewAll());
    final rowRect = tester.getRect(find.ancestor(of: title(), matching: find.byType(Row)).first);
    expect(titleRect.height, lessThan(30), reason: 'a single line of 16px text');
    expect((titleRect.center.dy - buttonRect.center.dy).abs(), lessThan(1), reason: 'same line');
    expect(titleRect.left, rowRect.left);
    expect(buttonRect.right, rowRect.right);

    await tester.tap(viewAll());
    await tester.pumpAndSettle();
    expect(find.text('A complete record of every income and expense transaction'), findsOneWidget);
  });
}
