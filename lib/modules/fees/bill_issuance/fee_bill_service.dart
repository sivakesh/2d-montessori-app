import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../calendar/models/calendar_event_model.dart';
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

/// Fee Bill Issuance's own records (docs/fee_bill_issuance.md):
///
/// - `fee_issued_bills/{schoolId}_{billNo}`: one immutable bill each, with
///   snapshots of the original payment, student and school header, and an
///   `audit` subcollection (issued, cancelled, reprinted).
/// - `fee_bill_allocations/{receiptId}`: how much of that payment active
///   bills represent. Every issue and cancel transaction reads and writes
///   it, so concurrent issuance is serialised and can never allocate more
///   than the payment.
///   It also holds that payment's bill sequence (`nextSequence`).
///
/// Bill References are `{receipt number}-{six-digit sequence}`
/// (`REC-2026-1792729533955-000001`), numbered separately for each original
/// payment from its allocation's `nextSequence`. That counter is advanced
/// in the same transaction as the allocation and the bills, never goes
/// back, and is never reused, cancellations included.
///
/// It reads `fee_receipts` and `students` and never writes them, nor any
/// assignment, transaction, Finance income or ledger record; it calls no
/// FeeService or FinanceService method. Writes take the requester's role
/// and refuse anyone but an administrator (the app's convention, e.g.
/// ExpenseEfficiencyService).
class FeeBillService {
  FeeBillService({FirebaseFirestore? firestore, FirebaseAuth? auth, this.schoolId = kDefaultSchoolId, DateTime Function()? clock})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DateTime Function() _clock;
  final String schoolId;

  static const billsCollection = 'fee_issued_bills';
  static const allocationsCollection = 'fee_bill_allocations';
  /// Six-digit, zero-padded sequence; at most this many bills per payment.
  static const sequenceDigits = 6, maxSequence = 999999;

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

  CollectionReference<Map<String, dynamic>> get _bills => _firestore.collection(billsCollection);
  CollectionReference<Map<String, dynamic>> get _allocations => _firestore.collection(allocationsCollection);
  CollectionReference<Map<String, dynamic>> get _receipts => _firestore.collection('fee_receipts');
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

  /// The bills issued against payment [receiptId] (this school only).
  Future<List<FeeIssuedBill>> billsForPayment(String receiptId) async =>
      [for (final b in await getBills()) if (b.payment.receiptId == receiptId) b];

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

