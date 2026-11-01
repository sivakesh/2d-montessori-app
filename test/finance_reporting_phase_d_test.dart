// Finance audit Phase D:
// - Part 1: the Dashboard shows the summary model's unclassified balance
//   (Unclassified card + explanation), and both Dashboard and Ledger show
//   how Cash + Bank + UPI + Unclassified make up the Closing Balance, all
//   read from FinanceDashboardSummaryModel (no UI recalculation).
// - Part 2: the Expense/Salary card's payment-date line distinguishes
//   loading, loaded with no payment, loaded with date(s), and lookup
//   failure (clear message + Retry, never a substitute date, no writes).
//
// Uses BufferedTransactionFirestore so payInvoice's merge writes keep the
// invoice's other fields, as real Firestore does.
import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';
import 'package:montessori_app/modules/finance/widgets/finance_summary_card.dart';

import 'support/buffered_transaction_firestore.dart';

/// Real FinanceService whose payment lookup can be held open ([gate]) or
/// made to fail ([failLookups]); everything else is unchanged.
class _LookupControlledFinanceService extends FinanceService {
  _LookupControlledFinanceService(BufferedTransactionFirestore firestore)
      : super(firestore: firestore, auth: MockFirebaseAuth());

  bool failLookups = false;
  Completer<void>? gate;
  int lookups = 0;

  @override
  Future<List<FinanceIncomeModel>> getInvoicePayments(String invoiceId) async {
    lookups++;
    if (gate != null) await gate!.future;
    if (failLookups) throw Exception('unavailable');
    return super.getInvoicePayments(invoiceId);
  }
}

