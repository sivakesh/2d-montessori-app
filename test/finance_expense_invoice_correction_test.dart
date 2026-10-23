// Covers correcting Finance -> Expenses invoices that already have
// payments:
// - Descriptive edits keep the invoice number, amount, and every payment
//   record (date, mode, reference, remarks) intact; the edit form never
//   rounds the stored amount.
// - Amount edits can't drop the total below what has been paid.
// - A payment recorded by mistake is reversed without erasing it: the
//   original is kept (marked reversed), its ledger entry is cancelled, the
//   account balance and invoice balance are restored, and it can't be
//   reversed twice.
// - An invoice raised by mistake is cancelled (kept for audit) only once it
//   has no active payments; it can't be cancelled twice, edited, paid, or
//   deleted, and drops out of active totals.
// - Deletion protections are unchanged; Salary invoices are unaffected.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

final _invoiceDate = DateTime(2026, 1, 10);
final _paidOn = DateTime(2026, 2, 3);

Map<String, dynamic> _invoicePayload({
  double amount = 5000,
  String invoiceNo = 'INV-00010013',
  String partyName = 'Vendor A',
}) {
  return {
    'partyId': '',
    'partyName': partyName,
    'categoryName': 'Vendor Payment',
    'invoiceNo': invoiceNo,
    'invoiceDate': _invoiceDate,
    'dueDate': _invoiceDate,
    'amount': amount,
    'taxAmount': 0,
    'deductions': 0,
    'bonus': 0,
    'totalAmount': amount,
    'description': 'Original description',
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

  CollectionReference<Map<String, dynamic>> invoices() => firestore.collection('finance_invoices');
  CollectionReference<Map<String, dynamic>> income() => firestore.collection('finance_income');
  CollectionReference<Map<String, dynamic>> ledger() => firestore.collection('finance_ledger');
  CollectionReference<Map<String, dynamic>> accounts() => firestore.collection('finance_accounts');

  Future<Map<String, double>> accountBalances() async {
    final snap = await accounts().get();
    return {for (final d in snap.docs) d.id: (d.data()['currentBalance'] as num?)?.toDouble() ?? 0};
  }

  // fake_cloud_firestore's transaction mock ignores SetOptions(merge: true)
  // (see FinanceService.updateIncome's doc comment), so payInvoice's merge
  // writes replace the invoice and account docs in tests. Real Firestore
  // merges; restore the untouched fields so later steps see realistic docs.
  Future<String> pay(String invoiceId, double amount, {String type = 'expense'}) async {
    final invoiceBefore = (await invoices().doc(invoiceId).get()).data()!;
    final accountsBefore = {for (final d in (await accounts().get()).docs) d.id: d.data()};
    final paymentId = await service.payInvoice(
      invoiceId: invoiceId,
      invoiceType: type,
      amount: amount,
      paidDate: _paidOn,
      paymentMode: 'cash',
      referenceNo: 'REF-1',
      remarks: 'Paid at counter',
    );
    final invoiceAfter = (await invoices().doc(invoiceId).get()).data()!;
    await invoices().doc(invoiceId).set({...invoiceBefore, ...invoiceAfter});
    for (final entry in accountsBefore.entries) {
      final after = (await accounts().doc(entry.key).get()).data() ?? {};
      await accounts().doc(entry.key).set({...entry.value, ...after});
    }
    return paymentId!;
  }

  Future<void> editDescriptive(String id, {double amount = 5000}) => service.updateExpenseInvoice(
        id: id,
        partyName: 'Vendor Corrected',
        categoryName: 'Utilities',
        invoiceDate: DateTime(2026, 1, 15),
        amount: amount,
        taxAmount: 0,
        description: 'Corrected description',
        attachmentUrl: 'https://example.com/bill.pdf',
      );

  group('Editing an invoice with recorded payments', () {
    test('descriptive edits keep the invoice number, amount and payment records intact', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      final paymentBefore = (await income().doc(paymentId).get()).data()!;
      final ledgerBefore = (await ledger().where('invoiceId', isEqualTo: id).get()).docs.single.data();

      await editDescriptive(id);

      expect((await invoices().get()).docs, hasLength(1));
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.invoiceNo, 'INV-00010013');
      expect(invoice.partyName, 'Vendor Corrected');
      expect(invoice.categoryName, 'Utilities');
      expect(invoice.description, 'Corrected description');
      expect(invoice.attachmentUrl, 'https://example.com/bill.pdf');
      expect(invoice.invoiceDate, DateTime(2026, 1, 15));
      expect(invoice.totalAmount, 5000);
      expect(invoice.paidAmount, 2000);
      expect(invoice.balanceAmount, 3000);
      expect(invoice.status, 'partial');

      final paymentAfter = (await income().doc(paymentId).get()).data()!;
      expect(paymentAfter, paymentBefore);
      expect((paymentAfter['incomeDate'] as Timestamp).toDate(), _paidOn);
      expect(paymentAfter['paymentMode'], 'cash');
      expect(paymentAfter['referenceNo'], 'REF-1');
      expect(paymentAfter['remarks'], 'Paid at counter');
      expect((await ledger().where('invoiceId', isEqualTo: id).get()).docs.single.data(), ledgerBefore);
    });

    test('an amount change recalculates balance and status; below-paid totals are rejected', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await pay(id, 2000);

      await editDescriptive(id, amount: 4000);
      var invoice = (await service.getInvoiceById(id))!;
      expect(invoice.balanceAmount, 2000);
      expect(invoice.status, 'partial');

      await editDescriptive(id, amount: 2000);
      invoice = (await service.getInvoiceById(id))!;
      expect(invoice.balanceAmount, 0);
      expect(invoice.status, 'paid');

      await expectLater(editDescriptive(id, amount: 1999), throwsStateError);
      invoice = (await service.getInvoiceById(id))!;
      expect(invoice.totalAmount, 2000);
      expect(invoice.paidAmount, 2000);
    });
  });

  group('Reversing a payment recorded by mistake', () {
    test('keeps the original payment, cancels its ledger entry, restores balances', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final balancesBefore = await accountBalances();
      final paymentId = await pay(id, 2000);
      expect((await service.watchDashboardSummary().first).totalExpenses, 2000);
      final original = (await income().doc(paymentId).get()).data()!;

      await service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Entered against wrong invoice');

      final reversed = (await income().doc(paymentId).get()).data()!;
      // Original transaction preserved field-for-field, plus reversal audit.
      for (final key in ['amount', 'incomeDate', 'paymentMode', 'referenceNo', 'remarks', 'invoiceId', 'invoiceNo', 'ledgerEntryId']) {
        expect(reversed[key], original[key], reason: key);
      }
      expect(reversed['isDeleted'], isTrue);
      expect(reversed['reversalReason'], 'Entered against wrong invoice');
      expect(reversed['reversedAt'], isNotNull);
      expect(reversed['reversedBy'], isNotEmpty);
      expect(reversed['deletedAt'], isNotNull);

      final ledgerDoc = (await ledger().where('invoiceId', isEqualTo: id).get()).docs.single.data();
      expect(ledgerDoc['status'], 'cancelled');
      expect(ledgerDoc['amount'], 2000);

      expect(await accountBalances(), balancesBefore);
      expect((await service.watchDashboardSummary().first).totalExpenses, 0);

      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.paidAmount, 0);
      expect(invoice.balanceAmount, 5000);
      expect(invoice.status, 'unpaid');
      expect(invoice.totalAmount, 5000);

      // Still listed in the invoice's payment history, as reversed.
      final history = await service.getInvoicePayments(id);
      expect(history.single.isDeleted, isTrue);
    });

    test('a payment cannot be reversed twice', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      await service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Mistake');
      final balances = await accountBalances();

      await expectLater(
        service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Again'),
        throwsStateError,
      );
      expect(await accountBalances(), balances);
      expect((await service.getInvoiceById(id))!.paidAmount, 0);
    });

    test('requires a reason and only applies to expense invoice payments', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      await expectLater(service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: '  '), throwsStateError);

      final salaryId = await service.createSalaryInvoice(_invoicePayload(invoiceNo: 'SAL-1'));
      final salaryPaymentId = await pay(salaryId, 1000, type: 'salary');
      await expectLater(
        service.reverseExpenseInvoicePayment(paymentId: salaryPaymentId, reason: 'x'),
        throwsStateError,
      );
      expect((await income().doc(salaryPaymentId).get()).data()!['isDeleted'], isNot(true));
    });

    test('reversing one of two payments leaves the other intact', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final first = await pay(id, 2000);
      final second = await pay(id, 1000);

      await service.reverseExpenseInvoicePayment(paymentId: first, reason: 'Duplicate entry');

      expect((await income().doc(second).get()).data()!['isDeleted'], isNot(true));
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.paidAmount, 1000);
      expect(invoice.balanceAmount, 4000);
      expect(invoice.status, 'partial');
      expect((await service.watchDashboardSummary().first).totalExpenses, 1000);
    });
  });

  group('Cancelling an invoice raised by mistake', () {
    test('is refused while the invoice has active payments', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await pay(id, 2000);
      await expectLater(service.cancelExpenseInvoice(id: id, reason: 'Wrong vendor'), throwsStateError);
      expect((await service.getInvoiceById(id))!.status, 'partial');
    });

    test('after reversing its mistaken payment, cancels and keeps an audit record', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      await service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Recorded by mistake');

      await service.cancelExpenseInvoice(id: id, reason: 'Invoice raised by mistake');

      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.status, 'cancelled');
      expect(invoice.cancellationReason, 'Invoice raised by mistake');
      expect(invoice.cancelledAt, isNotNull);
      expect(invoice.cancelledBy, isNotEmpty);
      expect(invoice.balanceAmount, 0);
      expect(invoice.totalAmount, 5000);
      expect(invoice.invoiceNo, 'INV-00010013');
      // Payment history is preserved.
      expect((await income().doc(paymentId).get()).exists, isTrue);
      expect((await ledger().where('invoiceId', isEqualTo: id).get()).docs, hasLength(1));
    });

    test('an unpaid invoice can be cancelled; repeat cancellation is refused', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await expectLater(service.cancelExpenseInvoice(id: id, reason: ''), throwsStateError);
      await service.cancelExpenseInvoice(id: id, reason: 'Duplicate invoice');
      await expectLater(service.cancelExpenseInvoice(id: id, reason: 'Again'), throwsStateError);
      expect((await service.getInvoiceById(id))!.cancellationReason, 'Duplicate invoice');
    });

    test('a cancelled invoice cannot be paid, edited or deleted', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await service.cancelExpenseInvoice(id: id, reason: 'Mistake');

      await expectLater(
        service.payInvoice(
          invoiceId: id,
          invoiceType: 'expense',
          amount: 100,
          paidDate: _paidOn,
          paymentMode: 'cash',
          referenceNo: '',
          remarks: '',
        ),
        throwsStateError,
      );
      expect((await income().where('invoiceId', isEqualTo: id).get()).docs, isEmpty);
      await expectLater(editDescriptive(id), throwsStateError);
      await expectLater(service.deleteExpenseInvoice(id), throwsStateError);
      expect(await service.getInvoiceById(id), isNotNull);
    });

    test('salary invoices cannot be cancelled here', () async {
      final id = await service.createSalaryInvoice(_invoicePayload(invoiceNo: 'SAL-1'));
      await expectLater(service.cancelExpenseInvoice(id: id, reason: 'x'), throwsStateError);
    });
  });

  group('Deletion protections are unchanged', () {
    test('unpaid invoice with no payments is still deletable', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await service.deleteExpenseInvoice(id);
      expect(await service.getInvoiceById(id), isNull);
    });

    test('an invoice with payments, even reversed ones, cannot be permanently deleted', () async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      await expectLater(service.deleteExpenseInvoice(id), throwsStateError);

      await service.reverseExpenseInvoicePayment(paymentId: paymentId, reason: 'Mistake');
      await expectLater(service.deleteExpenseInvoice(id), throwsStateError);
      expect(await service.getInvoiceById(id), isNotNull);
      expect((await income().doc(paymentId).get()).exists, isTrue);
    });

    test('salary invoice payments still work as before', () async {
      final id = await service.createSalaryInvoice(_invoicePayload(invoiceNo: 'SAL-1'));
      await pay(id, 1000, type: 'salary');
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.paidAmount, 1000);
      expect(invoice.status, 'partial');
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

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('INV-00010013: reverse the mistaken ₹2,000 payment, then cancel the invoice', (tester) async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      final paymentId = await pay(id, 2000);
      await pumpTab(tester, 'Expenses');

      // Cancel is blocked while the payment is active.
      await tapAndSettle(tester, find.byTooltip('Cancel Invoice'));
      expect(find.text('Cannot Cancel Invoice'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'OK'));

      // Open the invoice and reverse the payment from its history.
      await tapAndSettle(tester, find.text('INV-00010013'));
      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('₹2000'), findsWidgets);
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Reverse'));
      expect(find.text('Reverse Payment'), findsWidgets);

      // A reason is required.
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Reverse Payment'));
      expect(find.text('Reason is required'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reason *'), 'Recorded by mistake');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Reverse Payment'));
      expect(find.text('Payment reversed'), findsOneWidget);
      expect((await income().doc(paymentId).get()).data()!['isDeleted'], isTrue);

      // Now cancel. (Dismiss the previous snackbar so the next one isn't queued.)
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byTooltip('Cancel Invoice'));
      expect(find.text('Cancel Expense Invoice'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reason *'), 'Invoice raised by mistake');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Cancel Invoice'));
      expect(find.text('Expense invoice cancelled'), findsOneWidget);

      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Cancelled: Invoice raised by mistake'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pay'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
      expect(find.byTooltip('Cancel Invoice'), findsNothing);
      // Cancelled invoice no longer counts in the Expenses totals.
      expect(find.text('₹5000'), findsOneWidget); // only the card's own Amount stat
      expect((await service.getInvoiceById(id))!.status, 'cancelled');

      // Its details still show the reversed payment for audit.
      await tapAndSettle(tester, find.text('INV-00010013'));
      expect(find.text('REVERSED'), findsOneWidget);
      expect(find.text('Cancel Reason'), findsOneWidget);
    });

    testWidgets('Backing out of the cancel dialog leaves the invoice unchanged', (tester) async {
      final id = await service.createExpenseInvoice(_invoicePayload());
      await pumpTab(tester, 'Expenses');
      await tapAndSettle(tester, find.byTooltip('Cancel Invoice'));
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Back'));
      expect((await service.getInvoiceById(id))!.status, 'unpaid');
    });

    testWidgets('Editing a paid invoice pre-fills the exact amount and blocks totals below paid', (tester) async {
      await firestore.collection('finance_categories').add({'name': 'Vendor Payment', 'type': 'expense', 'isActive': true});
      final id = await service.createExpenseInvoice(_invoicePayload(amount: 2500.5));
      await pay(id, 2000);
      await pumpTab(tester, 'Expenses');

      await tapAndSettle(tester, find.byTooltip('Edit'));
      expect(find.widgetWithText(TextFormField, '2500.5'), findsOneWidget);
      expect(find.textContaining('already paid'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, '2500.5'), '1500');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('Total cannot be less than ₹2000 already paid'), findsOneWidget);
      expect((await service.getInvoiceById(id))!.totalAmount, 2500.5);

      // A descriptive-only edit keeps the exact stored amount.
      await tester.enterText(find.widgetWithText(TextFormField, '1500'), '2500.5');
      await tester.enterText(find.widgetWithText(TextFormField, 'Original description'), 'Fixed description');
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('Expense invoice updated'), findsOneWidget);
      final invoice = (await service.getInvoiceById(id))!;
      expect(invoice.totalAmount, 2500.5);
      expect(invoice.description, 'Fixed description');
      expect(invoice.paidAmount, 2000);
      expect(invoice.balanceAmount, 500.5);
    });

    testWidgets('Salary tab has no Cancel action or payment reversal', (tester) async {
      final id = await service.createSalaryInvoice(_invoicePayload(invoiceNo: 'SAL-1', partyName: 'Staff A'));
      await pay(id, 1000, type: 'salary');
      await pumpTab(tester, 'Salary');
      expect(find.byTooltip('Cancel Invoice'), findsNothing);
      await tapAndSettle(tester, find.text('SAL-1'));
      expect(find.text('Payments'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Reverse'), findsNothing);
    });
  });
}
