// Covers Finance -> Expenses:
// - Editing an expense invoice updates the same document (no duplicate),
//   keeps the invoice number and recorded payments, and recomputes
//   balance/status with payInvoice's formula.
// - Deleting requires confirmation, removes only an unpaid invoice, and is
//   refused (with an explanation) for an invoice that has payments.
// - The Pay Invoice dialog's Payment Date is persisted on the payment
//   (finance_income.incomeDate) and its ledger entry (transactionDate),
//   without touching the invoice's own date.
// - Salary invoices are unchanged (no Edit/Delete, no Payment Date field).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/models/finance_ledger_entry_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

final _invoiceDate = DateTime(2026, 1, 10);

Map<String, dynamic> _invoicePayload({
  required double amount,
  double taxAmount = 0,
  String partyName = 'Vendor A',
  String invoiceNo = 'INV-00010010',
  String categoryName = 'Vendor Payment',
}) {
  return {
    'partyId': '',
    'partyName': partyName,
    'categoryName': categoryName,
    'invoiceNo': invoiceNo,
    'invoiceDate': _invoiceDate,
    'dueDate': _invoiceDate,
    'amount': amount,
    'taxAmount': taxAmount,
    'deductions': 0,
    'bonus': 0,
    'totalAmount': amount + taxAmount,
    'description': 'Test invoice',
    'attachmentUrl': '',
  };
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  // fake_cloud_firestore's transaction mock ignores SetOptions(merge: true)
  // (see FinanceService.updateIncome's doc comment), so payInvoice's merge
  // write replaces the whole invoice doc in tests. Real Firestore merges.
  // Restore the untouched invoice fields so later steps see a realistic doc.
  Future<void> pay(String id, double amount, {DateTime? date}) async {
    final ref = firestore.collection('finance_invoices').doc(id);
    final before = (await ref.get()).data()!;
    await service.payInvoice(
      invoiceId: id,
      invoiceType: 'expense',
      amount: amount,
      paidDate: date ?? DateTime.now(),
      paymentMode: 'cash',
      referenceNo: 'REF',
      remarks: '',
    );
    final after = (await ref.get()).data()!;
    // The fake drops invoiceDate from the doc entirely, so check it was never
    // overwritten with the payment date before restoring it.
    expect(after.containsKey('invoiceDate'), isFalse);
    await ref.set({...before, ...after});
  }

  Future<void> updateWith(String id, {required double amount, double taxAmount = 0}) =>
      service.updateExpenseInvoice(
        id: id,
        partyName: 'Vendor B',
        categoryName: 'Utilities',
        invoiceDate: DateTime(2026, 1, 12),
        amount: amount,
        taxAmount: taxAmount,
        description: 'Edited',
        attachmentUrl: '',
      );

  group('Service: updateExpenseInvoice', () {
    test('updates the same invoice in place without creating a duplicate', () async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await updateWith(id, amount: 1500, taxAmount: 100);

      final snap = await firestore.collection('finance_invoices').get();
      expect(snap.docs, hasLength(1));
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.invoiceNo, 'INV-00010010');
      expect(invoice.partyName, 'Vendor B');
      expect(invoice.categoryName, 'Utilities');
      expect(invoice.description, 'Edited');
      expect(invoice.invoiceDate, DateTime(2026, 1, 12));
      expect(invoice.amount, 1500);
      expect(invoice.taxAmount, 100);
      expect(invoice.totalAmount, 1600);
      expect(invoice.paidAmount, 0);
      expect(invoice.balanceAmount, 1600);
      expect(invoice.status, 'unpaid');
      expect(invoice.type, 'expense');
    });

    test('keeps recorded payments and recomputes balance/status on a partially paid invoice', () async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pay(id, 400);

      await updateWith(id, amount: 1200);
      var invoice = (await service.getInvoiceById(id))!;
      expect(invoice.paidAmount, 400);
      expect(invoice.balanceAmount, 800);
      expect(invoice.status, 'partial');

      // Reducing the total to exactly the paid amount settles it.
      await updateWith(id, amount: 400);
      invoice = (await service.getInvoiceById(id))!;
      expect(invoice.balanceAmount, 0);
      expect(invoice.status, 'paid');

      // Payment records are untouched.
      final payments = await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get();
      expect(payments.docs, hasLength(1));
      expect(payments.docs.single.data()['amount'], 400);
    });

    test('rejects a total below the amount already paid', () async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pay(id, 600);
      await expectLater(updateWith(id, amount: 500), throwsStateError);
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.totalAmount, 1000);
      expect(invoice.balanceAmount, 400);
    });

    test('rejects editing a salary invoice', () async {
      final id = await service.createSalaryInvoice(_invoicePayload(amount: 1000));
      await expectLater(updateWith(id, amount: 2000), throwsStateError);
    });
  });

  group('Service: deleteExpenseInvoice', () {
    test('deletes an unpaid invoice and leaves other invoices and totals intact', () async {
      final keep = await service.createExpenseInvoice(_invoicePayload(amount: 300, invoiceNo: 'INV-1'));
      final remove = await service.createExpenseInvoice(_invoicePayload(amount: 700, invoiceNo: 'INV-2'));
      final before = await service.watchDashboardSummary().first;

      await service.deleteExpenseInvoice(remove);

      expect(await service.getInvoiceById(remove), isNull);
      expect(await service.getInvoiceById(keep), isNotNull);
      final items = await service.watchInvoicesByType('expense').first;
      expect(items.map((i) => i.id), [keep]);
      final after = await service.watchDashboardSummary().first;
      expect(after.totalExpenses, before.totalExpenses);
    });

    test('refuses to delete an invoice with payments and preserves payment history', () async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pay(id, 250);

      await expectLater(service.deleteExpenseInvoice(id), throwsStateError);

      expect(await service.getInvoiceById(id), isNotNull);
      final payments = await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get();
      expect(payments.docs, hasLength(1));
      final ledger = await firestore.collection('finance_ledger').where('invoiceId', isEqualTo: id).get();
      expect(ledger.docs, hasLength(1));
    });

    test('refuses to delete a salary invoice', () async {
      final id = await service.createSalaryInvoice(_invoicePayload(amount: 1000));
      await expectLater(service.deleteExpenseInvoice(id), throwsStateError);
      expect(await service.getInvoiceById(id), isNotNull);
    });
  });

  group('Service: payment date', () {
    test('a past payment date is stored on the payment and ledger, not on the invoice', () async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      final paidOn = DateTime(2026, 2, 3);
      await pay(id, 1000, date: paidOn);

      final payment = (await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get()).docs.single;
      expect(FinanceIncomeModel.fromMap(payment.id, payment.data()).incomeDate, paidOn);
      final ledger = (await firestore.collection('finance_ledger').where('invoiceId', isEqualTo: id).get()).docs.single;
      expect((ledger.data()['transactionDate'] as Timestamp).toDate(), paidOn);
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.invoiceDate, _invoiceDate);
      expect(invoice.status, 'paid');
    });

    test('historical payment records without a date still load', () async {
      await firestore.collection('finance_income').doc('legacy').set({
        'title': 'Expense Payment - Old',
        'amount': 100,
        'programType': 'invoice',
        'invoiceId': 'x',
      });
      await firestore.collection('finance_ledger').doc('legacy').set({
        'entryType': 'expense',
        'amount': 100,
        'status': 'confirmed',
      });
      final income = await service.watchIncome().first;
      expect(income.single.incomeDate, isNull);
      final ledger = await service.watchLedger().first;
      expect(ledger.single.transactionDate, isNull);
      expect(FinanceLedgerEntryModel.fromMap('legacy', {'amount': 100}).amount, 100);
    });
  });

  group('UI: Finance -> Expenses', () {
    Future<void> pumpTab(WidgetTester tester, String tab) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    Future<void> tapIcon(WidgetTester tester, IconData icon) async {
      final button = find.byIcon(icon).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('Edit opens a pre-filled form and saves to the same invoice', (tester) async {
      await firestore.collection('finance_categories').add({
        'name': 'Vendor Payment',
        'type': 'expense',
        'isActive': true,
      });
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pumpTab(tester, 'Expenses');

      await tapIcon(tester, Icons.edit_outlined);
      expect(find.text('Edit Expense Invoice'), findsOneWidget);
      expect(find.text('Invoice No: INV-00010010'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Vendor A'), findsOneWidget);
      expect(find.text(DateFormat('dd MMM yyyy').format(_invoiceDate)), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '2500');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Expense invoice updated'), findsOneWidget);
      final snap = await firestore.collection('finance_invoices').get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.id, id);
      expect(snap.docs.single.data()['totalAmount'], 2500);
      expect(snap.docs.single.data()['categoryName'], 'Vendor Payment');
      expect(snap.docs.single.data()['invoiceNo'], 'INV-00010010');
      // Totals on the Expenses tab reflect the edit.
      expect(find.text('₹2500'), findsWidgets);
    });

    testWidgets('Cancelling the delete confirmation keeps the invoice', (tester) async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pumpTab(tester, 'Expenses');

      await tapIcon(tester, Icons.delete_outline);
      expect(find.text('Delete Expense Invoice'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await service.getInvoiceById(id), isNotNull);
      expect(find.text('INV-00010010'), findsOneWidget);
    });

    testWidgets('Confirming delete removes an unpaid invoice and updates totals', (tester) async {
      await service.createExpenseInvoice(_invoicePayload(amount: 300, invoiceNo: 'INV-KEEP'));
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 700, invoiceNo: 'INV-DEL'));
      await pumpTab(tester, 'Expenses');
      expect(find.text('₹1000'), findsWidgets);

      // Newest first, so the first delete icon belongs to INV-DEL.
      await tapIcon(tester, Icons.delete_outline);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('INV-DEL')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Expense invoice deleted'), findsOneWidget);
      expect(await service.getInvoiceById(id), isNull);
      expect(find.text('INV-DEL'), findsNothing);
      expect(find.text('INV-KEEP'), findsOneWidget);
      expect(find.text('₹1000'), findsNothing);
    });

    testWidgets('Delete on an invoice with payments explains and does not delete', (tester) async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pay(id, 400);
      await pumpTab(tester, 'Expenses');

      await tapIcon(tester, Icons.delete_outline);
      expect(find.text('Cannot Delete Invoice'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      expect(await service.getInvoiceById(id), isNotNull);
      final payments = await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get();
      expect(payments.docs, hasLength(1));
    });

    testWidgets('Pay Invoice shows Payment Date defaulting to today and saves a selected past date', (tester) async {
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pumpTab(tester, 'Expenses');

      await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Date *'), findsOneWidget);
      expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField)),
        '02/03/2026',
      );
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.text('03 Feb 2026'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '400');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice payment saved'), findsOneWidget);

      final payments = await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get();
      expect(payments.docs, hasLength(1));
      expect((payments.docs.single.data()['incomeDate'] as Timestamp).toDate(), DateTime(2026, 2, 3));
      final ledger = await firestore.collection('finance_ledger').where('invoiceId', isEqualTo: id).get();
      expect((ledger.docs.single.data()['transactionDate'] as Timestamp).toDate(), DateTime(2026, 2, 3));
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.paidAmount, 400);
      expect(invoice.balanceAmount, 600);
      expect(invoice.status, 'partial');
      // The payment date never lands on the invoice (see `pay` helper note on
      // the fake's merge behaviour for why invoiceDate itself isn't asserted).
      expect(invoice.invoiceDate, isNot(DateTime(2026, 2, 3)));
    });

    testWidgets('Payment Date picker does not allow a future date', (tester) async {
      await service.createExpenseInvoice(_invoicePayload(amount: 1000));
      await pumpTab(tester, 'Expenses');

      await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.enterText(
        find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField)),
        DateFormat('MM/dd/yyyy').format(tomorrow),
      );
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      // The picker rejects it and stays open; the dialog keeps today's date.
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
      expect(find.text(DateFormat('dd MMM yyyy').format(tomorrow)), findsNothing);
    });

    // Payment Date on Salary is covered in finance_salary_payment_date_test.dart.
    testWidgets('Salary tab has no Edit/Delete actions', (tester) async {
      await service.createSalaryInvoice(_invoicePayload(amount: 1000, partyName: 'Staff A'));
      await pumpTab(tester, 'Salary');

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });
}
