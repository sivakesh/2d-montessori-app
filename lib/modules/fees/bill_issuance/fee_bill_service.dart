import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../calendar/models/calendar_event_model.dart';
import '../models/amount_in_words.dart';
import '../models/fee_month.dart';
import '../models/fee_student.dart';
import '../services/fee_receipt_regeneration.dart' show ReceiptParent;
import 'fee_bill_models.dart';

class UnauthorizedFeeBillException implements Exception {
  UnauthorizedFeeBillException(this.role);
  final String role;
  @override
  String toString() => 'Only an administrator can issue or cancel fee bills (signed in as "$role").';
}

/// Called after bills of [studentId] were issued or cancelled, once the
/// transaction has committed (never for a refused or failed operation).
/// It must not throw; FeeBillService also contains anything it throws.
typedef FeeBillsChanged = Future<void> Function(FirebaseFirestore firestore, String studentId);

/// What a [FeeBillsBackfill] did: bills found, copies written, copies that
/// could not be written, and the first error ('' when none).
typedef FeeBillsBackfillResult = ({int found, int written, int failed, String error});

/// Brings every copy kept of the bills up to date with the bills themselves
/// (e.g. bills issued before such a copy existed) and reports what it did.
/// Must not throw.
typedef FeeBillsBackfill = Future<FeeBillsBackfillResult> Function(FirebaseFirestore firestore);

/// Fee Bill Issuance's own records (docs/fee_bill_issuance.md):
///
/// - `fee_issued_bills/{schoolId}_{billNo}`: one immutable bill each, with
///   snapshots of the original payment, student and school header, and an
///   `audit` subcollection (issued, cancelled, reprinted).
/// - `fee_bill_allocations/{receiptId}`: how much of that payment active
///   bills use (per bill). Every issue and cancel transaction reads and
///   writes the record of every payment it uses, so concurrent issuance is
///   serialised and can never allocate more than a payment.
///   It also holds that payment's bill sequence (`nextSequence`).
/// - `fee_bill_payment_allocations/{billId}__{receiptId}`: the allocation
///   ledger, one entry per bill and supporting payment (a bill may use
///   several payments, a payment may support several bills). Active, or
///   released by a cancellation.
/// - `fee_bill_allocation_reversals/{allocationId}`: the explicit record of
///   each released allocation. Never deleted.
/// - `fee_bill_issue_requests/{requestId}`: the bills an issue request
///   created, so a retry returns them instead of issuing again.
///
/// Bill References are `{receipt number}-{six-digit sequence}`
/// (`REC-2026-1792729533955-000001`), numbered separately for each original
/// payment from its allocation's `nextSequence`. A bill supported by
/// several payments is numbered from its primary payment: the earliest by
/// payment date, then the lowest receipt number. That counter is advanced
/// in the same transaction as the allocation and the bills, never goes
/// back, and is never reused, cancellations included.
///
/// Bills issued before the ledger have no `allocations`; they are read as
/// one allocation of their net amount from their one payment
/// ([FeeIssuedBill.allocations]), and their ledger entry is recorded when
/// they are cancelled.
///
/// It reads `fee_receipts`, `fee_transactions` and `students` and never
/// writes them, nor any
/// assignment, transaction, Finance income or ledger record; it calls no
/// FeeService or FinanceService method. Writes take the requester's role
/// and refuse anyone but an administrator (the app's convention, e.g.
/// ExpenseEfficiencyService).
///
/// After an issue or cancellation has committed it calls its
/// [FeeBillsChanged] hook (the Parent module's parent-safe bill copies);
/// the hook runs outside the transaction and never changes a bill, an
/// allocation, a counter or the operation's result.
class FeeBillService {
  FeeBillService({FirebaseFirestore? firestore, FirebaseAuth? auth, this.schoolId = kDefaultSchoolId, DateTime Function()? clock, FeeBillsChanged? afterChange})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _clock = clock ?? DateTime.now,
        _afterChange = afterChange;

  /// The app-wide [FeeBillsChanged], set once at startup by the module that
  /// keeps copies of bills (the Parent module's parent-safe bill copies:
  /// registerParentFeeBillRefresh), so this module imports none of it.
  /// An instance's own `afterChange` takes precedence.
  static FeeBillsChanged? defaultAfterChange;

  /// The app-wide [FeeBillsBackfill], registered the same way.
  static FeeBillsBackfill? defaultBackfill;

  /// Runs [defaultBackfill] for an administrator (Fee Bill Issuance calls it
  /// when the page opens) and returns its report — null when it didn't run
  /// (not an administrator, or nothing registered). Reads the bills, never
  /// writes them; anything it throws is reported, not hidden.
  Future<FeeBillsBackfillResult?> backfillDerivedCopies({required String requesterRole}) async {
    final hook = defaultBackfill;
    if (hook == null || requesterRole.toLowerCase() != 'admin') return null;
    try {
      return await hook(_firestore);
    } catch (e) {
      debugPrint('Fee bill backfill failed: $e');
      return (found: 0, written: 0, failed: 1, error: e.toString());
    }
  }

  final FeeBillsChanged? _afterChange;

