import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../../admin/students/models/admission_date.dart';
import '../models/fee_admission.dart';
import '../models/fee_amount_revision.dart';
import '../models/fee_collection_record.dart';
import '../models/fee_component_model.dart';
import '../models/fee_discount.dart';
import '../models/fee_discount_apply.dart';
import '../models/fee_due_backfill.dart';
import '../models/fee_due_date.dart';
import '../models/fee_month.dart';
import '../models/fee_month_range.dart';
import '../models/fee_receipt_model.dart';
import '../models/fee_report.dart';
import '../models/fee_student.dart';
import '../models/fee_structure_model.dart';
import '../models/fee_transaction_model.dart';
import '../models/student_fee_assignment_model.dart';
import '../../finance/services/finance_service.dart';

class FeeService {
  FeeService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FinanceService? financeService,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _injectedFinanceService = financeService;

  final FirebaseFirestore _firestore;

  /// Today, for the admission check of Term and One-time assignments (the
  /// assignment date is the day it is made); tests pass a fixed date.
  final DateTime Function() _clock;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FinanceService? _injectedFinanceService;
  // Previously constructed inline as `FinanceService()` at each call site.
  // Lazy (only built the first time it's actually accessed, e.g. inside
  // collectFee/voidReceipt) rather than an eager field initializer: most
  // FeeService methods never touch Finance at all, and a plain
  // `FinanceService()` fallback reaches FirebaseFirestore.instance the
  // moment it's constructed — eagerly building it in every FeeService()
  // constructor would make even Finance-unrelated calls (getAssignments(),
  // etc.) require a real Firebase app in tests that never pass
  // `financeService:`. Same DI pattern as _firestore/_auth/_storage above
  // — no change to FinanceService itself.
  FinanceService get _financeService => _injectedFinanceService ?? FinanceService();

  CollectionReference<Map<String, dynamic>> get _structures => _firestore.collection('fee_structures');
  CollectionReference<Map<String, dynamic>> get _assignments => _firestore.collection('student_fee_assignments');
  CollectionReference<Map<String, dynamic>> get _transactions => _firestore.collection('fee_transactions');
  CollectionReference<Map<String, dynamic>> get _receipts => _firestore.collection('fee_receipts');
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');
  CollectionReference<Map<String, dynamic>> get _classes => _firestore.collection('classes');

