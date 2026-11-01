// Finance -> Settings -> Category Settings: edit and safe delete.
// - Edit opens a prefilled form (name, type, active); valid edits persist.
// - Name is required; another category of the same type can't share the
//   name (case-insensitive).
// - Delete asks for confirmation and only deletes a category no Finance
//   record uses (income/expense/ledger by categoryId or categoryName,
//   expense invoices by categoryName — voided records included). A category
//   in use can't be deleted, renamed or retyped; it can be deactivated.
// - Default (isSystem) categories are locked.
// - Transactions, classifications and totals never change.
// - Loading and persistence errors are shown, never treated as success.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_category_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

/// Real service with switchable failures.
class _FaultyFinanceService extends FinanceService {
  _FaultyFinanceService(BufferedTransactionFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());
  bool failCategoryStream = false;
  bool failReferences = false;
  bool failUpdate = false;
  bool failDelete = false;

  @override
  Stream<List<FinanceCategoryModel>> watchCategories() =>
      failCategoryStream ? Stream.error(Exception('unavailable')) : super.watchCategories();

  @override
  Future<List<String>> categoryReferences(FinanceCategoryModel category) =>
      failReferences ? Future.error(Exception('lookup failed')) : super.categoryReferences(category);

  @override
  Future<void> updateCategory({required String id, required String name, required String type, required bool isActive}) =>
      failUpdate
          ? Future.error(Exception('write failed'))
          : super.updateCategory(id: id, name: name, type: type, isActive: isActive);

  @override
  Future<void> deleteCategory(String id) => failDelete ? Future.error(Exception('write failed')) : super.deleteCategory(id);
}

