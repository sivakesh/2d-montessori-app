// Finance -> Expenses: the Raise / Edit Expense Invoice vendor field picks
// from Finance -> Vendors (the `vendors` collection) instead of free text.
// - Active vendors are listed by name and searchable; inactive ones aren't
//   offered. The selected vendor's id is saved as the invoice's `partyId`
//   (already in the invoice schema) and its name as `partyName`.
// - A vendor must be selected; typed text alone doesn't count.
// - Editing keeps the saved vendor: a legacy name-only invoice is linked
//   only when exactly one vendor has that name (stored name kept); a vendor
//   that is inactive, no longer in Vendors, unmatched or ambiguous is kept
//   as saved, with a note, unless another vendor is chosen.
// - Loading / empty / load-error states, and save errors keep the dialog.
// - Payment, cancellation and totals behave as before for these invoices.
import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/services/document_number_service.dart';
import 'package:montessori_app/modules/finance/models/finance_invoice_model.dart';
import 'package:montessori_app/modules/finance/models/vendor_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/dialogs/add_expense_dialog.dart';

import 'support/buffered_transaction_firestore.dart';

/// Lets a test control the vendor stream and make saves fail.
class _FaultyFinanceService extends FinanceService {
  _FaultyFinanceService({required super.firestore, required super.auth});

  StreamController<List<VendorModel>>? vendors;
  bool failCreate = false;
  bool failUpdate = false;

  @override
  Stream<List<VendorModel>> watchVendors() => vendors?.stream ?? super.watchVendors();

  @override
  Future<String> createExpenseInvoice(Map<String, dynamic> data) async {
    if (failCreate) throw StateError('write denied');
    return super.createExpenseInvoice(data);
  }

  @override
  Future<void> updateExpenseInvoice({
    required String id,
    String? partyId,
    required String partyName,
    required String categoryName,
    required DateTime invoiceDate,
    required double amount,
    required double taxAmount,
    required String description,
    required String attachmentUrl,
  }) async {
    if (failUpdate) throw StateError('write denied');
    return super.updateExpenseInvoice(
      id: id,
      partyId: partyId,
      partyName: partyName,
      categoryName: categoryName,
      invoiceDate: invoiceDate,
      amount: amount,
      taxAmount: taxAmount,
      description: description,
      attachmentUrl: attachmentUrl,
    );
  }
}

