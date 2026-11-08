// Finance -> Ledger: the floating Add button and the "Show cancelled
// transactions" control on the real screen.
// - Add (tooltip "Add income or expense") opens a menu with the two
//   existing entry workflows: Add Income (the Income tab's dialog) and Add
//   Expense (Raise Expense Invoice; paying it records the expense). Cancel
//   writes nothing; a saved income appears in the Ledger exactly once.
// - The button never covers the last transaction (desktop, tablet, phone).
// - "Show cancelled transactions" sits with All / Income / Expense and is
//   unchecked each time the Ledger tab opens.
// Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/services/document_number_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_expense_dialog.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_income_dialog.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';
import 'package:montessori_app/modules/finance/widgets/ledger_entry_card.dart';

import 'support/buffered_transaction_firestore.dart';

DateTime _today() => DateTime(2026, 11, 6, 10);

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

  Finder key(String k) => find.byKey(Key(k));

  var seq = 0;
  Future<void> add(String title, String type, double amount, {String status = 'confirmed'}) async {
    seq++;
    await firestore.collection('finance_ledger').add({
      'entryType': type, 'amount': amount, 'accountId': cashId, 'accountName': 'Cash', 'categoryName': 'General',
      'status': status, 'title': title, 'transactionDate': DateTime(2026, 11, 2), 'createdAt': DateTime(2026, 11, 2).add(Duration(minutes: seq)),
    });
  }

  Future<void> pumpLedger(WidgetTester tester, {Size size = const Size(1400, 1600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: AdminFinanceScreen(service: service, numberService: DocumentNumberService(firestore: firestore), clock: _today)),
    ));
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

  Future<int> docs(String collection) async => (await firestore.collection(collection).get()).docs.length;

  Future<void> chooseDropdown(WidgetTester tester, String label, String option) async {
    await tap(tester, find.widgetWithText(DropdownButtonFormField<String>, label));
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Add opens the menu; Cancel closes it and writes nothing', (tester) async {
    await pumpLedger(tester);
    expect(find.byTooltip('Add income or expense'), findsOneWidget);
    await tap(tester, key('finance-add'));
    expect(key('ledger-add-menu'), findsOneWidget);
    expect(find.text('Add Income'), findsOneWidget);
    expect(find.text('Add Expense'), findsOneWidget);
    await tap(tester, key('ledger-add-cancel'));
    expect(key('ledger-add-menu'), findsNothing);
    expect(find.byType(AddIncomeDialog), findsNothing);
    expect(find.byType(AddExpenseDialog), findsNothing);
    expect([await docs('finance_ledger'), await docs('finance_income'), await docs('finance_invoices')], [0, 0, 0]);
  });

  testWidgets('Add Income opens the existing dialog; a saved income appears in the Ledger once, with its totals', (tester) async {
    await pumpLedger(tester);
    await tap(tester, key('finance-add'));
    await tap(tester, key('ledger-add-income'));
    expect(find.byType(AddIncomeDialog), findsOneWidget);
    expect(tester.widget<AddIncomeDialog>(find.byType(AddIncomeDialog)).initial, isNull);

    // The existing validation: nothing is saved without the required fields.
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.byType(AddIncomeDialog), findsOneWidget);
    expect(await docs('finance_ledger'), 0);

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Book sale');
    await chooseDropdown(tester, 'Category', 'Other Income');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1250');
    await chooseDropdown(tester, 'Account', 'Cash');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.byType(AddIncomeDialog), findsNothing);

    expect(await docs('finance_ledger'), 1, reason: 'one ledger entry, written by the existing createIncome');
    expect(await docs('finance_income'), 1);
    final rows = tester.widgetList<LedgerEntryCard>(find.byType(LedgerEntryCard)).toList();
    expect(rows.where((c) => c.entry.title == 'Book sale'), hasLength(1));
    expect(rows.single.entry.accountId, cashId, reason: 'the account chosen in the dialog');
    expect(tester.widget<FinanceSummaryCard>(key('ledger-total-income')).value, '₹1250');
    expect(tester.widget<FinanceSummaryCard>(key('ledger-closing-balance')).value, '₹1250');
  });

  testWidgets('Add Expense opens the existing Raise Expense Invoice dialog; closing it writes nothing', (tester) async {
    await pumpLedger(tester);
    await tap(tester, key('finance-add'));
    await tap(tester, key('ledger-add-expense'));
    expect(find.byType(AddExpenseDialog), findsOneWidget);
    expect(tester.widget<AddExpenseDialog>(find.byType(AddExpenseDialog)).initial, isNull);
    await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
    expect(find.byType(AddExpenseDialog), findsNothing);
    expect([await docs('finance_ledger'), await docs('finance_invoices')], [0, 0]);
  });

  testWidgets('the other tabs keep their own Add', (tester) async {
    await pumpLedger(tester);
    for (final (tab, tip) in const [('Dashboard', 'Add income'), ('Expenses', 'Raise expense invoice'), ('Salary', 'Raise salary invoice'), ('Vendors', 'Add vendor'), ('Settings', 'Add category or account')]) {
      await tap(tester, find.widgetWithText(ChoiceChip, tab));
      expect(find.byTooltip(tip), findsOneWidget, reason: tab);
    }
    await tap(tester, find.widgetWithText(ChoiceChip, 'Reports'));
    expect(key('finance-add'), findsNothing);
  });

  for (final size in const [Size(1400, 900), Size(800, 1000), Size(360, 740)]) {
    testWidgets('${size.width.toInt()}px: Add never covers the last transaction; the cancelled control fits beside the filters', (tester) async {
      for (var n = 1; n <= 12; n++) {
        await add('Entry ${n.toString().padLeft(2, '0')}', n.isOdd ? 'income' : 'expense', n * 10.0, status: n == 4 ? 'cancelled' : 'confirmed');
      }
      await pumpLedger(tester, size: size);
      expect(tester.takeException(), isNull);
      final toggle = tester.getRect(key('ledger-show-cancelled'));
      final filter = tester.getRect(key('ledger-type-filter'));
      expect(toggle.right, lessThanOrEqualTo(size.width));
      expect(filter.right, lessThanOrEqualTo(size.width));
      if (size.width >= 1000) expect((toggle.center.dy - filter.center.dy).abs(), lessThan(4), reason: 'one row on desktop');

      // Scrolled to the end, the last row sits above the button.
      await tester.dragUntilVisible(find.text('Showing 1–10 of 11'), find.byType(SingleChildScrollView).first, const Offset(0, -300));
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -5000));
      await tester.pumpAndSettle();
      final lastRow = tester.getRect(find.byType(LedgerEntryCard).last);
      final fab = tester.getRect(key('finance-add'));
      expect(lastRow.overlaps(fab), isFalse);
      expect(tester.getRect(find.text('Showing 1–10 of 11')).overlaps(fab), isFalse, reason: 'nor the paging controls');
    });
  }

  testWidgets('"Show cancelled transactions" is unchecked each time the Ledger tab opens; totals unaffected', (tester) async {
    await add('Kept', 'income', 500);
    await add('Voided', 'income', 300, status: 'cancelled');
    await pumpLedger(tester);
    bool checked() => tester.widget<Checkbox>(key('ledger-show-cancelled-checkbox')).value!;
    expect(find.text('Show cancelled transactions'), findsOneWidget);
    expect(checked(), isFalse);
    expect(find.text('Voided'), findsNothing);
    await tester.enterText(find.byKey(const Key('ledger-search')), 'o');
    await tester.pumpAndSettle();
    await tap(tester, key('ledger-show-cancelled'));
    expect(find.text('Voided'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('ledger-search'))).controller!.text, 'o', reason: 'search kept');
    expect(tester.widget<FinanceSummaryCard>(key('ledger-total-income')).value, '₹500');

    await tap(tester, find.widgetWithText(ChoiceChip, 'Income'));
    await tap(tester, find.widgetWithText(ChoiceChip, 'Ledger'));
    expect(checked(), isFalse, reason: 'reopening the tab resets it');
    expect(find.text('Voided'), findsNothing);
    expect(tester.widget<FinanceSummaryCard>(key('ledger-total-income')).value, '₹500');
  });
}