void main() {
  late BufferedTransactionFirestore firestore;
  late _FaultyFinanceService service;
  late String donationsId; // unused income category
  late String eventsId; // income category used by a manual income entry
  late String stationeryId; // expense category used by an expense invoice (by name)

  Future<String> addCategory(String name, String type) async => (await firestore.collection('finance_categories').add({
        'name': name, 'type': type, 'parentId': null, 'isSystem': false, 'isActive': true,
        'createdAt': DateTime(2026, 1, 1), 'updatedAt': DateTime(2026, 1, 1),
      })).id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = _FaultyFinanceService(firestore);
    await service.ensureDefaults();
    donationsId = await addCategory('Donations', 'income');
    eventsId = await addCategory('Events', 'income');
    stationeryId = await addCategory('Stationery', 'expense');

    final cash = (await firestore.collection('finance_accounts').where('type', isEqualTo: 'cash').get()).docs.single;
    await service.createIncome(FinanceIncomeModel(
      id: '', title: 'Annual Day tickets', categoryId: eventsId, categoryName: 'Events', programType: 'other',
      studentId: '', studentName: '', classId: '', className: '', amount: 3000,
      incomeDate: DateTime(2026, 8, 1), paymentMode: 'cash', accountId: cash.id, accountName: 'Cash',
      referenceNo: '', remarks: '', attachmentUrls: const [], ledgerEntryId: '',
      createdAt: DateTime.now(), updatedAt: DateTime.now(), createdBy: 'admin',
    ));
    final invoiceId = await service.createExpenseInvoice({
      'partyName': 'Vendor', 'categoryName': 'Stationery', 'invoiceNo': 'INV-1', 'totalAmount': 1200, 'amount': 1200,
    });
    await service.payInvoice(
      invoiceId: invoiceId, invoiceType: 'expense', amount: 1200, paidDate: DateTime(2026, 8, 2),
      paymentMode: 'cash', referenceNo: '', remarks: '',
    );
  });

  Future<Map<String, dynamic>?> category(String id) async => (await firestore.doc('finance_categories/$id').get()).data();

  /// Every transaction-side document, for "nothing changed" checks.
  Future<Map<String, Map<String, dynamic>?>> transactions() async => {
        for (final c in ['finance_income', 'finance_ledger', 'finance_invoices', 'finance_expenses', 'finance_accounts'])
          for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
      };

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Settings'));
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
  Future<void> tapRowAction(WidgetTester tester, String name, String tooltip) async {
    final button = find.descendant(of: row(name), matching: find.byTooltip(tooltip));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Finder nameField() => find.widgetWithText(TextFormField, 'Name');
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('1. Edit opens a form prefilled with name, type and active; default categories are locked', (tester) async {
    await pumpSettings(tester);
    // Only the 3 custom categories offer Edit/Delete; the 4 defaults show a
    // lock. (Checked per category row: account cards on this tab have
    // their own Edit/Delete.)
    Finder categoryRow(String name) => find
        .ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate((w) => w is Container && w.padding == const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        )
        .first;
    for (final name in ['Donations', 'Events', 'Stationery']) {
      expect(find.descendant(of: categoryRow(name), matching: find.byTooltip('Edit')), findsOneWidget, reason: name);
      expect(find.descendant(of: categoryRow(name), matching: find.byTooltip('Delete')), findsOneWidget, reason: name);
    }
    for (final name in ['Fees', 'Other Income', 'Staff Salary', 'Vendor Payment']) {
      expect(find.descendant(of: categoryRow(name), matching: find.byTooltip('Edit')), findsNothing, reason: name);
      expect(find.descendant(of: categoryRow(name), matching: find.byTooltip('Delete')), findsNothing, reason: name);
      expect(find.descendant(of: categoryRow(name), matching: find.byTooltip('Default category')), findsOneWidget, reason: name);
    }
    expect(find.byTooltip('Default category'), findsNWidgets(4));

    await tapRowAction(tester, 'Donations', 'Edit');
    expect(find.text('Edit Category'), findsOneWidget);
    expect(tester.widget<TextFormField>(nameField()).controller!.text, 'Donations');
    expect(tester.widget<TextField>(find.descendant(of: nameField(), matching: find.byType(TextField))).enabled, isTrue);
    expect(find.descendant(of: find.byType(DropdownButtonFormField<String>), matching: find.text('income')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('2. a valid edit persists and appears in the list', (tester) async {
    await pumpSettings(tester);
    await tapRowAction(tester, 'Donations', 'Edit');
    await tester.enterText(nameField(), '  Gifts  ');
    await tester.tap(find.text('income').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('expense').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(find.text('Edit Category'), findsNothing);
    expect(find.text('Category updated'), findsOneWidget);
    expect(find.text('Gifts'), findsOneWidget);
    expect(find.text('Donations'), findsNothing);
    final doc = (await category(donationsId))!;
    expect(doc['name'], 'Gifts');
    expect(doc['type'], 'expense');
    expect(doc['isActive'], isTrue);
    expect(doc['isSystem'], isFalse);
    expect(doc['createdAt'], isNotNull); // other fields kept
  });

  testWidgets('3a. name is required', (tester) async {
    await pumpSettings(tester);
    await tapRowAction(tester, 'Donations', 'Edit');
    await tester.enterText(nameField(), '   ');
    await save(tester);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Edit Category'), findsOneWidget);
    expect((await category(donationsId))!['name'], 'Donations');
  });

  testWidgets('3b. a duplicate name of the same type is refused; the same name of another type is allowed', (tester) async {
    await pumpSettings(tester);
    await tapRowAction(tester, 'Donations', 'Edit');
    await tester.enterText(nameField(), ' other INCOME ');
    await save(tester);
    expect(find.text('Another income category is already named "other INCOME".'), findsOneWidget);
    expect(find.text('Edit Category'), findsOneWidget); // stays open
    expect((await category(donationsId))!['name'], 'Donations');

    // Service level: same name, other type is fine.
    await service.updateCategory(id: donationsId, name: 'Stationery', type: 'income', isActive: true);
    expect((await category(donationsId))!['name'], 'Stationery');
    await expectLater(
      service.updateCategory(id: donationsId, name: 'stationery', type: 'expense', isActive: true),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('already named'))),
    );
  });

  testWidgets('4. cancelling the delete confirmation changes nothing', (tester) async {
    final before = await transactions();
    await pumpSettings(tester);
    await tapRowAction(tester, 'Donations', 'Delete');
    expect(find.text('Delete Category'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await category(donationsId), isNotNull);
    expect(find.text('Donations'), findsOneWidget);
    expect(await transactions(), before);
  });

  testWidgets('5. an unused category is deleted', (tester) async {
    final before = await transactions();
    await pumpSettings(tester);
    await tapRowAction(tester, 'Donations', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await category(donationsId), isNull);
    expect(find.text('Category deleted'), findsOneWidget);
    expect(find.text('Donations'), findsNothing);
    expect(await transactions(), before);
  });

  testWidgets('6a. a category used by income can\'t be deleted; it can be deactivated instead', (tester) async {
    final before = await transactions();
    await pumpSettings(tester);
    await tapRowAction(tester, 'Events', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Category In Use'), findsOneWidget);
    expect(find.textContaining('used by income entries, ledger entries'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect((await category(eventsId))!['isActive'], isTrue);

    await tapRowAction(tester, 'Events', 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Category deactivated'), findsOneWidget);
    final doc = (await category(eventsId))!;
    expect(doc['isActive'], isFalse);
    expect(doc['name'], 'Events');
    expect(find.descendant(of: row('Events'), matching: find.text('INACTIVE')), findsOneWidget);
    expect(await transactions(), before, reason: 'transactions keep their category');
  });

  testWidgets('6b. a category used by an expense invoice (by name) is protected; its edit form is locked', (tester) async {
    await pumpSettings(tester);
    await tapRowAction(tester, 'Stationery', 'Edit');
    expect(find.textContaining('Used by expense invoices'), findsOneWidget);
    expect(tester.widget<TextField>(find.descendant(of: nameField(), matching: find.byType(TextField))).enabled, isFalse);
    expect(tester.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>)).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await expectLater(service.deleteCategory(stationeryId), throwsA(isA<StateError>()));
    await expectLater(
      service.updateCategory(id: stationeryId, name: 'Office Supplies', type: 'expense', isActive: true),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains("name and type can't be changed"))),
    );
    await expectLater(
      service.updateCategory(id: stationeryId, name: 'Stationery', type: 'income', isActive: true),
      throwsStateError,
    );
    expect((await category(stationeryId))!['name'], 'Stationery');
  });

  test('6c. voided records still protect their category; defaults are locked at the service', () async {
    final income = (await firestore.collection('finance_income').where('categoryId', isEqualTo: eventsId).get()).docs.single;
    await service.voidIncome(income.id);
    expect(await service.categoryReferences(FinanceCategoryModel.fromMap(eventsId, (await category(eventsId))!)), isNotEmpty);
    await expectLater(service.deleteCategory(eventsId), throwsStateError);

    final fees = (await firestore.collection('finance_categories').where('name', isEqualTo: 'Fees').get()).docs.single;
    await expectLater(service.deleteCategory(fees.id), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Default'))));
    await expectLater(service.updateCategory(id: fees.id, name: 'School Fees', type: 'income', isActive: true), throwsStateError);
    expect((await category(fees.id))!['name'], 'Fees');
  });

  test('7. classifications and totals are unchanged by category edits, deactivation and deletion', () async {
    final before = await transactions();
    final summaryBefore = await service.watchDashboardSummary().first;

    await service.updateCategory(id: donationsId, name: 'Gifts', type: 'expense', isActive: true);
    await service.updateCategory(id: eventsId, name: 'Events', type: 'income', isActive: false);
    await service.deleteCategory(donationsId);
    await expectLater(service.deleteCategory(eventsId), throwsStateError);

    expect(await transactions(), before);
    final summaryAfter = await service.watchDashboardSummary().first;
    expect(summaryAfter.totalIncome, summaryBefore.totalIncome);
    expect(summaryAfter.totalExpenses, summaryBefore.totalExpenses);
    expect(summaryAfter.netBalance, summaryBefore.netBalance);
    expect(summaryAfter.closingBalance, summaryBefore.closingBalance);
    expect(summaryAfter.cashBalance, summaryBefore.cashBalance);
    final income = (await firestore.collection('finance_income').where('categoryId', isEqualTo: eventsId).get()).docs.single.data();
    expect(income['categoryName'], 'Events');
  });

  group('8. loading and persistence errors', () {
    testWidgets('a category load failure is shown, not a spinner or an empty list', (tester) async {
      service.failCategoryStream = true;
      await pumpSettings(tester);
      expect(find.text("Couldn't load categories. Reopen Settings to try again."), findsOneWidget);
      expect(find.text('No categories yet'), findsNothing);
    });

    testWidgets('if usage can\'t be checked, the edit form locks name and type', (tester) async {
      await pumpSettings(tester);
      service.failReferences = true;
      await tapRowAction(tester, 'Donations', 'Edit');
      expect(find.textContaining("Couldn't check where this category is used"), findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: nameField(), matching: find.byType(TextField))).enabled, isFalse);
    });

    testWidgets('a failed save keeps the dialog open with the error and changes nothing', (tester) async {
      await pumpSettings(tester);
      await tapRowAction(tester, 'Donations', 'Edit');
      await tester.enterText(nameField(), 'Gifts');
      service.failUpdate = true;
      await save(tester);
      expect(find.text('Edit Category'), findsOneWidget);
      expect(find.textContaining('Could not save the category'), findsOneWidget);
      expect(find.text('Category updated'), findsNothing);
      expect((await category(donationsId))!['name'], 'Donations');
    });

    testWidgets('a failed usage check or delete is reported and nothing is deleted', (tester) async {
      await pumpSettings(tester);
      service.failReferences = true;
      await tapRowAction(tester, 'Donations', 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't check where this category is used, so it wasn't deleted"), findsOneWidget);
      expect(await category(donationsId), isNotNull);

      service.failReferences = false;
      service.failDelete = true;
      await tester.pump(const Duration(seconds: 5)); // let the previous SnackBar go
      await tester.pumpAndSettle();
      await tapRowAction(tester, 'Donations', 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed to delete category'), findsOneWidget);
      expect(find.text('Category deleted'), findsNothing);
      expect(await category(donationsId), isNotNull);
    });
  });
}