void main() {
  late BufferedTransactionFirestore firestore;
  late _FaultyFinanceService service;
  late String acmeId, brightId, oldId;
  bool? result;

  Future<String> addVendor(String name, {bool active = true, String serviceType = ''}) async =>
      (await firestore.collection('vendors').add({'name': name, 'isActive': active, 'serviceType': serviceType, 'phone': '', 'email': '', 'address': ''})).id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = _FaultyFinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
    acmeId = await addVendor('Acme Supplies', serviceType: 'Stationery');
    brightId = await addVendor('Bright Cleaners', serviceType: 'Housekeeping');
    oldId = await addVendor('Old Traders', active: false);
    result = null;
  });

  Future<String> seedInvoice({String partyId = '', String partyName = 'Acme Supplies', double amount = 1000}) async =>
      (await firestore.collection('finance_invoices').add({
        'type': 'expense',
        'partyId': partyId,
        'partyName': partyName,
        'categoryName': 'Vendor Payment',
        'invoiceNo': 'INV-00010001',
        'invoiceDate': DateTime(2026, 9, 1),
        'dueDate': DateTime(2026, 9, 1),
        'amount': amount,
        'taxAmount': 0,
        'deductions': 0,
        'bonus': 0,
        'totalAmount': amount,
        'paidAmount': 0,
        'balanceAmount': amount,
        'status': 'unpaid',
        'description': 'Legacy invoice',
        'attachmentUrl': '',
      }))
          .id;

  Future<Map<String, dynamic>> invoiceData(String id) async => (await firestore.doc('finance_invoices/$id').get()).data()!;
  Future<List<Map<String, dynamic>>> allInvoices() async => (await firestore.collection('finance_invoices').get()).docs.map((d) => d.data()).toList();

  Future<void> openDialog(WidgetTester tester, {String? editId}) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FinanceInvoiceModel? initial;
    if (editId != null) initial = (await service.getInvoiceById(editId))!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => AddExpenseDialog(initial: initial, service: service, numberService: DocumentNumberService(firestore: firestore)),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    if (service.vendors == null) {
      await tester.pumpAndSettle();
    } else {
      // Vendors still loading: the spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Finder vendorField() => find.descendant(of: find.byKey(const Key('expense-vendor')), matching: find.byType(TextFormField));
  String vendorText(WidgetTester tester) => tester.widget<TextFormField>(vendorField()).controller!.text;
  bool vendorEnabled(WidgetTester tester) => tester.widget<TextField>(find.descendant(of: vendorField(), matching: find.byType(TextField))).enabled ?? true;
  Finder option(String id) => find.byKey(Key('vendor-option-$id'));

  Future<void> search(WidgetTester tester, String text) async {
    await tester.tap(vendorField());
    await tester.pumpAndSettle();
    await tester.enterText(vendorField(), text);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String id) async {
    await tester.tap(option(id));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCategory(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Expense Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String amount = '1200', String tax = '50'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), amount);
    await tester.enterText(find.widgetWithText(TextFormField, 'Tax Amount (optional)'), tax);
    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Cleaning for September');
    await tester.enterText(find.widgetWithText(TextFormField, 'Attachment URL (optional)'), 'https://example.com/bill.pdf');
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('Raise Expense Invoice', () {
    testWidgets('1. loading state, then active vendors listed by name (inactive not offered)', (tester) async {
      service.vendors = StreamController<List<VendorModel>>();
      addTearDown(service.vendors!.close);
      await openDialog(tester);
      expect(find.text('Loading vendors…'), findsOneWidget);
      expect(vendorEnabled(tester), isFalse);

      final snap = await firestore.collection('vendors').orderBy('name').get();
      service.vendors!.add(snap.docs.map((d) => VendorModel.fromMap(d.id, d.data())).toList());
      await tester.pumpAndSettle();
      expect(find.text('Loading vendors…'), findsNothing);
      expect(vendorEnabled(tester), isTrue);

      await tester.tap(vendorField());
      await tester.pumpAndSettle();
      expect(option(acmeId), findsOneWidget);
      expect(option(brightId), findsOneWidget);
      expect(option(oldId), findsNothing);
      expect(find.descendant(of: option(acmeId), matching: find.text('Acme Supplies')), findsOneWidget);
      expect(find.descendant(of: option(acmeId), matching: find.text('Stationery')), findsOneWidget);
    });

    testWidgets('1b. no active vendors: explains, and nothing can be saved', (tester) async {
      for (final id in [acmeId, brightId]) {
        await firestore.doc('vendors/$id').update({'isActive': false});
      }
      await openDialog(tester);
      expect(find.text('No active vendors yet. Add one under Finance → Vendors first.'), findsOneWidget);
      await chooseCategory(tester, 'Vendor Payment');
      await fill(tester);
      await save(tester);
      expect(find.text('Select a vendor from the list'), findsOneWidget);
      expect(await allInvoices(), isEmpty);
    });

    testWidgets('2. searching filters by name (case-insensitive); selecting fills the field', (tester) async {
      await openDialog(tester);
      await search(tester, 'BRI');
      expect(option(brightId), findsOneWidget);
      expect(option(acmeId), findsNothing);
      await search(tester, 'supp');
      expect(option(acmeId), findsOneWidget);
      expect(option(brightId), findsNothing);
      await search(tester, 'zzz');
      expect(option(acmeId), findsNothing);
      expect(option(brightId), findsNothing);

      await search(tester, 'bright');
      await pick(tester, brightId);
      expect(vendorText(tester), 'Bright Cleaners');
      expect(option(brightId), findsNothing); // list closes after selecting
    });

    testWidgets('3. saving stores the vendor id and name with every other field as before', (tester) async {
      await openDialog(tester);
      await search(tester, 'bright');
      await pick(tester, brightId);
      await chooseCategory(tester, 'Vendor Payment');
      await fill(tester);
      await save(tester);

      expect(result, isTrue);
      expect(find.text('Raise Expense Invoice'), findsNothing);
      final invoices = await allInvoices();
      expect(invoices, hasLength(1));
      final data = invoices.single;
      expect(data['partyId'], brightId);
      expect(data['partyName'], 'Bright Cleaners');
      expect(data['type'], 'expense');
      expect(data['categoryName'], 'Vendor Payment');
      expect(data['invoiceNo'], 'INV-00010010');
      expect(data['amount'], 1200);
      expect(data['taxAmount'], 50);
      expect(data['totalAmount'], 1250);
      expect(data['balanceAmount'], 1250);
      expect(data['paidAmount'], 0);
      expect(data['status'], 'unpaid');
      expect(data['description'], 'Cleaning for September');
      expect(data['attachmentUrl'], 'https://example.com/bill.pdf');
    });

    testWidgets('4. a vendor must be selected: empty, typed-only, or edited-after-selection text is refused', (tester) async {
      await openDialog(tester);
      await chooseCategory(tester, 'Vendor Payment');
      await fill(tester);

      await save(tester);
      expect(find.text('Select a vendor from the list'), findsOneWidget);

      await search(tester, 'Corner Shop'); // not a vendor
      await save(tester);
      expect(find.text('Select a vendor from the list'), findsOneWidget);

      await search(tester, 'acme');
      await pick(tester, acmeId);
      await tester.enterText(vendorField(), 'Acme Supplies Ltd'); // changes the selection
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Select a vendor from the list'), findsOneWidget);
      expect(await allInvoices(), isEmpty);
      expect(find.text('Raise Expense Invoice'), findsOneWidget);
    });

    testWidgets('7a. vendor load error: explains and blocks saving', (tester) async {
      service.vendors = StreamController<List<VendorModel>>();
      addTearDown(service.vendors!.close);
      await openDialog(tester);
      service.vendors!.addError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load vendors. Close and reopen this form to try again."), findsOneWidget);
      await chooseCategory(tester, 'Vendor Payment');
      await fill(tester);
      await save(tester);
      expect(find.text('Select a vendor from the list'), findsOneWidget);
      expect(await allInvoices(), isEmpty);
    });

    testWidgets('7b. save error: message shown, dialog stays open with the vendor kept, nothing written', (tester) async {
      service.failCreate = true;
      await openDialog(tester);
      await search(tester, 'acme');
      await pick(tester, acmeId);
      await chooseCategory(tester, 'Vendor Payment');
      await fill(tester);
      await save(tester);
      expect(find.text('Failed to save expense invoice'), findsOneWidget);
      expect(find.text('Raise Expense Invoice'), findsOneWidget);
      expect(vendorText(tester), 'Acme Supplies');
      expect(result, isNull);
      expect(await allInvoices(), isEmpty);
    });
  });

  group('Edit Expense Invoice', () {
    testWidgets('5a. legacy name-only invoice matching one vendor: preselected, linked by id, name kept', (tester) async {
      final id = await seedInvoice(partyName: 'acme supplies');
      await openDialog(tester, editId: id);
      expect(vendorText(tester), 'acme supplies');
      expect(find.textContaining('The invoice keeps this vendor'), findsNothing);

      await save(tester);
      expect(result, isTrue);
      final data = await invoiceData(id);
      expect(data['partyId'], acmeId);
      expect(data['partyName'], 'acme supplies');
      expect(data['totalAmount'], 1000);
    });

    testWidgets('5b. legacy name-only invoice with no matching vendor: kept as saved with a note', (tester) async {
      final id = await seedInvoice(partyName: 'Corner Shop');
      await openDialog(tester, editId: id);
      expect(vendorText(tester), 'Corner Shop');
      expect(find.text('"Corner Shop" was saved as a name and doesn\'t match a vendor in Vendors. The invoice keeps this vendor unless you choose another.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1500');
      await save(tester);
      expect(result, isTrue);
      final data = await invoiceData(id);
      expect(data['partyId'], '');
      expect(data['partyName'], 'Corner Shop');
      expect(data['totalAmount'], 1500);
    });

    testWidgets('5c. choosing a vendor deliberately replaces the legacy name', (tester) async {
      final id = await seedInvoice(partyName: 'Corner Shop');
      await openDialog(tester, editId: id);
      await search(tester, 'bright');
      await pick(tester, brightId);
      expect(find.textContaining('The invoice keeps this vendor'), findsNothing);
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], brightId);
      expect(data['partyName'], 'Bright Cleaners');
    });

    testWidgets('6a. inactive vendor: kept as saved, explained, and not offered for new selection', (tester) async {
      final id = await seedInvoice(partyId: oldId, partyName: 'Old Traders');
      await openDialog(tester, editId: id);
      expect(vendorText(tester), 'Old Traders');
      expect(find.text('"Old Traders" is inactive in Vendors. The invoice keeps this vendor unless you choose another.'), findsOneWidget);
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], oldId);
      expect(data['partyName'], 'Old Traders');
    });

    testWidgets('6b. vendor no longer in Vendors: kept as saved and explained', (tester) async {
      final id = await seedInvoice(partyId: 'removed-vendor', partyName: 'Gone Ltd');
      await openDialog(tester, editId: id);
      expect(vendorText(tester), 'Gone Ltd');
      expect(find.text('"Gone Ltd" is no longer in Vendors. The invoice keeps this vendor unless you choose another.'), findsOneWidget);
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], 'removed-vendor');
      expect(data['partyName'], 'Gone Ltd');
    });

    testWidgets('6c. a legacy name matching several vendors is not linked to either', (tester) async {
      await addVendor('Twin Co');
      await addVendor('Twin Co');
      final id = await seedInvoice(partyName: 'Twin Co');
      await openDialog(tester, editId: id);
      expect(find.text('More than one vendor is named "Twin Co", so it isn\'t linked to either. The invoice keeps this vendor unless you choose another.'), findsOneWidget);
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], '');
      expect(data['partyName'], 'Twin Co');
    });

    testWidgets('6d. a vendor renamed in Vendors since: the invoice keeps its stored name', (tester) async {
      final id = await seedInvoice(partyId: acmeId, partyName: 'Acme (old name)');
      await openDialog(tester, editId: id);
      expect(vendorText(tester), 'Acme (old name)');
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], acmeId);
      expect(data['partyName'], 'Acme (old name)');
    });

    testWidgets('7c. vendor load error while editing: saved vendor kept and the edit still saves', (tester) async {
      final id = await seedInvoice(partyName: 'Corner Shop');
      service.vendors = StreamController<List<VendorModel>>();
      addTearDown(service.vendors!.close);
      await openDialog(tester, editId: id);
      service.vendors!.addError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load vendors. Close and reopen this form to try again."), findsOneWidget);
      expect(vendorText(tester), 'Corner Shop');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1100');
      await save(tester);
      final data = await invoiceData(id);
      expect(data['partyId'], '');
      expect(data['partyName'], 'Corner Shop');
      expect(data['totalAmount'], 1100);
    });

    testWidgets('7d. update error: message shown, dialog stays open, invoice unchanged', (tester) async {
      final id = await seedInvoice(partyName: 'Corner Shop');
      final before = await invoiceData(id);
      service.failUpdate = true;
      await openDialog(tester, editId: id);
      await search(tester, 'bright');
      await pick(tester, brightId);
      await save(tester);
      expect(find.textContaining('Failed to update expense invoice'), findsOneWidget);
      expect(find.text('Edit Expense Invoice'), findsOneWidget);
      expect(await invoiceData(id), before);
    });
  });

  group('8. existing behaviour for invoices with a selected vendor', () {
    // Same shape the dialog writes (test 3): partyId = vendor id.
    test('payment, ledger, totals and cancellation are unchanged', () async {
      final paidId = await seedInvoice(partyId: brightId, partyName: 'Bright Cleaners');
      final cancelId = await seedInvoice(partyId: acmeId, partyName: 'Acme Supplies', amount: 300);

      await service.payInvoice(invoiceId: paidId, invoiceType: 'expense', amount: 400, paidDate: DateTime(2026, 9, 5), paymentMode: 'cash', referenceNo: 'R1', remarks: '');
      await service.cancelExpenseInvoice(id: cancelId, reason: 'Raised twice');

      final paid = await invoiceData(paidId);
      expect(paid['partyId'], brightId);
      expect(paid['partyName'], 'Bright Cleaners');
      expect(paid['paidAmount'], 400);
      expect(paid['balanceAmount'], 600);
      expect(paid['status'], 'partial');
      final ledger = (await firestore.collection('finance_ledger').where('invoiceId', isEqualTo: paidId).get()).docs.single.data();
      expect(ledger['title'], 'Expense Payment - Bright Cleaners');
      expect(ledger['amount'], 400);

      final cancelled = await invoiceData(cancelId);
      expect(cancelled['status'], 'cancelled');
      expect(cancelled['partyId'], acmeId);
      expect(cancelled['partyName'], 'Acme Supplies');

      // Only the payment counts; the cancelled unpaid invoice moved no money.
      final summary = await service.watchDashboardSummary().first;
      expect(summary.totalExpenses, 400);
    });

    test('editing through the service without partyId leaves the stored partyId as it is', () async {
      final id = await seedInvoice(partyId: acmeId, partyName: 'Acme Supplies');
      await service.updateExpenseInvoice(
        id: id,
        partyName: 'Acme Supplies',
        categoryName: 'Vendor Payment',
        invoiceDate: DateTime(2026, 9, 2),
        amount: 1500,
        taxAmount: 0,
        description: 'Edited',
        attachmentUrl: '',
      );
      final data = await invoiceData(id);
      expect(data['partyId'], acmeId);
      expect(data['totalAmount'], 1500);
    });
  });
}
