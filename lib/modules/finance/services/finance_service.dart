import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../admin/settings/models/academic_year_date_range.dart';
import '../models/finance_account_model.dart';
import '../models/finance_category_model.dart';
import '../models/finance_cancelled_transactions_model.dart';
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

  /// Totals and per-account balances from non-cancelled ledger entries plus
  /// each account's stored `openingBalance`.
  ///
  /// Each entry and each account's opening balance is assigned to Cash, Bank
  /// or UPI exactly once, by the stored `type` of the account (for entries,
  /// the account its `accountId` points to) — never by account name, which
  /// could omit custom names ("HDFC Savings") or double-count misleading ones
  /// ("Bank UPI"). An entry whose account is missing, or an account of any
  /// other type (e.g. `wallet`, `other`), is not guessed into one of the
  /// three; its amount is reported in [FinanceDashboardSummaryModel
  /// .unclassifiedBalance] instead (opening part also in
  /// `unclassifiedOpeningBalance`).
  ///
  /// Formulas (all non-cancelled entries; inactive accounts included, like
  /// their entries):
  /// - Net Movement = income − expenses dated within the period.
  /// - Opening Balance (period) = stored opening balances + net movement of
  ///   entries dated before [periodStart]. The stored `openingBalance` has
  ///   no date of its own; it is the account's balance before its first
  ///   recorded entry.
  /// - Closing Balance = Opening Balance + Net Movement, so
  ///   Cash + Bank + UPI + Unclassified = Closing Balance exactly.
  ///
  /// [periodStart]/[periodEnd] are inclusive calendar days (same day-only
  /// comparison as AcademicYearDateRange.contains). With neither given (the
  /// Dashboard and Ledger tabs), the period is all-time and the opening
  /// balance is the stored one. Entries dated after [periodEnd] are
  /// excluded. Entries without a transaction date can't be placed in a
  /// period: they count in an all-time summary only.
  Stream<FinanceDashboardSummaryModel> watchDashboardSummary({DateTime? periodStart, DateTime? periodEnd}) {
    DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
    final start = periodStart == null ? null : dayOf(periodStart);
    final end = periodEnd == null ? null : dayOf(periodEnd);
    final bounded = start != null || end != null;
    return _ledger.snapshots().asyncMap((snap) async {
      final accounts = await _accounts.get();
      final accountTypeById = <String, String>{
        for (final doc in accounts.docs) doc.id: doc.data()['type']?.toString().trim().toLowerCase() ?? '',
      };
      final opening = <String, double>{'cash': 0, 'bank': 0, 'upi': 0, '': 0};
      final movement = <String, double>{'cash': 0, 'bank': 0, 'upi': 0, '': 0};
      String bucket(String? type) => const {'cash', 'bank', 'upi'}.contains(type) ? type! : '';
      // Presence of unclassified balances/activity, tracked separately from
      // the amounts so activity that nets to zero is still reported.
      var hasUnclassifiedActivity = false;
      for (final doc in accounts.docs) {
        final value = doc.data()['openingBalance'];
        final amount = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0.0;
        final key = bucket(accountTypeById[doc.id]);
        opening[key] = opening[key]! + amount;
        if (key.isEmpty && amount != 0) hasUnclassifiedActivity = true;
      }
      var totalIncome = 0.0;
      var totalExpenses = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status']?.toString() == 'cancelled') continue;
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final type = data['entryType']?.toString() ?? '';
        final signed = type == 'income' ? amount : -amount;
        final key = bucket(accountTypeById[data['accountId']?.toString() ?? '']);
        if (bounded) {
          final raw = data['transactionDate'];
          final date = raw is Timestamp ? raw.toDate() : raw is DateTime ? raw : null;
          if (date == null) continue;
          final day = dayOf(date);
          if (end != null && day.isAfter(end)) continue;
          if (start != null && day.isBefore(start)) {
            opening[key] = opening[key]! + signed;
            if (key.isEmpty && amount != 0) hasUnclassifiedActivity = true;
            continue;
          }
        }
        if (key.isEmpty && amount != 0) hasUnclassifiedActivity = true;
        if (type == 'income') {
          totalIncome += amount;
        } else if (type == 'expense') {
          totalExpenses += amount;
        }
        movement[key] = movement[key]! + signed;
      }
      double closing(String key) => opening[key]! + movement[key]!;
      final openingBalance = opening.values.fold<double>(0, (a, b) => a + b);
      final netMovement = totalIncome - totalExpenses;
      return FinanceDashboardSummaryModel(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        netBalance: netMovement,
        cashBalance: closing('cash'),
        bankBalance: closing('bank'),
        upiBalance: closing('upi'),
        thisMonthIncome: totalIncome,
        thisMonthExpenses: totalExpenses,
        unclassifiedBalance: closing(''),
        openingBalance: openingBalance,
        cashOpeningBalance: opening['cash']!,
        bankOpeningBalance: opening['bank']!,
        upiOpeningBalance: opening['upi']!,
        unclassifiedOpeningBalance: opening['']!,
        closingBalance: openingBalance + netMovement,
        hasUnclassifiedActivity: hasUnclassifiedActivity,
      );
    });
  }

  /// Read-only summary of cancelled/voided transactions for the Dashboard.
  /// Never feeds any total or balance, and writes nothing.
  ///
  /// The unit is the `finance_income` record — manual income, Fee
  /// Collection income and expense/salary invoice payments are all stored
  /// there — voided with `isDeleted: true` and keeping its original
  /// `amount`. Its ledger entry is a mirror cancelled in the same
  /// transaction, so it is never counted separately; a voided Fee
  /// Collection is counted through its Finance entry only (one per
  /// `sourceId`), not again for its fees receipt. A retried void changes
  /// no record, so it can't add to the count.
  ///
  /// Records whose status or link is unclear are listed in
  /// [FinanceCancelledTransactionsSummary.exclusions] instead of counted:
  /// a voided entry whose ledger entry is still active (or the reverse),
  /// several Finance entries linked to one Fee Collection, a voided entry
  /// with no stored amount, and a cancelled ledger entry with no Finance
  /// income record (direct expenses and salary payment records have no
  /// void workflow of their own). Two reads per update (income stream +
  /// one ledger read); nothing is fetched per record.
  ///
  /// For traceability each counted record also carries its linked fee
  /// receipt (receipt number, status) or invoice (invoice number, status)
  /// and ledger entry, looked up in batches by id (never one read per
  /// record). A counted record whose linked receipt/invoice can't be found
  /// stays counted — the voided Finance record is what Finance totals
  /// used — but is marked with a review note.
  Stream<FinanceCancelledTransactionsSummary> watchCancelledTransactions() {
    return _income.snapshots().asyncMap((incomeSnap) async {
      final ledgerSnap = await _ledger.get();
      final income = {for (final d in incomeSnap.docs) d.id: d.data()};
      final receiptIds = <String>{};
      final invoiceIds = <String>{};
      for (final d in income.values) {
        if (d['isDeleted'] != true) continue;
        final sourceId = d['sourceId']?.toString().trim() ?? '';
        final invoiceId = d['invoiceId']?.toString().trim() ?? '';
        if (d['sourceModule']?.toString() == 'fees' && sourceId.isNotEmpty) receiptIds.add(sourceId);
        if (invoiceId.isNotEmpty) invoiceIds.add(invoiceId);
      }
      return _summarizeCancellations(
        income,
        {for (final d in ledgerSnap.docs) d.id: d.data()},
        receipts: await _docsById(_firestore.collection('fee_receipts'), receiptIds),
        invoices: await _docsById(_invoices, invoiceIds),
      );
    });
  }

  /// Documents of [collection] with the given ids, read 30 at a time.
  static Future<Map<String, Map<String, dynamic>>> _docsById(
    CollectionReference<Map<String, dynamic>> collection,
    Set<String> ids,
  ) async {
    final list = ids.toList();
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < list.length; i += 30) {
      final chunk = list.sublist(i, i + 30 > list.length ? list.length : i + 30);
      final snap = await collection.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }

  static FinanceCancelledTransactionsSummary _summarizeCancellations(
    Map<String, Map<String, dynamic>> income,
    Map<String, Map<String, dynamic>> ledger, {
    Map<String, Map<String, dynamic>> receipts = const {},
    Map<String, Map<String, dynamic>> invoices = const {},
  }) {
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    String text(Object? v) => v?.toString().trim() ?? '';
    String titleOf(Map<String, dynamic> d, String fallback) => text(d['title']).isEmpty ? fallback : text(d['title']);

    final transactions = <FinanceCancelledTransaction>[];
    final exclusions = <FinanceCancellationExclusion>[];
    void exclude(String id, Map<String, dynamic> d, String reason) =>
        exclusions.add(FinanceCancellationExclusion(id: id, title: titleOf(d, 'Finance entry'), reason: reason));

    // Fee Collections linked from more than one Finance entry.
    final feeLinks = <String, int>{};
    for (final d in income.values) {
      if (text(d['sourceModule']) == 'fees' && text(d['sourceId']).isNotEmpty) {
        feeLinks.update(text(d['sourceId']), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final linkedLedgerIds = <String>{};

    for (final MapEntry(key: id, value: d) in income.entries) {
      final ledgerId = text(d['ledgerEntryId']);
      if (ledgerId.isNotEmpty) linkedLedgerIds.add(ledgerId);
      final ledgerStatus = ledger[ledgerId]?['status']?.toString();
      final voided = d['isDeleted'] == true;
      if (!voided) {
        if (ledgerStatus == 'cancelled') exclude(id, d, 'Active Finance entry, but its ledger entry is cancelled');
        continue;
      }
      if (ledgerStatus != null && ledgerStatus != 'cancelled') {
        exclude(id, d, 'Voided Finance entry, but its ledger entry is still active');
        continue;
      }
      final source = text(d['sourceModule']);
      final sourceId = text(d['sourceId']);
      if (source == 'fees' && (feeLinks[sourceId] ?? 0) > 1) {
        exclude(id, d, 'More than one Finance entry is linked to the same Fee Collection');
        continue;
      }
      final amount = d['amount'];
      if (amount is! num) {
        exclude(id, d, 'Original amount not recorded');
        continue;
      }
      final isInvoice = source == 'invoice' || text(d['programType']) == 'invoice';
      final invoiceType = text(d['invoiceType']);
      final isFee = source == 'fees';
      final invoiceId = text(d['invoiceId']);
      final linkedId = isFee ? sourceId : isInvoice ? invoiceId : '';
      final linked = isFee ? receipts[sourceId] : isInvoice ? invoices[invoiceId] : null;
      final linkedNumber = isFee
          ? text(linked?['receiptNo'])
          : isInvoice
              ? (text(d['invoiceNo']).isNotEmpty ? text(d['invoiceNo']) : text(linked?['invoiceNo']))
              : '';
      final linkedLabel = isFee ? 'Receipt' : isInvoice ? 'Invoice' : '';
      final reviewNote = !isFee && !isInvoice
          ? ''
          : linkedId.isEmpty
              ? 'No linked ${isFee ? 'Fee Collection' : 'invoice'} id is stored on this Finance record'
              : linked == null
                  ? 'The linked ${isFee ? 'Fee Collection receipt' : 'invoice'} record was not found'
                  : '';
      transactions.add(FinanceCancelledTransaction(
        id: id,
        sourceLabel: isFee
            ? 'Fees'
            : isInvoice
                ? (invoiceType == 'salary' ? 'Finance → Salary' : 'Finance → Expenses')
                : source.isEmpty || source == 'finance'
                    ? 'Finance → Income'
                    : source,
        typeLabel: isInvoice
            ? (invoiceType == 'salary' ? 'Salary payment' : 'Expense payment')
            : isFee
                ? 'Fee collection'
                : source.isEmpty || source == 'finance'
                    ? 'Manual income'
                    : 'Other ($source)',
        title: titleOf(d, isInvoice ? 'Invoice payment' : 'Income'),
        reference: text(d['referenceNo']),
        originalDate: date(d['incomeDate']),
        cancelledAt: date(d['reversedAt']) ?? date(d['deletedAt']),
        amount: amount.toDouble(),
        reason: text(d['reversalReason']),
        statusLabel: isInvoice ? 'Reversed' : 'Voided',
        linkedDocumentLabel: linkedLabel,
        linkedDocumentId: linkedId,
        linkedDocumentNumber: linkedNumber,
        linkedDocumentFound: linked != null,
        linkedDocumentStatus: linked == null
            ? ''
            : isFee
                ? (linked['isDeleted'] == true ? 'Voided' : 'Active')
                : text(linked['status']),
        ledgerId: ledgerId,
        ledgerStatus: ledgerStatus ?? '',
        reviewNote: reviewNote,
      ));
    }

    // Cancelled ledger lines that mirror no Finance income record.
    for (final MapEntry(key: id, value: d) in ledger.entries) {
      if (d['status']?.toString() != 'cancelled' || linkedLedgerIds.contains(id)) continue;
      exclusions.add(FinanceCancellationExclusion(
        id: id,
        title: titleOf(d, 'Ledger entry'),
        reason: 'Cancelled ledger entry with no linked Finance income record',
        collection: 'finance_ledger',
      ));
    }

    transactions.sort((a, b) {
      final x = a.cancelledAt;
      final y = b.cancelledAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return FinanceCancelledTransactionsSummary(transactions: transactions, exclusions: exclusions);
  }

  Stream<List<FinanceLedgerEntryModel>> watchLedger() {
    return _ledger.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => FinanceLedgerEntryModel.fromMap(d.id, d.data())).toList(),
        );
  }

  // Client-side isDeleted filter (not a `.where()` query) so pre-existing
  // docs that never had the field written at all still count as active —
  // Firestore's `!=`/`isNotEqualTo` excludes documents missing the field
  // entirely, which would have hidden every income entry created before
  // voiding existed. Same convention FeeService.getAssignments/getReceipts
  // already use for their own isDeleted filtering.
  Stream<List<FinanceIncomeModel>> watchIncome() {
    return _income.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs
              .where((d) => d.data()['isDeleted'] != true)
              .map((d) => FinanceIncomeModel.fromMap(d.id, d.data()))
              .toList(),
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

  // Filters server-side on 'type' only and sorts by createdAt client-side.
  // Combining an equality filter with orderBy on a different field requires
  // a manually-created Firestore composite index; without one deployed,
  // this query fails silently (the stream just never emits data), which is
  // why invoices that exist in Firestore were never showing up in the
  // Expense/Salary tabs. Sorting client-side avoids depending on a
  // composite index existing.
  Stream<List<FinanceInvoiceModel>> watchInvoicesByType(String type) {
    return _invoices.where('type', isEqualTo: type).snapshots().map((snap) {
      final items = snap.docs.map((d) => FinanceInvoiceModel.fromMap(d.id, d.data())).toList();
      items.sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return items;
    });
  }

  // ---------------------------------------------------------------------
  // AY-IMPLEMENT-03: date-derived Academic Year reporting support. Every
  // method below is a one-shot `.get()` (not a `.snapshots()` stream, since
  // a Report queries a fixed historical range, not a live view) plus a
  // client-side date filter — deliberately never a server-side range query
  // combined with any other filter/orderBy, mirroring [watchInvoicesByType]'s
  // own documented lesson above: an equality/range filter combined with an
  // orderBy on a different field silently requires a composite index that
  // doesn't exist here, and this collection set has already broken once in
  // production from exactly that. None of these write or read an
  // `academicYearId` — every Finance schema is completely untouched. Fee-
  // sourced entries deliberately have no method here: their Academic Year
  // is already fully resolvable through the existing `feeAssignmentId` ->
  // `StudentFeeAssignment.academicYearId` relationship (FeeService), and
  // duplicating that onto the Finance document would be exactly the kind
  // of redundant field AY-AUDIT-02 recommended against.

  /// Every non-deleted income entry whose [FinanceIncomeModel.incomeDate]
  /// falls within [range]. Filters `isDeleted` client-side, matching
  /// [watchIncome]'s own convention (a `!=` Firestore filter would exclude
  /// documents that predate the field's existence entirely).
  Future<List<FinanceIncomeModel>> getIncomeForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final snap = await _income.get();
    return snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => FinanceIncomeModel.fromMap(d.id, d.data()))
        .where((e) => e.incomeDate != null && range.contains(e.incomeDate!))
        .toList();
  }

  /// Every expense whose [FinanceExpenseModel.expenseDate] falls within
  /// [range].
  Future<List<FinanceExpenseModel>> getExpensesForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final snap = await _expenses.get();
    return snap.docs
        .map((d) => FinanceExpenseModel.fromMap(d.id, d.data()))
        .where((e) => e.expenseDate != null && range.contains(e.expenseDate!))
        .toList();
  }

  /// Every ledger entry whose [FinanceLedgerEntryModel.transactionDate]
  /// falls within [range]. Cancelled-status exclusion (if wanted) is left
  /// to the caller, exactly like [watchLedger] itself already leaves it to
  /// its own callers rather than baking it into the query.
  Future<List<FinanceLedgerEntryModel>> getLedgerForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final snap = await _ledger.get();
    return snap.docs
        .map((d) => FinanceLedgerEntryModel.fromMap(d.id, d.data()))
        .where((e) => e.transactionDate != null && range.contains(e.transactionDate!))
        .toList();
  }

  /// Every invoice (any type) whose [FinanceInvoiceModel.invoiceDate] falls
  /// within [range]. Type-agnostic — a caller wanting only expense/salary
  /// invoices filters `type` on the result, the same composability
  /// [watchInvoicesByType] already offers for the live-stream case.
  Future<List<FinanceInvoiceModel>> getInvoicesForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final snap = await _invoices.get();
    return snap.docs
        .map((d) => FinanceInvoiceModel.fromMap(d.id, d.data()))
        .where((e) => e.invoiceDate != null && range.contains(e.invoiceDate!))
        .toList();
  }

  /// Every staff salary payment whose
  /// [StaffSalaryPaymentModel.paymentDate] falls within [range].
  Future<List<StaffSalaryPaymentModel>> getSalaryPaymentsForAcademicYear(
    AcademicYearDateRange range,
  ) async {
    final snap = await _salary.get();
    return snap.docs
        .map((d) => StaffSalaryPaymentModel.fromMap(d.id, d.data()))
        .where((e) => e.paymentDate != null && range.contains(e.paymentDate!))
        .toList();
  }

  Future<String> createCategory(FinanceCategoryModel category) async {
    final doc = _categories.doc();
    await doc.set(category.toMap());
    return doc.id;
  }

  /// Which kinds of Finance record refer to [category], as plain labels
  /// (empty when it is unused). Transactions store the category both by id
  /// (`categoryId`: income, direct expenses, ledger) and by name
  /// (`categoryName`; expense invoices store only the name, and their edit
  /// dialog re-selects the category by that name), so both are checked —
  /// voided/cancelled records included, as they are kept for audit. One
  /// `limit(1)` query per check; nothing is changed.
  Future<List<String>> categoryReferences(FinanceCategoryModel category) async {
    final name = category.name.trim();
    Future<bool> used(CollectionReference<Map<String, dynamic>> c, {bool byId = true}) async {
      if (byId && (await c.where('categoryId', isEqualTo: category.id).limit(1).get()).docs.isNotEmpty) return true;
      if (name.isEmpty) return false;
      return (await c.where('categoryName', isEqualTo: name).limit(1).get()).docs.isNotEmpty;
    }

    return [
      if (await used(_income)) 'income entries',
      if (await used(_expenses)) 'expense records',
      if (await used(_invoices, byId: false)) 'expense invoices',
      if (await used(_ledger)) 'ledger entries',
    ];
  }

  /// Updates a non-default category's name, type and active flag.
  /// - Name is required (trimmed); no other category of the same type may
  ///   have the same name (case-insensitive).
  /// - A category in use keeps its name and type (renaming would detach
  ///   invoices that refer to it by name; a type change would reclassify
  ///   history); it can still be deactivated, which hides it from new
  ///   entries while existing records keep it.
  /// - Default (`isSystem`) categories can't be changed.
  /// Transactions are never modified.
  Future<void> updateCategory({
    required String id,
    required String name,
    required String type,
    required bool isActive,
  }) async {
    final ref = _categories.doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Category not found.');
    final current = FinanceCategoryModel.fromMap(snap.id, data);
    if (current.isSystem) throw StateError('Default categories can\'t be changed.');
    final newName = name.trim();
    if (newName.isEmpty) throw StateError('Category name is required.');
    if (type != 'income' && type != 'expense') throw StateError('Category type must be income or expense.');
    final all = await _categories.get();
    final duplicate = all.docs.any((d) =>
        d.id != id &&
        (d.data()['name']?.toString().trim().toLowerCase() ?? '') == newName.toLowerCase() &&
        (d.data()['type']?.toString() ?? 'income') == type);
    if (duplicate) throw StateError('Another $type category is already named "$newName".');
    if (newName != current.name.trim() || type != current.type) {
      final refs = await categoryReferences(current);
      if (refs.isNotEmpty) {
        throw StateError(
          '"${current.name}" is used by ${refs.join(', ')}, so its name and type can\'t be changed. '
          'You can deactivate it instead.',
        );
      }
    }
    await ref.set({
      'name': newName,
      'type': type,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes a category only when nothing refers to it (see
  /// [categoryReferences]) and it isn't a default category, so no
  /// transaction is left pointing at a missing category. A category in use
  /// should be deactivated instead ([updateCategory] with `isActive: false`).
  /// There is a brief window between the check and the delete in which a new
  /// transaction could pick the category; such a record still keeps its own
  /// copy of the category name.
  Future<void> deleteCategory(String id) async {
    final ref = _categories.doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Category not found.');
    final category = FinanceCategoryModel.fromMap(snap.id, data);
    if (category.isSystem) throw StateError('Default categories can\'t be deleted.');
    final refs = await categoryReferences(category);
    if (refs.isNotEmpty) {
      throw StateError(
        '"${category.name}" is used by ${refs.join(', ')}, so it can\'t be deleted without leaving '
        'those records pointing at a missing category. Deactivate it instead to hide it from new entries.',
      );
    }
    await ref.delete();
  }

  Future<String> createAccount(FinanceAccountModel account) async {
    final doc = _accounts.doc();
    await doc.set(account.toMap());
    return doc.id;
  }

  /// Account types offered by the Add/Edit Account form.
  static const accountTypes = ['cash', 'bank', 'upi', 'wallet', 'other'];

  /// The payment types (cash / bank / upi, see [_accountTypeForPaymentMode])
  /// whose payments are routed to an active account of that type by
  /// [_matchAccountForPaymentMode].
  static const _paymentTypes = ['cash', 'bank', 'upi'];

  static bool _servesPaymentType(String accountType, String paymentType) =>
      accountType.toLowerCase().contains(paymentType);

  /// What depends on [account] (read-only; one `limit(1)` query per record
  /// collection):
  /// - Finance records that store its `accountId` — ledger entries, income
  ///   (manual, fee collection and invoice payments), direct expenses and
  ///   salary payments — voided/cancelled ones included, as they are kept
  ///   for audit and still point at the account;
  /// - the payment types it is the only active account for, and whether it
  ///   is the last active account (new payments are routed to an active
  ///   account by type, falling back to any active one).
  Future<FinanceAccountUsage> accountUsage(FinanceAccountModel account) async {
    Future<bool> used(CollectionReference<Map<String, dynamic>> c) async =>
        (await c.where('accountId', isEqualTo: account.id).limit(1).get()).docs.isNotEmpty;
    final references = [
      if (await used(_ledger)) 'ledger entries',
      if (await used(_income)) 'income and payment records',
      if (await used(_expenses)) 'expense records',
      if (await used(_salary)) 'salary payment records',
    ];
    final others = (await _accounts.where('isActive', isEqualTo: true).get())
        .docs
        .where((d) => d.id != account.id)
        .map((d) => d.data()['type']?.toString() ?? '')
        .toList();
    return FinanceAccountUsage(
      references: references,
      onlyActiveFor: account.isActive
          ? [
              for (final t in _paymentTypes)
                if (_servesPaymentType(account.type, t) && !others.any((o) => _servesPaymentType(o, t))) t,
            ]
          : const [],
      isLastActive: account.isActive && others.isEmpty,
      openingBalance: account.openingBalance,
      currentBalance: account.currentBalance,
    );
  }

  /// Edits an account in place (same document id; transactions are never
  /// touched — they keep their own `accountId` and saved `accountName`).
  /// - Name is required (trimmed) and unique across accounts
  ///   (case-insensitive). Balances are worked out by id and type, never by
  ///   name, so a rename is safe; existing records keep the name they were
  ///   saved with.
  /// - Type and opening balance can change only while no Finance record
  ///   uses the account (a type change would move its history between
  ///   Cash/Bank/UPI; an opening-balance change would rewrite its closing
  ///   balance). A new opening balance moves the current balance by the same
  ///   difference.
  /// - It can't stop being the only active account for a payment type (by
  ///   type change or deactivation), nor can the last active account be
  ///   deactivated, since new payments would then go to another account
  ///   type or fail.
  Future<void> updateAccount({
    required String id,
    required String name,
    required String type,
    required double openingBalance,
    required bool isActive,
  }) async {
    final ref = _accounts.doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Account not found.');
    final current = FinanceAccountModel.fromMap(snap.id, data);
    final newName = name.trim();
    if (newName.isEmpty) throw StateError('Account name is required.');
    if (type != current.type && !accountTypes.contains(type)) throw StateError('Choose a valid account type.');
    if (!openingBalance.isFinite) throw StateError('Opening balance must be a number.');
    final all = await _accounts.get();
    final duplicate = all.docs.any((d) => d.id != id && (d.data()['name']?.toString().trim().toLowerCase() ?? '') == newName.toLowerCase());
    if (duplicate) throw StateError('Another account is already named "$newName".');

    final typeChanged = type != current.type;
    final openingChanged = openingBalance != current.openingBalance;
    final usage = await accountUsage(current);
    if ((typeChanged || openingChanged) && usage.references.isNotEmpty) {
      throw StateError(
        '"${current.name}" is used by ${usage.references.join(', ')}, so its type and opening balance can\'t be '
        'changed without changing past balances. You can still rename or deactivate it.',
      );
    }
    final lost = [for (final t in usage.onlyActiveFor) if (!isActive || !_servesPaymentType(type, t)) t];
    if (lost.isNotEmpty) {
      throw StateError(
        '"${current.name}" is the only active ${lost.join('/')} account, so new ${lost.join('/')} payments '
        'would go to a different account. Add or activate another ${lost.join('/')} account first.',
      );
    }
    if (!isActive && usage.isLastActive) {
      throw StateError('"${current.name}" is the last active account; new payments need at least one.');
    }

    await _firestore.runTransaction((txn) async {
      final live = await txn.get(ref);
      final liveData = live.data();
      if (!live.exists || liveData == null) throw StateError('Account not found.');
      double numVal(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
      txn.set(ref, {
        ...liveData,
        'name': newName,
        'type': type,
        'openingBalance': openingBalance,
        if (openingChanged) 'currentBalance': numVal(liveData['currentBalance']) + (openingBalance - numVal(liveData['openingBalance'])),
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Deletes an account only when nothing depends on it (see
  /// [FinanceAccountUsage.deleteBlockedReason]): no Finance record (voided
  /// ones included) points at it, its opening and current balances are
  /// zero (so no total changes), and it isn't required for routing new
  /// payments. Otherwise it should be deactivated instead, where allowed.
  /// There is a brief window between the check and the delete in which a new
  /// payment could pick the account; such a record keeps its own copy of the
  /// account name.
  Future<void> deleteAccount(String id) async {
    final ref = _accounts.doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Account not found.');
    final usage = await accountUsage(FinanceAccountModel.fromMap(snap.id, data));
    final reason = usage.deleteBlockedReason(data['name']?.toString() ?? 'This account');
    if (reason != null) throw StateError(reason);
    await ref.delete();
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
    final targetType = _accountTypeForPaymentMode(paymentMode);
    for (final doc in accounts) {
      final type = doc.data()['type']?.toString().toLowerCase() ?? '';
      if (type.contains(targetType)) return doc;
    }
    return accounts.first;
  }

  /// The account type a payment mode maps to — the mapping
  /// [_matchAccountForPaymentMode] has always used.
  static String _accountTypeForPaymentMode(String paymentMode) {
    final mode = paymentMode.toLowerCase();
    return mode.contains('cash')
        ? 'cash'
        : mode.contains('upi')
            ? 'upi'
            : 'bank';
  }

  /// When an edit changes an income entry's payment mode, the account the
  /// money belongs to must follow it. Returns null when no move is needed
  /// (mode unchanged, or the current account already has the matching
  /// type); otherwise the single active account of the matching type. Unlike
  /// [_matchAccountForPaymentMode] it never falls back to an arbitrary
  /// account: zero or several candidates reject the edit, since the right
  /// account can't be determined. Expense/salary invoice payments (also in
  /// finance_income, but money out) can't have their mode changed here.
  Future<DocumentReference<Map<String, dynamic>>?> _destinationAccountForModeChange({
    required Map<String, dynamic> current,
    required String newPaymentMode,
  }) async {
    final oldMode = (current['paymentMode']?.toString() ?? '').trim().toLowerCase();
    final newMode = newPaymentMode.trim().toLowerCase();
    if (oldMode == newMode) return null;
    if (current['sourceModule']?.toString() == 'invoice') {
      throw StateError('The payment mode of an invoice payment cannot be changed here.');
    }
    final targetType = _accountTypeForPaymentMode(newMode);
    bool matches(Map<String, dynamic>? account) =>
        (account?['type']?.toString().toLowerCase() ?? '').contains(targetType);
    final accountId = current['accountId']?.toString() ?? '';
    if (accountId.isNotEmpty) {
      final currentAccount = await _accounts.doc(accountId).get();
      if (currentAccount.exists && matches(currentAccount.data())) return null;
    }
    final active = await _accounts.where('isActive', isEqualTo: true).get();
    final candidates = active.docs.where((d) => matches(d.data())).toList();
    if (candidates.length != 1) {
      throw StateError(
        'Cannot change the payment mode to "$newPaymentMode": '
        '${candidates.isEmpty ? 'there is no active' : 'there is more than one active'} '
        '$targetType account, so the account this payment belongs to cannot be '
        'determined. Save without changing the payment mode, or adjust the accounts first.',
      );
    }
    return candidates.single.reference;
  }

  /// Applies an income edit (and its ledger mirror and account balances) in
  /// one Firestore transaction: all reads first, then all writes, re-reading
  /// the income entry so a concurrent void is never overwritten. If the
  /// payment mode change requires a different account (see
  /// [_destinationAccountForModeChange]), the old amount leaves the original
  /// account, the new amount lands in the destination account, and both the
  /// income and ledger entries point at the destination; otherwise the
  /// original account is adjusted by the amount delta, as before. Full
  /// merged maps are written rather than `SetOptions(merge: true)` — see
  /// [updateIncome].
  Future<void> _commitIncomeEdit({
    required DocumentReference<Map<String, dynamic>> incomeRef,
    required Map<String, dynamic> preRead,
    required String paymentMode,
    required double amount,
    required Map<String, dynamic> incomeFields,
    required Map<String, dynamic> ledgerFields,
    required bool throwIfVoided,
  }) async {
    final destinationRef = await _destinationAccountForModeChange(current: preRead, newPaymentMode: paymentMode);
    final accountId = preRead['accountId']?.toString() ?? '';
    final ledgerId = preRead['ledgerEntryId']?.toString() ?? '';
    final ledgerRef = ledgerId.isNotEmpty ? _ledger.doc(ledgerId) : null;
    final accountRef = accountId.isNotEmpty ? _accounts.doc(accountId) : null;

    await _firestore.runTransaction((txn) async {
      final incomeSnap = await txn.get(incomeRef);
      final ledgerSnap = ledgerRef != null ? await txn.get(ledgerRef) : null;
      final accountSnap = accountRef != null ? await txn.get(accountRef) : null;
      final destinationSnap = destinationRef != null ? await txn.get(destinationRef) : null;

      final live = incomeSnap.data();
      if (!incomeSnap.exists || live == null) throw StateError('Income entry not found');
      if (live['isDeleted'] == true) {
        if (throwIfVoided) {
          throw StateError('This income entry has been voided and can no longer be edited.');
        }
        return;
      }
      if ((live['accountId']?.toString() ?? '') != accountId ||
          (live['ledgerEntryId']?.toString() ?? '') != ledgerId) {
        throw StateError('This entry was changed while being edited. Please try again.');
      }
      final destinationData = destinationSnap?.data();
      if (destinationRef != null && (destinationData == null || destinationData['isActive'] != true)) {
        throw StateError('The account for the new payment mode is no longer available.');
      }

      final oldAmount = (live['amount'] as num?)?.toDouble() ?? 0.0;
      final accountFields = destinationRef != null
          ? {'accountId': destinationRef.id, 'accountName': destinationData!['name']?.toString() ?? ''}
          : const <String, dynamic>{};

      txn.set(incomeRef, {
        ...live,
        ...incomeFields,
        ...accountFields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final ledgerData = ledgerSnap?.data();
      if (ledgerRef != null && ledgerData != null) {
        txn.set(ledgerRef, {
          ...ledgerData,
          ...ledgerFields,
          ...accountFields,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final accountData = accountSnap?.data();
      double balanceOf(Map<String, dynamic> data) => (data['currentBalance'] as num?)?.toDouble() ?? 0.0;
      if (destinationRef != null) {
        if (accountRef != null && accountData != null) {
          txn.set(accountRef, {...accountData, 'currentBalance': balanceOf(accountData) - oldAmount});
        }
        txn.set(destinationRef, {...destinationData!, 'currentBalance': balanceOf(destinationData) + amount});
      } else if (accountRef != null && accountData != null) {
        txn.set(accountRef, {...accountData, 'currentBalance': balanceOf(accountData) + (amount - oldAmount)});
      }
    });
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
    final snap = await invoiceRef.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Invoice not found');
    }
    final invoice = FinanceInvoiceModel.fromMap(snap.id, snap.data()!);
    if (invoice.status == 'cancelled') {
      throw StateError('This invoice has been cancelled and cannot receive payments.');
    }
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
        'invoiceNo': invoice.invoiceNo,
        'invoicePaymentId': paymentRef.id,
        'invoiceType': invoice.type,
        'description': invoice.description,
      });
      txn.set(ledgerRef, {
        'id': ledgerRef.id,
        'entryType': 'expense',
        'sourceModule': 'invoice',
        'sourceId': invoiceId,
        'invoiceId': invoiceId,
        'invoiceNo': invoice.invoiceNo,
        'invoicePaymentId': paymentRef.id,
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

  /// Edits an existing expense invoice's descriptive fields and amount in
  /// place (same document id — never a new invoice). The invoice number,
  /// type, and recorded payments are never touched: `paidAmount` stays
  /// as-is, and `balanceAmount`/`status` are recomputed from the new total
  /// with the exact same formula [payInvoice] uses. Refuses a new total
  /// below what has already been paid, since that would leave payments
  /// exceeding the invoice. Raising/editing an invoice never moves money,
  /// so no ledger or account balance changes here.
  ///
  /// [partyId] is the selected vendor's id (`vendors` doc id); when null the
  /// invoice's stored `partyId` is left exactly as it is, so legacy invoices
  /// that only carry a vendor name keep it.
  ///
  /// Writes a full merged map inside a transaction rather than
  /// `SetOptions(merge: true)`, for the same fake_cloud_firestore reason
  /// documented on [updateIncome].
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
    if (amount <= 0) throw StateError('Amount must be greater than 0');
    if (taxAmount < 0) throw StateError('Tax amount cannot be negative');
    final invoiceRef = _invoices.doc(id);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(invoiceRef);
      if (!snap.exists || snap.data() == null) {
        throw StateError('Invoice not found');
      }
      final current = snap.data()!;
      final invoice = FinanceInvoiceModel.fromMap(snap.id, current);
      if (invoice.type != 'expense') {
        throw StateError('Only expense invoices can be edited here.');
      }
      if (invoice.status == 'cancelled') {
        throw StateError('This invoice has been cancelled and can no longer be edited.');
      }
      final totalAmount = amount + taxAmount;
      if (totalAmount < invoice.paidAmount) {
        throw StateError(
          'Total amount cannot be less than the ₹${invoice.paidAmount.toStringAsFixed(0)} already paid on this invoice.',
        );
      }
      final paidAmount = invoice.paidAmount;
      final balanceAmount = (totalAmount - paidAmount).clamp(0, double.infinity);
      final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
      txn.set(invoiceRef, {
        ...current,
        'partyId': ?partyId,
        'partyName': partyName,
        'categoryName': categoryName,
        'invoiceDate': invoiceDate,
        'amount': amount,
        'taxAmount': taxAmount,
        'totalAmount': totalAmount,
        'balanceAmount': balanceAmount,
        'status': status,
        'description': description,
        'attachmentUrl': attachmentUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Deletes an expense invoice that has no recorded payments. An invoice
  /// with any payment (non-zero `paidAmount`, or any payment entry in
  /// `finance_income` linked by `invoiceId`) is refused with an explanation
  /// rather than deleted, so payment history and ledger entries are never
  /// orphaned. An unpaid invoice has never posted anything to the ledger or
  /// an account balance (see [_createInvoice]), so removing it leaves
  /// accounting totals unchanged. The invoice number is not reused.
  Future<void> deleteExpenseInvoice(String id) async {
    final linkedPayments = await _income.where('invoiceId', isEqualTo: id).get();
    if (linkedPayments.docs.isNotEmpty) {
      throw StateError(
        'This invoice has recorded payments and cannot be deleted. Payment history must be preserved — use Cancel instead.',
      );
    }
    final invoiceRef = _invoices.doc(id);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(invoiceRef);
      if (!snap.exists || snap.data() == null) {
        throw StateError('Invoice not found');
      }
      final invoice = FinanceInvoiceModel.fromMap(snap.id, snap.data()!);
      if (invoice.type != 'expense') {
        throw StateError('Only expense invoices can be deleted here.');
      }
      if (invoice.status == 'cancelled') {
        throw StateError('A cancelled invoice is kept for audit and cannot be deleted.');
      }
      if (invoice.paidAmount > 0) {
        throw StateError(
          'This invoice has recorded payments and cannot be deleted. Payment history must be preserved — use Cancel instead.',
        );
      }
      txn.delete(invoiceRef);
    });
  }

  /// Every payment recorded against an expense invoice (from
  /// `finance_income`, where [payInvoice] writes them), including reversed
  /// ones (`isDeleted == true`), newest first — the invoice's full payment
  /// history for the Expenses UI.
  Future<List<FinanceIncomeModel>> getInvoicePayments(String invoiceId) async {
    final snap = await _income.where('invoiceId', isEqualTo: invoiceId).get();
    final items = snap.docs.map((d) => FinanceIncomeModel.fromMap(d.id, d.data())).toList();
    items.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  /// Reverses an expense-invoice payment that was recorded by mistake (no
  /// money actually moved). The original payment document is preserved —
  /// marked with the existing void convention (`isDeleted`, `deletedAt`,
  /// `deletedBy`) plus `reversalReason`/`reversedAt`/`reversedBy` — and its
  /// ledger mirror is marked `status: 'cancelled'` (the flag
  /// [watchDashboardSummary] already excludes), so nothing is erased.
  ///
  /// Unlike [_voidIncomeDoc] (which reverses *income*, so it subtracts),
  /// an expense payment reduced the account balance when recorded, so the
  /// reversal adds the amount back. The invoice's `paidAmount` is reduced
  /// and `balanceAmount`/`status` recomputed with [payInvoice]'s formula.
  /// A second reversal of the same payment is refused.
  ///
  /// Not a refund: if money was actually paid, the payment must stay.
  Future<void> reverseExpenseInvoicePayment({
    required String paymentId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw StateError('A reversal reason is required.');
    final paymentRef = _income.doc(paymentId);
    final initial = await paymentRef.get();
    if (!initial.exists || initial.data() == null) {
      throw StateError('Payment not found');
    }
    final invoiceId = initial.data()!['invoiceId']?.toString() ?? '';
    final ledgerId = initial.data()!['ledgerEntryId']?.toString() ?? '';
    final accountId = initial.data()!['accountId']?.toString() ?? '';
    if (invoiceId.isEmpty) throw StateError('This entry is not an invoice payment.');
    final invoiceRef = _invoices.doc(invoiceId);
    final ledgerRef = ledgerId.isNotEmpty ? _ledger.doc(ledgerId) : null;
    final accountRef = accountId.isNotEmpty ? _accounts.doc(accountId) : null;

    // Full merged maps rather than SetOptions(merge: true) — see [updateIncome].
    await _firestore.runTransaction((txn) async {
      final paymentSnap = await txn.get(paymentRef);
      final invoiceSnap = await txn.get(invoiceRef);
      final ledgerSnap = ledgerRef != null ? await txn.get(ledgerRef) : null;
      final accountSnap = accountRef != null ? await txn.get(accountRef) : null;

      final payment = paymentSnap.data()!;
      if (payment['sourceModule']?.toString() != 'invoice' || payment['invoiceType']?.toString() != 'expense') {
        throw StateError('Only expense invoice payments can be reversed here.');
      }
      if (payment['isDeleted'] == true) {
        throw StateError('This payment has already been reversed.');
      }
      if (!invoiceSnap.exists || invoiceSnap.data() == null) {
        throw StateError('Invoice not found');
      }
      final invoiceData = invoiceSnap.data()!;
      final invoice = FinanceInvoiceModel.fromMap(invoiceSnap.id, invoiceData);
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      final actor = _createdBy;

      txn.set(paymentRef, {
        ...payment,
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': actor,
        'reversalReason': reason.trim(),
        'reversedAt': FieldValue.serverTimestamp(),
        'reversedBy': actor,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (ledgerRef != null && ledgerSnap != null && ledgerSnap.data() != null) {
        txn.set(ledgerRef, {
          ...ledgerSnap.data()!,
          'status': 'cancelled',
          'reversalReason': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (accountRef != null && accountSnap != null && accountSnap.data() != null) {
        final currentBalance = (accountSnap.data()!['currentBalance'] as num?)?.toDouble() ?? 0.0;
        txn.set(accountRef, {
          ...accountSnap.data()!,
          'currentBalance': currentBalance + amount,
        });
      }
      final paidAmount = (invoice.paidAmount - amount).clamp(0, double.infinity).toDouble();
      final balanceAmount = (invoice.totalAmount - paidAmount).clamp(0, double.infinity);
      final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
      txn.set(invoiceRef, {
        ...invoiceData,
        'paidAmount': paidAmount,
        'balanceAmount': balanceAmount,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Cancels an expense invoice raised by mistake, keeping it as an
  /// auditable record (`status: 'cancelled'`, `cancellationReason`,
  /// `cancelledAt`, `cancelledBy`) instead of deleting it. Only allowed
  /// once the invoice has no active payments — mistaken payments must be
  /// reversed first via [reverseExpenseInvoicePayment], and real payments
  /// (money that actually moved) block cancellation entirely, since there
  /// is no refund workflow to offset them. `balanceAmount` is set to 0 so
  /// the cancelled invoice no longer counts as outstanding anywhere that
  /// sums balances; `totalAmount` and every other field are kept. A
  /// cancelled invoice cannot be cancelled again, edited, or paid.
  Future<void> cancelExpenseInvoice({
    required String id,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw StateError('A cancellation reason is required.');
    final payments = await _income.where('invoiceId', isEqualTo: id).get();
    if (payments.docs.any((d) => d.data()['isDeleted'] != true)) {
      throw StateError(
        'This invoice has active payments. Reverse any payment recorded by mistake before cancelling. '
        'Invoices with real payments cannot be cancelled.',
      );
    }
    final invoiceRef = _invoices.doc(id);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(invoiceRef);
      if (!snap.exists || snap.data() == null) {
        throw StateError('Invoice not found');
      }
      final current = snap.data()!;
      final invoice = FinanceInvoiceModel.fromMap(snap.id, current);
      if (invoice.type != 'expense') {
        throw StateError('Only expense invoices can be cancelled here.');
      }
      if (invoice.status == 'cancelled') {
        throw StateError('This invoice has already been cancelled.');
      }
      if (invoice.paidAmount > 0) {
        throw StateError(
          'This invoice has active payments. Reverse any payment recorded by mistake before cancelling.',
        );
      }
      txn.set(invoiceRef, {
        ...current,
        'status': 'cancelled',
        'balanceAmount': 0,
        'cancellationReason': reason.trim(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': _createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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

  /// Not called anywhere in the app (salary is paid through salary
  /// invoices and [payInvoice]). Its ledger entry records `netPayable`
  /// while the account is debited `paidAmount`, so a payment where the two
  /// differ would leave the ledger and the account balance disagreeing.
  /// Which amount is right is not defined, so such a payment is refused
  /// rather than guessed; when they agree the behaviour is unchanged.
  Future<String> createSalaryPayment(StaffSalaryPaymentModel payment) async {
    if ((payment.paidAmount * 100).round() != (payment.netPayable * 100).round()) {
      throw StateError(
        'Salary payment not recorded: the paid amount (${payment.paidAmount}) differs from the net '
        'payable (${payment.netPayable}), so the ledger and account balance would disagree. '
        'Record salary through a salary invoice instead.',
      );
    }
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

  /// Not called anywhere in the app. Cancelling a ledger entry on its own
  /// removes it from the summary totals but leaves its source record
  /// (income, expense payment, fee collection) active and its account's
  /// running balance unchanged, so Finance would disagree with itself. It
  /// is therefore refused for any entry linked to a source record or an
  /// account — use that record's own void/reverse action, which cancels
  /// the ledger entry with it. An unlinked entry can still be cancelled;
  /// the reason is stored as `cancellationReason` and the original
  /// description is kept for audit.
  Future<void> cancelLedgerEntry(String id, {String? reason}) async {
    final ref = _ledger.doc(id);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Ledger entry not found');
    bool has(String key) => (data[key]?.toString() ?? '').trim().isNotEmpty;
    if (has('sourceModule') || has('sourceId') || has('accountId')) {
      throw StateError(
        'This ledger entry belongs to a transaction and an account balance, so it cannot be '
        'cancelled on its own. Void or reverse the original transaction instead.',
      );
    }
    await ref.set({
      'status': 'cancelled',
      'cancellationReason': reason ?? '',
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

  /// Core void mechanics shared by [reverseFeeIncomeByCollectionId] (looked
  /// up by the originating Fee Collection's id) and [voidIncome] (looked up
  /// by the income entry's own id) — exactly one reversal implementation,
  /// two lookup entry points, so there is no second reversal architecture.
  /// Marks the income doc voided (soft-delete via `isDeleted`, preserving
  /// every original field for audit/history), cancels its linked ledger
  /// mirror (the same `status: 'cancelled'` flag [cancelLedgerEntry]
  /// already uses and [watchDashboardSummary] already filters on), and
  /// reverses the amount out of the linked account's running balance.
  ///
  /// All three documents change in one Firestore transaction: every read
  /// (income, ledger, account) happens first, then every write, so Firestore
  /// commits all of them or none, and retries the whole handler on a
  /// concurrent modification. The voided state is re-checked inside the
  /// transaction from its own fresh read; returns `false` (writing nothing)
  /// if the entry was already voided by the time it ran, so a repeated or
  /// concurrent void never reverses the account balance twice. A missing
  /// linked ledger entry or account is skipped rather than recreated as a
  /// stub. Full merged maps are written rather than
  /// `SetOptions(merge: true)` — see [updateIncome].
  ///
  /// With [refuseCancelledLedger] (the Fee Collection path), an active
  /// income entry whose ledger entry is already cancelled is refused with a
  /// [StateError], writing nothing: its account balance may already have
  /// been reversed, so reversing it again could double-count.
  Future<bool> _voidIncomeDoc(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    bool refuseCancelledLedger = false,
  }) async {
    final ledgerId = data['ledgerEntryId']?.toString() ?? '';
    final accountId = data['accountId']?.toString() ?? '';
    final ledgerRef = ledgerId.isNotEmpty ? _ledger.doc(ledgerId) : null;
    final accountRef = accountId.isNotEmpty ? _accounts.doc(accountId) : null;
    final actor = _createdBy;
    return _firestore.runTransaction<bool>((txn) async {
      final incomeSnap = await txn.get(ref);
      final ledgerSnap = ledgerRef != null ? await txn.get(ledgerRef) : null;
      final accountSnap = accountRef != null ? await txn.get(accountRef) : null;

      final current = incomeSnap.data();
      if (!incomeSnap.exists || current == null) {
        throw StateError('Income entry not found');
      }
      if (current['isDeleted'] == true) return false;
      if (refuseCancelledLedger && ledgerSnap?.data()?['status']?.toString() == 'cancelled') {
        throw StateError(_activeIncomeCancelledLedgerMessage);
      }
      final amount = (current['amount'] as num?)?.toDouble() ?? 0.0;

      txn.set(ref, {
        ...current,
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': actor,
      });
      final ledgerData = ledgerSnap?.data();
      if (ledgerRef != null && ledgerData != null) {
        txn.set(ledgerRef, {
          ...ledgerData,
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final accountData = accountSnap?.data();
      if (accountRef != null && accountData != null && amount > 0) {
        final balance = (accountData['currentBalance'] as num?)?.toDouble() ?? 0.0;
        txn.set(accountRef, {...accountData, 'currentBalance': balance - amount});
      }
      return true;
    });
  }

  /// Reverses the Finance income entry generated from Fee Collection
  /// [feeCollectionId]. Idempotent: a missing or already-voided entry is a
  /// no-op, and [_voidIncomeDoc] re-checks inside its transaction, so a
  /// retry or a concurrent call never reverses the account twice. Refuses
  /// (writing nothing) when more than one entry is linked to the collection,
  /// or when the entry is active but its ledger entry is already cancelled.
  Future<void> reverseFeeIncomeByCollectionId(String feeCollectionId) async {
    final existing = await _feeIncomeDocs(feeCollectionId);
    if (existing.isEmpty) return;
    if (existing.length > 1) throw StateError(_ambiguousFeeIncomeMessage(existing.length));
    final doc = existing.single;
    final data = doc.data();
    if (data['isDeleted'] == true) return;
    await _voidIncomeDoc(doc.reference, data, refuseCancelledLedger: true);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _feeIncomeDocs(String feeCollectionId) async =>
      (await _income
              .where('sourceModule', isEqualTo: 'fees')
              .where('sourceId', isEqualTo: feeCollectionId)
              .get())
          .docs;

  static String _ambiguousFeeIncomeMessage(int count) =>
      '$count Finance income entries are linked to this Fee Collection, so it cannot be '
      'voided safely. Nothing was changed. Review the duplicate Finance entries before retrying.';

  static const _activeIncomeCancelledLedgerMessage =
      'The linked Finance entry is active but its ledger entry is already cancelled, so the '
      'account balance may already have been reversed. Nothing was changed. Review the Finance '
      'ledger for this collection before retrying.';

  /// Read-only check of the Finance side of Fee Collection
  /// [feeCollectionId], used by FeeService.voidReceipt before it writes
  /// anything. Writes nothing.
  Future<FeeIncomeLink> inspectFeeIncomeLink(String feeCollectionId) async {
    final docs = await _feeIncomeDocs(feeCollectionId);
    if (docs.isEmpty) return const FeeIncomeLink(FeeIncomeLinkState.missing);
    if (docs.length > 1) {
      return FeeIncomeLink(FeeIncomeLinkState.ambiguous, message: _ambiguousFeeIncomeMessage(docs.length));
    }
    final doc = docs.single;
    final data = doc.data();
    final voided = data['isDeleted'] == true;
    final ledgerId = data['ledgerEntryId']?.toString() ?? '';
    // Null when there is no linked ledger entry (skipped on void, as before).
    final ledgerData = ledgerId.isEmpty ? null : (await _ledger.doc(ledgerId).get()).data();
    final ledgerStatus = ledgerData?['status']?.toString();
    double? amountOf(Map<String, dynamic>? d) => (d?['amount'] as num?)?.toDouble();
    if (!voided && ledgerStatus == 'cancelled') {
      return FeeIncomeLink(FeeIncomeLinkState.inconsistent, incomeId: doc.id, message: _activeIncomeCancelledLedgerMessage);
    }
    if (voided && ledgerStatus != null && ledgerStatus != 'cancelled') {
      return FeeIncomeLink(
        FeeIncomeLinkState.inconsistent,
        incomeId: doc.id,
        message: 'The linked Finance entry is voided but its ledger entry is still active, so the '
            'Finance records disagree. Nothing was changed. Review the Finance ledger for this '
            'collection before retrying.',
      );
    }
    return FeeIncomeLink(
      voided ? FeeIncomeLinkState.reversed : FeeIncomeLinkState.active,
      incomeId: doc.id,
      incomeAmount: amountOf(data),
      ledgerAmount: amountOf(ledgerData),
    );
  }

  /// [voidIncome] and [updateIncome] apply income-side accounting (a void
  /// takes the amount back out of the account; an edit adds the delta) and
  /// never touch an invoice. That is only right for manual income
  /// (`sourceModule` 'finance', or none on older entries). An expense or
  /// salary invoice payment is also stored in finance_income but is money
  /// out: voiding it here would debit the account a second time and leave
  /// the invoice's paid amount unchanged. The Income tab already hides
  /// those records; this refuses them (and any other source) at the
  /// service too.
  static void _refuseUnlessManualIncome(Map<String, dynamic> data, {required String action}) {
    final source = data['sourceModule']?.toString() ?? '';
    final isInvoicePayment = source == 'invoice' ||
        data['programType']?.toString() == 'invoice' ||
        (data['invoiceId']?.toString() ?? '').isNotEmpty;
    if (isInvoicePayment) {
      throw StateError(
        'This is an invoice payment, so it cannot be $action here. Use Reverse on the payment in '
        'the invoice details instead, which also updates the invoice balance.',
      );
    }
    if (source.isNotEmpty && source != 'finance') {
      throw StateError('This entry was created by "$source", so it cannot be $action here.');
    }
  }

  /// Voids a Finance income entry directly — the Finance UI's own Void
  /// action, keyed by the entry's own document id (as opposed to
  /// [reverseFeeIncomeByCollectionId]'s lookup by the originating Fee
  /// Collection's id), but sharing the exact same [_voidIncomeDoc]
  /// reversal mechanics.
  ///
  /// Refuses to void a Fee-Collection-sourced entry (`sourceModule ==
  /// 'fees'`): that entry's lifecycle is owned by its Fee Collection —
  /// voiding it here independently would leave the Fee Collection still
  /// showing as collected while Finance shows it voided, exactly the
  /// conflicting state a Finance edit/void must not create. Voiding the
  /// Fee Collection itself (in the Fees module) already reverses this
  /// entry via [reverseFeeIncomeByCollectionId].
  ///
  /// Also refuses a double-void, unlike [reverseFeeIncomeByCollectionId]'s
  /// silent no-op — that method is an idempotent internal safety net
  /// called from FeeService's own void path; this one is a direct,
  /// user-initiated action and should surface a clear error instead of
  /// silently doing nothing.
  Future<void> voidIncome(String id) async {
    final snap = await _income.doc(id).get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Income entry not found');
    }
    final data = snap.data()!;
    if (data['sourceModule']?.toString() == 'fees') {
      throw StateError(
        'This entry was generated from a Fee Collection. Void the Fee '
        'Collection in the Fees module instead — it will reverse this '
        'entry automatically.',
      );
    }
    _refuseUnlessManualIncome(data, action: 'voided');
    if (data['isDeleted'] == true) {
      throw StateError('This income entry has already been voided.');
    }
    final voided = await _voidIncomeDoc(snap.reference, data);
    if (!voided) {
      throw StateError('This income entry has already been voided.');
    }
  }

  /// Edits an existing, non-Fee-sourced income entry's fields in place.
  /// The account can't be picked directly, but it follows a payment-mode
  /// change (see [_commitIncomeEdit]) so the entry's mode and account never
  /// disagree. Refuses to edit a
  /// Fee-Collection-sourced entry for the same reason [voidIncome]
  /// refuses to void one.
  ///
  /// Updates the income doc, its linked ledger mirror, and the account
  /// running balance(s), all inside one Firestore transaction — the same
  /// atomic pattern [createIncome] already uses.
  ///
  /// Transactions here write complete merged maps (spread + overrides)
  /// rather than `Transaction.set(..., SetOptions(merge: true))`:
  /// fake_cloud_firestore's transaction mock does not honor that merge
  /// option (it silently drops every field not in the payload), so this
  /// avoids depending on it at all — and is equally correct against real
  /// Firestore.
  Future<void> updateIncome({
    required String id,
    required String title,
    required String categoryId,
    required String categoryName,
    required double amount,
    required DateTime date,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final incomeRef = _income.doc(id);
    final snap = await incomeRef.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Income entry not found');
    }
    final current = snap.data()!;
    if (current['sourceModule']?.toString() == 'fees') {
      throw StateError(
        'This entry was generated from a Fee Collection. Edit the Fee '
        'Collection in the Fees module instead — it will update this '
        'entry automatically.',
      );
    }
    _refuseUnlessManualIncome(current, action: 'edited');
    if (current['isDeleted'] == true) {
      throw StateError('This income entry has been voided and can no longer be edited.');
    }
    if (amount <= 0) {
      throw StateError('Amount must be greater than 0');
    }
    await _commitIncomeEdit(
      incomeRef: incomeRef,
      preRead: current,
      paymentMode: paymentMode,
      amount: amount,
      incomeFields: {
        'title': title,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'amount': amount,
        'incomeDate': date,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'remarks': remarks,
      },
      ledgerFields: {
        'title': title,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'amount': amount,
        'transactionDate': date,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'description': remarks,
      },
      throwIfVoided: true,
    );
  }

  /// Pushes a Fee Collection's corrected amount/date/paymentMode/
  /// referenceNo/remarks into its already-linked Finance income entry
  /// (plus that entry's ledger mirror and the account's running balance),
  /// found via the exact same `sourceModule == 'fees' + sourceId` lookup
  /// [createFeeIncomeEntry]/[reverseFeeIncomeByCollectionId] already use —
  /// reusing the existing relationship rather than creating a new one.
  /// This is an in-place field update on the SAME document, which is
  /// exactly what avoids [createFeeIncomeEntry]'s dedup-by-sourceId guard:
  /// that guard only ever matters when *creating* a new entry, and this
  /// method never does that.
  ///
  /// If no linked entry exists (Finance wasn't configured when the fee
  /// was originally collected) or it was already voided, this is a silent
  /// no-op — a voided linked entry can't normally happen from
  /// FeeService.updateCollection's caller (a voided collection is refused
  /// for edit before this is ever reached), so this is a defensive
  /// guard, not an expected path.
  ///
  /// Called from FeeService.updateCollection *after* its own Fees-side
  /// batch has already committed. True cross-service atomicity between
  /// that batch and this transaction is not achievable without merging
  /// FeeService and FinanceService into one write path (out of scope —
  /// see FeeService.updateCollection's doc comment for how a failure here
  /// is surfaced rather than hidden).
  Future<void> updateFeeIncomeEntry({
    required String feeCollectionId,
    required double amount,
    required DateTime date,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final existing = await _income
        .where('sourceModule', isEqualTo: 'fees')
        .where('sourceId', isEqualTo: feeCollectionId)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) return;
    final doc = existing.docs.first;
    final data = doc.data();
    if (data['isDeleted'] == true) return;
    await _commitIncomeEdit(
      incomeRef: _income.doc(doc.id),
      preRead: data,
      paymentMode: paymentMode,
      amount: amount,
      incomeFields: {
        'amount': amount,
        'incomeDate': date,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'remarks': remarks,
      },
      ledgerFields: {
        'amount': amount,
        'transactionDate': date,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
      },
      throwIfVoided: false,
    );
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

/// Finance-side state of a Fee Collection's income entry, as reported by
/// [FinanceService.inspectFeeIncomeLink].
enum FeeIncomeLinkState {
  /// No Finance income entry is linked to the collection.
  missing,

  /// One entry, not voided, ledger entry not cancelled.
  active,

  /// One entry, already voided (ledger entry cancelled or absent).
  reversed,

  /// More than one entry is linked to the collection.
  ambiguous,

  /// The income entry and its ledger entry disagree.
  inconsistent,
}

class FeeIncomeLink {
  const FeeIncomeLink(this.state, {this.incomeId = '', this.message = '', this.incomeAmount, this.ledgerAmount});

  final FeeIncomeLinkState state;

  /// The linked finance_income doc id, when there is exactly one.
  final String incomeId;

  /// Actionable explanation for [FeeIncomeLinkState.ambiguous] and
  /// [FeeIncomeLinkState.inconsistent].
  final String message;

  /// For [FeeIncomeLinkState.active]/[FeeIncomeLinkState.reversed]: the
  /// income entry's stored amount, and its ledger entry's (null when there
  /// is no ledger entry or no stored amount).
  final double? incomeAmount;
  final double? ledgerAmount;
}

/// See [FinanceService.accountUsage].
class FinanceAccountUsage {
  const FinanceAccountUsage({
    required this.references,
    required this.onlyActiveFor,
    required this.isLastActive,
    required this.openingBalance,
    required this.currentBalance,
  });

  /// Kinds of Finance record that point at the account (empty when none).
  final List<String> references;

  /// Payment types (cash/bank/upi) it is the only active account for.
  final List<String> onlyActiveFor;
  final bool isLastActive;
  final double openingBalance;
  final double currentBalance;

  /// True when it must stay active (and can't be deleted).
  bool get isRequired => onlyActiveFor.isNotEmpty || isLastActive;

  /// Why it can't be deactivated, or null.
  String? deactivateBlockedReason(String name) {
    if (onlyActiveFor.isNotEmpty) {
      final types = onlyActiveFor.join('/');
      return '"$name" is the only active $types account, so new $types payments would go to a different '
          'account. Add or activate another $types account first.';
    }
    if (isLastActive) return '"$name" is the last active account; new payments need at least one.';
    return null;
  }

  /// Why it can't be deleted, or null when deleting is safe.
  String? deleteBlockedReason(String name) {
    if (references.isNotEmpty) {
      return '"$name" is used by ${references.join(', ')}, so deleting it would leave those records '
          'pointing at a missing account and change the balances they count towards.';
    }
    if (openingBalance != 0 || currentBalance != 0) {
      return '"$name" has an opening balance of ₹${openingBalance.toStringAsFixed(0)} and a current balance of '
          '₹${currentBalance.toStringAsFixed(0)}, so deleting it would change the Closing Balance.';
    }
    return deactivateBlockedReason(name);
  }
}
