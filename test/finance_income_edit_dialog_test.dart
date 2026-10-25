// Finance -> Income -> Edit Income dialog:
// - Entries generated from a Fee Collection store categoryId 'fees' and
//   programType 'fees' (FinanceService.createFeeIncomeEntry), which are not
//   among the Category (category doc ids) or Program Type dropdown items.
//   Opening one must not trip DropdownButton's "exactly one item with
//   value" assertion; the stored values are shown as-is and stay locked.
// - Other legacy values (inactive category/account, unlisted payment mode)
//   are shown as stored, never converted.
// - Normal entries keep exactly one item per value.
// - D1 account reassignment works end-to-end through the dialog.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_income_dialog.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  Future<Map<String, dynamic>> accountByType(String type) async {
    final snap = await firestore.collection('finance_accounts').where('type', isEqualTo: type).get();
    return {'id': snap.docs.single.id, ...snap.docs.single.data()};
  }

  Future<FinanceIncomeModel> incomeModel(String id) async {
    final doc = await firestore.collection('finance_income').doc(id).get();
    return FinanceIncomeModel.fromMap(doc.id, doc.data()!);
  }

  Future<String> createManualIncome({
    String mode = 'cash',
    String accountType = 'cash',
    String? categoryId,
    String categoryName = 'Other Income',
  }) async {
    final account = await accountByType(accountType);
    final cat = (await service.watchCategories().first).firstWhere((c) => c.name == 'Other Income');
    return service.createIncome(FinanceIncomeModel(
      id: '',
      title: 'Donation',
      categoryId: categoryId ?? cat.id,
      categoryName: categoryName,
      programType: 'other',
      studentId: '',
      studentName: '',
      classId: '',
      className: '',
      amount: 5000,
      incomeDate: DateTime(2026, 8, 1),
      paymentMode: mode,
      accountId: account['id'] as String,
      accountName: account['name'] as String,
      referenceNo: 'REF-1',
      remarks: 'Original remarks',
      attachmentUrls: const [],
      ledgerEntryId: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: 'admin',
    ));
  }

  Future<void> openDialog(WidgetTester tester, FinanceIncomeModel initial) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AddIncomeDialog(initial: initial, service: service),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Across every dropdown in the dialog, how many of its `items` carry
  /// [value] — the list DropdownButton's "exactly one item" assertion checks.
  /// (A closed dropdown only renders its selected item, so rendered widgets
  /// can't be counted instead.)
  int Function(String) countItemsFor(WidgetTester tester) => (value) => tester
      .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
      .map((d) => (d.items ?? const []).where((i) => i.value == value).length)
      .fold(0, (a, b) => a + b);

  testWidgets('a Fee Collection entry (category/program "fees") opens without the dropdown assertion', (tester) async {
    await service.createFeeIncomeEntry({'feeCollectionId': 'fc-1', 'amount': 4500.0, 'paymentMode': 'cash'});
    final id = (await firestore.collection('finance_income').where('sourceId', isEqualTo: 'fc-1').get()).docs.single.id;
    final initial = await incomeModel(id);
    expect(initial.categoryId, 'fees');
    expect(initial.programType, 'fees');

    await openDialog(tester, initial);
    final itemsWithValue = countItemsFor(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Income'), findsOneWidget);
    // Stored values are shown as-is, each as exactly one item.
    expect(itemsWithValue('fees'), 2); // one Category item + one Program Type item
    expect(find.text('Fees'), findsWidgets);
    expect(find.text('fees'), findsWidgets);
    // Linked fee collection stays locked: banner, no Save, fields disabled.
    expect(find.textContaining('generated from a Fee Collection'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
    final titleField = tester.widget<TextField>(find.widgetWithText(TextField, 'Title'));
    expect(titleField.enabled, isFalse);

    // Closing leaves the stored record untouched.
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    final after = await incomeModel(id);
    expect(after.categoryId, 'fees');
    expect(after.programType, 'fees');
  });

  testWidgets('a normal entry has exactly one item for its category and program type', (tester) async {
    final id = await createManualIncome();
    final initial = await incomeModel(id);
    await openDialog(tester, initial);
    final itemsWithValue = countItemsFor(tester);

    expect(tester.takeException(), isNull);
    expect(itemsWithValue(initial.categoryId), 1);
    expect(itemsWithValue('other'), 2); // Program Type 'other' + Payment Mode 'other' are separate dropdowns
    expect(itemsWithValue('fees'), 0);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('legacy values (inactive category/account, unlisted payment mode) are shown as stored', (tester) async {
    final id = await createManualIncome(categoryId: 'retired-category', categoryName: 'Old Category');
    final cash = await accountByType('cash');
    await firestore.collection('finance_accounts').doc(cash['id'] as String).update({'isActive': false});
    await firestore.collection('finance_income').doc(id).update({'paymentMode': 'card'});
    final initial = await incomeModel(id);

    await openDialog(tester, initial);
    final itemsWithValue = countItemsFor(tester);

    expect(tester.takeException(), isNull);
    expect(itemsWithValue('retired-category'), 1);
    expect(find.text('Old Category'), findsWidgets);
    expect(itemsWithValue('card'), 1);
    expect(itemsWithValue(cash['id'] as String), 1);
    // Nothing is rewritten just by opening.
    final after = await incomeModel(id);
    expect(after.categoryId, 'retired-category');
    expect(after.paymentMode, 'card');
  });

  testWidgets('D1 through the dialog: changing Cash to UPI moves the entry and balances', (tester) async {
    final id = await createManualIncome();
    final initial = await incomeModel(id);
    await openDialog(tester, initial);

    await tester.tap(find.text('cash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('upi').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Income'), findsNothing);
    final upi = await accountByType('upi');
    final cash = await accountByType('cash');
    final after = await incomeModel(id);
    expect(after.paymentMode, 'upi');
    expect(after.accountId, upi['id']);
    expect(after.amount, 5000);
    expect(after.referenceNo, 'REF-1');
    expect(after.remarks, 'Original remarks');
    final ledger = (await firestore.collection('finance_ledger').doc(after.ledgerEntryId).get()).data()!;
    expect(ledger['accountId'], upi['id']);
    expect(ledger['paymentMode'], 'upi');
    expect(cash['currentBalance'], 0);
    expect(upi['currentBalance'], 5000);
  });
}