  /// Issues one bill per line in [lines] against payment [receiptId] of
  /// [studentId], numbered in order. [requestId] identifies this attempt
  /// (one per Issue button press): repeating it returns the bills it
  /// already issued instead of issuing again.
  ///
  /// In one transaction, reading first: the receipt must exist, be active,
  /// belong to this school and to [studentId]; every line must be valid
  /// and none may repeat an active bill line of this payment (or another
  /// line in [lines]); the net total plus what active bills already
  /// represent must not exceed the payment. Then the bills, their audit
  /// entries, the allocation and the counter are written together. Nothing
  /// else is written.
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
    if (studentId.isEmpty) throw StateError('Choose the student.');
    if (requestId.trim().isEmpty) throw StateError('Missing issue request id.');
    final normalized = [for (final l in lines) l.normalized];
    _checkLines(normalized);
    final base = await _checkedReferenceBase(receiptId);
    final issueDates = await _issueDates(normalized);
    return _firestore.runTransaction((txn) async {
      final receiptRef = _receipts.doc(receiptId);
      final allocRef = _allocations.doc(receiptId);
      final receipt = (await txn.get(receiptRef)).data();
      final parent = parentOf((await txn.get(_students.doc(studentId))).data());
      final allocData = (await txn.get(allocRef)).data();
      final alloc = FeeBillAllocation.fromMap(receiptId, allocData);
      if (allocData != null && allocData['schoolId'] != schoolId) throw StateError(otherSchoolMessage);

      // A repeated request: the bills it issued, unchanged.
      final done = alloc.requests[requestId];
      if (done != null) {
        return [
          for (final id in done)
            if ((await txn.get(_bills.doc(id))).data() case final d?) FeeIssuedBill.fromMap(id, d),
        ];
      }

      final payment = _checkPayment(receipt, receiptId, studentId);
      if (payment.receiptNo != base) throw StateError(unusableReceiptNoMessage(payment.receiptNo));
      if (allocData != null && !alloc.isConsistent) throw StateError(inconsistentMessage);
      _checkDuplicates(normalized, alloc.lineKeys);
      final newNet = normalized.fold<int>(0, (s, l) => s + l.netPaise);
      _checkAvailable(payment.amountPaise, alloc.allocatedPaise, newNet);

      // This payment's next sequence numbers.
      var next = alloc.nextSequence;
      if (next - 1 + normalized.length > maxSequence) {
        throw StateError('This payment already has the maximum of $maxSequence Bill References, so no more bills can be issued against it.');
      }
      final numbers = [for (var i = 0; i < normalized.length; i++) billReference(base, next++)];
      for (final n in numbers) {
        if ((await txn.get(_bills.doc(FeeIssuedBill.idFor(schoolId, n)))).exists) {
          throw StateError('Bill Reference $n already exists, so nothing was issued. Please report this.');
        }
      }

      // Writes.
      final now = _clock();
      final issued = <FeeIssuedBill>[];
      final bills = {...alloc.bills};
      final keys = {...alloc.lineKeys};
      for (var i = 0; i < normalized.length; i++) {
        final bill = _writeBill(txn,
            billNo: numbers[i], line: normalized[i], payment: payment, school: school, now: now, requestId: requestId,
            issueDate: issueDates[normalized[i].billingMonth]!, parent: parent, amountIncludesGst: amountIncludesGst);
        bills[bill.id] = bill.line.netPaise;
        keys[bill.line.key] = bill.id;
        issued.add(bill);
      }
      txn.set(allocRef, _allocationMap(
        receiptId: receiptId,
        studentId: payment.studentId,
        paymentPaise: payment.amountPaise,
        bills: bills,
        keys: keys,
        requests: {...alloc.requests, requestId: [for (final b in issued) b.id]},
        version: alloc.version + 1,
        nextSequence: next,
        created: allocData?['createdAt'],
      ));
      return issued;
    });
  }

  /// Cancels bill [billId] with [reason] (required). Its record, snapshot
  /// and history are kept; its net amount is released back to the
  /// payment's unallocated amount. With [replacement], a new bill (new
  /// number) is issued for the corrected line in the same transaction and
  /// linked both ways; it is checked like any issue against the payment's
  /// amount after the release. Refused, writing nothing, when the bill is
  /// not an issued bill of this school, or the allocation does not record
  /// it exactly (it would be left inconsistent). Returns the replacement.
  Future<FeeIssuedBill?> cancelBill({
    required String requesterRole,
    required String billId,
    required String reason,
    FeeBillLine? replacement,
    FeeBillSchool? replacementSchool,
  }) async {
    _requireAdmin(requesterRole);
    final why = reason.trim();
    if (why.isEmpty) throw StateError('Enter the reason for cancelling this bill.');
    if (why.length > maxReason) throw StateError('The reason must be $maxReason characters or fewer.');
    final line = replacement?.normalized;
    if (line != null) _checkLines([line]);
    final replacementIssueDate = line == null ? null : await issueDateFor(line.billingMonth);
    String? base;
    if (line != null) {
      final b = await getBill(billId);
      if (b != null) base = await _checkedReferenceBase(b.payment.receiptId);
    }
    return _firestore.runTransaction((txn) async {
      final billRef = _bills.doc(billId);
      final data = (await txn.get(billRef)).data();
      if (data == null || data['schoolId'] != schoolId) throw StateError('This bill could not be found.');
      final bill = FeeIssuedBill.fromMap(billId, data);
      if (bill.isCancelled) throw StateError('Bill ${bill.billNo} is already cancelled.');
      final receiptId = bill.payment.receiptId;
      final allocRef = _allocations.doc(receiptId);
      final allocData = (await txn.get(allocRef)).data();
      final alloc = FeeBillAllocation.fromMap(receiptId, allocData);
      if (allocData == null || allocData['schoolId'] != schoolId || !alloc.isConsistent || alloc.bills[billId] != bill.line.netPaise || alloc.lineKeys[bill.line.key] != billId) {
        throw StateError(inconsistentMessage);
      }
      final bills = {...alloc.bills}..remove(billId);
      final keys = {...alloc.lineKeys}..remove(bill.line.key);
      final allocated = alloc.allocatedPaise - bill.line.netPaise;

      // The receipt as it is now: its amount is what the allocation records
      // (it may have been edited in Fees since); a replacement also needs
      // it to be active and this student's.
      final receiptData = (await txn.get(_receipts.doc(receiptId))).data();
      final currentPaise = receiptData == null ? alloc.paymentPaise : FeeBillPayment.fromReceipt(receiptId, receiptData).amountPaise;
      FeeBillPayment? payment;
      String? newNo;
      ReceiptParent? parent;
      if (line != null) {
        if (base == null) throw StateError('This bill could not be found.');
        parent = parentOf((await txn.get(_students.doc(bill.payment.studentId))).data());
        payment = _checkPayment(receiptData, receiptId, bill.payment.studentId);
        _checkDuplicates([line], keys);
        _checkAvailable(payment.amountPaise, allocated, line.netPaise);
        if (payment.receiptNo != base) throw StateError(unusableReceiptNoMessage(payment.receiptNo));
        if (alloc.nextSequence > maxSequence) {
          throw StateError('This payment already has the maximum of $maxSequence Bill References, so no replacement can be issued.');
        }
        newNo = billReference(base, alloc.nextSequence);
        if ((await txn.get(_bills.doc(FeeIssuedBill.idFor(schoolId, newNo)))).exists) {
          throw StateError('Bill Reference $newNo already exists, so nothing was changed. Please report this.');
        }
      }

      // Writes.
      final now = _clock();
      FeeIssuedBill? issued;
      if (line != null) {
        // The replacement keeps the cancelled bill's GST choices.
        issued = _writeBill(txn,
            billNo: newNo!, line: line, payment: payment!, school: replacementSchool ?? bill.school, now: now, replacesBillId: billId,
            issueDate: replacementIssueDate!, parent: parent, amountIncludesGst: bill.amountIncludesGst);
        bills[issued.id] = line.netPaise;
        keys[line.key] = issued.id;
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
        if (issued != null) 'replacedBy': issued.billNo,
        'by': _actor,
        'at': now,
      });
      txn.set(allocRef, _allocationMap(
        receiptId: receiptId,
        studentId: bill.payment.studentId,
        paymentPaise: currentPaise,
        bills: bills,
        keys: keys,
        requests: alloc.requests,
        version: alloc.version + 1,
        // A cancelled bill's number is never given out again.
        nextSequence: issued != null ? alloc.nextSequence + 1 : alloc.nextSequence,
        created: allocData['createdAt'],
      ));
      return issued;
    });
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

  FeeBillPayment _checkPayment(Map<String, dynamic>? receipt, String receiptId, String studentId) {
    if (receipt == null) throw StateError(notFoundMessage);
    if (_receiptSchool(receipt) != schoolId) throw StateError(otherSchoolMessage);
    final payment = FeeBillPayment.fromReceipt(receiptId, receipt);
    if (payment.voided) throw StateError(voidedMessage);
    if (payment.studentId != studentId) throw StateError(otherStudentMessage);
    if (payment.amountPaise <= 0) throw StateError('The original payment has no amount, so no bill can be issued against it.');
    return payment;
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

  static void _checkAvailable(int payment, int allocated, int requested) {
    final available = payment - allocated;
    if (requested > available) {
      throw StateError('These bills total ${billMoney(requested)} net, but only ${billMoney(available < 0 ? 0 : available)} of this payment '
          '(${billMoney(payment)}) is not yet billed. Reduce the amounts or add a bill-only adjustment.');
    }
  }

  FeeIssuedBill _writeBill(
    Transaction txn, {
    required String billNo,
    required FeeBillLine line,
    required FeeBillPayment payment,
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
    );
  }

  Map<String, dynamic> _allocationMap({
    required String receiptId,
    required String studentId,
    required int paymentPaise,
    required Map<String, int> bills,
    required Map<String, String> keys,
    required Map<String, List<String>> requests,
    required int version,
    required int nextSequence,
    Object? created,
  }) =>
      {
        'schoolId': schoolId,
        'receiptId': receiptId,
        'studentId': studentId,
        'paymentPaise': paymentPaise,
        'allocatedPaise': bills.values.fold<int>(0, (s, v) => s + v),
        'bills': bills,
        'lineKeys': keys,
        'requests': requests,
        'version': version,
        'nextSequence': nextSequence,
        'createdAt': created ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _actor,
      };
}
