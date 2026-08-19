import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/finance_account_model.dart';
import '../models/finance_category_model.dart';
import '../models/finance_dashboard_summary_model.dart';
import '../models/finance_expense_model.dart';
import '../models/finance_invoice_model.dart';
import '../models/finance_income_model.dart';
import '../models/finance_ledger_entry_model.dart';
import '../models/staff_salary_payment_model.dart';
import '../models/vendor_model.dart';

class FinanceService {
  FinanceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _ledger =>
      _firestore.collection('finance_ledger');
  CollectionReference<Map<String, dynamic>> get _income =>
      _firestore.collection('finance_income');
  CollectionReference<Map<String, dynamic>> get _expenses =>
      _firestore.collection('finance_expenses');
  CollectionReference<Map<String, dynamic>> get _salary =>
      _firestore.collection('staff_salary_payments');
  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection('finance_categories');
  CollectionReference<Map<String, dynamic>> get _accounts =>
      _firestore.collection('finance_accounts');
  CollectionReference<Map<String, dynamic>> get _vendors =>
      _firestore.collection('vendors');
  CollectionReference<Map<String, dynamic>> get _invoices =>
      _firestore.collection('finance_invoices');

  String get _createdBy =>
      _auth.currentUser?.email ??
      _auth.currentUser?.uid ??
      'admin';

