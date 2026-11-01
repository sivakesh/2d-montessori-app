// Finance -> Salary -> Pay Invoice: the Payment Date field (same as the
// Expenses Pay Invoice dialog) defaults to today, accepts a past date, is
// persisted on the payment (finance_income.incomeDate) and its ledger entry
// (transactionDate), and leaves amount, partial-payment, balance and status
// behaviour unchanged. The recorded date(s) are then displayed on the
// Salary invoice card and in its details dialog.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

final _invoiceDate = DateTime(2026, 1, 10);

Map<String, dynamic> _salaryPayload({double amount = 5000}) => {
      'partyId': 'staff-1',
      'partyName': 'Malani D',
      'categoryName': 'Salary',
      'invoiceNo': 'INV-00010014',
      'invoiceDate': _invoiceDate,
      'dueDate': _invoiceDate,
      'amount': amount,
      'taxAmount': 0,
      'deductions': 0,
      'bonus': 0,
      'totalAmount': amount,
      'description': 'Salary',
      'attachmentUrl': '',
    };

void main() {
  late FakeFirebaseFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  Future<void> pumpSalaryTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Salary'));
    await tester.pumpAndSettle();
  }

  Future<void> enterPickerDate(WidgetTester tester, String mmddyyyy) async {
    await tester.tap(find.widgetWithText(TextButton, 'Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.edit_outlined)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField)),
      mmddyyyy,
    );
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('Salary Pay Invoice shows Payment Date defaulting to today', (tester) async {
    await service.createSalaryInvoice(_salaryPayload());
    await pumpSalaryTab(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Pay Invoice - Malani D'), findsOneWidget);
    expect(find.text('Payment Date *'), findsOneWidget);
    expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
    // Existing fields are still present.
    expect(find.widgetWithText(TextField, 'Amount'), findsOneWidget);
    expect(find.text('Payment Mode'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reference No'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Remarks'), findsOneWidget);
  });

  testWidgets('A selected past date is saved on the salary payment and its ledger entry', (tester) async {
    final id = await service.createSalaryInvoice(_salaryPayload());
    await pumpSalaryTab(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    await enterPickerDate(tester, '09/30/2026');
    expect(find.text('30 Sep 2026'), findsOneWidget);

    // Partial payment with reference and remarks.
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '3000');
    await tester.enterText(find.widgetWithText(TextField, 'Reference No'), 'SAL-REF-1');
    await tester.enterText(find.widgetWithText(TextField, 'Remarks'), 'September salary');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice payment saved'), findsOneWidget);

    final payments = await firestore.collection('finance_income').where('invoiceId', isEqualTo: id).get();
    expect(payments.docs, hasLength(1));
    final payment = payments.docs.single.data();
    expect((payment['incomeDate'] as Timestamp).toDate(), DateTime(2026, 9, 30));
    expect(payment['amount'], 3000);
    expect(payment['paymentMode'], 'cash');
    expect(payment['referenceNo'], 'SAL-REF-1');
    expect(payment['remarks'], 'September salary');
    expect(payment['invoiceType'], 'salary');
    // createdAt is still the server timestamp, not the payment date.
    expect((payment['createdAt'] as Timestamp).toDate(), isNot(DateTime(2026, 9, 30)));

    final ledger = await firestore.collection('finance_ledger').where('invoiceId', isEqualTo: id).get();
    expect(ledger.docs, hasLength(1));
    expect((ledger.docs.single.data()['transactionDate'] as Timestamp).toDate(), DateTime(2026, 9, 30));

    final invoice = (await service.getInvoiceById(id))!;
    expect(invoice.paidAmount, 3000);
    expect(invoice.balanceAmount, 2000);
    expect(invoice.status, 'partial');
    expect(invoice.invoiceDate, isNot(DateTime(2026, 9, 30)));
  });

  testWidgets('Salary Payment Date cannot be set in the future', (tester) async {
    await service.createSalaryInvoice(_salaryPayload());
    await pumpSalaryTab(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await enterPickerDate(tester, DateFormat('MM/dd/yyyy').format(tomorrow));

    // The picker rejects it and stays open; the dialog keeps today's date.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
  });

  test('historical salary payments without a date still load', () async {
    await firestore.collection('finance_income').doc('legacy-salary').set({
      'title': 'Salary Payment - Old',
      'amount': 1000,
      'programType': 'invoice',
      'invoiceType': 'salary',
      'invoiceId': 'old',
    });
    final income = await service.watchIncome().first;
    expect(income.single.incomeDate, isNull);
    final history = await service.getInvoicePayments('old');
    expect(history.single.amount, 1000);
  });

  group('Displaying salary payment dates', () {
    // fake_cloud_firestore's transaction mock ignores SetOptions(merge: true)
    // (see FinanceService.updateIncome), so payInvoice's merge write replaces
    // the invoice doc in tests; real Firestore merges. Restore the untouched
    // invoice fields so the invoice stays listed on the Salary tab.
    Future<void> pay(String invoiceId, double amount, DateTime paidOn) async {
      final ref = firestore.collection('finance_invoices').doc(invoiceId);
      final before = (await ref.get()).data()!;
      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'salary',
        amount: amount,
        paidDate: paidOn,
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      await ref.set({...before, ...(await ref.get()).data()!});
    }

    /// An older payment record written directly, with [incomeDate] as given
    /// (omitted when null) — e.g. legacy or malformed data.
    Future<void> seedLegacyPayment(String invoiceId, double amount, {Object? incomeDate}) async {
      await firestore.collection('finance_income').add({
        'title': 'Salary Payment - Malani D',
        'amount': amount,
        'programType': 'invoice',
        'sourceModule': 'invoice',
        'invoiceId': invoiceId,
        'invoiceType': 'salary',
        'paymentMode': 'cash',
        'incomeDate': ?incomeDate,
      });
      final ref = firestore.collection('finance_invoices').doc(invoiceId);
      final data = (await ref.get()).data()!;
      final paid = (data['paidAmount'] as num).toDouble() + amount;
      final total = (data['totalAmount'] as num).toDouble();
      await ref.set({
        ...data,
        'paidAmount': paid,
        'balanceAmount': total - paid,
        'status': paid >= total ? 'paid' : 'partial',
      });
    }

    Future<void> openDetails(WidgetTester tester) async {
      await tester.tap(find.text('INV-00010014'));
      await tester.pumpAndSettle();
    }

    testWidgets('single payment: card and details show its recorded date, distinct from invoice/created dates', (tester) async {
      final id = await service.createSalaryInvoice(_salaryPayload());
      await pay(id, 5000, DateTime(2026, 9, 30));
      await pumpSalaryTab(tester);

      expect(find.text('Payment Date: 30 Sep 2026'), findsOneWidget);

      await openDetails(tester);
      expect(find.text('Invoice Date'), findsOneWidget);
      expect(find.text('10 Jan 2026'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
      expect(find.text('Payment Date'), findsOneWidget);
      expect(find.text('30 Sep 2026'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reverse'), findsNothing);
    });

    testWidgets('multiple partial payments: each keeps its own date, no shared Payment Date', (tester) async {
      final id = await service.createSalaryInvoice(_salaryPayload());
      await pay(id, 2000, DateTime(2026, 9, 1));
      await pay(id, 1000, DateTime(2026, 9, 30));
      await pumpSalaryTab(tester);

      expect(find.text('Payment Dates: ₹2000 on 01 Sep 2026, ₹1000 on 30 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Payment Date:'), findsNothing);

      await openDetails(tester);
      expect(find.text('Payment Date'), findsNothing);
      // Each payment's own date in the payment history list.
      expect(find.text('01 Sep 2026 • cash'), findsOneWidget);
      expect(find.text('30 Sep 2026 • cash'), findsOneWidget);
    });

    testWidgets('older payment without a date shows "Not recorded", never a substitute date', (tester) async {
      final id = await service.createSalaryInvoice(_salaryPayload());
      await seedLegacyPayment(id, 5000);
      await pumpSalaryTab(tester);

      expect(find.text('Payment Date: Not recorded'), findsOneWidget);
      expect(find.textContaining('Payment Date: 10 Jan 2026'), findsNothing);

      await openDetails(tester);
      expect(find.text('Payment Date'), findsOneWidget);
      expect(find.text('Not recorded'), findsOneWidget);
    });

    testWidgets('a malformed stored date is handled safely', (tester) async {
      final id = await service.createSalaryInvoice(_salaryPayload());
      await seedLegacyPayment(id, 5000, incomeDate: 'not-a-date');
      await pumpSalaryTab(tester);
      expect(find.text('Payment Date: Not recorded'), findsOneWidget);
    });

    testWidgets('unpaid salary invoice shows no payment date', (tester) async {
      await service.createSalaryInvoice(_salaryPayload());
      await pumpSalaryTab(tester);
      expect(find.textContaining('Payment Date'), findsNothing);
    });
    // Expense payment dates: see finance_expense_payment_date_test.dart.
  });
}
