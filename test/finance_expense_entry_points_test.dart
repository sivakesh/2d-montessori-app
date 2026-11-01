// Finance -> Expenses: both Raise Expense Invoice entry points — the Add
// FAB on the Expenses tab and the empty state's "Raise Expense Invoice"
// button — open the vendor-enabled dialog on the screen's own
// FinanceService (and the screen's invoice-number service), so:
// - the vendor list loads from the same `vendors` collection as
//   Finance -> Vendors (active vendors only);
// - saving creates the invoice with the vendor's id in `partyId` and its
//   name in `partyName`, numbered by DocumentNumberService, and it appears
//   in the Expenses list;
// - validation, category selection and the Pay action are unchanged.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/services/document_number_service.dart';
import 'package:montessori_app/modules/admin/ui/admin_fab.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;
  late String acmeId, brightId, oldId;

  Future<String> addVendor(String name, {bool active = true}) async =>
      (await firestore.collection('vendors').add({'name': name, 'isActive': active, 'serviceType': '', 'phone': '', 'email': '', 'address': ''})).id;

  setUp(() async {
    // No transactions here: BufferedTransactionFirestore's commit lock must
    // be created inside the testWidgets zone.
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
    acmeId = await addVendor('Acme Supplies');
    brightId = await addVendor('Bright Cleaners');
    oldId = await addVendor('Old Traders', active: false);
  });

  Future<void> pumpExpenses(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: AdminFinanceScreen(service: service, numberService: DocumentNumberService(firestore: firestore))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Expenses'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder vendorField() => find.descendant(of: find.byKey(const Key('expense-vendor')), matching: find.byType(TextFormField));
  Finder option(String id) => find.byKey(Key('vendor-option-$id'));
  Finder emptyStateButton() => find.ancestor(of: find.text('Raise Expense Invoice'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  /// Vendors load from the `vendors` collection; picks [vendorId] by
  /// searching [query], then fills the rest and saves.
  Future<void> raise(WidgetTester tester, {required String query, required String vendorId, String amount = '1500', String tax = '100'}) async {
    expect(find.text('Raise Expense Invoice'), findsWidgets);
    await tapAndSettle(tester, vendorField());
    expect(option(acmeId), findsOneWidget);
    expect(option(brightId), findsOneWidget);
    expect(option(oldId), findsNothing, reason: 'inactive vendors are not offered');
    await tester.enterText(vendorField(), query);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, option(vendorId));

    await tapAndSettle(tester, find.widgetWithText(DropdownButtonFormField<String>, 'Expense Category'));
    await tester.tap(find.text('Vendor Payment').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), amount);
    await tester.enterText(find.widgetWithText(TextFormField, 'Tax Amount (optional)'), tax);
    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Supplies for term 1');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
  }

  Future<List<Map<String, dynamic>>> invoices() async => (await firestore.collection('finance_invoices').get()).docs.map((d) => d.data()).toList();

  testWidgets('empty-state button: loads vendors, saves with partyId/partyName, invoice listed', (tester) async {
    await pumpExpenses(tester);
    expect(find.text('No expense invoices'), findsOneWidget);
    await tapAndSettle(tester, emptyStateButton());

    // Validation unchanged: a vendor and a category are required.
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Select a vendor from the list'), findsOneWidget);
    expect(await invoices(), isEmpty);

    await raise(tester, query: 'acme', vendorId: acmeId);
    expect(find.text('Raise Expense Invoice'), findsNothing, reason: 'dialog closed after saving');
    final saved = await invoices();
    expect(saved, hasLength(1));
    final invoice = saved.single;
    expect(invoice['type'], 'expense');
    expect(invoice['partyId'], acmeId);
    expect(invoice['partyName'], 'Acme Supplies');
    expect(invoice['invoiceNo'], 'INV-00010010');
    expect(invoice['categoryName'], 'Vendor Payment');
    expect(invoice['totalAmount'], 1600);
    expect(invoice['status'], 'unpaid');

    expect(find.text('No expense invoices'), findsNothing);
    expect(find.text('INV-00010010'), findsOneWidget);
    expect(find.text('Acme Supplies'), findsOneWidget);
  });

  testWidgets('Add FAB: loads vendors, saves with partyId/partyName, numbering continues; Pay still works', (tester) async {
    await pumpExpenses(tester);
    await tapAndSettle(tester, find.byType(AdminFab));
    await raise(tester, query: 'bright', vendorId: brightId, amount: '800', tax: '0');
    await tapAndSettle(tester, find.byType(AdminFab)); // list no longer empty: FAB is the entry point
    await raise(tester, query: 'ACME', vendorId: acmeId, amount: '300', tax: '0');

    final saved = await invoices();
    expect(saved, hasLength(2));
    final byNo = {for (final i in saved) i['invoiceNo']: i};
    expect(byNo['INV-00010010']!['partyId'], brightId);
    expect(byNo['INV-00010010']!['partyName'], 'Bright Cleaners');
    expect(byNo['INV-00010010']!['totalAmount'], 800);
    expect(byNo['INV-00010011']!['partyId'], acmeId);
    expect(byNo['INV-00010011']!['partyName'], 'Acme Supplies');
    expect(find.text('INV-00010010'), findsOneWidget);
    expect(find.text('INV-00010011'), findsOneWidget);
    expect(find.text('₹1100'), findsWidgets, reason: 'Total Expenses covers both');

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Pay').first);
    expect(find.textContaining('Pay Invoice - '), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('both entry points use the screen\'s vendors: a vendor added on the Vendors collection shows up', (tester) async {
    await pumpExpenses(tester);
    final newId = await addVendor('Zenith Foods');
    await tapAndSettle(tester, find.byType(AdminFab));
    await tapAndSettle(tester, vendorField());
    expect(option(newId), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await invoices(), isEmpty, reason: 'cancel never allocates a number or saves');
    expect((await firestore.doc('system_counters/finance_invoice').get()).exists, isFalse);

    await tapAndSettle(tester, emptyStateButton());
    await tapAndSettle(tester, vendorField());
    expect(option(newId), findsOneWidget);
  });
}