  Stream<FinanceDashboardSummaryModel> watchDashboardSummary() {
    return _ledger.snapshots().map((snap) {
      var totalIncome = 0.0;
      var totalExpenses = 0.0;
      var cashBalance = 0.0;
      var bankBalance = 0.0;
      var upiBalance = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status']?.toString() == 'cancelled') continue;
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final type = data['entryType']?.toString() ?? '';
        if (type == 'income') {
          totalIncome += amount;
        } else if (type == 'expense') {
          totalExpenses += amount;
        }
        final account = data['accountName']?.toString().toLowerCase() ?? '';
        if (account.contains('cash')) cashBalance += type == 'income' ? amount : -amount;
        if (account.contains('bank')) bankBalance += type == 'income' ? amount : -amount;
        if (account.contains('upi')) upiBalance += type == 'income' ? amount : -amount;
      }
      return FinanceDashboardSummaryModel(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        netBalance: totalIncome - totalExpenses,
        cashBalance: cashBalance,
        bankBalance: bankBalance,
        upiBalance: upiBalance,
        thisMonthIncome: totalIncome,
        thisMonthExpenses: totalExpenses,
      );
    });
  }

  Stream<List<FinanceLedgerEntryModel>> watchLedger() {
    return _ledger.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => FinanceLedgerEntryModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FinanceIncomeModel>> watchIncome() {
    return _income.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => FinanceIncomeModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FinanceExpenseModel>> watchExpenses() {
    return _expenses.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => FinanceExpenseModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<StaffSalaryPaymentModel>> watchSalaryPayments() {
    return _salary.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => StaffSalaryPaymentModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FinanceCategoryModel>> watchCategories() {
    return _categories.orderBy('name').snapshots().map(
          (snap) => snap.docs.map((d) => FinanceCategoryModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FinanceAccountModel>> watchAccounts() {
    return _accounts.orderBy('name').snapshots().map(
          (snap) => snap.docs.map((d) => FinanceAccountModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<VendorModel>> watchVendors() {
    return _vendors.orderBy('name').snapshots().map(
          (snap) => snap.docs.map((d) => VendorModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FinanceInvoiceModel>> watchInvoicesByType(String type) {
    return _invoices
        .where('type', isEqualTo: type)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FinanceInvoiceModel.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCategory(FinanceCategoryModel category) async {
    final doc = _categories.doc();
    await doc.set(category.toMap());
    return doc.id;
  }

  Future<String> createAccount(FinanceAccountModel account) async {
    final doc = _accounts.doc();
    await doc.set(account.toMap());
    return doc.id;
  }

  Future<String> createVendor(VendorModel vendor) async {
    final doc = _vendors.doc();
    await doc.set(vendor.toMap());
    return doc.id;
  }

  Future<String> createIncome(FinanceIncomeModel income) async {
    final incomeRef = _income.doc();
    final ledgerRef = _ledger.doc();
    await _firestore.runTransaction((txn) async {
      final accountRef = _accounts.doc(income.accountId);
      final accountSnap = await txn.get(accountRef);
      final current = (accountSnap.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      final amount = income.amount;
      txn.set(incomeRef, income.toMap(incomeRef.id, ledgerEntryId: ledgerRef.id, createdBy: _createdBy));
      txn.set(ledgerRef, {
        ...income.toLedgerMap(ledgerRef.id, createdBy: _createdBy),
        'status': 'confirmed',
      });
      txn.set(accountRef, {'currentBalance': current + amount}, SetOptions(merge: true));
    });
    return incomeRef.id;
  }

  Future<String> createExpenseInvoice(Map<String, dynamic> data) async {
    return _createInvoice({...data, 'type': 'expense'});
  }

  Future<String> createSalaryInvoice(Map<String, dynamic> data) async {
    return _createInvoice({...data, 'type': 'salary'});
  }

  Future<String> _createInvoice(Map<String, dynamic> data) async {
    final doc = _invoices.doc();
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    await doc.set({
      ...data,
      'id': doc.id,
      // A newly raised invoice always starts unpaid with nothing collected yet;
      // status only advances via payInvoice. Ignore any caller-supplied values
      // so an invoice can never be raised as already paid/partial.
      'paidAmount': 0,
      'balanceAmount': totalAmount,
      'status': 'unpaid',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': _createdBy,
    });
    return doc.id;
  }

  /// Picks the account whose type best matches a payment mode string
  /// (e.g. 'upi', 'bank_transfer', 'cash'), falling back to the first
  /// active account if nothing matches.
  QueryDocumentSnapshot<Map<String, dynamic>> _matchAccountForPaymentMode(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> accounts,
    String paymentMode,
  ) {
    final mode = paymentMode.toLowerCase();
    final targetType = mode.contains('cash')
        ? 'cash'
        : mode.contains('upi')
            ? 'upi'
            : 'bank';
    for (final doc in accounts) {
      final type = doc.data()['type']?.toString().toLowerCase() ?? '';
      if (type.contains(targetType)) return doc;
    }
    return accounts.first;
  }

  Future<FinanceInvoiceModel?> getInvoiceById(String id) async {
    final snap = await _invoices.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return FinanceInvoiceModel.fromMap(snap.id, snap.data()!);
  }

  Future<String?> payInvoice({
    required String invoiceId,
    required String invoiceType,
    required double amount,
    required DateTime paidDate,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final invoiceRef = _invoices.doc(invoiceId);
    final existing = await _ledger
        .where('sourceModule', isEqualTo: 'invoice')
        .where('sourceId', isEqualTo: invoiceId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;

    final snap = await invoiceRef.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Invoice not found');
    }
    final invoice = FinanceInvoiceModel.fromMap(snap.id, snap.data()!);
    if (amount <= 0 || amount > invoice.balanceAmount) {
      throw StateError('Invalid amount');
    }
    final accounts = await _accounts.where('isActive', isEqualTo: true).get();
    if (accounts.docs.isEmpty) throw StateError('No active finance account found');
    final accountDoc = _matchAccountForPaymentMode(accounts.docs, paymentMode);
    final account = FinanceAccountModel.fromMap(accountDoc.id, accountDoc.data());
    final ledgerRef = _ledger.doc();
    final paymentRef = _income.doc();
    await _firestore.runTransaction((txn) async {
      final currentBalance = (accountDoc.data()['currentBalance'] as num?)?.toDouble() ?? 0.0;
      txn.set(paymentRef, {
        'id': paymentRef.id,
        'title': invoice.type == 'salary' ? 'Salary Payment - ${invoice.partyName}' : 'Expense Payment - ${invoice.partyName}',
        'categoryId': invoice.type,
        'categoryName': invoice.type == 'salary' ? 'Salary' : 'Expense',
        'programType': 'invoice',
        'studentId': '',
        'studentName': invoice.partyName,
        'classId': '',
        'className': '',
        'amount': amount,
        'incomeDate': paidDate,
        'paymentMode': paymentMode,
        'accountId': account.id,
        'accountName': account.name,
        'referenceNo': referenceNo,
        'remarks': remarks,
        'attachmentUrls': <String>[],
        'ledgerEntryId': ledgerRef.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _createdBy,
        'sourceModule': 'invoice',
        'sourceId': invoiceId,
        'invoiceId': invoiceId,
        'invoiceType': invoice.type,
        'description': invoice.description,
      });
      txn.set(ledgerRef, {
        'id': ledgerRef.id,
        'entryType': 'expense',
        'sourceModule': 'invoice',
        'sourceId': invoiceId,
        'categoryId': invoice.type,
        'categoryName': invoice.type == 'salary' ? 'Salary' : 'Expense',
        'subCategoryName': '',
        'title': invoice.type == 'salary' ? 'Salary Payment - ${invoice.partyName}' : 'Expense Payment - ${invoice.partyName}',
        'description': invoice.description,
        'amount': amount,
        'transactionDate': paidDate,
        'paymentMode': paymentMode,
        'accountId': account.id,
        'accountName': account.name,
        'referenceNo': referenceNo,
        'attachmentUrls': <String>[],
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _createdBy,
      });
      txn.set(accountDoc.reference, {'currentBalance': currentBalance - amount}, SetOptions(merge: true));
      final paidAmount = (invoice.paidAmount + amount);
      final balanceAmount = (invoice.totalAmount - paidAmount).clamp(0, double.infinity);
      final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
      txn.set(invoiceRef, {
        'paidAmount': paidAmount,
        'balanceAmount': balanceAmount,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return paymentRef.id;
  }

  Future<String> createExpense(FinanceExpenseModel expense) async {
    final expenseRef = _expenses.doc();
    final ledgerRef = _ledger.doc();
    await _firestore.runTransaction((txn) async {
      final accountRef = _accounts.doc(expense.accountId);
      final accountSnap = await txn.get(accountRef);
      final current = (accountSnap.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      txn.set(expenseRef, expense.toMap(expenseRef.id, ledgerEntryId: ledgerRef.id, createdBy: _createdBy));
      txn.set(ledgerRef, {
        ...expense.toLedgerMap(ledgerRef.id, createdBy: _createdBy),
        'status': 'confirmed',
      });
      txn.set(accountRef, {'currentBalance': current - expense.amount}, SetOptions(merge: true));
    });
    return expenseRef.id;
  }

  Future<String> createSalaryPayment(StaffSalaryPaymentModel payment) async {
    final paymentRef = _salary.doc();
    final ledgerRef = _ledger.doc();
    await _firestore.runTransaction((txn) async {
      final accountRef = _accounts.doc(payment.accountId);
      final accountSnap = await txn.get(accountRef);
      final current = (accountSnap.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      txn.set(paymentRef, payment.toMap(paymentRef.id, ledgerEntryId: ledgerRef.id, createdBy: _createdBy));
      txn.set(ledgerRef, {
        'id': ledgerRef.id,
        'entryType': 'expense',
        'sourceModule': 'salary',
        'sourceId': paymentRef.id,
        'categoryId': 'salary',
        'categoryName': 'Staff Salary',
        'subCategoryName': '',
        'title': 'Salary Payment - ${payment.staffName}',
        'description': payment.remarks,
        'amount': payment.netPayable,
        'transactionDate': payment.paymentDate,
        'paymentMode': payment.paymentMode,
        'accountId': payment.accountId,
        'accountName': payment.accountName,
        'referenceNo': payment.referenceNo,
        'attachmentUrls': <String>[],
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _createdBy,
      });
      txn.set(accountRef, {'currentBalance': current - payment.paidAmount}, SetOptions(merge: true));
    });
    return paymentRef.id;
  }

  Future<void> cancelLedgerEntry(String id, {String? reason}) async {
    await _ledger.doc(id).set({
      'status': 'cancelled',
      'description': reason ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> postFeeCollectionToLedger({
    required String title,
    required double amount,
    required String paymentMode,
    required String accountId,
    required String accountName,
    String sourceId = '',
    String referenceNo = '',
  }) async {
    final ledgerRef = _ledger.doc();
    await ledgerRef.set({
      'id': ledgerRef.id,
      'entryType': 'income',
      'sourceModule': 'fees',
      'sourceId': sourceId,
      'categoryId': 'fees',
      'categoryName': 'Fees',
      'subCategoryName': '',
      'title': title,
      'description': '',
      'amount': amount,
      'transactionDate': FieldValue.serverTimestamp(),
      'paymentMode': paymentMode,
      'accountId': accountId,
      'accountName': accountName,
      'referenceNo': referenceNo,
      'attachmentUrls': <String>[],
      'status': 'confirmed',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': _createdBy,
    });
  }

  Future<String?> createFeeIncomeEntry(Map<String, dynamic> entry) async {
    final feeCollectionId = entry['feeCollectionId']?.toString() ?? '';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0.0;
    final existing = await _income
        .where('sourceModule', isEqualTo: 'fees')
        .where('sourceId', isEqualTo: feeCollectionId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final accounts = await _accounts.where('isActive', isEqualTo: true).get();
    if (accounts.docs.isEmpty) {
      throw StateError('No active finance account found');
    }
    final accountDoc = _matchAccountForPaymentMode(accounts.docs, entry['paymentMode']?.toString() ?? '');
    final account = FinanceAccountModel.fromMap(accountDoc.id, accountDoc.data());

    final incomeRef = _income.doc();
    final ledgerRef = _ledger.doc();
    await _firestore.runTransaction((txn) async {
      final duplicateSnap = await txn.get(
        _income.doc(incomeRef.id),
      );
      if (duplicateSnap.exists) return;
      final accountRef = _accounts.doc(account.id);
      final accountSnap = await txn.get(accountRef);
      final current = (accountSnap.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      final title = entry['description']?.toString().isNotEmpty == true
          ? entry['description'].toString()
          : 'Fee collected';
      final payload = {
        'id': incomeRef.id,
        'title': title,
        'categoryId': 'fees',
        'categoryName': 'Fees',
        'programType': 'fees',
        'studentId': entry['studentId']?.toString() ?? '',
        'studentName': entry['studentName']?.toString() ?? '',
        'classId': entry['classId']?.toString() ?? '',
        'className': entry['className']?.toString() ?? '',
        'amount': amount,
        'incomeDate': entry['date'] ?? FieldValue.serverTimestamp(),
        'paymentMode': entry['paymentMode']?.toString() ?? '',
        'accountId': account.id,
        'accountName': account.name,
        'referenceNo': entry['referenceNo']?.toString() ?? '',
        'remarks': entry['remarks']?.toString() ?? '',
        'attachmentUrls': <String>[],
        'ledgerEntryId': ledgerRef.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _createdBy,
        'sourceModule': 'fees',
        'sourceId': feeCollectionId,
        'type': 'income',
        'category': 'Fees',
        'feeAssignmentId': entry['feeAssignmentId']?.toString() ?? '',
        'feeStructureId': entry['feeStructureId']?.toString() ?? '',
        'feeCollectionId': feeCollectionId,
        'admissionNo': entry['admissionNo']?.toString() ?? '',
        'description': title,
      };
      txn.set(incomeRef, payload);
      txn.set(ledgerRef, {
        'id': ledgerRef.id,
        'entryType': 'income',
        'sourceModule': 'fees',
        'sourceId': feeCollectionId,
        'categoryId': 'fees',
        'categoryName': 'Fees',
        'subCategoryName': '',
        'title': title,
        'description': title,
        'amount': amount,
        'transactionDate': entry['date'] ?? FieldValue.serverTimestamp(),
        'paymentMode': entry['paymentMode']?.toString() ?? '',
        'accountId': account.id,
        'accountName': account.name,
        'referenceNo': entry['referenceNo']?.toString() ?? '',
        'attachmentUrls': <String>[],
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _createdBy,
      });
      txn.set(accountRef, {'currentBalance': current + amount}, SetOptions(merge: true));
    });
    return incomeRef.id;
  }

  Future<void> reverseFeeIncomeByCollectionId(String feeCollectionId) async {
    final existing = await _income
        .where('sourceModule', isEqualTo: 'fees')
        .where('sourceId', isEqualTo: feeCollectionId)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) return;
    final doc = existing.docs.first;
    final data = doc.data();
    if (data['isDeleted'] == true) return;
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final accountId = data['accountId']?.toString() ?? '';
    await doc.reference.set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _createdBy,
    }, SetOptions(merge: true));
    final ledgerId = data['ledgerEntryId']?.toString() ?? '';
    if (ledgerId.isNotEmpty) {
      await _ledger.doc(ledgerId).set({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (accountId.isNotEmpty && amount > 0) {
      final accountRef = _accounts.doc(accountId);
      final accountSnap = await accountRef.get();
      final current = (accountSnap.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
      await accountRef.set({'currentBalance': current - amount}, SetOptions(merge: true));
    }
  }

  Future<void> ensureDefaults() async {
    final categorySnap = await _categories.limit(1).get();
    if (categorySnap.docs.isEmpty) {
      final defaults = <FinanceCategoryModel>[
        FinanceCategoryModel(id: '', name: 'Fees', type: 'income', parentId: null, isSystem: true, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        FinanceCategoryModel(id: '', name: 'Other Income', type: 'income', parentId: null, isSystem: true, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        FinanceCategoryModel(id: '', name: 'Staff Salary', type: 'expense', parentId: null, isSystem: true, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        FinanceCategoryModel(id: '', name: 'Vendor Payment', type: 'expense', parentId: null, isSystem: true, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      ];
      for (final category in defaults) {
        await createCategory(category);
      }
    }

    final accountSnap = await _accounts.limit(1).get();
    if (accountSnap.docs.isEmpty) {
      final defaults = <FinanceAccountModel>[
        FinanceAccountModel(id: '', name: 'Cash', type: 'cash', openingBalance: 0, currentBalance: 0, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        FinanceAccountModel(id: '', name: 'Bank', type: 'bank', openingBalance: 0, currentBalance: 0, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        FinanceAccountModel(id: '', name: 'UPI', type: 'upi', openingBalance: 0, currentBalance: 0, isActive: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      ];
      for (final account in defaults) {
        await createAccount(account);
      }
    }
  }
}