Map<String, dynamic> _expensePayload({double amount = 5000}) => {
      'partyId': '',
      'partyName': 'School Owner',
      'categoryName': 'Rent',
      'invoiceNo': 'INV-00010030',
      'invoiceDate': DateTime(2026, 1, 10),
      'dueDate': DateTime(2026, 1, 10),
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
  late _LookupControlledFinanceService service;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    service = _LookupControlledFinanceService(firestore);
    await service.ensureDefaults();
  });

  void useLargeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    useLargeView(tester);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: service))));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  group('Part 1: unclassified balance and reconciliation', () {
    Future<String> accountIdByType(String type) async =>
        (await firestore.collection('finance_accounts').where('type', isEqualTo: type).get()).docs.single.id;

    var seq = 0;
    Future<void> addEntry(String accountId, double amount, {String entryType = 'income'}) async {
      seq++;
      await firestore.collection('finance_ledger').add({
        'entryType': entryType,
        'amount': amount,
        'accountId': accountId,
        'status': 'confirmed',
        'title': 'Entry $seq',
        'transactionDate': DateTime(2026, 9, 1),
        'createdAt': DateTime(2026, 9, 1).add(Duration(minutes: seq)),
      });
    }

    Future<void> setOpening(String type, double amount) async => firestore
        .collection('finance_accounts')
        .doc(await accountIdByType(type))
        .update({'openingBalance': amount, 'currentBalance': amount});

    const reconciliation = 'Closing Balance ₹16700 = Cash ₹14500 + Bank ₹0 + UPI ₹2000 + Unclassified ₹200';

    Future<void> seedWithUnclassified() async {
      await setOpening('cash', 10000);
      await setOpening('upi', 2000);
      final wallet = (await firestore.collection('finance_accounts').add({
        'name': 'Cash Box', 'type': 'wallet', 'openingBalance': 300, 'currentBalance': 300, 'isActive': true,
      })).id;
      await addEntry(await accountIdByType('cash'), 4500);
      await addEntry(wallet, 100, entryType: 'expense');
    }

    testWidgets('Dashboard shows the unclassified balance with its explanation', (tester) async {
      await seedWithUnclassified();
      await pumpScreen(tester);

      expect(find.widgetWithText(Container, 'Unclassified'), findsWidgets);
      expect(find.text('₹200'), findsOneWidget);
      expect(
        find.text('₹200 is not shown in Cash, Bank or UPI: it is the opening balances and/or transactions '
            "of accounts whose type can't be classified as Cash, Bank or UPI, or whose account is missing "
            '(includes ₹300 opening balance).'),
        findsOneWidget,
      );
      expect(find.text(reconciliation), findsOneWidget);
    });

    testWidgets('Cash + Bank + UPI + Unclassified reconcile with Closing Balance on Dashboard and Ledger', (tester) async {
      await seedWithUnclassified();
      final s = await service.watchDashboardSummary().first;
      expect(s.cashBalance + s.bankBalance + s.upiBalance + s.unclassifiedBalance, s.closingBalance);
      expect(s.closingBalance, 16700);

      await pumpScreen(tester);
      expect(find.text('₹14500'), findsOneWidget); // Cash card
      expect(find.text('₹2000'), findsOneWidget); // UPI card
      expect(find.text(reconciliation), findsOneWidget);

      await openTab(tester, 'Ledger');
      expect(find.text('₹16700'), findsOneWidget); // Closing Balance card
      expect(find.text(reconciliation), findsOneWidget); // same figures, same model
      expect(find.textContaining('₹200 is not shown in Cash, Bank or UPI'), findsOneWidget);
    });

    testWidgets('Dashboard card is labelled "Net Movement" and still shows income − expenses', (tester) async {
      await seedWithUnclassified(); // 10000 + 2000 + 300 opening; +4500 income, −100 expense
      final s = await service.watchDashboardSummary().first;
      expect(s.netBalance, s.totalIncome - s.totalExpenses);
      expect(s.netBalance, 4400);
      expect(s.closingBalance, 16700); // differs, so the card can't be showing it

      await pumpScreen(tester);
      expect(find.text('Net Balance'), findsNothing);
      final card = find.ancestor(of: find.text('Net Movement'), matching: find.byType(FinanceSummaryCard));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('₹4400')), findsOneWidget);
    });

    testWidgets('without an unclassified amount no Unclassified card or note is shown', (tester) async {
      await setOpening('cash', 1000);
      await addEntry(await accountIdByType('cash'), 500);
      await pumpScreen(tester);

      expect(find.text('Unclassified'), findsNothing);
      expect(find.textContaining('is not shown in Cash, Bank or UPI'), findsNothing);
      expect(find.text('Closing Balance ₹1500 = Cash ₹1500 + Bank ₹0 + UPI ₹0'), findsOneWidget);
    });
  });

  group('Part 2: payment-date lookup states', () {
    Future<String> pay(String invoiceId, double amount, DateTime paidOn) async => (await service.payInvoice(
          invoiceId: invoiceId,
          invoiceType: 'expense',
          amount: amount,
          paidDate: paidOn,
          paymentMode: 'cash',
          referenceNo: '',
          remarks: '',
        ))!;

    const collections = ['finance_invoices', 'finance_income', 'finance_ledger', 'finance_accounts'];
    Future<Map<String, Map<String, dynamic>?>> snapshotAll() async => {
          for (final c in collections)
            for (final d in (await firestore.collection(c).get()).docs) '$c/${d.id}': d.data(),
        };

    testWidgets('loading is shown while the lookup is pending, then the date', (tester) async {
      final id = await service.createExpenseInvoice(_expensePayload());
      await pay(id, 2000, DateTime(2026, 9, 30));
      service.gate = Completer<void>();
      await pumpScreen(tester);
      await openTab(tester, 'Expenses');

      expect(find.text('Loading payment date…'), findsOneWidget);
      expect(find.textContaining('Payment Date:'), findsNothing);

      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Loading payment date…'), findsNothing);
      expect(find.text('Payment Date: 30 Sep 2026'), findsOneWidget);
    });

    testWidgets('loaded with no active payment: nothing shown, not an error', (tester) async {
      final id = await service.createExpenseInvoice(_expensePayload());
      // Paid amount recorded without any linked payment record.
      final ref = firestore.collection('finance_invoices').doc(id);
      await ref.set({...(await ref.get()).data()!, 'paidAmount': 2000, 'balanceAmount': 3000, 'status': 'partial'});
      await pumpScreen(tester);
      await openTab(tester, 'Expenses');

      expect(service.lookups, greaterThan(0));
      expect(find.textContaining('Payment Date'), findsNothing);
      expect(find.textContaining("couldn't be loaded"), findsNothing);
      expect(find.text('Loading payment date…'), findsNothing);
    });

    testWidgets('partial payments list each date; a reversed payment is excluded', (tester) async {
      final id = await service.createExpenseInvoice(_expensePayload());
      await pay(id, 2000, DateTime(2026, 9, 1));
      final mistaken = await pay(id, 500, DateTime(2026, 9, 15));
      await pay(id, 1000, DateTime(2026, 9, 30));
      await service.reverseExpenseInvoicePayment(paymentId: mistaken, reason: 'Recorded by mistake');
      await pumpScreen(tester);
      await openTab(tester, 'Expenses');

      expect(find.text('Payment Dates: ₹2000 on 01 Sep 2026, ₹1000 on 30 Sep 2026'), findsOneWidget);
      expect(find.textContaining('15 Sep 2026'), findsNothing);
    });

    testWidgets('a lookup failure is shown clearly, offers Retry and writes nothing', (tester) async {
      final id = await service.createExpenseInvoice(_expensePayload());
      await pay(id, 2000, DateTime(2026, 9, 1));
      await pay(id, 1000, DateTime(2026, 9, 30));
      final before = await snapshotAll();
      service.failLookups = true;
      await pumpScreen(tester);
      await openTab(tester, 'Expenses');

      expect(find.text("Payment date couldn't be loaded."), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      // No fabricated or substitute date (invoice date is 10 Jan 2026).
      expect(find.textContaining('Payment Date'), findsNothing);
      expect(find.textContaining('10 Jan 2026'), findsNothing);
      // The invoice's own figures and actions are unaffected.
      expect(find.text('INV-00010030'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);

      // Details dialog: clear message, no Payment Date row.
      await tester.tap(find.text('INV-00010030'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load payments, so the payment date can't be shown"), findsOneWidget);
      expect(find.text('Payment Date'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(await snapshotAll(), before);

      // Retry once the lookup works again.
      service.failLookups = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text("Payment date couldn't be loaded."), findsNothing);
      expect(find.text('Payment Dates: ₹2000 on 01 Sep 2026, ₹1000 on 30 Sep 2026'), findsOneWidget);
      expect(await snapshotAll(), before);
    });

    testWidgets('Salary cards use the same states', (tester) async {
      final id = await service.createSalaryInvoice({..._expensePayload(), 'partyName': 'Malani D', 'invoiceNo': 'INV-00010031'});
      await service.payInvoice(
        invoiceId: id, invoiceType: 'salary', amount: 5000, paidDate: DateTime(2026, 9, 5),
        paymentMode: 'cash', referenceNo: '', remarks: '',
      );
      service.failLookups = true;
      await pumpScreen(tester);
      await openTab(tester, 'Salary');
      expect(find.text("Payment date couldn't be loaded."), findsOneWidget);

      service.failLookups = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Date: 05 Sep 2026'), findsOneWidget);
    });
  });
}