  /// Runs the after-change hook for [studentId]; a failure there never
  /// affects the committed bill operation or its result.
  Future<void> _changed(String studentId) async {
    final hook = _afterChange ?? defaultAfterChange;
    if (hook == null || studentId.isEmpty) return;
    try {
      await hook(_firestore, studentId);
    } catch (e) {
      debugPrint('Fee bill after-change hook failed for $studentId: $e');
    }
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DateTime Function() _clock;
  final String schoolId;

  static const billsCollection = 'fee_issued_bills';
  static const allocationsCollection = 'fee_bill_allocations';
  static const ledgerCollection = 'fee_bill_payment_allocations';
  static const reversalsCollection = 'fee_bill_allocation_reversals';
  static const requestsCollection = 'fee_bill_issue_requests';

  /// Six-digit, zero-padded sequence; at most this many bills per payment.
  static const sequenceDigits = 6, maxSequence = 999999;

  /// At most this many bills in one issue, and payments supporting a bill
  /// (one transaction's writes, and a one-page PDF).
  static const maxBillsPerIssue = 12, maxPaymentsPerBill = 6;

  /// A receipt number usable as a Bill Reference base: letters, digits and
  /// single hyphens inside, starting and ending with a letter or digit, at
  /// most [maxReferenceBase] characters (so a reference stays within 40).
  static const maxReferenceBase = 33;
  static final _referenceBase = RegExp(r'^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$');

  /// The Bill Reference base for [receiptNo], or null when it can't make a
  /// valid, unambiguous reference (empty, too long, or with spaces, slashes
  /// or other characters).
  static String? referenceBaseOf(String receiptNo) {
    final r = receiptNo.trim();
    if (r.isEmpty || r.length > maxReferenceBase || r != receiptNo || !_referenceBase.hasMatch(r)) return null;
    return r;
  }

  /// `{base}-{sequence, six digits}`.
  static String billReference(String base, int sequence) => '$base-${sequence.toString().padLeft(sequenceDigits, '0')}';

  static String unusableReceiptNoMessage(String receiptNo) =>
      'This payment\'s receipt number "${receiptNo.trim().isEmpty ? '(none)' : receiptNo}" can\'t be used for Bill References '
      '(letters, digits and hyphens only, up to $maxReferenceBase characters), so no bill can be issued against it.';
  static String sharedReceiptNoMessage(String receiptNo) =>
      'More than one payment has the receipt number "$receiptNo", so its Bill References would be ambiguous. No bill was issued; please report this.';

  /// The school of a receipt with no `schoolId` field (every receipt today).
  static const legacyReceiptSchool = kDefaultSchoolId;

  static const maxReason = 500;
  static const notFoundMessage = 'The original payment could not be found, so no bill was issued.';
  static const voidedMessage = 'The original payment has been voided in Fees, so no bill can be issued against it.';
  static const otherSchoolMessage = 'The original payment belongs to another school, so no bill was issued.';
  static const otherStudentMessage = 'The original payment does not belong to the selected student, so no bill was issued.';
  static const inconsistentMessage = 'The bill allocation for this payment is inconsistent, so nothing was changed. Please report this.';
  static const noAmountMessage = 'The original payment has no amount, so no bill can be issued against it.';
  static String noTransactionMessage(String receiptNo) =>
      'Receipt $receiptNo has no linked Fees transaction record, so the payment can\'t be verified and can\'t support a new bill.';
  static String transactionMissingMessage(String receiptNo) =>
      'The Fees transaction record of receipt $receiptNo could not be found, so the payment can\'t be verified and can\'t support a new bill.';
  static String transactionVoidedMessage(String receiptNo) =>
      'The Fees transaction record of receipt $receiptNo has been voided, so the payment can\'t support a new bill.';
  static String transactionMismatchMessage(String receiptNo, String what) =>
      'The Fees transaction record of receipt $receiptNo does not match the receipt\'s $what, so the payment can\'t be verified '
      'and can\'t support a new bill. Please report this.';

  CollectionReference<Map<String, dynamic>> get _bills => _firestore.collection(billsCollection);
  CollectionReference<Map<String, dynamic>> get _allocations => _firestore.collection(allocationsCollection);
  CollectionReference<Map<String, dynamic>> get _receipts => _firestore.collection('fee_receipts');
  CollectionReference<Map<String, dynamic>> get _transactions => _firestore.collection('fee_transactions');
  CollectionReference<Map<String, dynamic>> get _ledger => _firestore.collection(ledgerCollection);
  CollectionReference<Map<String, dynamic>> get _reversals => _firestore.collection(reversalsCollection);
  CollectionReference<Map<String, dynamic>> get _requests => _firestore.collection(requestsCollection);
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');

  String get _actor => _auth.currentUser?.uid ?? _auth.currentUser?.email ?? 'admin';

  void _requireAdmin(String role) {
    if (role.toLowerCase() != 'admin') throw UnauthorizedFeeBillException(role);
  }

  // ------------------------------------------------ reads (read only)

  /// Every student, by name (the `students` collection, read only).
  Future<List<FeeStudent>> getStudents() async {
    final snap = await _students.get();
    return [for (final d in snap.docs) FeeStudent.fromMap(d.id, d.data())]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// [studentId]'s payments in this school, newest first, voided ones
  /// included (marked) so a bill's original payment can always be shown.
  Future<List<FeeBillPayment>> paymentsForStudent(String studentId) async {
    if (studentId.isEmpty) return const [];
    final snap = await _receipts.where('studentId', isEqualTo: studentId).get();
    final list = [
      for (final d in snap.docs)
        if (_receiptSchool(d.data()) == schoolId) FeeBillPayment.fromReceipt(d.id, d.data()),
    ]..sort((a, b) => (b.paymentDate ?? DateTime(0)).compareTo(a.paymentDate ?? DateTime(0)));
    return list;
  }

  Future<FeeBillPayment?> getPayment(String receiptId) async {
    if (receiptId.isEmpty) return null;
    final d = (await _receipts.doc(receiptId).get()).data();
    if (d == null || _receiptSchool(d) != schoolId) return null;
    return FeeBillPayment.fromReceipt(receiptId, d);
  }

  /// The allocation of payment [receiptId] (none issued yet: allocated 0).
  Future<FeeBillAllocation?> getAllocation(String receiptId) async {
    if (receiptId.isEmpty) return null;
    final d = (await _allocations.doc(receiptId).get()).data();
    if (d == null) return null;
    if ((d['schoolId']?.toString() ?? '') != schoolId) return null;
    return FeeBillAllocation.fromMap(receiptId, d);
  }

  List<FeeIssuedBill> _sorted(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) FeeIssuedBill.fromMap(d.id, d.data())]..sort((a, b) {
          // Newest issued first; a payment's bills by their sequence.
          final t = (b.issuedAt ?? DateTime(0)).compareTo(a.issuedAt ?? DateTime(0));
          return t != 0 ? t : b.billNo.compareTo(a.billNo);
        });

  /// This school's bills, newest first (cancelled ones included).
  Stream<List<FeeIssuedBill>> watchBills() => _bills.where('schoolId', isEqualTo: schoolId).snapshots().map(_sorted);
  Future<List<FeeIssuedBill>> getBills() async => _sorted(await _bills.where('schoolId', isEqualTo: schoolId).get());

  /// The bills supported by payment [receiptId] (this school only).
  Future<List<FeeIssuedBill>> billsForPayment(String receiptId) async =>
      [for (final b in await getBills()) if (b.usesPayment(receiptId)) b];

  /// [studentId]'s payments in this school, newest first, each with what
  /// active bills use of it, what is available, and why it can't support a
  /// new bill (voided, unverifiable, ...). Read only.
  Future<List<FeeBillPaymentBalance>> paymentBalancesForStudent(String studentId) async {
    final out = <FeeBillPaymentBalance>[];
    for (final p in await paymentsForStudent(studentId)) {
      final receipt = (await _receipts.doc(p.receiptId).get()).data();
      final tid = receipt?['transactionId']?.toString() ?? '';
      final transaction = tid.isEmpty ? null : (await _transactions.doc(tid).get()).data();
      out.add(FeeBillPaymentBalance(
        payment: p,
        allocatedPaise: (await getAllocation(p.receiptId))?.allocatedPaise ?? 0,
        ineligibleReason: ineligibility(receipt, transaction, studentId),
      ));
    }
    return out;
  }

  /// Every payment of this school with its allocation (the bill issuance
  /// report). Read only; never counted as income.
  Future<FeeBillAllocationReport> allocationReport() async {
    final receipts = await _receipts.get();
    final transactions = {for (final d in (await _transactions.get()).docs) d.id: d.data()};
    final allocations = {
      for (final d in (await _allocations.where('schoolId', isEqualTo: schoolId).get()).docs) d.id: FeeBillAllocation.fromMap(d.id, d.data()),
    };
    final out = <FeeBillPaymentBalance>[];
    for (final d in receipts.docs) {
      if (_receiptSchool(d.data()) != schoolId) continue;
      final p = FeeBillPayment.fromReceipt(d.id, d.data());
      out.add(FeeBillPaymentBalance(
        payment: p,
        allocatedPaise: allocations[d.id]?.allocatedPaise ?? 0,
        ineligibleReason: ineligibility(d.data(), transactions[d.data()['transactionId']?.toString() ?? ''], p.studentId),
      ));
    }
    out.sort((a, b) => (b.payment.paymentDate ?? DateTime(0)).compareTo(a.payment.paymentDate ?? DateTime(0)));
    return FeeBillAllocationReport(payments: out);
  }

  /// Bill [billId]'s ledger entries (none for a bill issued before the
  /// ledger until it is cancelled). Read only.
  Future<List<Map<String, dynamic>>> ledgerForBill(String billId) async =>
      [for (final d in (await _ledger.where('billId', isEqualTo: billId).get()).docs) if (d.data()['schoolId'] == schoolId) d.data()];

  Future<FeeIssuedBill?> getBill(String id) async {
    final d = (await _bills.doc(id).get()).data();
    if (d == null || d['schoolId'] != schoolId) return null;
    return FeeIssuedBill.fromMap(id, d);
  }

  /// A bill's history (issued, cancelled, reprinted), oldest first.
  Future<List<Map<String, dynamic>>> history(String billId) async {
    final docs = (await _bills.doc(billId).collection('audit').get()).docs.map((d) => d.data()).toList();
    docs.sort((a, b) => _ms(a['at']).compareTo(_ms(b['at'])));
    return docs;
  }

  static int _ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : v is DateTime ? v.millisecondsSinceEpoch : 0;

  static String _receiptSchool(Map<String, dynamic> d) {
    final s = d['schoolId']?.toString() ?? '';
    return s.isEmpty ? legacyReceiptSchool : s;
  }

  /// Every class as id → name (the `classes` collection, read only), for
  /// the bill's class selector.
  Future<Map<String, String>> getClassNames() async {
    final snap = await _firestore.collection('classes').get();
    return {for (final d in snap.docs) d.id: d.data()['name']?.toString() ?? ''};
  }

  /// The parent or guardian a bill for [studentId] names: the father, else
  /// the mother, else a guardian, from the student's linked parents
  /// (`students.parentLinks`, as on the regenerated receipt); null : none.
  static ReceiptParent? parentOf(Map<String, dynamic>? student) => ReceiptParent.preferred(ReceiptParent.fromStudent(student));

  Future<ReceiptParent?> parentFor(String studentId) async =>
      studentId.isEmpty ? null : parentOf((await _students.doc(studentId).get()).data());

  static const calendarCollection = 'school_calendar_events';
  static const calendarUnreadableMessage = 'The school calendar could not be read, so the bills\' issue dates (the first working day of each '
      'billing month) can\'t be worked out. Nothing was issued; please try again.';

  /// The Issue Date of a bill for [billingMonth] (`YYYY-MM`): its first
  /// working day ([FeeBillIssueDate]), from that month's school calendar
  /// events (read only). Refuses, rather than guessing, when the calendar
  /// can't be read.
  Future<DateTime> issueDateFor(String billingMonth) async {
    if (!FeeMonth.isValid(billingMonth)) throw StateError('Choose the billing month.');
    final year = int.parse(billingMonth.substring(0, 4)), month = int.parse(billingMonth.substring(5));
    final List<CalendarEventModel> events;
    try {
      final snap = await _firestore
          .collection(calendarCollection)
          .where('date', isGreaterThanOrEqualTo: DateTime(year, month))
          .where('date', isLessThan: DateTime(year, month + 1))
          .get();
      events = [for (final d in snap.docs) CalendarEventModel.fromMap(d.id, d.data())];
    } catch (_) {
      throw StateError(calendarUnreadableMessage);
    }
    return FeeBillIssueDate.firstWorkingDay(billingMonth, events);
  }

  Future<Map<String, DateTime>> _issueDates(Iterable<FeeBillLine> lines) async =>
      {for (final m in {for (final l in lines) l.billingMonth}) m: await issueDateFor(m)};

  /// A new, unique issue request id (a Firestore auto-id: 20 random
  /// characters), for [issueBills]'s `requestId`. Plain string generation,
  /// so it behaves the same on the web and on the Dart VM.
  String newRequestId() => _bills.doc().id;

  // ------------------------------------------------ issuing

  /// Issues one bill per line in [lines], each supported by payment
  /// [receiptId] alone (its whole net amount), numbered in order. The
  /// one-payment form of [issueAllocatedBills], with the same checks and
  /// records.
  Future<List<FeeIssuedBill>> issueBills({
    required String requesterRole,
    required String studentId,
    required String receiptId,
    required List<FeeBillLine> lines,
    required String requestId,
    required FeeBillSchool school,
    bool amountIncludesGst = false,
  }) async {
    _requireAdmin(requesterRole);
    if (receiptId.isEmpty) throw StateError('Choose the original payment.');
    return issueAllocatedBills(
      requesterRole: requesterRole,
      studentId: studentId,
      drafts: [for (final l in lines) FeeBillDraft(line: l, allocations: {receiptId: l.normalized.netPaise})],
      requestId: requestId,
      school: school,
      amountIncludesGst: amountIncludesGst,
    );
  }

  /// Issues one bill per draft in [drafts], each supported by the payments
  /// in its allocations (receipt id → paise), which must total its net
  /// amount. [requestId] identifies this attempt (one per Issue button
  /// press): repeating it returns the bills it already issued.
  ///
  /// Checked before the transaction: the administrator; at most
  /// [maxBillsPerIssue] bills and [maxPaymentsPerBill] payments per bill;
  /// every line valid with a net amount above 0; no negative allocation;
  /// each bill's allocations equal to its net; each bill's primary payment
  /// (earliest payment date, then lowest receipt number) with a usable,
  /// unique receipt number.
  ///
  /// Then in one transaction, reading first: every payment must be an
  /// active receipt of this school and of [studentId] with its matching,
  /// active Fees transaction record of the same amount; no bill line may
  /// repeat an active bill line of any payment supporting it; no payment
  /// may be allocated beyond what active bills leave of it. The bills,
  /// their audit entries, one ledger entry per bill and payment, the
  /// payments' allocation records (and the primary payments' sequences)
  /// and the request record are written together, or nothing is.
  Future<List<FeeIssuedBill>> issueAllocatedBills({
    required String requesterRole,
    required String studentId,
    required List<FeeBillDraft> drafts,
    required String requestId,
    required FeeBillSchool school,
    bool amountIncludesGst = false,
  }) async {
    _requireAdmin(requesterRole);
    if (studentId.isEmpty) throw StateError('Choose the student.');
    if (requestId.trim().isEmpty) throw StateError('Missing issue request id.');
    final planned = _checkDrafts(drafts);
    final receiptIds = {for (final d in planned) ...d.allocations.keys};
    final multi = receiptIds.length > 1;

    // Read only: each bill's primary payment and its Bill Reference base
    // (re-checked in the transaction).
    final pre = <String, Map<String, dynamic>?>{};
    for (final id in receiptIds) {
      pre[id] = (await _receipts.doc(id).get()).data();
    }
    final primaries = [for (final d in planned) _primaryOf(d.allocations.keys, pre, multi)];
    final bases = <String, String>{};
    for (final p in primaries.toSet()) {
      bases[p] = await _checkedReferenceBase(p);
    }
    final issueDates = await _issueDates([for (final d in planned) d.line]);

    final issuedBills = await _firestore.runTransaction((txn) async {
      // A repeated request: the bills it issued, unchanged.
      final requestRef = _requests.doc(requestId);
      final request = (await txn.get(requestRef)).data();
      if (request != null) return _requestedBills(txn, request);
      final states = <String, _PaymentState>{};
      for (final id in receiptIds) {
        states[id] = await _readPayment(txn, id);
      }
      for (final s in states.values) {
        if (s.allocData != null && s.allocData!['schoolId'] != schoolId) throw StateError(otherSchoolMessage);
      }
      // Requests recorded before request records existed.
      for (final s in states.values) {
        if (s.alloc.requests[requestId] case final done?) return _billsById(txn, done);
      }
      final parent = parentOf((await txn.get(_students.doc(studentId))).data());

      for (final s in states.values) {
        _verify(s, studentId, multi);
      }
      _checkPrimaries(planned, primaries, states, bases);
      for (final s in states.values) {
        if (s.allocData != null && !s.alloc.isConsistent) throw StateError(inconsistentMessage);
      }
      for (final d in planned) {
        for (final r in d.allocations.keys) {
          _checkDuplicates([d.line], states[r]!.keys);
        }
      }
      _checkAvailability(planned, states);

      final numbers = _numbers(primaries, states, bases);
      for (final (i, n) in numbers.indexed) {
        final billId = FeeIssuedBill.idFor(schoolId, n);
        if ((await txn.get(_bills.doc(billId))).exists) {
          throw StateError('Bill Reference $n already exists, so nothing was issued. Please report this.');
        }
        for (final r in planned[i].allocations.keys) {
          if ((await txn.get(_ledger.doc(FeeBillPaymentAllocation.idFor(billId, r)))).exists) {
            throw StateError('An allocation for Bill Reference $n already exists, so nothing was issued. Please report this.');
          }
        }
      }

      // Writes.
      final now = _clock();
      final issued = <FeeIssuedBill>[];
      for (final (i, d) in planned.indexed) {
        issued.add(_issueOne(txn,
            billNo: numbers[i], draft: d, primary: primaries[i], states: states, school: school, now: now, requestId: requestId,
            issueDate: issueDates[d.line.billingMonth]!, parent: parent, amountIncludesGst: amountIncludesGst, studentId: studentId));
      }
      final ids = [for (final b in issued) b.id];
      for (final s in states.values) {
        s.requests[requestId] = ids;
        _writeAllocation(txn, s, studentId);
      }
      txn.set(requestRef, {
        'schoolId': schoolId,
        'studentId': studentId,
        'billIds': ids,
        'receiptIds': receiptIds.toList(),
        'by': _actor,
        'at': now,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return issued;
    });
    // Committed (or a repeated request answered with its bills).
    await _changed(studentId);
    return issuedBills;
  }

  /// Cancels bill [billId] with [reason] (required). Its record, snapshot,
  /// allocations and history are kept. Each payment supporting it gets
  /// back exactly what this bill used of it: its ledger entry is marked
  /// released and an explicit reversal record is written (for a bill issued
  /// before the ledger, its entry is recorded now, already released). No
  /// other bill's allocation is touched.
  ///
  /// With [replacement], a new bill (new Bill Reference, new allocations)
  /// is issued in the same transaction and linked both ways, checked like
  /// any issue after the release. Its allocations are
  /// [replacementAllocations]; when omitted, the cancelled bill's own
  /// payment for a one-payment bill, or its same allocations when the net
  /// amount is unchanged. Returns the replacement.
  ///
  /// Refused, writing nothing, when the bill is not an issued bill of this
  /// school, or its payments' records don't show exactly its allocations
  /// (they would be left inconsistent).
  Future<FeeIssuedBill?> cancelBill({
    required String requesterRole,
    required String billId,
    required String reason,
    FeeBillLine? replacement,
    FeeBillSchool? replacementSchool,
    Map<String, int>? replacementAllocations,
  }) async {
    _requireAdmin(requesterRole);
    final why = reason.trim();
    if (why.isEmpty) throw StateError('Enter the reason for cancelling this bill.');
    if (why.length > maxReason) throw StateError('The reason must be $maxReason characters or fewer.');
    final line = replacement?.normalized;
    FeeBillDraft? draft;
    String? primary, base;
    DateTime? replacementIssueDate;
    if (line != null) {
      _checkLines([line]);
      replacementIssueDate = await issueDateFor(line.billingMonth);
      final b = await getBill(billId);
      if (b != null) {
        draft = _checkDrafts([FeeBillDraft(line: line, allocations: _replacementAllocations(b, line, replacementAllocations))], replacement: true).single;
        final pre = <String, Map<String, dynamic>?>{};
        for (final id in draft.allocations.keys) {
          pre[id] = (await _receipts.doc(id).get()).data();
        }
        primary = _primaryOf(draft.allocations.keys, pre, draft.allocations.length > 1);
        base = await _checkedReferenceBase(primary);
      }
    }
    var studentId = '';
    final replacementBill = await _firestore.runTransaction((txn) async {
      final billRef = _bills.doc(billId);
      final data = (await txn.get(billRef)).data();
      if (data == null || data['schoolId'] != schoolId) throw StateError('This bill could not be found.');
      final bill = FeeIssuedBill.fromMap(billId, data);
      if (bill.isCancelled) throw StateError('Bill ${bill.billNo} is already cancelled.');
      studentId = bill.payment.studentId;
      final allocations = bill.allocations;
      final receiptIds = {for (final a in allocations) a.receiptId, ...?draft?.allocations.keys};
      final states = <String, _PaymentState>{};
      for (final id in receiptIds) {
        states[id] = await _readPayment(txn, id);
      }
      final ledger = <String, Map<String, dynamic>?>{};
      for (final a in allocations) {
        ledger[a.allocationId] = (await txn.get(_ledger.doc(a.allocationId))).data();
        if ((await txn.get(_reversals.doc(a.allocationId))).exists) throw StateError(inconsistentMessage);
      }

      // The payments' records must show exactly this bill's allocations.
      if (bill.allocatedPaise != bill.line.netPaise) throw StateError(inconsistentMessage);
      for (final a in allocations) {
        final s = states[a.receiptId]!;
        final entry = ledger[a.allocationId];
        final ledgerOk = bill.isLegacy
            ? entry == null
            : entry != null &&
                entry['billId'] == billId &&
                entry['receiptId'] == a.receiptId &&
                FeeBillAllocationStatus.of(entry['status']) == FeeBillAllocationStatus.active &&
                (entry['allocatedPaise'] as num?)?.toInt() == a.allocatedPaise;
        if (s.allocData == null ||
            s.allocData!['schoolId'] != schoolId ||
            !s.alloc.isConsistent ||
            s.alloc.bills[billId] != a.allocatedPaise ||
            s.alloc.lineKeys[bill.line.key] != billId ||
            !ledgerOk) {
          throw StateError(inconsistentMessage);
        }
      }
      // Release only this bill's allocations.
      for (final a in allocations) {
        states[a.receiptId]!
          ..bills.remove(billId)
          ..keys.remove(bill.line.key);
      }

      ReceiptParent? parent;
      String? newNo;
      if (line != null) {
        if (draft == null || base == null || primary == null) throw StateError('This bill could not be found.');
        parent = parentOf((await txn.get(_students.doc(bill.payment.studentId))).data());
        final multi = draft.allocations.length > 1;
        for (final r in draft.allocations.keys) {
          final s = states[r]!;
          if (s.allocData != null && s.allocData!['schoolId'] != schoolId) throw StateError(otherSchoolMessage);
          _verify(s, bill.payment.studentId, multi);
          if (s.allocData != null && !s.alloc.isConsistent) throw StateError(inconsistentMessage);
          _checkDuplicates([line], s.keys);
        }
        _checkAvailability([draft], states);
        _checkPrimaries([draft], [primary], states, {primary: base});
        final s = states[primary]!;
        if (s.next > maxSequence) {
          throw StateError('This payment already has the maximum of $maxSequence Bill References, so no replacement can be issued.');
        }
        newNo = billReference(base, s.next);
        final newId = FeeIssuedBill.idFor(schoolId, newNo);
        if ((await txn.get(_bills.doc(newId))).exists) {
          throw StateError('Bill Reference $newNo already exists, so nothing was changed. Please report this.');
        }
        for (final r in draft.allocations.keys) {
          if ((await txn.get(_ledger.doc(FeeBillPaymentAllocation.idFor(newId, r)))).exists) {
            throw StateError('An allocation for Bill Reference $newNo already exists, so nothing was changed. Please report this.');
          }
        }
        s.next++;
      }

      // Writes.
      final now = _clock();
      FeeIssuedBill? issued;
      if (line != null) {
        // The replacement keeps the cancelled bill's GST choices.
        issued = _issueOne(txn,
            billNo: newNo!, draft: draft!, primary: primary!, states: states, school: replacementSchool ?? bill.school, now: now,
            replacesBillId: billId, issueDate: replacementIssueDate!, parent: parent, amountIncludesGst: bill.amountIncludesGst,
            studentId: bill.payment.studentId);
      }
      txn.update(billRef, {
        'status': FeeBillStatus.cancelled.key,
        'cancellation': {'reason': why, 'by': _actor, 'at': now},
        if (issued != null) 'replacedByBillId': issued.id,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _actor,
      });
      txn.set(billRef.collection('audit').doc(), {
        'action': 'cancelled',
        'reason': why,
        'releasedPaise': bill.line.netPaise,
        'released': [for (final a in allocations) {'receiptNo': a.receiptNo, 'allocatedPaise': a.allocatedPaise}],
        if (issued != null) 'replacedBy': issued.billNo,
        'by': _actor,
        'at': now,
      });
      for (final a in allocations) {
        final reversal = {
          'schoolId': schoolId,
          'allocationId': a.allocationId,
          'billId': billId,
          'billNo': bill.billNo,
          'studentId': bill.payment.studentId,
          'receiptId': a.receiptId,
          'receiptNo': a.receiptNo,
          'releasedPaise': a.allocatedPaise,
          'reason': why,
          'replacedByBillId': issued?.id ?? '',
          'legacy': bill.isLegacy,
          'by': _actor,
          'at': now,
          'createdAt': FieldValue.serverTimestamp(),
        };
        txn.set(_reversals.doc(a.allocationId), reversal);
        final released = {'status': FeeBillAllocationStatus.released.key, 'reversalId': a.allocationId, 'releasedAt': now, 'releasedBy': _actor};
        if (bill.isLegacy) {
          // A bill issued before the ledger: its allocation, as the bill
          // has always implied it, recorded now and already released.
          txn.set(_ledger.doc(a.allocationId), {
            ..._ledgerEntry(bill: bill, allocation: a, requestId: '', at: bill.issuedAt ?? now, by: bill.issuedBy),
            'legacy': true,
            'recordedAt': now,
            ...released,
          });
        } else {
          txn.update(_ledger.doc(a.allocationId), released);
        }
      }
      for (final s in states.values) {
        _writeAllocation(txn, s, s.allocData?['studentId']?.toString() ?? bill.payment.studentId);
      }
      return issued;
    });
    await _changed(studentId);
    return replacementBill;
  }

  /// Records that bill [billId] was reprinted (its history only; the bill,
  /// its number and snapshot are unchanged).
  Future<void> recordReprint({required String requesterRole, required String billId}) async {
    _requireAdmin(requesterRole);
    final ref = _bills.doc(billId);
    final d = (await ref.get()).data();
    if (d == null || d['schoolId'] != schoolId) throw StateError('This bill could not be found.');
    await ref.collection('audit').add({'action': 'reprinted', 'billNo': d['billNo'], 'by': _actor, 'at': _clock()});
  }


  // ------------------------------------------------ helpers

  /// The Bill Reference base of payment [receiptId]: its receipt number,
  /// when that is usable ([referenceBaseOf]) and no other receipt of this
  /// school has the same number (references must be unambiguous). Read
  /// only; the issuing transaction re-checks the receipt number.
  Future<String> _checkedReferenceBase(String receiptId) async {
    final data = (await _receipts.doc(receiptId).get()).data();
    if (data == null) throw StateError(notFoundMessage);
    if (_receiptSchool(data) != schoolId) throw StateError(otherSchoolMessage);
    final payment = FeeBillPayment.fromReceipt(receiptId, data);
    final base = referenceBaseOf(payment.receiptNo);
    if (base == null) throw StateError(unusableReceiptNoMessage(payment.receiptNo));
    final same = await _receipts.where('receiptNo', isEqualTo: base).get();
    if (same.docs.where((d) => _receiptSchool(d.data()) == schoolId).length > 1) throw StateError(sharedReceiptNoMessage(base));
    return base;
  }

  static void _checkLines(List<FeeBillLine> lines) {
    if (lines.isEmpty) throw StateError('Add at least one bill line.');
    for (final (i, l) in lines.indexed) {
      if (l.error case final e?) throw StateError('Bill line ${i + 1}: $e');
    }
    final seen = <String>{};
    for (final l in lines) {
      if (!seen.add(l.key)) throw StateError('Two bill lines are for the same month and description (${l.description.trim()}). Remove one.');
    }
  }

  /// [drafts] with normalized lines and only their non-zero allocations,
  /// after every check that needs no data: the limits, the lines, no
  /// negative allocation, at least one payment, allocations equal to net.
  static List<FeeBillDraft> _checkDrafts(List<FeeBillDraft> drafts, {bool replacement = false}) {
    if (drafts.length > maxBillsPerIssue) {
      throw StateError('At most $maxBillsPerIssue bills can be issued at once, and ${drafts.length} were entered. Issue the rest separately.');
    }
    final lines = [for (final d in drafts) d.line.normalized];
    _checkLines(lines);
    String label(int i) => replacement ? 'Replacement bill' : 'Bill line ${i + 1}';
    final out = <FeeBillDraft>[];
    for (final (i, d) in drafts.indexed) {
      final line = lines[i];
      if (line.netPaise <= 0) {
        throw StateError('${label(i)}: the net bill amount must be more than ₹0, because a bill must be supported by an amount actually paid.');
      }
      if (d.allocations.values.any((v) => v < 0)) throw StateError('${label(i)}: a payment allocation cannot be negative.');
      if (d.allocations.keys.any((k) => k.trim().isEmpty)) throw StateError('${label(i)}: choose the payment(s) supporting this bill.');
      final allocations = {for (final e in d.allocations.entries) if (e.value > 0) e.key: e.value};
      if (allocations.isEmpty) throw StateError('${label(i)}: choose the payment(s) supporting this bill and enter how much of each it uses.');
      if (allocations.length > maxPaymentsPerBill) {
        throw StateError('${label(i)} is supported by ${allocations.length} payments, but a bill can be supported by at most $maxPaymentsPerBill.');
      }
      final total = allocations.values.fold<int>(0, (s, v) => s + v);
      if (total != line.netPaise) {
        throw StateError('${label(i)}: its payment allocations total ${billMoney(total)}, but its net bill amount is ${billMoney(line.netPaise)}. They must be equal.');
      }
      out.add(FeeBillDraft(line: line, allocations: allocations));
    }
    return out;
  }

  /// The replacement's allocations: [given]; otherwise the cancelled
  /// bill's one payment (all of the new net), or the bill's own
  /// allocations when the net amount is unchanged.
  static Map<String, int> _replacementAllocations(FeeIssuedBill bill, FeeBillLine line, Map<String, int>? given) {
    if (given != null) return given;
    final a = bill.allocations;
    if (a.length == 1) return {a.single.receiptId: line.netPaise};
    if (line.netPaise == bill.line.netPaise) return {for (final x in a) x.receiptId: x.allocatedPaise};
    throw StateError('Bill ${bill.billNo} was supported by ${a.length} payments. Enter how much of each the replacement uses '
        '(they must total its net amount, ${billMoney(line.netPaise)}).');
  }

  /// The primary payment of the receipts in [ids] (earliest payment date,
  /// then lowest receipt number), from their records [receipts].
  String _primaryOf(Iterable<String> ids, Map<String, Map<String, dynamic>?> receipts, bool multi) {
    String? best;
    FeeBillPayment? bestPayment;
    for (final id in ids) {
      final d = receipts[id];
      if (d == null) throw StateError(multi ? 'A payment chosen for these bills could not be found, so no bill was issued.' : notFoundMessage);
      final p = FeeBillPayment.fromReceipt(id, d);
      if (bestPayment == null || comparePrimaryPayment(p.paymentDate, p.receiptNo, bestPayment.paymentDate, bestPayment.receiptNo) < 0) {
        best = id;
        bestPayment = p;
      }
    }
    return best!;
  }

  /// The primaries worked out before the transaction still hold for the
  /// payments as read in it, and their receipt numbers are unchanged.
  void _checkPrimaries(List<FeeBillDraft> drafts, List<String> primaries, Map<String, _PaymentState> states, Map<String, String> bases) {
    for (final (i, d) in drafts.indexed) {
      final now = _primaryOf(d.allocations.keys, {for (final r in d.allocations.keys) r: states[r]!.receipt}, true);
      if (now != primaries[i]) {
        throw StateError('A payment\'s date or receipt number changed while the bills were being issued, so nothing was issued. Please try again.');
      }
      final p = states[now]!.payment!;
      if (p.receiptNo != bases[now]) throw StateError(unusableReceiptNoMessage(p.receiptNo));
    }
  }

  /// Every payment's new allocations fit in what active bills leave of it.
  void _checkAvailability(List<FeeBillDraft> drafts, Map<String, _PaymentState> states) {
    final requested = <String, int>{};
    for (final d in drafts) {
      for (final e in d.allocations.entries) {
        requested[e.key] = (requested[e.key] ?? 0) + e.value;
      }
    }
    for (final e in requested.entries) {
      final s = states[e.key]!;
      final payment = s.payment!.amountPaise;
      final available = payment - s.allocatedNow;
      if (e.value <= available) continue;
      final left = billMoney(available < 0 ? 0 : available);
      if (requested.length == 1) {
        throw StateError('These bills total ${billMoney(e.value)} net, but only $left of this payment (${billMoney(payment)}) is not yet billed. '
            'Reduce the amounts or add a bill-only adjustment.');
      }
      throw StateError('These bills use ${billMoney(e.value)} of receipt ${s.payment!.receiptNo}, but only $left of that payment '
          '(${billMoney(payment)}) is not yet billed. Reduce its allocations.');
    }
  }

  /// The Bill Reference of each bill, from its primary payment's next
  /// sequence numbers, in order (advancing them).
  List<String> _numbers(List<String> primaries, Map<String, _PaymentState> states, Map<String, String> bases) {
    final perPrimary = <String, int>{};
    for (final p in primaries) {
      perPrimary[p] = (perPrimary[p] ?? 0) + 1;
    }
    for (final e in perPrimary.entries) {
      if (states[e.key]!.next - 1 + e.value > maxSequence) {
        throw StateError('This payment already has the maximum of $maxSequence Bill References, so no more bills can be issued against it.');
      }
    }
    return [for (final p in primaries) billReference(bases[p]!, states[p]!.next++)];
  }

  /// Reads payment [receiptId] in [txn]: its receipt, its Fees transaction
  /// record and its allocation record.
  Future<_PaymentState> _readPayment(Transaction txn, String receiptId) async {
    final receipt = (await txn.get(_receipts.doc(receiptId))).data();
    final transactionId = receipt?['transactionId']?.toString() ?? '';
    final transaction = transactionId.isEmpty ? null : (await txn.get(_transactions.doc(transactionId))).data();
    final allocData = (await txn.get(_allocations.doc(receiptId))).data();
    return _PaymentState(receiptId, receipt, transaction, allocData);
  }

  /// Why the payment with [receipt] (and its Fees [transaction] record)
  /// can't support a new bill of [studentId], or null when it can.
  String? ineligibility(Map<String, dynamic>? receipt, Map<String, dynamic>? transaction, String studentId) {
    if (receipt == null) return notFoundMessage;
    if (_receiptSchool(receipt) != schoolId) return otherSchoolMessage;
    final p = FeeBillPayment.fromReceipt('', receipt);
    if (p.voided) return voidedMessage;
    if (p.studentId != studentId) return otherStudentMessage;
    if (p.amountPaise <= 0) return noAmountMessage;
    if (referenceBaseOf(p.receiptNo) == null) return unusableReceiptNoMessage(p.receiptNo);
    if ((receipt['transactionId']?.toString() ?? '').isEmpty) return noTransactionMessage(p.receiptNo);
    if (transaction == null) return transactionMissingMessage(p.receiptNo);
    if (transaction['isDeleted'] == true) return transactionVoidedMessage(p.receiptNo);
    if ((transaction['studentId']?.toString() ?? '') != studentId) return transactionMismatchMessage(p.receiptNo, 'student');
    if (_receiptSchool(transaction) != schoolId) return transactionMismatchMessage(p.receiptNo, 'school');
    if (_paise(transaction['amount']) != p.amountPaise) return transactionMismatchMessage(p.receiptNo, 'amount');
    return null;
  }

  static int _paise(Object? amount) =>
      IndianAmount.paiseOf(amount is num ? amount.toDouble() : double.tryParse(amount?.toString() ?? '') ?? -1);

  /// Refuses (throws) unless [s] can support a new bill of [studentId];
  /// then records its payment. [multi]: name the receipt in the message.
  void _verify(_PaymentState s, String studentId, bool multi) {
    if (ineligibility(s.receipt, s.transaction, studentId) case final why?) {
      final no = s.receipt?['receiptNo']?.toString() ?? '';
      throw StateError(multi && no.isNotEmpty && !why.contains(no) ? 'Receipt $no: $why' : why);
    }
    s.payment = FeeBillPayment.fromReceipt(s.receiptId, s.receipt!);
  }

  /// The Bill Reference in bill id [id] (`{schoolId}_{billNo}`).
  String _billNoOf(String id) => id.startsWith('${schoolId}_') ? id.substring(schoolId.length + 1) : id;

  void _checkDuplicates(List<FeeBillLine> lines, Map<String, String> activeKeys) {
    for (final l in lines) {
      if (activeKeys[l.key] case final existing?) {
        throw StateError('Bill ${_billNoOf(existing)} has already been issued against this payment for ${l.description.trim()} '
            '(${FeeMonth.label(l.billingMonth)}). Cancel that bill first, or change this line.');
      }
    }
  }

  /// The bills recorded for a repeated request.
  Future<List<FeeIssuedBill>> _requestedBills(Transaction txn, Map<String, dynamic> request) async {
    if (request['schoolId'] != schoolId) throw StateError('This issue request belongs to another school, so nothing was issued.');
    return _billsById(txn, [for (final v in (request['billIds'] as List? ?? const [])) v.toString()]);
  }

  Future<List<FeeIssuedBill>> _billsById(Transaction txn, List<String> ids) async => [
        for (final id in ids)
          if ((await txn.get(_bills.doc(id))).data() case final d?) FeeIssuedBill.fromMap(id, d),
      ];

  /// Writes bill [billNo] for [draft] with its ledger entries, and records
  /// its allocations on its payments' states.
  FeeIssuedBill _issueOne(
    Transaction txn, {
    required String billNo,
    required FeeBillDraft draft,
    required String primary,
    required Map<String, _PaymentState> states,
    required FeeBillSchool school,
    required DateTime now,
    required DateTime issueDate,
    required ReceiptParent? parent,
    required bool amountIncludesGst,
    required String studentId,
    String requestId = '',
    String replacesBillId = '',
  }) {
    final billId = FeeIssuedBill.idFor(schoolId, billNo);
    final ordered = draft.allocations.keys.toList()
      ..sort((a, b) {
        final pa = states[a]!.payment!, pb = states[b]!.payment!;
        return comparePrimaryPayment(pa.paymentDate, pa.receiptNo, pb.paymentDate, pb.receiptNo);
      });
    final allocations = [
      for (final r in ordered)
        FeeBillPaymentAllocation(
          allocationId: FeeBillPaymentAllocation.idFor(billId, r),
          receiptId: r,
          receiptNo: states[r]!.payment!.receiptNo,
          paymentDate: states[r]!.payment!.paymentDate,
          paymentAmountPaise: states[r]!.payment!.amountPaise,
          allocatedPaise: draft.allocations[r]!,
        ),
    ];
    final bill = _writeBill(txn,
        billNo: billNo, line: draft.line, payment: states[primary]!.payment!, allocations: allocations, school: school, now: now,
        requestId: requestId, replacesBillId: replacesBillId, issueDate: issueDate, parent: parent, amountIncludesGst: amountIncludesGst);
    for (final a in allocations) {
      txn.set(_ledger.doc(a.allocationId), _ledgerEntry(bill: bill, allocation: a, requestId: requestId, at: now, by: _actor));
      states[a.receiptId]!
        ..bills[billId] = a.allocatedPaise
        ..keys[bill.line.key] = billId;
    }
    return bill;
  }

  /// A ledger entry (`fee_bill_payment_allocations/{allocationId}`),
  /// active. Its details are never changed afterwards; a cancellation only
  /// marks it released with its reversal record.
  Map<String, dynamic> _ledgerEntry({required FeeIssuedBill bill, required FeeBillPaymentAllocation allocation, required String requestId, required DateTime at, required String by}) => {
        'schoolId': schoolId,
        'allocationId': allocation.allocationId,
        'billId': bill.id,
        'billNo': bill.billNo,
        'studentId': bill.payment.studentId,
        'receiptId': allocation.receiptId,
        'receiptNo': allocation.receiptNo,
        'paymentDate': allocation.paymentDate,
        'paymentAmountPaise': allocation.paymentAmountPaise,
        'allocatedPaise': allocation.allocatedPaise,
        'status': FeeBillAllocationStatus.active.key,
        'reversalId': '',
        'requestId': requestId,
        'legacy': false,
        'allocatedAt': at,
        'allocatedBy': by,
      };

  void _writeAllocation(Transaction txn, _PaymentState s, String studentId) {
    // The payment amount as it is now (it may have been edited in Fees).
    final paymentPaise = s.receipt == null ? s.alloc.paymentPaise : FeeBillPayment.fromReceipt(s.receiptId, s.receipt!).amountPaise;
    txn.set(_allocations.doc(s.receiptId), {
      'schoolId': schoolId,
      'receiptId': s.receiptId,
      'studentId': studentId,
      'paymentPaise': paymentPaise,
      'allocatedPaise': s.allocatedNow,
      'bills': s.bills,
      'lineKeys': s.keys,
      'requests': s.requests,
      'version': s.alloc.version + 1,
      'nextSequence': s.next,
      'createdAt': s.allocData?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actor,
    });
  }

  FeeIssuedBill _writeBill(
    Transaction txn, {
    required String billNo,
    required FeeBillLine line,
    required FeeBillPayment payment,
    required List<FeeBillPaymentAllocation> allocations,
    required FeeBillSchool school,
    required DateTime now,
    required DateTime issueDate,
    required ReceiptParent? parent,
    required bool amountIncludesGst,
    String requestId = '',
    String replacesBillId = '',
  }) {
    final id = FeeIssuedBill.idFor(schoolId, billNo);
    final className = line.className.isNotEmpty ? line.className : payment.className;
    final ref = _bills.doc(id);
    txn.set(ref, {
      'schoolId': schoolId,
      'billNo': billNo,
      'status': FeeBillStatus.issued.key,
      'receiptId': payment.receiptId,
      'studentId': payment.studentId,
      'studentName': payment.studentName,
      'admissionNo': payment.admissionNo,
      'className': className,
      'payment': payment.toSnapshot(),
      'allocations': [for (final a in allocations) a.toSnapshot()],
      'receiptIds': [for (final a in allocations) a.receiptId],
      'allocationSchema': 2,
      'issueDate': issueDate,
      'parentRelation': parent?.relation ?? '',
      'parentName': parent?.name ?? '',
      'amountIncludesGst': amountIncludesGst,
      ...line.toMap(),
      if (line.adjustmentPaise > 0)
        'adjustment': {
          'type': line.adjustmentType.key,
          'amountPaise': line.adjustmentPaise,
          'reason': line.adjustmentReason,
          'createdBy': _actor,
          'createdAt': now,
        },
      'school': school.toMap(),
      'issuedAt': now,
      'issuedBy': _actor,
      'issueRequestId': requestId,
      'replacesBillId': replacesBillId,
      'replacedByBillId': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    txn.set(ref.collection('audit').doc(), {
      'action': 'issued',
      'billNo': billNo,
      ...line.toMap(),
      'className': className,
      'issueDate': issueDate,
      'allocations': [for (final a in allocations) {'receiptNo': a.receiptNo, 'allocatedPaise': a.allocatedPaise}],
      if (replacesBillId.isNotEmpty) 'replaces': replacesBillId,
      'by': _actor,
      'at': now,
    });
    return FeeIssuedBill(
      id: id,
      schoolId: schoolId,
      billNo: billNo,
      status: FeeBillStatus.issued,
      payment: payment.withClass(className),
      line: line,
      school: school,
      issuedAt: now,
      issuedBy: _actor,
      replacesBillId: replacesBillId,
      issueDate: issueDate,
      parentRelation: parent?.relation ?? '',
      parentName: parent?.name ?? '',
      amountIncludesGst: amountIncludesGst,
      storedAllocations: allocations,
    );
  }
}

/// One payment as read in an issue or cancel transaction, and what that
/// transaction will write to its allocation record.
class _PaymentState {
  _PaymentState(this.receiptId, this.receipt, this.transaction, this.allocData) : alloc = FeeBillAllocation.fromMap(receiptId, allocData) {
    bills = {...alloc.bills};
    keys = {...alloc.lineKeys};
    requests = {...alloc.requests};
    next = alloc.nextSequence;
  }

  final String receiptId;
  final Map<String, dynamic>? receipt, transaction, allocData;
  final FeeBillAllocation alloc;
  late final Map<String, int> bills;
  late final Map<String, String> keys;
  late final Map<String, List<String>> requests;
  late int next;

  /// Set once verified for a new bill.
  FeeBillPayment? payment;

  int get allocatedNow => bills.values.fold<int>(0, (s, v) => s + v);
}
