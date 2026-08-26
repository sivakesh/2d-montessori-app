import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../models/fee_component_model.dart';
import '../models/fee_receipt_model.dart';
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
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _injectedFinanceService = financeService;

  final FirebaseFirestore _firestore;
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

  Future<List<FeeStructureModel>> getActiveStructuresForClass(String classId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  Future<List<FeeStructureModel>> getActiveStructuresForStudent(String studentId) async {
    final all = await getFeeStructures();
    return all.where((s) => s.isActive).toList();
  }

  Future<String> createFeeStructure(Map<String, dynamic> data) async {
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
  Future<bool> _hasDuplicateAssignment({
    required String studentId,
    required String feeStructureId,
    required String academicYearId,
    required String academicYear,
    String? excludeId,
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

  Future<String?> assignFee(Map<String, dynamic> data) async {
    final studentId = data['studentId']?.toString() ?? '';
    final feeStructureId = data['feeStructureId']?.toString() ?? '';
    final academicYearId = data['academicYearId']?.toString() ?? '';
    final academicYear = data['academicYear']?.toString() ?? '';
    final isDuplicate = await _hasDuplicateAssignment(
      studentId: studentId,
      feeStructureId: feeStructureId,
      academicYearId: academicYearId,
      academicYear: academicYear,
    );
    if (isDuplicate) return null;
    final doc = _assignments.doc();
    await doc.set({
      ...data,
      'id': doc.id,
      'discountAmount': (data['discountAmount'] as num?)?.toDouble() ?? 0,
      'paidAmount': (data['paidAmount'] as num?)?.toDouble() ?? 0,
      'balanceAmount': (data['balanceAmount'] as num?)?.toDouble() ?? 0,
      'assignedBy': _auth.currentUser?.uid ?? data['assignedBy']?.toString() ?? 'admin',
      'assignedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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
          newYear != current.academicYear) {
        final hasLiveDuplicate = await _hasDuplicateAssignment(
          studentId: newStudentId,
          feeStructureId: newFeeStructureId,
          academicYearId: newAcademicYearId,
          academicYear: newYear,
          excludeId: id,
        );
        if (hasLiveDuplicate) {
          throw StateError('An assignment for this student, fee structure, and academic year already exists.');
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
      ...data,
      'totalFee': totalFee,
      'discountAmount': discountAmount,
      'payableAmount': payableAmount,
      'balanceAmount': balanceAmount,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
  /// [FinanceService.reverseFeeIncomeByCollectionId]. Guarded against
  /// double-voiding: a receipt already marked `isDeleted` is refused
  /// rather than re-subtracting its amount from the assignment a second
  /// time.
  Future<void> voidReceipt(String id) async {
    final snap = await _receipts.doc(id).get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('Collection not found');
    }
    final data = snap.data()!;
    if (data['isDeleted'] == true) {
      throw StateError('This collection has already been voided.');
    }
    final receipt = FeeReceiptModel.fromMap(snap.id, data);

    // Finance reversal first, same fail-safe-first ordering collectFee
    // already uses for its own Finance call: if this throws, neither the
    // assignment nor the receipt below has been touched yet, so a retry is
    // always safe. Doing the assignment/receipt writes first and Finance
    // last would risk exactly the partial-corruption this ordering avoids
    // — the assignment balance already reversed while the receipt still
    // reads as a valid, uncounted payment.
    await _financeService.reverseFeeIncomeByCollectionId(receipt.id);

    // Assignment balance + receipt soft-delete land together in one
    // atomic batch, so a mid-write failure can never leave one updated
    // without the other.
    final batch = _firestore.batch();
    if (receipt.assignmentId.isNotEmpty) {
      final assignmentRef = _assignments.doc(receipt.assignmentId);
      final assignmentSnap = await assignmentRef.get();
      if (assignmentSnap.exists && assignmentSnap.data() != null) {
        final a = StudentFeeAssignmentModel.fromMap(assignmentSnap.id, assignmentSnap.data()!);
        final paidAmount = (a.paidAmount - receipt.amount).clamp(0, double.infinity);
        final balanceAmount = (a.payableAmount - paidAmount).clamp(0, double.infinity);
        final status = balanceAmount == 0 ? 'paid' : paidAmount > 0 ? 'partial' : 'unpaid';
        batch.set(assignmentRef, {
          'paidAmount': paidAmount,
          'balanceAmount': balanceAmount,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    batch.set(_receipts.doc(id), {
      'isDeleted': true,
      'voidedAt': FieldValue.serverTimestamp(),
      'voidedBy': _auth.currentUser?.uid,
      // Kept for backward compatibility with anything still reading the
      // original soft-delete field name (e.g. getReceipts()'s filter).
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<Map<String, int>> syncAssignmentsForFeeStructure({
    required String feeStructureId,
    required String feeStructureName,
    required String academicYearId,
    required String academicYear,
    required double totalFee,
    required String assignmentScope,
    required List<String> classIds,
    required List<String> studentIds,
  }) async {
    final targetStudents = assignmentScope == 'student'
        ? await _fetchStudentsByIds(studentIds)
        : await getStudentsByClassIds(classIds);

    var created = 0;
    var updated = 0;
    var skipped = 0;

    for (final student in targetStudents) {
      final studentData = student.data();
      final studentId = student.id;
      final existing = await _findExistingAssignment(
        studentId: studentId,
        feeStructureId: feeStructureId,
        academicYearId: academicYearId,
        academicYear: academicYear,
      );

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
          'assignedBy': _auth.currentUser?.uid ?? 'admin',
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        created++;
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

    return {'created': created, 'updated': updated, 'skipped': skipped};
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
  }) async {
    final students = await getStudentsByClassId(classId);
    var assigned = 0;
    var skipped = 0;
    final batch = _firestore.batch();
    for (final student in students) {
      final studentData = student.data();
      final isDuplicate = await _hasDuplicateAssignment(
        studentId: student.id,
        feeStructureId: feeStructureId,
        academicYearId: academicYearId,
        academicYear: academicYear,
      );
      if (isDuplicate) {
        skipped++;
        continue;
      }
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
        'totalFee': totalFee,
        'discountAmount': discountAmount,
        'payableAmount': payable,
        'paidAmount': 0,
        'balanceAmount': payable,
        'status': 'unpaid',
        'assignedBy': _auth.currentUser?.uid ?? 'admin',
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      assigned++;
    }
    await batch.commit();
    return {'assigned': assigned, 'skipped': skipped};
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
        'description': 'Fee collected from ${a.studentName} - ${a.feeStructureName}',
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
    final overdue = assignments.where((a) => a.status == 'overdue').length;
    final today = DateTime.now();
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
