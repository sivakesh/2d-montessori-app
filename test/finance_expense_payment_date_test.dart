// Finance -> Expenses: actual payment dates (finance_income.incomeDate on
// each payment linked by invoiceId) are shown on the Expense invoice card
// and in its details dialog, mirroring the Salary presentation. Reversed
// payments are excluded, missing/malformed dates read "Not recorded", and
// unpaid or cancelled invoices show no payment date.
//
// Uses BufferedTransactionFirestore so payInvoice's merge writes keep the
// invoice's other fields, as real Firestore does.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

import 'support/buffered_transaction_firestore.dart';

final _invoiceDate = DateTime(2026, 1, 10);

Map<String, dynamic> _expensePayload({double amount = 5000}) => {
      'partyId': '',
      'partyName': 'School Owner',
      'categoryName': 'Rent',
      'invoiceNo': 'INV-00010020',
      'invoiceDate': _invoiceDate,
      'dueDate': _invoiceDate,
      'amount': amount,
      'taxAmount': 0,
      'deductions': 0,
      'bonus': 0,
      'totalAmount': amount,
      'description': 'Rent',
      'attachmentUrl': '',
    };

void main() {
  late BufferedTransactionFirestore firestore;
  late FinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = FinanceService(firestore: firestore, auth: MockFirebaseAuth());
    await service.ensureDefaults();
  });

  Future<String> pay(String invoiceId, double amount, DateTime paidOn) async => (await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: amount,
        paidDate: paidOn,
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      ))!;

  /// An older payment record written directly, with [incomeDate] as given
  /// (omitted when null) — e.g. legacy or malformed data.
  Future<void> seedLegacyPayment(String invoiceId, double amount, {Object? incomeDate}) async {
    await firestore.collection('finance_income').add({
      'title': 'Expense Payment - School Owner',
      'amount': amount,
      'programType': 'invoice',
      'sourceModule': 'invoice',
      'invoiceId': invoiceId,
      'invoiceType': 'expense',
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

  Future<void> pumpExpensesTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Expenses'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.text('INV-00010020'));
    await tester.pumpAndSettle();
  }

  testWidgets('single payment: card and details show its date, distinct from invoice/created dates', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    await pay(id, 2000, DateTime(2026, 9, 30));
    await pumpExpensesTab(tester);

    expect(find.text('Payment Date: 30 Sep 2026'), findsOneWidget);
    // Existing card actions are unchanged (partially paid invoice).
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byTooltip('Cancel Invoice'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);

    await openDetails(tester);
    expect(find.text('Invoice Date'), findsOneWidget);
    expect(find.text('10 Jan 2026'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text(DateFormat('dd MMM yyyy').format(DateTime.now())), findsOneWidget);
    expect(find.text('Payment Date'), findsOneWidget);
    expect(find.text('30 Sep 2026'), findsOneWidget);
    // Existing payment history with Reverse is unchanged.
    expect(find.text('30 Sep 2026 • cash'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reverse'), findsOneWidget);
  });

  testWidgets('multiple partial payments: each amount with its own date, no shared date', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    await pay(id, 2000, DateTime(2026, 9, 1));
    await pay(id, 1000, DateTime(2026, 9, 30));
    await pumpExpensesTab(tester);

    expect(find.text('Payment Dates: ₹2000 on 01 Sep 2026, ₹1000 on 30 Sep 2026'), findsOneWidget);
    expect(find.textContaining('Payment Date:'), findsNothing);

    await openDetails(tester);
    expect(find.text('Payment Date'), findsNothing);
    expect(find.text('01 Sep 2026 • cash'), findsOneWidget);
    expect(find.text('30 Sep 2026 • cash'), findsOneWidget);
  });

  testWidgets('a reversed payment is excluded from the displayed dates', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    final mistaken = await pay(id, 2000, DateTime(2026, 9, 1));
    await pay(id, 1000, DateTime(2026, 9, 30));
    await service.reverseExpenseInvoicePayment(paymentId: mistaken, reason: 'Recorded by mistake');
    await pumpExpensesTab(tester);

    expect(find.text('Payment Date: 30 Sep 2026'), findsOneWidget);
    expect(find.textContaining('01 Sep 2026'), findsNothing);

    await openDetails(tester);
    expect(find.text('Payment Date'), findsOneWidget);
    expect(find.text('30 Sep 2026'), findsOneWidget);
    // Still listed in history for audit, marked reversed.
    expect(find.text('REVERSED'), findsOneWidget);
  });

  testWidgets('a cancelled invoice (payment reversed) shows no payment date', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    final paymentId = await pay(id, 2000, DateTime(2026, 9, 1));
    await service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Mistake');
    await service.cancelExpenseInvoice(id: id, reason: 'Raised by mistake');
    await pumpExpensesTab(tester);

    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.textContaining('Payment Date'), findsNothing);

    await openDetails(tester);
    expect(find.text('Payment Date'), findsNothing);
    expect(find.text('REVERSED'), findsOneWidget);
  });

  testWidgets('missing payment date shows "Not recorded", never a substitute date', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    await seedLegacyPayment(id, 5000);
    await pumpExpensesTab(tester);

    expect(find.text('Payment Date: Not recorded'), findsOneWidget);
    expect(find.textContaining('Payment Date: 10 Jan 2026'), findsNothing);

    await openDetails(tester);
    expect(find.text('Payment Date'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
  });

  testWidgets('a malformed stored date is handled safely', (tester) async {
    final id = await service.createExpenseInvoice(_expensePayload());
    await seedLegacyPayment(id, 5000, incomeDate: 'not-a-date');
    await pumpExpensesTab(tester);
    expect(find.text('Payment Date: Not recorded'), findsOneWidget);
  });

  testWidgets('unpaid invoice shows no payment date', (tester) async {
    await service.createExpenseInvoice(_expensePayload());
    await pumpExpensesTab(tester);
    expect(find.text('INV-00010020'), findsOneWidget);
    expect(find.textContaining('Payment Date'), findsNothing);

    await openDetails(tester);
    expect(find.text('Payment Date'), findsNothing);
    expect(find.text('No payments recorded.'), findsOneWidget);
  });
}