  Future<List<FeeStructureModel>> getFeeStructures() async {
    final snap = await _structures.orderBy('createdAt', descending: true).get();
    return snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => FeeStructureModel.fromMap(d.id, d.data()))
        .toList();
  }

  Future<List<StudentFeeAssignmentModel>> getAssignments() async {
    final snap = await _assignments.orderBy('assignedAt', descending: true).get();
    return snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => StudentFeeAssignmentModel.fromMap(d.id, d.data()))
        .toList();
  }

  Future<StudentFeeAssignmentModel?> getAssignmentById(String id) async {
    final snap = await _assignments.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    final data = snap.data()!;
    if (data['isDeleted'] == true) return null;
    return StudentFeeAssignmentModel.fromMap(snap.id, data);
  }

  /// Assignments for one student, using the same `studentId` equality
  /// filter already used inline elsewhere in this file (e.g. [assignFee]).
  /// Read-only — added for the Parent dashboard so it can show one child's
  /// fee summary without fetching every assignment in the school.
  Future<List<StudentFeeAssignmentModel>> getAssignmentsForStudent(
    String studentId,
  ) async {
    final snap = await _assignments.where('studentId', isEqualTo: studentId).get();
    return snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => StudentFeeAssignmentModel.fromMap(d.id, d.data()))
        .toList();
  }

  Future<List<FeeReceiptModel>> getReceipts() async {
    final snap = await _receipts.orderBy('createdAt', descending: true).get();
    return snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => FeeReceiptModel.fromMap(d.id, d.data()))
        .toList();
  }

  Future<FeeReceiptModel?> getReceiptById(String id) async {
    final snap = await _receipts.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return FeeReceiptModel.fromMap(snap.id, snap.data()!);
  }

  /// Every payment recorded against one assignment, oldest first, for the
  /// read-only Collection Details view: its fee receipts (matched only by
  /// their stored `assignmentId`, never by student or structure), voided
  /// ones included and marked, each with the notes from its own fee
  /// transaction (matched by the receipt's `transactionId`). Reads only.
  Future<List<FeeCollectionRecord>> getCollectionHistory(String assignmentId) =>
      getCollectionHistoryForAssignments([assignmentId]);

  /// [getCollectionHistory] for several assignments at once (a student's
  /// fee history): receipts and transactions read with `assignmentId in`
  /// queries of up to 30 ids each, so one student's history costs a few
  /// reads however many assignments it has, and never reads other
  /// students' receipts. Each receipt appears once. Reads only.
  Future<List<FeeCollectionRecord>> getCollectionHistoryForAssignments(Iterable<String> assignmentIds) async {
    final ids = {for (final id in assignmentIds) if (id.isNotEmpty) id}.toList();
    if (ids.isEmpty) return const [];
    final receipts = <String, Map<String, dynamic>>{};
    final remarksById = <String, String>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      final receiptSnap = chunk.length == 1
          ? await _receipts.where('assignmentId', isEqualTo: chunk.single).get()
          : await _receipts.where('assignmentId', whereIn: chunk).get();
      final transactionSnap = chunk.length == 1
          ? await _transactions.where('assignmentId', isEqualTo: chunk.single).get()
          : await _transactions.where('assignmentId', whereIn: chunk).get();
      for (final d in receiptSnap.docs) {
        if (chunk.contains(d.data()['assignmentId'])) receipts[d.id] = d.data();
      }
      for (final t in transactionSnap.docs) {
        remarksById[t.id] = t.data()['remarks']?.toString() ?? '';
      }
    }
    return _collectionRecords(receipts, remarksById);
  }

  /// A student's fee receipts (by stable `studentId`) that aren't linked
  /// to any of [linkedAssignmentIds] — older receipts with no
  /// `assignmentId`, or ones whose assignment was deleted. They can't be
  /// placed in an academic year or month, so the student fee history lists
  /// them apart and never counts them. Reads only.
  Future<List<FeeCollectionRecord>> getUnlinkedCollectionsForStudent(String studentId, Set<String> linkedAssignmentIds) async {
    if (studentId.isEmpty) return const [];
    final snap = await _receipts.where('studentId', isEqualTo: studentId).get();
    final receipts = {
      for (final d in snap.docs)
        if (d.data()['studentId'] == studentId && !linkedAssignmentIds.contains(d.data()['assignmentId']?.toString() ?? '')) d.id: d.data(),
    };
    if (receipts.isEmpty) return const [];
    final transactions = await _transactions.where('studentId', isEqualTo: studentId).get();
    return _collectionRecords(receipts, {for (final t in transactions.docs) t.id: t.data()['remarks']?.toString() ?? ''});
  }

  List<FeeCollectionRecord> _collectionRecords(Map<String, Map<String, dynamic>> receipts, Map<String, String> remarksById) {
    DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    final records = [
      for (final MapEntry(key: id, value: data) in receipts.entries)
        FeeCollectionRecord(
          receipt: FeeReceiptModel.fromMap(id, data),
          isVoided: data['isDeleted'] == true,
          voidedAt: date(data['voidedAt'] ?? data['deletedAt']),
          remarks: remarksById[data['transactionId']?.toString() ?? ''] ?? '',
        ),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    records.sort((a, b) {
      final byDate = (a.receipt.paymentDate ?? a.receipt.createdAt ?? epoch).compareTo(b.receipt.paymentDate ?? b.receipt.createdAt ?? epoch);
      return byDate != 0 ? byDate : (a.receipt.createdAt ?? epoch).compareTo(b.receipt.createdAt ?? epoch);
    });
    return records;
  }

  /// Every student record (active or not), for the Fees Students tab and
  /// the shared Student filter: one read of `students`.
  Future<List<FeeStudent>> getStudents() async {
    final snap = await _students.get();
    return [for (final d in snap.docs) FeeStudent.fromMap(d.id, d.data())]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Every class (active or not) as id -> name, for the shared Class
  /// filter: one read of `classes`.
  Future<Map<String, String>> getClassNames() async {
    final snap = await _classes.get();
    return {for (final d in snap.docs) d.id: d.data()['name']?.toString() ?? ''};
  }

  Future<List<FeeTransactionModel>> getTransactions() async {
    final snap = await _transactions.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => FeeTransactionModel.fromMap(d.id, d.data())).toList();
  }

  Future<FeeTransactionModel?> getTransactionById(String id) async {
    final snap = await _transactions.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return FeeTransactionModel.fromMap(snap.id, snap.data()!);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveClasses() async {
    final snap = await _classes.where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  /// Bypasses the `isActive` filter — used only when editing an existing
  /// assignment whose class may since have been deactivated, so the Edit
  /// dialog's Class dropdown always has an item matching its
  /// `initialValue` (an active-only list wouldn't, and
  /// DropdownButtonFormField asserts when `initialValue` isn't among
  /// `items` — the same crash class documented in
  /// admin_student_form_class_dropdown_test.dart for the Class dropdown on
  /// the Student form).
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> getClassById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _classes.where(FieldPath.documentId, isEqualTo: id).limit(1).get();
    return snap.docs.isEmpty ? null : snap.docs.first;
  }

  /// Same rationale as [getClassById], for the Student dropdown.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> getStudentById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _students.where(FieldPath.documentId, isEqualTo: id).limit(1).get();
    return snap.docs.isEmpty ? null : snap.docs.first;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClassId(String classId) async {
    final snap = await _students.where('classId', isEqualTo: classId).where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClassIds(List<String> classIds) async {
    if (classIds.isEmpty) return [];
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final classId in classIds) {
      final snap = await getStudentsByClassId(classId);
      results.addAll(snap);
    }
    final seen = <String>{};
    return results.where((doc) => seen.add(doc.id)).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getActiveStudents() async {
    final snap = await _students.where('isActive', isEqualTo: true).get();
    return snap.docs;
  }

  /// Fee structure [id] (active or not), or null.
  Future<FeeStructureModel?> getFeeStructureById(String id) async {
    if (id.isEmpty) return null;
    final data = (await _structures.doc(id).get()).data();
    return data == null ? null : FeeStructureModel.fromMap(id, data);
  }

  Future<List<FeeStructureModel>> getActiveStructuresForClass(String classId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  Future<List<FeeStructureModel>> getActiveStructuresForStudent(String studentId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  /// Why [value] can't be a component's Due Day of Month, or null when it
  /// can: empty, or a whole number from 1 to 31.
  static String? dueDayOfMonthError(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      final day = int.tryParse(text);
      return day == null ? dueDayOfMonthMessage : dueDayOfMonthError(day);
    }
    if (value is int) return value >= 1 && value <= 31 ? null : dueDayOfMonthMessage;
    return dueDayOfMonthMessage;
  }

  static const dueDayOfMonthMessage = 'Due Day of Month must be a whole number from 1 to 31, or left empty.';

  /// Why [value] can't be a component's Default Due Date, or null when it
  /// can: none, or a date (DateTime or Timestamp) in the years 2000–2100,
  /// the range every due date uses.
  static String? componentDueDateError(Object? value) {
    if (value == null) return null;
    final date = value is Timestamp ? value.toDate() : value is DateTime ? value : null;
    if (date == null || date.year < 2000 || date.year > 2100) return componentDueDateMessage;
    return null;
  }

  static const componentDueDateMessage = 'Default Due Date must be a date from 2000 to 2100, or left empty.';

  /// Refuses a structure whose components have an invalid Due Day of Month
  /// or Default Due Date.
  void _checkComponents(Map<String, dynamic> data) {
    final components = data['components'];
    if (components is! List) return;
    for (final c in components) {
      if (c is! Map) continue;
      if (dueDayOfMonthError(c['dueDayOfMonth']) != null) throw StateError(dueDayOfMonthMessage);
      if (componentDueDateError(c['dueDate']) != null) throw StateError(componentDueDateMessage);
    }
  }

  Future<String> createFeeStructure(Map<String, dynamic> data) async {
    _checkComponents(data);
    final doc = _structures.doc();
    await doc.set({
      ...data,
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateFeeStructure(String id, Map<String, dynamic> data) async {
    _checkComponents(data);
    await _structures.doc(id).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deactivateFeeStructure(String id) async {
    await updateFeeStructure(id, {'isActive': false});
  }

  Future<void> deleteFeeStructure(String id) async {
    await _structures.doc(id).set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  /// True if a live (non-deleted, not [excludeId]) assignment already
  /// exists for `(studentId, feeStructureId, <academic year>)` —
  /// FEES-AY-IMPLEMENT-01's compatibility-aware duplicate identity. Checks
  /// both the canonical [academicYearId] (when non-empty) and the legacy
  /// [academicYear] string (when non-empty) as two separate queries and
  /// unions the results, rather than relying on either alone: a live
  /// assignment created before this task has `academicYearId == ''` and
  /// would never be found by an id-only query, while a newly-created one
  /// always carries both fields. Checking only one side during this
  /// transition period would let a duplicate slip through in whichever
  /// direction wasn't checked — every write path below (`assignFee`,
  /// `updateAssignment`, `syncAssignmentsForFeeStructure`,
  /// `bulkAssignClassFees`) uses this same helper so the identity rule can
  /// never drift between them.
  ///
  /// With a [feeMonth] (a Monthly structure's month), only an assignment
  /// for that same month — or one with no month recorded (made before
  /// months were; its month is unknown, so it may be this one) — counts:
  /// other months are separate assignments. Without one, any live
  /// assignment counts, as before.
  Future<bool> _hasDuplicateAssignment({
    required String studentId,
    required String feeStructureId,
    required String academicYearId,
    required String academicYear,
    String? excludeId,
    String feeMonth = '',
  }) async {
    final candidates = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (academicYearId.isNotEmpty) {
      final byId = await _assignments
          .where('studentId', isEqualTo: studentId)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYearId', isEqualTo: academicYearId)
          .get();
      candidates.addAll(byId.docs);
    }
    if (academicYear.isNotEmpty) {
      final byString = await _assignments
          .where('studentId', isEqualTo: studentId)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYear', isEqualTo: academicYear)
          .get();
      candidates.addAll(byString.docs);
    }
    final seen = <String>{};
    for (final doc in candidates) {
      if (!seen.add(doc.id)) continue;
      if (excludeId != null && doc.id == excludeId) continue;
      if (doc.data()['isDeleted'] == true) continue;
      if (feeMonth.isNotEmpty) {
        final other = doc.data()['feeMonth']?.toString() ?? '';
        if (other.isNotEmpty && other != feeMonth) continue;
      }
      return true;
    }
    return false;
  }

  /// Same lookup as [_hasDuplicateAssignment], but returns the matching
  /// live document (if any) instead of a bool — used by
  /// [syncAssignmentsForFeeStructure]/[bulkAssignClassFees], which need to
  /// update an existing assignment in place rather than merely refuse a
  /// second one.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findExistingAssignment({
    required String studentId,
    required String feeStructureId,
    required String academicYearId,
    required String academicYear,
  }) async {
    if (academicYearId.isNotEmpty) {
      final byId = await _assignments
          .where('studentId', isEqualTo: studentId)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYearId', isEqualTo: academicYearId)
          .get();
      final live = byId.docs.where((d) => d.data()['isDeleted'] != true);
      if (live.isNotEmpty) return live.first;
    }
    if (academicYear.isNotEmpty) {
      final byString = await _assignments
          .where('studentId', isEqualTo: studentId)
          .where('feeStructureId', isEqualTo: feeStructureId)
          .where('academicYear', isEqualTo: academicYear)
          .get();
      final live = byString.docs.where((d) => d.data()['isDeleted'] != true);
      if (live.isNotEmpty) return live.first;
    }
    return null;
  }

  static const feeMonthRequiredMessage = 'Choose the fee month for this monthly fee structure.';

  /// The fee month for a new assignment of [feeStructureId]: required (as
  /// `YYYY-MM`) for a Monthly structure, refused for any other. A structure
  /// that can't be read is checked only for the month's format.
  Future<String> _checkFeeMonth(String feeStructureId, Object? value) async {
    final feeMonth = value?.toString().trim() ?? '';
    if (feeMonth.isNotEmpty && !FeeMonth.isValid(feeMonth)) throw StateError('The fee month "$feeMonth" is not a month (expected YYYY-MM).');
    final snap = feeStructureId.isEmpty ? null : await _structures.doc(feeStructureId).get();
    final data = snap?.data();
    if (data == null) return feeMonth;
    final monthly = FeeMonth.isMonthlyStructure(FeeStructureModel.fromMap(snap!.id, data));
    if (monthly && feeMonth.isEmpty) throw StateError(feeMonthRequiredMessage);
    if (!monthly && feeMonth.isNotEmpty) throw StateError('This fee structure is not monthly, so it has no fee month.');
    return feeMonth;
  }

  static const dueDateRequiredMessage = 'A due date is required for a new fee assignment.';

  /// A due date from [value] (a DateTime or Timestamp), as a calendar date
  /// at local midnight. Any valid date is accepted, in any month: a fee
  /// month is the period a fee is for, the due date when it is to be paid.
  /// Missing: refused when [required] (every new assignment), otherwise
  /// null. A non-date, or a year outside 2000–2100, is refused.
  DateTime? _checkDueDate(Object? value, {required bool required}) {
    if (value == null) {
      if (required) throw StateError(dueDateRequiredMessage);
      return null;
    }
    final date = value is Timestamp ? value.toDate() : value is DateTime ? value : null;
    if (date == null) throw StateError('The due date "$value" is not a date.');
    if (date.year < 2000 || date.year > 2100) throw StateError('The due date ${FeeDueDate.label(date)} is not a valid due date.');
    return FeeDueDate.dateOnly(date);
  }

  /// Single Student: refuses a fee month that ends before the student's
  /// Admission Date (or, with no fee month, an admission after today, the
  /// assignment date). A student with no admission date recorded is not
  /// refused here: assigning one student is itself the manual review the
  /// automatic paths ask for (the Assign Fee dialog flags it).
  Future<Map<String, dynamic>?> _checkAdmission(String studentId, String studentName, String feeMonth) async {
    if (studentId.isEmpty) return null;
    final data = (await _students.doc(studentId).get()).data();
    final admitted = AdmissionDate.parse(data?['admissionDate']);
    final today = _clock();
    if (FeeAdmission.check(admitted, feeMonth: feeMonth, assignmentDate: today) == FeeAdmissionStatus.notYetAdmitted) {
      final name = studentName.isNotEmpty ? studentName : data?['name']?.toString() ?? '';
      throw StateError(FeeAdmission.notYetAdmittedMessage(name, admitted!, feeMonth: feeMonth, assignmentDate: today));
    }
    return data;
  }

  // ------------------------------------------------ Student discounts

  static int _paise(double v) => (v * 100).round();

  /// The components of fee structure [id], to allocate a student discount
  /// over; empty when it can't be read.
  Future<List<FeeComponentModel>> _componentsOf(String id) async {
    if (id.isEmpty) return const [];
    final data = (await _structures.doc(id).get()).data();
    return data == null ? const [] : FeeStructureModel.fromMap(id, data).components;
  }

  /// The fee period of a new assignment: its fee month, or (Term, One-time,
  /// mixed) the assignment date, today.
  FeeDiscountPeriod _newPeriod(String feeMonth) =>
      FeeMonth.isValid(feeMonth) ? FeeDiscountPeriod.month(feeMonth) : FeeDiscountPeriod.date(_clock());

  /// The student discount for a new assignment of [gross] for the student
  /// whose record is [student] (FeeDiscountCalculator), as the snapshot to
  /// store; none when the student has no discount that applies to the
  /// period. [conflict]: one applies but the assignment is being given a
  /// manual discount, so neither is combined (flagged for manual review).
  ({FeeDiscountSnapshot? snapshot, StudentFeeDiscount? config, FeeDiscountPeriod period, bool conflict}) _discountForNew(
    Map<String, dynamic>? student, {
    required double gross,
    required double manualDiscount,
    required String feeMonth,
    required List<FeeComponentModel> components,
  }) {
    final config = StudentFeeDiscount.fromStudent(student);
    final period = _newPeriod(feeMonth);
    if (config == null || !config.appliesTo(period)) return (snapshot: null, config: config, period: period, conflict: false);
    final calc = FeeDiscountCalculator.calculate(config, gross, components);
    if (_paise(calc.discount) <= 0) return (snapshot: null, config: config, period: period, conflict: false);
    if (_paise(manualDiscount) > 0) return (snapshot: null, config: config, period: period, conflict: true);
    return (
      snapshot: FeeDiscountSnapshot.of(config, calc, period, source: FeeDiscountSource.assignment, appliedBy: _auth.currentUser?.uid ?? 'admin'),
      config: config,
      period: period,
      conflict: false,
    );
  }

  /// The amount fields of a new assignment of [gross] carrying [snapshot].
  static Map<String, dynamic> _discountedAmounts(double gross, FeeDiscountSnapshot snapshot) {
    final payable = (_paise(gross) - _paise(snapshot.amount)) / 100;
    return {
      'discountAmount': snapshot.amount,
      'payableAmount': payable,
      'balanceAmount': payable,
      FeeDiscountSnapshot.field: snapshot.toMap(),
    };
  }

  static String discountConflictMessage(String name, StudentFeeDiscount d, FeeDiscountPeriod period) =>
      '${name.isEmpty ? 'This student' : name} has a student discount (${d.valueLabel}) for ${period.label}. '
      'It is not combined with an assignment-specific discount: set Discount Amount to 0 to apply the student discount, '
      'or change the student\'s discount first.';

  /// Assigns a fee to one student; null when the same assignment exists
  /// ([_hasDuplicateAssignment]: for a Monthly structure, the same month).
  /// A Monthly structure needs `feeMonth` (`YYYY-MM`, [FeeMonth]); every
  /// new assignment needs a `dueDate`.
  Future<String?> assignFee(Map<String, dynamic> data) async {
    final studentId = data['studentId']?.toString() ?? '';
    final feeStructureId = data['feeStructureId']?.toString() ?? '';
    final academicYearId = data['academicYearId']?.toString() ?? '';
    final academicYear = data['academicYear']?.toString() ?? '';
    final feeMonth = await _checkFeeMonth(feeStructureId, data['feeMonth']);
    final dueDate = _checkDueDate(data['dueDate'], required: true);
    final student = await _checkAdmission(studentId, data['studentName']?.toString() ?? '', feeMonth);
    final gross = (data['totalFee'] as num?)?.toDouble() ?? 0;
    final discount = _discountForNew(
      student,
      gross: gross,
      manualDiscount: (data['discountAmount'] as num?)?.toDouble() ?? 0,
      feeMonth: feeMonth,
      components: StudentFeeDiscount.fromStudent(student) == null ? const [] : await _componentsOf(feeStructureId),
    );
    if (discount.conflict) {
      throw StateError(discountConflictMessage(data['studentName']?.toString() ?? student?['name']?.toString() ?? '', discount.config!, discount.period));
    }
    final isDuplicate = await _hasDuplicateAssignment(
      studentId: studentId,
      feeStructureId: feeStructureId,
      academicYearId: academicYearId,
      academicYear: academicYear,
      feeMonth: feeMonth,
    );
    if (isDuplicate) return null;
    final doc = _assignments.doc();
    await doc.set({
      // A student-discount snapshot is only ever the one calculated here.
      ...Map<String, dynamic>.of(data)..remove('feeMonth')..remove('dueDate')..remove(FeeDiscountSnapshot.field),
      if (feeMonth.isNotEmpty) 'feeMonth': feeMonth,
      'dueDate': ?dueDate,
      'id': doc.id,
      'discountAmount': (data['discountAmount'] as num?)?.toDouble() ?? 0,
      'paidAmount': (data['paidAmount'] as num?)?.toDouble() ?? 0,
      'balanceAmount': (data['balanceAmount'] as num?)?.toDouble() ?? 0,
      'assignedBy': _auth.currentUser?.uid ?? data['assignedBy']?.toString() ?? 'admin',
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (discount.snapshot case final snap?) ..._discountedAmounts(gross, snap),
    });
    return doc.id;
  }

  Future<void> deleteAssignment(String id) async {
    await _assignments.doc(id).set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  /// Edits an existing assignment's amount-basis/identity fields in place.
  /// Reuses exactly the same payable/balance/status formula every other
  /// assignment mutation in this file already applies — nothing new
  /// invented. Collections/receipts belonging to this assignment are never
  /// read or written here, and `paidAmount` is always carried over
  /// unchanged from the current document, so existing payment history is
  /// completely untouched by an assignment edit.
  ///
  /// Once a payment exists (`paidAmount > 0`), changing the student, fee
  /// structure, or total fee is refused — mirrors the business rule
  /// [syncAssignmentsForFeeStructure] already enforces (only touches
  /// amount-basis fields when `paidAmount <= 0`, `skipped++` otherwise):
  /// those fields are this assignment's identity, and every payment
  /// document under it has already denormalized the *old* student/fee
  /// name at collection time, so silently changing them here would leave
  /// that payment history pointing at stale, mismatched context.
  Future<void> updateAssignment(String id, Map<String, dynamic> data) async {
    final snap = await _assignments.doc(id).get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Assignment not found');
    }
    final current = StudentFeeAssignmentModel.fromMap(snap.id, snap.data()!);
    // The student-discount snapshot is never written by an edit (neither
    // set, replaced nor removed): only assigning or Apply Student Discounts
    // to Existing Fees records one.
    data = Map<String, dynamic>.of(data)..remove(FeeDiscountSnapshot.field);
    if (current.studentDiscount case final snap?) _checkDiscountLocked(current, snap, data);
    // The fee month: a recorded one is part of the assignment's identity
    // (fixed once paid); one made before months were recorded may be given
    // its month, even when paid, as an explicit correction.
    final newFeeMonth = data.containsKey('feeMonth') ? (data['feeMonth']?.toString().trim() ?? '') : current.feeMonth;
    if (newFeeMonth.isNotEmpty && !FeeMonth.isValid(newFeeMonth)) throw StateError('The fee month "$newFeeMonth" is not a month (expected YYYY-MM).');
    final monthChanged = newFeeMonth != current.feeMonth;
    // The due date: kept unless a new one is given (an older assignment
    // without one may stay without, or be given one).
    final newDueDate = data['dueDate'] != null ? _checkDueDate(data['dueDate'], required: false) : current.dueDate;
    if (current.paidAmount > 0 && monthChanged && current.feeMonth.isNotEmpty) {
      throw StateError('Cannot change the fee month: this assignment already has payments recorded against it.');
    }
    if (current.paidAmount > 0 && monthChanged) {
      final hasLiveDuplicate = await _hasDuplicateAssignment(
        studentId: current.studentId,
        feeStructureId: current.feeStructureId,
        academicYearId: current.academicYearId,
        academicYear: current.academicYear,
        excludeId: id,
        feeMonth: newFeeMonth,
      );
      if (hasLiveDuplicate) throw StateError('An assignment for this student, fee structure, academic year and month already exists.');
    }

    if (current.paidAmount > 0) {
      final newStudentId = data['studentId']?.toString();
      final newFeeStructureId = data['feeStructureId']?.toString();
      final newTotalFee = (data['totalFee'] as num?)?.toDouble();
      final identityChanged = (newStudentId != null && newStudentId != current.studentId) ||
          (newFeeStructureId != null && newFeeStructureId != current.feeStructureId) ||
          (newTotalFee != null && newTotalFee != current.totalFee);
      if (identityChanged) {
        throw StateError(
          'Cannot change student, fee structure, or total fee: this assignment already has payments recorded against it.',
        );
      }
    } else {
      // No payment yet — reassigning student/structure/year is safe, but
      // must not silently create a duplicate of another live assignment
      // (the same compatibility-aware uniqueness rule assignFee already
      // enforces on create — see _hasDuplicateAssignment's doc comment).
      final newStudentId = data['studentId']?.toString() ?? current.studentId;
      final newFeeStructureId = data['feeStructureId']?.toString() ?? current.feeStructureId;
      final newAcademicYearId = data['academicYearId']?.toString() ?? current.academicYearId;
      final newYear = data['academicYear']?.toString() ?? current.academicYear;
      if (newStudentId != current.studentId ||
          newFeeStructureId != current.feeStructureId ||
          newAcademicYearId != current.academicYearId ||
          newYear != current.academicYear ||
          monthChanged) {
        final hasLiveDuplicate = await _hasDuplicateAssignment(
          studentId: newStudentId,
          feeStructureId: newFeeStructureId,
          academicYearId: newAcademicYearId,
          academicYear: newYear,
          excludeId: id,
          feeMonth: newFeeMonth,
        );
        if (hasLiveDuplicate) {
          throw StateError(newFeeMonth.isEmpty
              ? 'An assignment for this student, fee structure, and academic year already exists.'
              : 'An assignment for this student, fee structure, academic year and month already exists.');
        }
      }
    }

    final totalFee = (data['totalFee'] as num?)?.toDouble() ?? current.totalFee;
    final discountAmount = (data['discountAmount'] as num?)?.toDouble() ?? current.discountAmount;
    if (discountAmount < 0 || discountAmount > totalFee) {
      throw StateError('Discount amount must be between 0 and the total fee.');
    }
    final payableAmount = totalFee - discountAmount;
    final balanceAmount = (payableAmount - current.paidAmount).clamp(0, double.infinity);
    final status = balanceAmount == 0
        ? 'paid'
        : current.paidAmount > 0
            ? 'partial'
            : 'unpaid';

    await _assignments.doc(id).set({
      ...Map<String, dynamic>.of(data)..remove('feeMonth')..remove('dueDate'),
      if (newFeeMonth.isNotEmpty) 'feeMonth': newFeeMonth,
      'dueDate': ?newDueDate,
      'totalFee': totalFee,
      'discountAmount': discountAmount,
      'payableAmount': payableAmount,
      'balanceAmount': balanceAmount,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static const revisionReasonMessage = 'Enter the reason for revising this fee.';
  static const revisionUnchangedMessage = 'The fee amount and discount are unchanged: there is nothing to revise.';

  /// Revises the fee amount (and, without a student discount, the manual
  /// discount) of an existing assignment, unpaid, partially or fully paid:
  /// the explicit correction after a fee structure changes, or any other.
  /// The rules are FeeRevision's: collected (`paidAmount`) is kept, payable,
  /// outstanding and status follow, an excess over the revised payable is a
  /// credit held (never refunded), and a student discount is recalculated
  /// from its own terms.
  ///
  /// In one transaction: the assignment is re-read and must still be as
  /// [expected] (the one the administrator reviewed: same revision,
  /// collected, gross, discount, student and structure), else nothing is
  /// written ([FeeRevision.concurrentMessage]), so a collection, edit or
  /// other revision made meanwhile is never overwritten; then its amounts,
  /// revision counter and audit record (`feeRevisions`) are written
  /// together. No receipt, fee transaction or Finance entry is read or
  /// written, and nothing else on the assignment changes.
  ///
  /// [source]: FeeRevision.fromStructure when the revised gross is the fee
  /// structure's current amount ([structureAmount], recorded), else
  /// FeeRevision.entered. [reason] is required.
  Future<FeeAmountRevision> reviseAssignmentFee({
    required StudentFeeAssignmentModel expected,
    required double totalFee,
    double? manualDiscount,
    required String reason,
    String source = FeeRevision.entered,
    double? structureAmount,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) throw StateError(revisionReasonMessage);
    if (why.length > 500) throw StateError('The reason must be 500 characters or fewer.');
    final ref = _assignments.doc(expected.id);
    // For allocating a recalculated student discount only (as when applied).
    final components = expected.studentDiscount == null ? const <FeeComponentModel>[] : await _componentsOf(expected.feeStructureId);
    final user = _auth.currentUser;
    return _firestore.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      if (!snap.exists || data == null || data['isDeleted'] == true) throw StateError('Assignment not found');
      final a = StudentFeeAssignmentModel.fromMap(snap.id, data);
      if (a.feeRevision != expected.feeRevision ||
          _paise(a.paidAmount) != _paise(expected.paidAmount) ||
          _paise(a.totalFee) != _paise(expected.totalFee) ||
          _paise(a.discountAmount) != _paise(expected.discountAmount) ||
          a.studentId != expected.studentId ||
          a.feeStructureId != expected.feeStructureId) {
        throw StateError(FeeRevision.concurrentMessage);
      }
      final f = FeeRevision.figures(a, totalFee: totalFee, manualDiscount: manualDiscount, components: components);
      if (f.error case final e?) throw StateError(e);
      if (!FeeRevision.changes(a, f)) throw StateError(revisionUnchangedMessage);
      final revision = FeeAmountRevision(
        revision: a.feeRevision + 1,
        previousTotalFee: a.totalFee,
        newTotalFee: f.totalFee,
        previousDiscount: a.discountAmount,
        newDiscount: f.discount,
        previousPayable: a.payableAmount,
        newPayable: f.payable,
        collected: f.collected,
        previousStatus: a.status,
        newStatus: f.status,
        excess: f.excess,
        source: source == FeeRevision.fromStructure ? FeeRevision.fromStructure : FeeRevision.entered,
        structureAmount: source == FeeRevision.fromStructure ? structureAmount : null,
        reason: why,
        revisedBy: user?.uid ?? 'admin',
        revisedByName: user?.displayName ?? user?.email ?? 'Admin',
        revisedAt: _clock(),
      );
      txn.update(ref, {
        'totalFee': f.totalFee,
        'discountAmount': f.discount,
        'payableAmount': f.payable,
        'balanceAmount': f.outstanding,
        'status': f.status,
        if (f.snapshot case final s?) FeeDiscountSnapshot.field: s.toMap(),
        FeeRevision.revisionField: revision.revision,
        FeeRevision.historyField: [...(data[FeeRevision.historyField] as List? ?? const []), revision.toMap()],
        'lastRevisedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return revision;
    });
  }

  /// An assignment with a student discount: its snapshot was calculated for
  /// this student, fee structure, academic year, gross fee and period, so
  /// none of those, nor the class (`classId`, locked in the edit dialog
  /// too), the discount or the amounts derived from it, can be changed by
  /// an edit (refused, naming the fields). Everything else (due date, the
  /// class's display name and other details) is edited as usual. Values equal
  /// to the current ones are not changes.
  static void _checkDiscountLocked(StudentFeeAssignmentModel a, FeeDiscountSnapshot snap, Map<String, dynamic> data) {
    String text(String key) => data[key]?.toString().trim() ?? '';
    bool amount(String key, double current) => data[key] is num && _paise((data[key] as num).toDouble()) != _paise(current);
    final locked = [
      if (data.containsKey('studentId') && text('studentId') != a.studentId) 'student',
      if (data.containsKey('classId') && text('classId') != a.classId) 'class',
      if (data.containsKey('feeStructureId') && text('feeStructureId') != a.feeStructureId) 'fee structure',
      if ((data.containsKey('academicYearId') && text('academicYearId') != a.academicYearId) ||
          (data.containsKey('academicYear') && text('academicYear') != a.academicYear))
        'academic year',
      if (data.containsKey('feeMonth') && text('feeMonth') != a.feeMonth) 'fee month',
      if (amount('totalFee', a.totalFee)) 'gross fee',
      if (amount('discountAmount', a.discountAmount)) 'discount',
      if (amount('payableAmount', a.payableAmount) || amount('paidAmount', a.paidAmount) || amount('balanceAmount', a.balanceAmount))
        'payable, collected or outstanding amount',
    ];
    if (locked.isEmpty) return;
    throw StateError('Cannot change the ${locked.join(', ')}: this assignment has the student discount ${snap.label}, '
        'calculated for its student, fee, academic year and period. Those and the discount are fixed; '
        'other details such as the due date can still be edited.');
  }

  /// Edits an existing collection's amount/date/mode/reference/remarks in
  /// place across its paired fee_transactions + fee_receipts documents
  /// (the two records [collectFee] always creates together, linked by
  /// `transactionId`), then recalculates the parent assignment's
  /// paidAmount/balanceAmount/status using the same delta approach
  /// [voidReceipt] already uses for its own reversal. Every other
  /// collection/receipt is untouched — only the one receipt/transaction/
  /// assignment referenced by `receiptId` is read or written.
  ///
  /// After the Fees-side batch below commits, also pushes the correction
  /// into the linked Finance income entry via
  /// [FinanceService.updateFeeIncomeEntry] — an in-place field update on
  /// the same document (found by the existing `sourceId` relationship),
  /// which is what avoids createFeeIncomeEntry's dedup-by-sourceId guard
  /// entirely rather than needing to change Finance's own dedup logic.
  ///
  /// The two writes are NOT cross-service atomic: the Fees-side batch is
  /// its own atomic unit, and the Finance sync is a separate atomic unit
  /// run afterward. True atomicity across both would require merging
  /// FeeService and FinanceService into a single write path spanning two
  /// otherwise-independent service classes — out of scope ("do not create
  /// a new accounting architecture" / "do not redesign the Finance
  /// module"). If the Finance sync fails, the Fees-side correction is
  /// NOT rolled back (it is the authoritative, already-valid record), and
  /// the failure is surfaced with a distinct message telling the caller
  /// Finance is now out of sync and can be corrected manually via
  /// Finance's own Edit action — never silently swallowed.
  Future<void> updateCollection({
    required String receiptId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final receiptSnap = await _receipts.doc(receiptId).get();
    if (!receiptSnap.exists || receiptSnap.data() == null) {
      throw StateError('Collection not found');
    }
    final receiptData = receiptSnap.data()!;
    if (receiptData['isDeleted'] == true) {
      throw StateError('This collection has been voided and can no longer be edited.');
    }
    final receipt = FeeReceiptModel.fromMap(receiptSnap.id, receiptData);
    if (amount <= 0) {
      throw StateError('Amount must be greater than 0');
    }

    final assignmentRef = _assignments.doc(receipt.assignmentId);
    final assignmentSnap = await assignmentRef.get();
    if (!assignmentSnap.exists || assignmentSnap.data() == null) {
      throw StateError('Assignment not found');
    }
    final a = StudentFeeAssignmentModel.fromMap(assignmentSnap.id, assignmentSnap.data()!);

    final paidAmount = a.paidAmount - receipt.amount + amount;
    if (paidAmount > a.payableAmount) {
      throw StateError('Amount would exceed the total payable amount for this assignment.');
    }
    final balanceAmount = (a.payableAmount - paidAmount).clamp(0, double.infinity);
    final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';

    final batch = _firestore.batch();
    batch.set(_receipts.doc(receiptId), {
      'amount': amount,
      'paymentDate': paymentDate,
      'paymentMode': paymentMode,
      'referenceNo': referenceNo,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (receipt.transactionId.isNotEmpty) {
      batch.set(_transactions.doc(receipt.transactionId), {
        'amount': amount,
        'paymentDate': paymentDate,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'remarks': remarks,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    batch.set(assignmentRef, {
      'paidAmount': paidAmount,
      'balanceAmount': balanceAmount,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    try {
      await _financeService.updateFeeIncomeEntry(
        feeCollectionId: receiptId,
        amount: amount,
        date: paymentDate,
        paymentMode: paymentMode,
        referenceNo: referenceNo,
        remarks: remarks,
      );
    } catch (e) {
      throw StateError(
        'Collection updated, but the linked Finance record could not be '
        'synced: $e. You can correct it manually from the Finance module.',
      );
    }
  }

  /// Voids a collection: preserves the original fee_receipts/
  /// fee_transactions documents (soft-delete via `isDeleted`, the same
  /// mechanism [getReceipts]/[getFeeStructures]/[getAssignments] already
  /// filter on — reused rather than inventing a new status field, since
  /// this collection model has none), reverses the amount out of the
  /// parent assignment's paidAmount/balanceAmount/status, and reverses the
  /// linked Finance income entry via the existing
  /// [FinanceService.reverseFeeIncomeByCollectionId].
  ///
  /// Not one atomic write: Firestore transactions can't run the query that
  /// finds the Finance entry. Instead it runs as two atomic steps — the
  /// Finance reversal (income, ledger, account in one transaction), then
  /// the Fees step (receipt + assignment in one transaction) — after a
  /// read-only status check, so every retry is safe:
  /// - Receipt or Finance records ambiguous/inconsistent, or (with
  ///   [expectedFinanceIncomeId]) the Finance entry missing or a different
  ///   one: refused with a [FeeVoidException] before anything is written.
  /// - Receipt active, Finance active: both steps run.
  /// - Receipt active, Finance already reversed (an earlier attempt failed
  ///   after the Finance step): only the Fees step runs.
  /// - Receipt active, no Finance entry (collections recorded before the
  ///   Finance link existed): only the Fees step runs.
  /// - Receipt voided, Finance still active: only the Finance step runs;
  ///   returns [FeeVoidOutcome.financeReconciled].
  /// - Receipt voided, Finance reversed or absent: refused as already
  ///   voided.
  /// - Whenever a write would follow and a Finance entry exists, the
  ///   receipt, Finance income and ledger amounts must agree to the paisa;
  ///   otherwise refused ([FeeVoidFailure.amountMismatch]) before anything
  ///   is written. Neither amount is changed or treated as authoritative,
  ///   and since the check runs on every attempt a retry can't skip it.
  /// Each step re-checks its own state inside its transaction, so a
  /// repeated or concurrent void never reverses the account balance or
  /// restores the assignment balance twice.
  Future<FeeVoidOutcome> voidReceipt(String id, {String? expectedFinanceIncomeId}) async {
    final snap = await _receipts.doc(id).get();
    if (!snap.exists || snap.data() == null) {
      throw FeeVoidException(FeeVoidFailure.collectionNotFound, 'Collection not found');
    }
    final receiptVoided = snap.data()!['isDeleted'] == true;
    final receiptAmount = (snap.data()!['amount'] as num?)?.toDouble() ?? 0.0;

    final link = await _financeService.inspectFeeIncomeLink(id);
    switch (link.state) {
      case FeeIncomeLinkState.ambiguous:
        throw FeeVoidException(FeeVoidFailure.financeAmbiguous, link.message);
      case FeeIncomeLinkState.inconsistent:
        throw FeeVoidException(FeeVoidFailure.financeInconsistent, link.message);
      case FeeIncomeLinkState.missing || FeeIncomeLinkState.active || FeeIncomeLinkState.reversed:
        break;
    }
    if (expectedFinanceIncomeId != null) {
      if (link.state == FeeIncomeLinkState.missing) {
        throw FeeVoidException(
          FeeVoidFailure.financeMissing,
          'The Finance entry linked to this Fee Collection could not be found. Nothing was changed. '
          'Refresh and try again, or void the collection from Fees -> Collections.',
        );
      }
      if (link.incomeId != expectedFinanceIncomeId) {
        throw FeeVoidException(
          FeeVoidFailure.financeMismatch,
          'This Fee Collection is linked to a different Finance entry. Nothing was changed. '
          'Review the Finance entries for this collection before retrying.',
        );
      }
    }

    final writesFollow = !(receiptVoided && link.state != FeeIncomeLinkState.active);
    if (writesFollow && link.state != FeeIncomeLinkState.missing) {
      final incomeAmount = link.incomeAmount;
      final ledgerAmount = link.ledgerAmount;
      final mismatch = incomeAmount == null || !_sameAmount(incomeAmount, receiptAmount)
          ? 'its Finance entry (${incomeAmount == null ? 'no amount' : _formatAmount(incomeAmount)})'
          : ledgerAmount != null && !_sameAmount(ledgerAmount, incomeAmount)
              ? 'its ledger entry (${_formatAmount(ledgerAmount)})'
              : null;
      if (mismatch != null) {
        throw FeeVoidException(
          FeeVoidFailure.amountMismatch,
          'The Fee Collection amount (${_formatAmount(receiptAmount)}) does not match $mismatch, '
          'so it cannot be voided safely. Nothing was changed. Correct the amounts first — '
          'editing the collection in Fees -> Collections re-syncs its Finance entry — '
          'or ask an administrator to review them, then try again.',
        );
      }
    }

    if (receiptVoided) {
      if (link.state == FeeIncomeLinkState.active) {
        await _financeService.reverseFeeIncomeByCollectionId(id);
        return FeeVoidOutcome.financeReconciled;
      }
      throw FeeVoidException(FeeVoidFailure.alreadyVoided, 'This collection has already been voided.');
    }

    // Finance reversal first, same fail-safe-first ordering collectFee
    // already uses for its own Finance call: if this throws, neither the
    // assignment nor the receipt below has been touched yet. If the Fees
    // step below fails instead, the receipt stays active with Finance
    // reversed, and a retry skips straight to the Fees step.
    if (link.state != FeeIncomeLinkState.reversed) {
      await _financeService.reverseFeeIncomeByCollectionId(id);
    }

    // Receipt soft-delete + assignment balance in one transaction: the
    // receipt is re-read and re-checked first, so a concurrent void can't
    // restore the assignment balance twice. Full merged maps are written
    // rather than SetOptions(merge: true), as FinanceService does.
    final receiptRef = _receipts.doc(id);
    final uid = _auth.currentUser?.uid;
    await _firestore.runTransaction((txn) async {
      final receiptSnap = await txn.get(receiptRef);
      final data = receiptSnap.data();
      if (!receiptSnap.exists || data == null) {
        throw FeeVoidException(FeeVoidFailure.collectionNotFound, 'Collection not found');
      }
      if (data['isDeleted'] == true) {
        throw FeeVoidException(FeeVoidFailure.alreadyVoided, 'This collection has already been voided.');
      }
      final receipt = FeeReceiptModel.fromMap(receiptSnap.id, data);
      if (!_sameAmount(receipt.amount, receiptAmount)) {
        // Edited after the checks above: don't restore an unchecked amount.
        throw FeeVoidException(
          FeeVoidFailure.amountMismatch,
          'The Fee Collection amount changed while it was being voided, so the collection was not '
          'voided. Its Finance entry may already have been reversed. Review the collection and its '
          'Finance entry before trying again.',
        );
      }
      final assignmentRef = receipt.assignmentId.isEmpty ? null : _assignments.doc(receipt.assignmentId);
      final assignmentSnap = assignmentRef == null ? null : await txn.get(assignmentRef);
      final assignmentData = assignmentSnap?.data();

      if (assignmentRef != null && assignmentData != null) {
        final a = StudentFeeAssignmentModel.fromMap(assignmentSnap!.id, assignmentData);
        final paidAmount = (a.paidAmount - receipt.amount).clamp(0, double.infinity);
        final balanceAmount = (a.payableAmount - paidAmount).clamp(0, double.infinity);
        final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
        txn.set(assignmentRef, {
          ...assignmentData,
          'paidAmount': paidAmount,
          'balanceAmount': balanceAmount,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      txn.set(receiptRef, {
        ...data,
        'isDeleted': true,
        'voidedAt': FieldValue.serverTimestamp(),
        'voidedBy': uid,
        // Kept for backward compatibility with anything still reading the
        // original soft-delete field name (e.g. getReceipts()'s filter).
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': uid,
      });
    });
    return FeeVoidOutcome.voided;
  }

  /// Amounts are stored as plain doubles (rupees); two amounts are the same
  /// when they agree to the paisa.
  static bool _sameAmount(double a, double b) => (a * 100).round() == (b * 100).round();

  static String _formatAmount(double v) =>
      '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

  Future<Map<String, int>> syncAssignmentsForFeeStructure({
    required String feeStructureId,
    required String feeStructureName,
    required String academicYearId,
    required String academicYear,
    required double totalFee,
    required String assignmentScope,
    required List<String> classIds,
    required List<String> studentIds,
    DateTime? dueDate,
  }) async {
    final due = _checkDueDate(dueDate, required: false);
    final targetStudents = assignmentScope == 'student'
        ? await _fetchStudentsByIds(studentIds)
        : await getStudentsByClassIds(classIds);

    var created = 0;
    var updated = 0;
    var skipped = 0;
    // New assignments only: by Admission Date against today (this path has
    // no fee month). Existing assignments are updated as before.
    var admissionSkipped = 0;
    var manualReview = 0;
    final today = _clock();
    final components = await _componentsOf(feeStructureId);

    // Each student's existing assignment, found before anything is
    // written: a new assignment needs a due date, so without one nothing
    // is created or updated.
    final existingByStudent = {
      for (final student in targetStudents)
        student.id: await _findExistingAssignment(
          studentId: student.id,
          feeStructureId: feeStructureId,
          academicYearId: academicYearId,
          academicYear: academicYear,
        ),
    };
    if (due == null && existingByStudent.values.any((e) => e == null)) throw StateError(dueDateRequiredMessage);

    for (final student in targetStudents) {
      final studentData = student.data();
      final studentId = student.id;
      final existing = existingByStudent[studentId];

      final discountAmount = existing?['discountAmount'] is num ? (existing?['discountAmount'] as num).toDouble() : 0.0;
      final paidAmount = existing?['paidAmount'] is num ? (existing?['paidAmount'] as num).toDouble() : 0.0;
      final payableAmount = totalFee - discountAmount;
      final balanceAmount = (payableAmount - paidAmount).clamp(0, double.infinity);
      final status = balanceAmount == 0
          ? 'paid'
          : paidAmount > 0
              ? 'partial'
              : 'unpaid';

      if (existing == null) {
        switch (FeeAdmission.forDate(AdmissionDate.parse(studentData['admissionDate']), today)) {
          case FeeAdmissionStatus.notYetAdmitted:
            admissionSkipped++;
            continue;
          case FeeAdmissionStatus.notRecorded:
            manualReview++;
            continue;
          case FeeAdmissionStatus.eligible:
        }
        // A new assignment has no manual discount, so the student's
        // discount (if one applies to today) is applied.
        final discount = _discountForNew(studentData, gross: totalFee, manualDiscount: 0, feeMonth: '', components: components);
        final doc = _assignments.doc();
        await doc.set({
          'id': doc.id,
          'studentId': studentId,
          'studentName': studentData['name']?.toString() ?? '',
          'admissionNo': studentData['admissionNo']?.toString() ?? '',
          'classId': studentData['classId']?.toString() ?? '',
          'className': studentData['className']?.toString() ?? studentData['classId']?.toString() ?? '',
          'feeStructureId': feeStructureId,
          'feeStructureName': feeStructureName,
          'academicYearId': academicYearId,
          'academicYear': academicYear,
          'totalFee': totalFee,
          'discountAmount': 0,
          'payableAmount': payableAmount,
          'paidAmount': 0,
          'balanceAmount': payableAmount,
          'status': 'unpaid',
          'dueDate': due,
          'assignedBy': _auth.currentUser?.uid ?? 'admin',
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (discount.snapshot case final snap?) ..._discountedAmounts(totalFee, snap),
        });
        created++;
      } else if (((existing.data()[FeeRevision.revisionField] as num?) ?? 0) > 0) {
        // Its fee was revised by an administrator (FeeRevision): that
        // amount stands until revised again; counted as skipped.
        skipped++;
      } else if (existing.data()[FeeDiscountSnapshot.field] != null && _paise((existing['totalFee'] as num?)?.toDouble() ?? 0) != _paise(totalFee)) {
        // Its student discount was calculated on the old fee: left as it
        // is (never recalculated or doubled); counted as skipped.
        skipped++;
      } else if (paidAmount <= 0) {
        await existing.reference.update({
          'studentName': studentData['name']?.toString() ?? '',
          'admissionNo': studentData['admissionNo']?.toString() ?? '',
          'classId': studentData['classId']?.toString() ?? '',
          'className': studentData['className']?.toString() ?? studentData['classId']?.toString() ?? '',
          'feeStructureId': feeStructureId,
          'feeStructureName': feeStructureName,
          'academicYearId': academicYearId,
          'academicYear': academicYear,
          'totalFee': totalFee,
          'discountAmount': discountAmount,
          'payableAmount': payableAmount,
          'balanceAmount': balanceAmount,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      } else {
        skipped++;
      }
    }

    return {'created': created, 'updated': updated, 'skipped': skipped, 'admissionSkipped': admissionSkipped, 'manualReview': manualReview};
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchStudentsByIds(List<String> studentIds) async {
    if (studentIds.isEmpty) return [];
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final studentId in studentIds) {
      final snap = await _students.where(FieldPath.documentId, isEqualTo: studentId).limit(1).get();
      results.addAll(snap.docs);
    }
    return results;
  }

  Future<Map<String, int>> bulkAssignClassFees({
    required String classId,
    required String className,
    required String feeStructureId,
    required String feeStructureName,
    required String academicYearId,
    required String academicYear,
    required double totalFee,
    required double discountAmount,
    String feeMonth = '',
    DateTime? dueDate,
  }) async {
    feeMonth = await _checkFeeMonth(feeStructureId, feeMonth);
    // One due date for the whole class, required; each assignment can be
    // changed later with Edit.
    dueDate = _checkDueDate(dueDate, required: true);
    final students = await getStudentsByClassId(classId);
    var assigned = 0;
    var skipped = 0;
    // Each student by their own Admission Date: not yet admitted for this
    // month (or, for a Term / One-time fee, today), or no date recorded
    // (manual review), is skipped; neither counts as a duplicate.
    var admissionSkipped = 0;
    var manualReview = 0;
    // Student discounts: applied to each student whose discount covers the
    // period ([studentDiscounted]); a student whose discount applies while
    // a manual discount is being given is skipped ([discountConflict],
    // manual review): the two are never combined.
    var studentDiscounted = 0;
    var discountConflict = 0;
    final today = _clock();
    final components = students.any((s) => StudentFeeDiscount.fromStudent(s.data()) != null) ? await _componentsOf(feeStructureId) : const <FeeComponentModel>[];
    final batch = _firestore.batch();
    for (final student in students) {
      final studentData = student.data();
      switch (FeeAdmission.check(AdmissionDate.parse(studentData['admissionDate']), feeMonth: feeMonth, assignmentDate: today)) {
        case FeeAdmissionStatus.notYetAdmitted:
          admissionSkipped++;
          continue;
        case FeeAdmissionStatus.notRecorded:
          manualReview++;
          continue;
        case FeeAdmissionStatus.eligible:
      }
      final isDuplicate = await _hasDuplicateAssignment(
        studentId: student.id,
        feeStructureId: feeStructureId,
        academicYearId: academicYearId,
        academicYear: academicYear,
        feeMonth: feeMonth,
      );
      if (isDuplicate) {
        skipped++;
        continue;
      }
      final discount = _discountForNew(studentData, gross: totalFee, manualDiscount: discountAmount, feeMonth: feeMonth, components: components);
      if (discount.conflict) {
        discountConflict++;
        continue;
      }
      if (discount.snapshot != null) studentDiscounted++;
      final payable = totalFee - discountAmount;
      final doc = _assignments.doc();
      batch.set(doc, {
        'id': doc.id,
        'studentId': student.id,
        'studentName': studentData['name']?.toString() ?? '',
        'admissionNo': studentData['admissionNo']?.toString() ?? '',
        'classId': classId,
        'className': className,
        'feeStructureId': feeStructureId,
        'feeStructureName': feeStructureName,
        'academicYearId': academicYearId,
        'academicYear': academicYear,
        if (feeMonth.isNotEmpty) 'feeMonth': feeMonth,
        'dueDate': ?dueDate,
        'totalFee': totalFee,
        'discountAmount': discountAmount,
        'payableAmount': payable,
        'paidAmount': 0,
        'balanceAmount': payable,
        'status': 'unpaid',
        'assignedBy': _auth.currentUser?.uid ?? 'admin',
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (discount.snapshot case final snap?) ..._discountedAmounts(totalFee, snap),
      });
      assigned++;
    }
    await batch.commit();
    return {
      'assigned': assigned,
      'skipped': skipped,
      'admissionSkipped': admissionSkipped,
      'manualReview': manualReview,
      'studentDiscounted': studentDiscounted,
      'discountConflict': discountConflict,
    };
  }

  // ------------------------------------------------ Reports

  /// Everything Fees → Reports needs beyond the students and classes the
  /// screen already has: one read of `student_fee_assignments` (every live
  /// one, including older ones without `assignedAt`, which the ordered
  /// list skips) and one of `fee_receipts` (voided ones included, marked).
  /// Read-only; never one query per student.
  Future<FeeReportData> getReportData() async {
    final assignments = (await _assignments.get()).docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => StudentFeeAssignmentModel.fromMap(d.id, d.data()))
        .toList();
    final payments = [
      for (final d in (await _receipts.get()).docs) FeeReportPayment(FeeReceiptModel.fromMap(d.id, d.data()), voided: d.data()['isDeleted'] == true),
    ];
    return FeeReportData(assignments: assignments, payments: payments);
  }

  // ------------------------------------------------ Set Missing Due Dates

  /// The fee structure [id] for an assignment, or null and why it can't be
  /// used (none recorded, not found, deleted). An inactive structure is
  /// still used: its settings are unchanged.
  static (FeeStructureModel?, String) _backfillStructure(String id, Map<String, dynamic>? data, String name) {
    final named = name.trim().isEmpty ? 'Its fee structure' : 'Its fee structure "${name.trim()}"';
    if (id.isEmpty) return (null, 'No fee structure is recorded on this assignment.');
    if (data == null) return (null, '$named was not found.');
    if (data['isDeleted'] == true) return (null, '$named has been deleted.');
    return (FeeStructureModel.fromMap(id, data), '');
  }

  /// Set Missing Due Dates, step 1: a read-only scan of every assignment
  /// that isn't deleted (including older ones without `assignedAt`),
  /// classified by FeeDueBackfill.classify against its structure's
  /// current settings. Writes nothing.
  Future<FeeDueBackfillPreview> previewMissingDueDates() async {
    final assignments = (await _assignments.get()).docs.where((d) => d.data()['isDeleted'] != true);
    final structures = {for (final d in (await _structures.get()).docs) d.id: d.data()};
    final items = [
      for (final d in assignments)
        if (StudentFeeAssignmentModel.fromMap(d.id, d.data()) case final a)
          if (_backfillStructure(a.feeStructureId, structures[a.feeStructureId], a.feeStructureName) case (final s, final problem))
            FeeDueBackfill.classify(a, s, structureProblem: problem),
    ]..sort((x, y) => x.assignment.studentName.toLowerCase().compareTo(y.assignment.studentName.toLowerCase()));
    return FeeDueBackfillPreview(items);
  }

  /// Assignments per Set Missing Due Dates transaction: at most this many
  /// writes each, well inside Firestore's 500.
  static const dueBackfillChunk = 200;

  /// Set Missing Due Dates, step 2, after the administrator confirms
  /// [preview]: for each eligible assignment, in transactions of at most
  /// [chunkSize], the assignment and its structure are read again and
  /// classified again inside the transaction, so a record changed by
  /// anyone else meanwhile is rechecked, never overwritten:
  /// - now has a due date: skipped;
  /// - deleted or gone, or no date can be calculated any more: skipped;
  /// - still eligible: only `dueDate` is written (the date recalculated
  ///   from the structure's current settings).
  /// A failed transaction writes nothing for its records; they are
  /// reported as failed, and the other transactions still run. Nothing
  /// else (amounts, payments, receipts, Finance, status) is touched.
  /// Running it again changes nothing already dated.
  Future<FeeDueBackfillResult> applyMissingDueDates(FeeDueBackfillPreview preview, {int chunkSize = dueBackfillChunk}) async {
    if (chunkSize < 1 || chunkSize > maxBatchWrites) throw ArgumentError.value(chunkSize, 'chunkSize');
    final eligible = {for (final i in preview.eligible) i.assignment.id: i}.values.toList();
    final updated = <FeeDueBackfillItem>[], had = <FeeDueBackfillItem>[], changed = <FeeDueBackfillItem>[], failed = <FeeDueBackfillItem>[];
    final attention = [for (final i in preview.items) if (i.category.needsAttention) i];
    final errors = <String>[];
    for (var start = 0; start < eligible.length; start += chunkSize) {
      final chunk = eligible.sublist(start, (start + chunkSize).clamp(0, eligible.length));
      try {
        final outcomes = await _firestore.runTransaction((txn) async {
          // Fresh on every attempt: a retried transaction re-reads.
          final out = <(String, FeeDueBackfillItem)>[];
          final writes = <(DocumentReference<Map<String, dynamic>>, DateTime)>[];
          final structures = <String, (FeeStructureModel?, String)>{};
          for (final item in chunk) {
            final ref = _assignments.doc(item.assignment.id);
            final data = (await txn.get(ref)).data();
            if (data == null) {
              out.add(('changed', item.withReason('The assignment no longer exists.')));
              continue;
            }
            if (data['isDeleted'] == true) {
              out.add(('changed', item.withReason('The assignment has been deleted.')));
              continue;
            }
            final a = StudentFeeAssignmentModel.fromMap(ref.id, data);
            final sid = a.feeStructureId;
            final s = structures[sid] ??=
                _backfillStructure(sid, sid.isEmpty ? null : (await txn.get(_structures.doc(sid))).data(), a.feeStructureName);
            final now = FeeDueBackfill.classify(a, s.$1, structureProblem: s.$2);
            switch (now.category) {
              case FeeDueBackfillCategory.hasDueDate:
                out.add(('had', now));
              case FeeDueBackfillCategory.eligible:
                final date = now.proposedDate!;
                final recalculated = date != item.proposedDate;
                writes.add((ref, date));
                out.add(('updated', recalculated
                    ? now.withReason('Recalculated: the fee structure changed since the preview (it proposed ${FeeDueDate.label(item.proposedDate!)}).')
                    : now));
              default:
                out.add(('attention', now.withReason('Changed since the preview: ${now.reason}')));
            }
          }
          for (final (ref, date) in writes) {
            txn.update(ref, {'dueDate': FeeDueDate.dateOnly(date)});
          }
          return out;
        });
        for (final (kind, item) in outcomes) {
          switch (kind) {
            case 'updated':
              updated.add(item);
            case 'had':
              had.add(item);
            case 'attention':
              changed.add(item);
              attention.add(item);
            default:
              changed.add(item);
          }
        }
      } catch (e) {
        failed.addAll([for (final i in chunk) i.withReason('Not saved: $e')]);
        errors.add('$e');
      }
    }
    return FeeDueBackfillResult(updated: updated, alreadyHadDate: had, changed: changed, failed: failed, stillNeedAttention: attention, errors: errors);
  }

  // ------------------------------------------------ Apply Student Discounts to Existing Fees

  /// Step 1: a read-only scan. Every live assignment of a student who has
  /// a discount configuration is classified (FeeDiscountApply.classify).
  /// Three reads (students, assignments, structures); writes nothing.
  Future<FeeDiscountApplyPreview> previewStudentDiscounts() async {
    final students = {
      for (final d in (await _students.get()).docs)
        if (StudentFeeDiscount.fromStudent(d.data()) != null) d.id: d.data(),
    };
    if (students.isEmpty) return FeeDiscountApplyPreview(const []);
    final structures = {
      for (final d in (await _structures.get()).docs)
        if (d.data()['isDeleted'] != true) d.id: FeeStructureModel.fromMap(d.id, d.data()),
    };
    final items = [
      for (final d in (await _assignments.get()).docs)
        if (d.data()['isDeleted'] != true && students.containsKey(d.data()['studentId']?.toString()))
          if (StudentFeeAssignmentModel.fromMap(d.id, d.data()) case final a) FeeDiscountApply.classify(a, students[a.studentId], structures[a.feeStructureId]),
    ]..sort((x, y) {
        final c = x.assignment.studentName.toLowerCase().compareTo(y.assignment.studentName.toLowerCase());
        return c != 0 ? c : x.assignment.feeMonth.compareTo(y.assignment.feeMonth);
      });
    return FeeDiscountApplyPreview(items);
  }

  /// Assignments per Apply Student Discounts transaction.
  static const discountApplyChunk = 200;

  /// Step 2, after the administrator confirms [preview]: for each eligible
  /// assignment, in transactions of at most [chunkSize], the assignment, the
  /// student and the fee structure are read again inside the transaction
  /// and classified again. It is written only when it is still eligible
  /// with exactly the previewed discount; otherwise it is skipped (reported
  /// with why), never recalculated silently.
  ///
  /// The write changes only `discountAmount`, `payableAmount`,
  /// `balanceAmount`, `status` and `updatedAt`, and adds the
  /// `studentDiscount` snapshot, which is also the audit record: the terms,
  /// the amount and allocation, [FeeDiscountSnapshot.previous] figures, the
  /// administrator's uid, the time and this run's operation id.
  /// `paidAmount`, receipts, transactions and Finance are never touched.
  /// An assignment with a snapshot is never processed again, so running
  /// this again (or retrying after a failed transaction) is safe.
  Future<FeeDiscountApplyResult> applyStudentDiscounts(FeeDiscountApplyPreview preview, {int chunkSize = discountApplyChunk}) async {
    if (chunkSize < 1 || chunkSize > maxBatchWrites) throw ArgumentError.value(chunkSize, 'chunkSize');
    final operationId = 'discount-${_clock().millisecondsSinceEpoch}-${_assignments.doc().id}';
    final uid = _auth.currentUser?.uid ?? 'admin';
    final eligible = {for (final i in preview.eligible) i.assignment.id: i}.values.toList();
    final applied = <FeeDiscountApplyItem>[], skipped = <FeeDiscountApplyItem>[], failed = <FeeDiscountApplyItem>[];
    final errors = <String>[];
    for (var start = 0; start < eligible.length; start += chunkSize) {
      final chunk = eligible.sublist(start, (start + chunkSize).clamp(0, eligible.length));
      try {
        final outcomes = await _firestore.runTransaction((txn) async {
          // Fresh on every attempt: a retried transaction re-reads.
          final out = <(bool, FeeDiscountApplyItem)>[];
          final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[];
          final students = <String, Map<String, dynamic>?>{};
          final structures = <String, FeeStructureModel?>{};
          for (final item in chunk) {
            final ref = _assignments.doc(item.assignment.id);
            final data = (await txn.get(ref)).data();
            if (data == null || data['isDeleted'] == true) {
              out.add((false, item.withReason(data == null ? 'The assignment no longer exists.' : 'The assignment has been deleted.')));
              continue;
            }
            final a = StudentFeeAssignmentModel.fromMap(ref.id, data);
            if (a.studentId != item.assignment.studentId) {
              out.add((false, item.withReason('The assignment now belongs to another student.')));
              continue;
            }
            final student = students.containsKey(a.studentId)
                ? students[a.studentId]
                : students[a.studentId] = a.studentId.isEmpty ? null : (await txn.get(_students.doc(a.studentId))).data();
            final sid = a.feeStructureId;
            final structure = structures.containsKey(sid)
                ? structures[sid]
                : structures[sid] = switch (sid.isEmpty ? null : (await txn.get(_structures.doc(sid))).data()) {
                    final d? when d['isDeleted'] != true => FeeStructureModel.fromMap(sid, d),
                    _ => null,
                  };
            final now = FeeDiscountApply.classify(a, student, structure);
            if (now.category != FeeDiscountApplyCategory.eligible) {
              out.add((false, now.withReason('Changed since the preview: ${now.reason}')));
              continue;
            }
            if (_paise(now.proposed) != _paise(item.proposed) || now.config?.id != item.config?.id) {
              out.add((false, now.withReason('Changed since the preview: the discount would now be ${_formatAmount(now.proposed)} '
                  '(previewed ${_formatAmount(item.proposed)}). Preview again to apply it.')));
              continue;
            }
            final snapshot = FeeDiscountSnapshot.of(now.config!, now.calculation!, now.period!,
                source: FeeDiscountSource.existing,
                appliedBy: uid,
                operationId: operationId,
                previous: {
                  'totalFee': a.totalFee,
                  'discountAmount': a.discountAmount,
                  'payableAmount': a.payableAmount,
                  'paidAmount': a.paidAmount,
                  'balanceAmount': a.balanceAmount,
                  'status': a.status,
                });
            writes.add((ref, {
              'discountAmount': (_paise(a.discountAmount) + _paise(now.proposed)) / 100,
              'payableAmount': now.revisedPayable,
              'balanceAmount': now.revisedOutstanding,
              'status': now.revisedStatus,
              FeeDiscountSnapshot.field: snapshot.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            }));
            out.add((true, now));
          }
          for (final (ref, update) in writes) {
            txn.update(ref, update);
          }
          return out;
        });
        for (final (ok, item) in outcomes) {
          (ok ? applied : skipped).add(item);
        }
      } catch (e) {
        failed.addAll([for (final i in chunk) i.withReason('Not saved: $e')]);
        errors.add('$e');
      }
    }
    return FeeDiscountApplyResult(operationId: operationId, applied: applied, skipped: skipped, failed: failed, errors: errors);
  }

  /// Firestore allows 500 writes per batch; recurring assignments are
  /// written in batches of at most this many.
  static const maxBatchWrites = 400;

  /// Recurring monthly assignment: one separate assignment for every
  /// student in [students] and every month in [months] (each with its own
  /// fee month, academic year, due date, payable, paid and balance).
  ///
  /// The whole request is checked before anything is written: a Monthly
  /// structure, valid months in order with no repeats, each month's
  /// academic year, a valid due date for every month, and a discount within
  /// the fee. A student/month that already exists (the same rule as
  /// [assignFee]: the same month, or an older assignment of that structure
  /// and year with no month recorded) is skipped; the student's other
  /// months are still created. Writes go in batches of [maxBatchWrites];
  /// if a batch fails, the result says how many were created and how many
  /// failed. No collection, receipt or Finance entry is created.
  Future<FeeRecurringResult> assignMonthlyFees({
    required List<FeeStudent> students,
    required String classId,
    required String className,
    required String feeStructureId,
    required String feeStructureName,
    required List<FeeMonthPlan> months,
    required double totalFee,
    required double discountAmount,
  }) async {
    if (students.isEmpty) throw StateError('There are no students to assign.');
    if (months.isEmpty) throw StateError('Choose the months to assign.');
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      await _checkFeeMonth(feeStructureId, m.feeMonth);
      if (m.feeMonth.isEmpty) throw StateError(feeMonthRequiredMessage);
      if (i > 0 && m.feeMonth.compareTo(months[i - 1].feeMonth) <= 0) throw StateError('The months must be in order, each once.');
      if (m.academicYearId.isEmpty) throw StateError('${FeeMonth.label(m.feeMonth)} has no academic year.');
      _checkDueDate(m.dueDate, required: true);
    }
    if (discountAmount < 0 || discountAmount > totalFee) throw StateError('Discount amount must be between 0 and the total fee.');

    // Existing assignments: one read per student, checked in memory with
    // the same rule as _hasDuplicateAssignment.
    final toCreate = <(FeeStudent, FeeMonthPlan, FeeDiscountSnapshot?)>[];
    var skipped = 0;
    // Admission Date from each student's own record (read here, not taken
    // from the caller): months ending before admission are skipped, so a
    // student admitted partway through starts at their admission month; a
    // student with none recorded is skipped for manual review.
    var admissionSkipped = 0;
    var manualReview = 0;
    final reviewStudents = <String>[];
    final unique = {for (final s in students) s.id: s}.values.toList();
    final studentData = {
      for (final (i, snap) in (await Future.wait([for (final s in unique) _students.doc(s.id).get()])).indexed) unique[i].id: snap.data(),
    };
    final admitted = {for (final s in unique) s.id: AdmissionDate.parse(studentData[s.id]?['admissionDate'])};
    final components = studentData.values.any((d) => StudentFeeDiscount.fromStudent(d) != null) ? await _componentsOf(feeStructureId) : const <FeeComponentModel>[];
    var studentDiscounted = 0;
    var discountConflict = 0;
    final conflictStudents = <String>[];
    // Each student once, so each student/month is created at most once.
    for (final student in unique) {
      final eligibleMonths = <FeeMonthPlan>[];
      for (final m in months) {
        switch (FeeAdmission.forMonth(admitted[student.id], m.feeMonth)) {
          case FeeAdmissionStatus.eligible:
            eligibleMonths.add(m);
          case FeeAdmissionStatus.notYetAdmitted:
            admissionSkipped++;
          case FeeAdmissionStatus.notRecorded:
            manualReview++;
        }
      }
      if (admitted[student.id] == null) reviewStudents.add(student.name.isEmpty ? student.id : student.name);
      if (eligibleMonths.isEmpty) continue;
      final existing = (await _assignments.where('studentId', isEqualTo: student.id).where('feeStructureId', isEqualTo: feeStructureId).get())
          .docs
          .map((d) => d.data())
          .where((d) => d['isDeleted'] != true)
          .toList();
      for (final m in eligibleMonths) {
        final duplicate = existing.any((d) {
          final sameYear = (d['academicYearId']?.toString() ?? '') == m.academicYearId || (d['academicYear']?.toString() ?? '') == m.academicYear;
          final other = d['feeMonth']?.toString() ?? '';
          return sameYear && (other.isEmpty || other == m.feeMonth);
        });
        if (duplicate) {
          skipped++;
          continue;
        }
        // The student's discount for this month (each month is its own
        // fee period): applied, or (with a manual discount) not combined.
        final discount = _discountForNew(studentData[student.id], gross: totalFee, manualDiscount: discountAmount, feeMonth: m.feeMonth, components: components);
        if (discount.conflict) {
          discountConflict++;
          final name = student.name.isEmpty ? student.id : student.name;
          if (!conflictStudents.contains(name)) conflictStudents.add(name);
          continue;
        }
        if (discount.snapshot != null) studentDiscounted++;
        toCreate.add((student, m, discount.snapshot));
      }
    }

    final payable = totalFee - discountAmount;
    final uid = _auth.currentUser?.uid ?? 'admin';
    var created = 0;
    for (var i = 0; i < toCreate.length; i += maxBatchWrites) {
      final chunk = toCreate.sublist(i, (i + maxBatchWrites).clamp(0, toCreate.length));
      final batch = _firestore.batch();
      for (final (student, m, snap) in chunk) {
        final doc = _assignments.doc();
        batch.set(doc, {
          'id': doc.id,
          'studentId': student.id,
          'studentName': student.name,
          'admissionNo': student.admissionNo,
          'classId': classId,
          'className': className,
          'feeStructureId': feeStructureId,
          'feeStructureName': feeStructureName,
          'academicYearId': m.academicYearId,
          'academicYear': m.academicYear,
          'feeMonth': m.feeMonth,
          'dueDate': FeeDueDate.dateOnly(m.dueDate),
          'totalFee': totalFee,
          'discountAmount': discountAmount,
          'payableAmount': payable,
          'paidAmount': 0,
          'balanceAmount': payable,
          'status': 'unpaid',
          'assignedBy': uid,
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (snap != null) ..._discountedAmounts(totalFee, snap),
        });
      }
      try {
        await batch.commit();
        created += chunk.length;
      } catch (e) {
        return FeeRecurringResult(created: created, skipped: skipped, failed: toCreate.length - created, error: '$e',
            admissionSkipped: admissionSkipped, manualReview: manualReview, reviewStudents: reviewStudents,
            studentDiscounted: studentDiscounted, discountConflict: discountConflict, conflictStudents: conflictStudents);
      }
    }
    return FeeRecurringResult(created: created, skipped: skipped, failed: 0,
        admissionSkipped: admissionSkipped, manualReview: manualReview, reviewStudents: reviewStudents,
        studentDiscounted: studentDiscounted, discountConflict: discountConflict, conflictStudents: conflictStudents);
  }

  Future<FeeReceiptModel> collectFee({
    required String assignmentId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMode,
    required String referenceNo,
    required String remarks,
  }) async {
    final assignmentRef = _assignments.doc(assignmentId);
    final txRef = _transactions.doc();
    final assignmentSnap = await assignmentRef.get();
    if (!assignmentSnap.exists) {
      throw StateError('Assignment not found');
    }
    final a = StudentFeeAssignmentModel.fromMap(assignmentSnap.id, assignmentSnap.data()!);
    if (amount <= 0 || amount > a.balanceAmount) {
      throw StateError('Invalid amount');
    }
    final paidAmount = a.paidAmount + amount;
    final balanceAmount = (a.payableAmount - paidAmount).clamp(0, double.infinity);
    final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
    final receiptNo = 'REC-2026-${DateTime.now().millisecondsSinceEpoch}';
    final currentUser = _auth.currentUser;
    final currentName = currentUser?.displayName ?? currentUser?.email ?? 'Admin';
    final receiptDoc = _receipts.doc();

    // Post the finance income entry first. If this fails (e.g. no active
    // finance account configured), nothing below has been written yet, so
    // the caller can safely retry without risking a duplicate collection.
    try {
      await _financeService.createFeeIncomeEntry({
        'type': 'income',
        'category': 'Fees',
        'amount': amount,
        'source': 'fees',
        'sourceId': receiptDoc.id,
        'feeCollectionId': receiptDoc.id,
        'feeAssignmentId': assignmentId,
        'feeStructureId': a.feeStructureId,
        'studentId': a.studentId,
        'studentName': a.studentName,
        'admissionNo': a.admissionNo,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo,
        'remarks': remarks,
        'description': 'Fee collected from ${a.studentName} - ${a.feeStructureName}${a.feeMonth.isEmpty ? '' : ' (${FeeMonth.label(a.feeMonth)})'}',
        'date': paymentDate,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser?.uid ?? currentName,
      });
    } catch (e) {
      throw StateError('Finance entry creation failed: $e');
    }

    final batch = _firestore.batch();
    batch.set(txRef, {
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'classId': a.classId,
      'className': a.className,
      'feeStructureId': a.feeStructureId,
      'feeStructureName': a.feeStructureName,
      if (a.feeMonth.isNotEmpty) 'feeMonth': a.feeMonth,
      'amount': amount,
      'paymentDate': paymentDate,
      'paymentMode': paymentMode,
      'referenceNo': referenceNo,
      'remarks': remarks,
      'collectedBy': currentName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(receiptDoc, {
      'receiptNo': receiptNo,
      'transactionId': txRef.id,
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'className': a.className,
      'feeStructureName': a.feeStructureName,
      'feeStructureId': a.feeStructureId,
      'feeCollectionId': receiptDoc.id,
      if (a.feeMonth.isNotEmpty) 'feeMonth': a.feeMonth,
      'amount': amount,
      'paymentMode': paymentMode,
      'paymentDate': paymentDate,
      'referenceNo': referenceNo,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': currentName,
      'pdfUrl': '',
      'pdfPath': '',
      'pdfGeneratedAt': null,
    });
    batch.update(assignmentRef, {
      'paidAmount': paidAmount,
      'balanceAmount': balanceAmount,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    final receiptSnap = await receiptDoc.get();
    final receipt = FeeReceiptModel.fromMap(receiptSnap.id, receiptSnap.data() ?? {
      'receiptNo': receiptNo,
      'transactionId': txRef.id,
      'assignmentId': assignmentId,
      'studentId': a.studentId,
      'studentName': a.studentName,
      'admissionNo': a.admissionNo,
      'className': a.className,
      'feeStructureName': a.feeStructureName,
      'amount': amount,
      'paymentMode': paymentMode,
      'paymentDate': paymentDate,
      'referenceNo': referenceNo,
      'createdAt': DateTime.now(),
      'createdBy': currentName,
      'pdfUrl': '',
      'pdfPath': '',
      'pdfGeneratedAt': null,
    });
    // PDF generation is best-effort: the collection and finance entry are
    // already recorded above, and the Receipts UI offers a "Generate PDF"
    // retry, so a failure here must not surface as a failed collection
    // (that would invite a retry that double-collects the fee).
    await generateAndUploadReceiptPdf(receipt);
    return receipt;
  }

  Future<bool> generateAndUploadReceiptPdf(FeeReceiptModel receipt) async {
    final pdf = pw.Document();
    pw.ImageProvider? logo;
    try {
      final data = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {}
    String safe(String? value) => (value == null || value.trim().isEmpty) ? '-' : value.trim();
    final rows = <Map<String, String>>[
      {'label': 'Receipt No', 'value': safe(receipt.receiptNo)},
      {'label': 'Student Name', 'value': safe(receipt.studentName)},
      {'label': 'Admission No', 'value': safe(receipt.admissionNo)},
      {'label': 'Class', 'value': safe(receipt.className)},
      {'label': 'Fee Name', 'value': safe(receipt.feeStructureName)},
      if (receipt.feeMonth.isNotEmpty) {'label': 'Fee Month', 'value': safe(FeeMonth.label(receipt.feeMonth))},
      {'label': 'Amount Paid', 'value': 'Rs. ${receipt.amount.toStringAsFixed(0)}'},
      {'label': 'Payment Mode', 'value': safe(receipt.paymentMode)},
      {'label': 'Reference No', 'value': safe(receipt.referenceNo)},
      {'label': 'Payment Date', 'value': safe(receipt.paymentDate?.toIso8601String().split('T').first)},
      {'label': 'Generated Date', 'value': DateTime.now().toIso8601String().split('T').first},
    ];
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  if (logo != null) pw.Image(logo, height: 42),
                  pw.SizedBox(height: 6),
                  pw.Text('2D Montessori', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('FEE RECEIPT', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
              columnWidths: const {
                0: pw.FixedColumnWidth(150),
                1: pw.FlexColumnWidth(),
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              data: <List<String>>[
                ['Label', 'Value'],
                ...rows.map((row) => [row['label']!, row['value']!]),
              ],
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('System generated receipt', style: const pw.TextStyle(fontSize: 8)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 10),
                    pw.Container(width: 110, height: 0.6, color: PdfColors.grey700),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final bytes = await pdf.save();
    final path = 'fee_receipts/${receipt.id}/${receipt.receiptNo}.pdf';
    try {
      final ref = _storage.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();
      await _receipts.doc(receipt.id).set({
        'pdfUrl': url,
        'pdfPath': path,
        'pdfGeneratedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final assignments = await getAssignments();
    final receipts = await getReceipts();
    final totalExpected = assignments.fold<double>(0, (total, a) => total + a.payableAmount);
    final totalCollected = assignments.fold<double>(0, (total, a) => total + a.paidAmount);
    final outstanding = assignments.fold<double>(0, (total, a) => total + a.balanceAmount);
    final today = DateTime.now();
    // Distinct students with an overdue assignment (FeeDueDate.isOverdue).
    final overdue = FeeDueDate.overdueStudents(assignments, today);
    final todayCollected = receipts.where((r) => r.paymentDate != null && r.paymentDate!.year == today.year && r.paymentDate!.month == today.month && r.paymentDate!.day == today.day).fold<double>(0, (total, r) => total + r.amount);
    return {
      'totalExpected': totalExpected,
      'totalCollected': totalCollected,
      'outstanding': outstanding,
      'collectionPercent': totalExpected == 0 ? 0 : (totalCollected / totalExpected) * 100,
      'overdueStudents': overdue,
      'todayCollection': todayCollected,
    };
  }

  Future<void> seedSampleFeeStructures() async {
    final existing = await _structures.get();
    final names = existing.docs.map((d) => d.data()['name']?.toString().trim().toLowerCase() ?? '').toSet();
    final samples = [
      {
        'name': 'Montessori Core Fees',
        'description': 'Primary tuition and activity fees.',
        'components': [
          FeeComponentModel(name: 'Tuition', amount: 25000, frequency: 'term', termName: 'Term 1', isOptional: false).toMap(),
          FeeComponentModel(name: 'Activity', amount: 5000, frequency: 'oneTime', isOptional: false).toMap(),
        ],
        'totalAmount': 30000,
        'academicYear': '2026-2027',
        'isActive': true,
        'createdBy': 'seed',
      },
    ];
    for (final s in samples) {
      if (names.contains(s['name'].toString().trim().toLowerCase())) continue;
      await createFeeStructure(s);
    }
  }
}

/// Result of a successful [FeeService.voidReceipt].
enum FeeVoidOutcome {
  /// The collection and its Finance entry are now both voided.
  voided,

  /// The collection was already voided; its Finance entry, left active by
  /// an earlier partial failure, has now been reversed to match.
  financeReconciled,
}

enum FeeVoidFailure {
  collectionNotFound,
  alreadyVoided,
  financeMissing,
  financeMismatch,
  financeAmbiguous,
  financeInconsistent,
  amountMismatch,
}

/// Why [FeeService.voidReceipt] refused, before writing anything. A
/// [StateError], as before, so existing callers and messages still work.
class FeeVoidException extends StateError {
  FeeVoidException(this.failure, super.message);

  final FeeVoidFailure failure;
}

/// What [FeeService.assignMonthlyFees] did: assignments created, skipped
/// as duplicates, skipped because the month ends before the student's
/// admission ([admissionSkipped]), not created because no admission date
/// is recorded ([manualReview] student-months, for [reviewStudents]), and
/// not created because a write failed ([error]).
class FeeRecurringResult {
  const FeeRecurringResult({
    required this.created,
    required this.skipped,
    required this.failed,
    this.error,
    this.admissionSkipped = 0,
    this.manualReview = 0,
    this.reviewStudents = const [],
    this.studentDiscounted = 0,
    this.discountConflict = 0,
    this.conflictStudents = const [],
  });

  final int created, skipped, failed, admissionSkipped, manualReview;
  final List<String> reviewStudents;

  /// Created with the student's discount; skipped because the student's
  /// discount applies while a manual discount was given (manual review).
  final int studentDiscounted, discountConflict;
  final List<String> conflictStudents;
  final String? error;

  String get message => [
        'Created $created ${created == 1 ? 'assignment' : 'assignments'}',
        'skipped $skipped as duplicates',
        'skipped $admissionSkipped before admission',
        '$manualReview need manual review${reviewStudents.isEmpty ? '' : ' (no admission date: ${reviewStudents.join(', ')})'}',
        if (studentDiscounted > 0) '$studentDiscounted with the student\'s discount',
        if (discountConflict > 0)
          'skipped $discountConflict for manual review (student discount not combined with the manual discount: ${conflictStudents.join(', ')})',
        'failed $failed',
      ].join(', ') + (error == null ? '.' : '. Some assignments could not be saved: $error');
}
