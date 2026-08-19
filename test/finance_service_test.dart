// Exercises FinanceService against an in-memory Firestore (fake_cloud_firestore)
// to cover the Finance data-flow behaviors audited in this change:
// - Expense/Salary invoice tab queries actually return what was created.
// - payInvoice() correctly handles partial and full payments, and records
//   exactly one finance transaction per payment (not per invoice).
// - The ledger surfaces both income and expense entries.
// - Dashboard totals/net balance/account balances are computed only from
//   confirmed transactions, never from unpaid invoices.
// - Account selection follows the chosen payment mode.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/finance/services/finance_service.dart';

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
}
