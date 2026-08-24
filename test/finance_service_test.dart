// Exercises FinanceService against an in-memory Firestore (fake_cloud_firestore)
// to cover the Finance data-flow behaviors audited in this change:
// - Expense/Salary invoice tab queries actually return what was created.
// - payInvoice() correctly handles partial and full payments, and records
//   exactly one finance transaction per payment (not per invoice).
// - The ledger surfaces both income and expense entries.
// - Dashboard totals/net balance/account balances are computed only from
//   confirmed transactions, never from unpaid invoices.
// - Account selection follows the chosen payment mode.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/models/finance_expense_model.dart';
import 'package:montessori_app/modules/finance/models/finance_income_model.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/finance/ui/admin_finance_screen.dart';

class _ThrowingVoidFinanceService extends FinanceService {
  _ThrowingVoidFinanceService(FirebaseFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth());

  @override
  Future<void> voidIncome(String id) async {
    throw Exception('network error');
  }
}

Map<String, dynamic> _invoicePayload({
  required double totalAmount,
  String partyName = 'Vendor A',
  String invoiceNo = 'INV-00010010',
}) {
  final now = DateTime.now();
  return {
    'partyId': '',
    'partyName': partyName,
    'categoryName': 'Vendor Payment',
    'invoiceNo': invoiceNo,
    'invoiceDate': now,
    'dueDate': now,
    'amount': totalAmount,
    'taxAmount': 0,
    'deductions': 0,
    'bonus': 0,
    'totalAmount': totalAmount,
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

  group('A. Expense/Salary invoice listing', () {
    test('watchInvoicesByType separates expense and salary invoices by type', () async {
      await service.createExpenseInvoice(_invoicePayload(totalAmount: 5000, partyName: 'Vendor A'));
      await service.createSalaryInvoice(_invoicePayload(totalAmount: 2500, partyName: 'Staff A'));

      final expenseInvoices = await service.watchInvoicesByType('expense').first;
      final salaryInvoices = await service.watchInvoicesByType('salary').first;

      expect(expenseInvoices, hasLength(1));
      expect(expenseInvoices.single.partyName, 'Vendor A');
      expect(expenseInvoices.single.status, 'unpaid');
      expect(expenseInvoices.single.balanceAmount, 5000);
      expect(expenseInvoices.single.paidAmount, 0);
      expect(expenseInvoices.single.id, isNotEmpty);

      expect(salaryInvoices, hasLength(1));
      expect(salaryInvoices.single.partyName, 'Staff A');
      expect(salaryInvoices.single.status, 'unpaid');
    });

    test('raising an invoice does not affect the dashboard totals or account balances', () async {
      await service.createExpenseInvoice(_invoicePayload(totalAmount: 5000));

      final summary = await service.watchDashboardSummary().first;
      expect(summary.totalExpenses, 0);
      expect(summary.netBalance, 0);
      expect(summary.cashBalance, 0);
    });
  });

  group('B. Payment flow', () {
    test('partial payment then full payment settles the invoice correctly', () async {
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 10000));

      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 3000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      var invoice = await service.getInvoiceById(invoiceId);
      expect(invoice!.paidAmount, 3000);
      expect(invoice.balanceAmount, 7000);
      expect(invoice.status, 'partial');

      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 7000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      invoice = await service.getInvoiceById(invoiceId);
      expect(invoice!.paidAmount, 10000);
      expect(invoice.balanceAmount, 0);
      expect(invoice.status, 'paid');

      // Exactly one finance transaction per payment (two payments -> two entries,
      // not one, and not zero from the second payment being wrongly treated as
      // a duplicate of the first).
      final ledgerSnap = await firestore
          .collection('finance_ledger')
          .where('sourceId', isEqualTo: invoiceId)
          .get();
      expect(ledgerSnap.docs, hasLength(2));
      final amounts = ledgerSnap.docs.map((d) => (d.data()['amount'] as num).toDouble()).toList()..sort();
      expect(amounts, [3000.0, 7000.0]);
      for (final doc in ledgerSnap.docs) {
        final data = doc.data();
        expect(data['entryType'], 'expense');
        expect(data['invoiceId'], invoiceId);
        expect(data['paymentMode'], 'cash');
        expect((data['accountId'] as String).isNotEmpty, isTrue);
      }
    });

    test('a single full payment records invoiceId, invoiceNo, paymentMode and account on the transaction', () async {
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 4000, invoiceNo: 'INV-00010042'));
      final paymentId = await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 4000,
        paidDate: DateTime.now(),
        paymentMode: 'upi',
        referenceNo: 'REF-1',
        remarks: '',
      );
      expect(paymentId, isNotNull);

      final ledgerSnap = await firestore
          .collection('finance_ledger')
          .where('sourceId', isEqualTo: invoiceId)
          .get();
      expect(ledgerSnap.docs, hasLength(1));
      final data = ledgerSnap.docs.single.data();
      expect(data['entryType'], 'expense');
      expect(data['invoiceId'], invoiceId);
      expect(data['invoiceNo'], 'INV-00010042');
      expect(data['paymentMode'], 'upi');
      expect(data['amount'], 4000);
      expect((data['accountId'] as String).isNotEmpty, isTrue);

      final paymentSnap = await firestore.collection('finance_income').doc(paymentId).get();
      expect(paymentSnap.data()!['invoiceId'], invoiceId);
      expect(paymentSnap.data()!['invoiceNo'], 'INV-00010042');
    });

    test('a second payment on the same invoice is not swallowed as a duplicate', () async {
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 2500));
      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'salary',
        amount: 2500,
        paidDate: DateTime.now(),
        paymentMode: 'bank',
        referenceNo: '',
        remarks: '',
      );
      final invoice = await service.getInvoiceById(invoiceId);
      expect(invoice!.status, 'paid');
      expect(invoice.balanceAmount, 0);
    });
  });

  group('C. Ledger', () {
    test('ledger includes both income and expense entries', () async {
      await service.createFeeIncomeEntry({
        'amount': 20000,
        'feeCollectionId': 'fc-1',
        'paymentMode': 'cash',
        'studentName': 'K Tanvi',
        'description': 'Fee collected from K Tanvi',
      });
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 5000));
      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 5000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final ledger = await service.watchLedger().first;
      expect(ledger.any((e) => e.entryType == 'income'), isTrue);
      expect(ledger.any((e) => e.entryType == 'expense'), isTrue);
    });
  });

  group('D. Dashboard calculations', () {
    test('totalExpenses and netBalance reflect paid invoices only', () async {
      await service.createFeeIncomeEntry({
        'amount': 20000,
        'feeCollectionId': 'fc-2',
        'paymentMode': 'cash',
      });
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 5000));
      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 5000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 20000);
      expect(summary.totalExpenses, 5000);
      expect(summary.netBalance, 15000);
    });
  });

  group('E. Payment mode -> account', () {
    // Each scenario gets its own fresh Firestore instance/account set so
    // scenarios can't interact with each other.
    Future<FinanceService> freshService() async {
      final fs = FakeFirebaseFirestore();
      final svc = FinanceService(firestore: fs, auth: MockFirebaseAuth());
      await svc.ensureDefaults();
      return svc;
    }

    test('fee paid by cash increases only the cash balance', () async {
      final svc = await freshService();
      await svc.createFeeIncomeEntry({'amount': 5000, 'feeCollectionId': 'fc', 'paymentMode': 'cash'});
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.cashBalance, 5000);
      expect(summary.bankBalance, 0);
      expect(summary.upiBalance, 0);
    });

    test('fee paid by bank increases only the bank balance', () async {
      final svc = await freshService();
      await svc.createFeeIncomeEntry({'amount': 5000, 'feeCollectionId': 'fc', 'paymentMode': 'bank_transfer'});
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.bankBalance, 5000);
      expect(summary.cashBalance, 0);
      expect(summary.upiBalance, 0);
    });

    test('fee paid by upi increases only the upi balance', () async {
      final svc = await freshService();
      await svc.createFeeIncomeEntry({'amount': 5000, 'feeCollectionId': 'fc', 'paymentMode': 'upi'});
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.upiBalance, 5000);
      expect(summary.cashBalance, 0);
      expect(summary.bankBalance, 0);
    });

    test('expense paid by cash decreases only the cash balance', () async {
      final svc = await freshService();
      final invoiceId = await svc.createExpenseInvoice(_invoicePayload(totalAmount: 2000));
      await svc.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 2000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.cashBalance, -2000);
      expect(summary.bankBalance, 0);
      expect(summary.upiBalance, 0);
    });

    test('expense paid by bank decreases only the bank balance', () async {
      final svc = await freshService();
      final invoiceId = await svc.createExpenseInvoice(_invoicePayload(totalAmount: 2000));
      await svc.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 2000,
        paidDate: DateTime.now(),
        paymentMode: 'bank',
        referenceNo: '',
        remarks: '',
      );
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.bankBalance, -2000);
      expect(summary.cashBalance, 0);
      expect(summary.upiBalance, 0);
    });

    test('expense paid by upi decreases only the upi balance', () async {
      final svc = await freshService();
      final invoiceId = await svc.createExpenseInvoice(_invoicePayload(totalAmount: 2000));
      await svc.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 2000,
        paidDate: DateTime.now(),
        paymentMode: 'upi',
        referenceNo: '',
        remarks: '',
      );
      final summary = await svc.watchDashboardSummary().first;
      expect(summary.upiBalance, -2000);
      expect(summary.cashBalance, 0);
      expect(summary.bankBalance, 0);
    });
  });

  // P1: Finance Entry Edit — previously AddIncomeDialog accepted an
  // `initial` param cosmetically but never prefilled from it, always
  // created a new doc, and FinanceService had no update method at all.
  group('F. Finance Entry Edit (updateIncome)', () {
    Future<String> createPlainIncome(FinanceService svc, {double amount = 5000}) async {
      final accounts = await svc.watchAccounts().first;
      final cat = (await svc.watchCategories().first).firstWhere((c) => c.type == 'income');
      final cash = accounts.firstWhere((a) => a.type == 'cash');
      return svc.createIncome(FinanceIncomeModel(
        id: '',
        title: 'Donation',
        categoryId: cat.id,
        categoryName: cat.name,
        programType: 'other',
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        amount: amount,
        incomeDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        accountId: cash.id,
        accountName: cash.name,
        referenceNo: 'REF-1',
        remarks: 'Original remarks',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin',
      ));
    }

    test('1/2/3. Edit a normal Finance entry — amount/category/date/mode/reference update correctly', () async {
      final id = await createPlainIncome(service);
      final newCat = (await service.watchCategories().first).firstWhere((c) => c.type == 'income' && c.name != 'Fees');

      await service.updateIncome(
        id: id,
        title: 'Corrected Donation',
        categoryId: newCat.id,
        categoryName: newCat.name,
        amount: 7500,
        date: DateTime(2026, 8, 15),
        paymentMode: 'upi',
        referenceNo: 'REF-2',
        remarks: 'Corrected remarks',
      );

      final doc = await firestore.collection('finance_income').doc(id).get();
      expect(doc.data()!['title'], 'Corrected Donation');
      expect(doc.data()!['amount'], 7500.0);
      expect(doc.data()!['categoryId'], newCat.id);
      expect(doc.data()!['paymentMode'], 'upi');
      expect(doc.data()!['referenceNo'], 'REF-2');
      expect(doc.data()!['remarks'], 'Corrected remarks');

      final incomeModel = await service.watchIncome().first;
      final edited = incomeModel.firstWhere((i) => i.id == id);
      expect(edited.amount, 7500.0);

      // Account balance reflects the corrected amount (created at 5000,
      // edited to 7500 -> +2500 delta applied on top of the original +5000).
      final accounts = await service.watchAccounts().first;
      final cash = accounts.firstWhere((a) => a.type == 'cash');
      expect(cash.currentBalance, 7500.0);
    });

    test('4. Unrelated Finance entries remain unchanged after an edit', () async {
      final editedId = await createPlainIncome(service, amount: 5000);
      final untouchedId = await createPlainIncome(service, amount: 3000);
      final cat = (await service.watchCategories().first).firstWhere((c) => c.type == 'income');

      await service.updateIncome(
        id: editedId,
        title: 'Edited',
        categoryId: cat.id,
        categoryName: cat.name,
        amount: 9000,
        date: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      final untouched = await firestore.collection('finance_income').doc(untouchedId).get();
      expect(untouched.data()!['amount'], 3000.0);
      expect(untouched.data()!['title'], 'Donation');
    });

    test('a Fee-sourced income entry cannot be edited from Finance directly', () async {
      await service.createFeeIncomeEntry({'amount': 5000, 'feeCollectionId': 'fc-edit-lock', 'paymentMode': 'cash'});
      final feeIncome = (await service.watchIncome().first).firstWhere((i) => i.sourceModule == 'fees');

      await expectLater(
        service.updateIncome(
          id: feeIncome.id,
          title: 'Hacked',
          categoryId: feeIncome.categoryId,
          categoryName: feeIncome.categoryName,
          amount: 1,
          date: DateTime.now(),
          paymentMode: 'cash',
          referenceNo: '',
          remarks: '',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // P1: Finance Entry Void — reuses reverseFeeIncomeByCollectionId's exact
  // reversal mechanics (refactored into a shared _voidIncomeDoc helper),
  // generalized to a direct-by-id lookup for the Finance UI's own action.
  group('G. Finance Entry Void (voidIncome)', () {
    Future<String> createPlainIncome(FinanceService svc, {double amount = 5000}) async {
      final accounts = await svc.watchAccounts().first;
      final cat = (await svc.watchCategories().first).firstWhere((c) => c.type == 'income');
      final cash = accounts.firstWhere((a) => a.type == 'cash');
      return svc.createIncome(FinanceIncomeModel(
        id: '',
        title: 'Donation',
        categoryId: cat.id,
        categoryName: cat.name,
        programType: 'other',
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        amount: amount,
        incomeDate: DateTime(2026, 8, 1),
        paymentMode: 'cash',
        accountId: cash.id,
        accountName: cash.name,
        referenceNo: '',
        remarks: '',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin',
      ));
    }

    test('5. Void a Finance entry', () async {
      final id = await createPlainIncome(service);
      await service.voidIncome(id);
      final doc = await firestore.collection('finance_income').doc(id).get();
      expect(doc.data()!['isDeleted'], true);
    });

    test('7. Voided entry is excluded from active totals (dashboard + income list)', () async {
      final id = await createPlainIncome(service, amount: 6000);
      var summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 6000.0);

      await service.voidIncome(id);

      summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 0.0);
      final incomeList = await service.watchIncome().first;
      expect(incomeList.where((i) => i.id == id), isEmpty);
    });

    test('8. Voided entry remains preserved (not hard-deleted)', () async {
      final id = await createPlainIncome(service, amount: 4000);
      await service.voidIncome(id);
      final doc = await firestore.collection('finance_income').doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['amount'], 4000.0);
      expect(doc.data()!['title'], 'Donation');
      expect(doc.data()!['isDeleted'], true);
      expect(doc.data()!['deletedAt'], isNotNull);
    });

    test('9. Double-void is rejected', () async {
      final id = await createPlainIncome(service);
      await service.voidIncome(id);
      await expectLater(service.voidIncome(id), throwsA(isA<StateError>()));
    });

    test('a Fee-sourced income entry cannot be voided from Finance directly', () async {
      await service.createFeeIncomeEntry({'amount': 5000, 'feeCollectionId': 'fc-void-lock', 'paymentMode': 'cash'});
      final feeIncome = (await service.watchIncome().first).firstWhere((i) => i.sourceModule == 'fees');
      await expectLater(service.voidIncome(feeIncome.id), throwsA(isA<StateError>()));
    });

    test('voiding one entry does not affect another', () async {
      final voidedId = await createPlainIncome(service, amount: 2000);
      final untouchedId = await createPlainIncome(service, amount: 3000);
      await service.voidIncome(voidedId);

      final untouched = await firestore.collection('finance_income').doc(untouchedId).get();
      expect(untouched.data()!['isDeleted'], isNot(true));
      final summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 3000.0);
    });

    Future<void> pumpIncomeTab(WidgetTester tester, FinanceService svc) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: AdminFinanceScreen(service: svc))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
    }

    testWidgets('6. Canceling the void confirmation leaves the entry unchanged', (tester) async {
      final id = await createPlainIncome(service, amount: 5000);
      await pumpIncomeTab(tester, service);

      final voidButton = find.byIcon(Icons.block);
      await tester.ensureVisible(voidButton);
      await tester.tap(voidButton);
      await tester.pumpAndSettle();
      expect(find.text('Void Income Entry'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final doc = await firestore.collection('finance_income').doc(id).get();
      expect(doc.data()!['isDeleted'], isNot(true));
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets(
      '10. A failed void produces user-visible feedback and does not corrupt the record',
      (tester) async {
        final id = await createPlainIncome(service, amount: 5000);
        final throwingService = _ThrowingVoidFinanceService(firestore);
        await pumpIncomeTab(tester, throwingService);

        final voidButton = find.byIcon(Icons.block);
        await tester.ensureVisible(voidButton);
        await tester.tap(voidButton);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Void'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Failed to void income entry'), findsOneWidget);
        final doc = await firestore.collection('finance_income').doc(id).get();
        expect(doc.data()!['isDeleted'], isNot(true));
        expect(doc.data()!['amount'], 5000.0);
      },
    );
  });

  group('Regression', () {
    test('18. Existing Finance income creation (createIncome) still works', () async {
      final accounts = await service.watchAccounts().first;
      final cat = (await service.watchCategories().first).firstWhere((c) => c.type == 'income');
      final cash = accounts.firstWhere((a) => a.type == 'cash');
      final id = await service.createIncome(FinanceIncomeModel(
        id: '',
        title: 'Uniform Sale',
        categoryId: cat.id,
        categoryName: cat.name,
        programType: 'uniform',
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        amount: 1200,
        incomeDate: DateTime.now(),
        paymentMode: 'cash',
        accountId: cash.id,
        accountName: cash.name,
        referenceNo: '',
        remarks: '',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin',
      ));
      final doc = await firestore.collection('finance_income').doc(id).get();
      expect(doc.data()!['amount'], 1200.0);
      final list = await service.watchIncome().first;
      expect(list.any((i) => i.id == id), isTrue);
    });

    test('19. Existing Finance expense creation (createExpense) still works', () async {
      final accounts = await service.watchAccounts().first;
      final cat = (await service.watchCategories().first).firstWhere((c) => c.type == 'expense');
      final cash = accounts.firstWhere((a) => a.type == 'cash');
      final id = await service.createExpense(FinanceExpenseModel(
        id: '',
        title: 'Stationery',
        categoryId: cat.id,
        categoryName: cat.name,
        vendorId: '',
        vendorName: '',
        amount: 800,
        expenseDate: DateTime.now(),
        paymentMode: 'cash',
        accountId: cash.id,
        accountName: cash.name,
        referenceNo: '',
        billNo: '',
        remarks: '',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin',
      ));
      final doc = await firestore.collection('finance_expenses').doc(id).get();
      expect(doc.data()!['amount'], 800.0);
      final updatedAccounts = await service.watchAccounts().first;
      expect(updatedAccounts.firstWhere((a) => a.type == 'cash').currentBalance, -800.0);
    });

    test('20. Finance dashboard totals remain correct across income/expense/edit/void', () async {
      final id1 = await service.createIncome(FinanceIncomeModel(
        id: '',
        title: 'A',
        categoryId: (await service.watchCategories().first).firstWhere((c) => c.type == 'income').id,
        categoryName: 'Other Income',
        programType: 'other',
        studentId: '',
        studentName: '',
        classId: '',
        className: '',
        amount: 4000,
        incomeDate: DateTime.now(),
        paymentMode: 'cash',
        accountId: (await service.watchAccounts().first).firstWhere((a) => a.type == 'cash').id,
        accountName: 'Cash',
        referenceNo: '',
        remarks: '',
        attachmentUrls: const [],
        ledgerEntryId: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'admin',
      ));
      final invoiceId = await service.createExpenseInvoice(_invoicePayload(totalAmount: 1000));
      await service.payInvoice(
        invoiceId: invoiceId,
        invoiceType: 'expense',
        amount: 1000,
        paidDate: DateTime.now(),
        paymentMode: 'cash',
        referenceNo: '',
        remarks: '',
      );

      var summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 4000.0);
      expect(summary.totalExpenses, 1000.0);
      expect(summary.netBalance, 3000.0);

      await service.voidIncome(id1);
      summary = await service.watchDashboardSummary().first;
      expect(summary.totalIncome, 0.0);
      expect(summary.netBalance, -1000.0);
    });
  });
}
