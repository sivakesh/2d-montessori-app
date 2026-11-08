import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import 'expense_efficiency_models.dart';

class UnauthorizedExpenseEfficiencyException implements Exception {
  UnauthorizedExpenseEfficiencyException(this.role);
  final String role;
  @override
  String toString() => 'Only an administrator can change expense assessments and targets (signed in as "$role").';
}

/// Expense Efficiency's own data: `finance_expense_assessments` (one per
/// expense, document id = the ledger entry's id) and
/// `finance_expense_targets`, each change also recorded in the record's
/// `audit` subcollection (the convention of `website_media/{id}/audit`).
///
/// It reads `finance_ledger` only to check that an assessment is for a real
/// expense of this school, and never writes to it, nor to any Finance, fee
/// or account record: every write here is to the two collections above.
///
/// Writes take the requester's role and refuse anyone but an
/// administrator (the AcademicYearService convention). Reads are open to
/// whoever can open Finance.
class ExpenseEfficiencyService {
  ExpenseEfficiencyService({FirebaseFirestore? firestore, FirebaseAuth? auth, this.schoolId = kDefaultSchoolId})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String schoolId;

  static const assessmentsCollection = 'finance_expense_assessments';
  static const targetsCollection = 'finance_expense_targets';

  CollectionReference<Map<String, dynamic>> get _assessments => _firestore.collection(assessmentsCollection);
  CollectionReference<Map<String, dynamic>> get _targets => _firestore.collection(targetsCollection);
  CollectionReference<Map<String, dynamic>> get _ledger => _firestore.collection('finance_ledger');

  String get _actor => _auth.currentUser?.uid ?? _auth.currentUser?.email ?? 'admin';

  void _requireAdmin(String role) {
    if (role.toLowerCase() != 'admin') throw UnauthorizedExpenseEfficiencyException(role);
  }

  // Removed records are kept with `isDeleted: true` (the app's soft-delete
  // convention), so their audit history stays attached; they are left out
  // of every read below.
  static Map<String, ExpenseAssessment> _liveAssessments(QuerySnapshot<Map<String, dynamic>> s) =>
      {for (final d in s.docs) if (d.data()['isDeleted'] != true) d.id: ExpenseAssessment.fromMap(d.id, d.data())};
  static List<ExpenseTarget> _liveTargets(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) if (d.data()['isDeleted'] != true) ExpenseTarget.fromMap(d.id, d.data())]..sort((a, b) {
          final c = a.categoryName.toLowerCase().compareTo(b.categoryName.toLowerCase());
          return c != 0 ? c : a.startMonth.compareTo(b.startMonth);
        });

  /// This school's assessments, by transaction id.
  Stream<Map<String, ExpenseAssessment>> watchAssessments() => _assessments.where('schoolId', isEqualTo: schoolId).snapshots().map(_liveAssessments);
  Stream<List<ExpenseTarget>> watchTargets() => _targets.where('schoolId', isEqualTo: schoolId).snapshots().map(_liveTargets);
  Future<Map<String, ExpenseAssessment>> getAssessments() async => _liveAssessments(await _assessments.where('schoolId', isEqualTo: schoolId).get());
  Future<List<ExpenseTarget>> getTargets() async => _liveTargets(await _targets.where('schoolId', isEqualTo: schoolId).get());

  /// The change history of an assessment or target, newest first.
  Future<List<Map<String, dynamic>>> history({required bool target, required String id}) async {
    final docs = (await (target ? _targets : _assessments).doc(id).collection('audit').get()).docs.map((d) => d.data()).toList();
    docs.sort((a, b) => ((b['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return docs;
  }

  // ------------------------------------------------ assessments

  /// Saves (creates or replaces) the assessment of ledger entry
  /// [transactionId]. In one transaction: the ledger entry is read and must
  /// exist, be an expense, not be cancelled and (when it records one)
  /// belong to this school; the avoidable amount is checked against its
  /// current amount (Waste / Avoidable defaults to the whole amount when
  /// none is given; Necessary, Useful and Under Review record none). Writes
  /// the assessment and an audit entry; the ledger entry is not written.
  Future<ExpenseAssessment> saveAssessment({
    required String requesterRole,
    required String transactionId,
    required ExpenseAssessmentCategory category,
    double? avoidableAmount,
    String reason = '',
    String managementNote = '',
    String correctiveAction = '',
    ExpenseActionStatus actionStatus = ExpenseActionStatus.none,
  }) async {
    _requireAdmin(requesterRole);
    if (transactionId.trim().isEmpty) throw StateError('Choose the expense to assess.');
    final ref = _assessments.doc(transactionId);
    return _firestore.runTransaction((txn) async {
      final ledger = (await txn.get(_ledger.doc(transactionId))).data();
      final existingSnap = await txn.get(ref);
      if (ledger == null) throw StateError('This expense is no longer in the ledger, so it cannot be assessed.');
      if (ledger['entryType']?.toString() != 'expense') throw StateError('Only expenses can be assessed.');
      if (ledger['status']?.toString() == 'cancelled') throw StateError('This expense has been cancelled; its assessment can no longer be changed.');
      final ledgerSchool = ledger['schoolId']?.toString() ?? '';
      if (ledgerSchool.isNotEmpty && ledgerSchool != schoolId) throw StateError('This expense belongs to another school.');
      final stored = existingSnap.data();
      if (stored != null && (stored['schoolId']?.toString() ?? schoolId) != schoolId) throw StateError('This assessment belongs to another school.');
      final existing = stored == null || stored['isDeleted'] == true ? null : stored;
      final amount = (ledger['amount'] as num?)?.toDouble() ?? 0;
      final avoidable = category.hasAvoidable ? (avoidableAmount ?? (category == ExpenseAssessmentCategory.waste ? amount : 0)) : 0.0;
      if (ExpenseAssessment.validate(category, avoidable, amount) case final e?) throw StateError(e);
      final a = ExpenseAssessment(
        transactionId: transactionId,
        schoolId: schoolId,
        category: category,
        reason: reason,
        managementNote: managementNote,
        correctiveAction: correctiveAction,
        actionStatus: actionStatus,
        avoidableAmount: avoidable,
        amountAtAssessment: amount,
      );
      final now = FieldValue.serverTimestamp();
      txn.set(ref, {
        ...a.toMap(),
        'assessedAt': existing?['assessedAt'] ?? now,
        'assessedBy': existing?['assessedBy'] ?? _actor,
        'updatedAt': now,
        'updatedBy': _actor,
      });
      txn.set(ref.collection('audit').doc(), {
        'action': existing == null ? 'created' : 'updated',
        if (existing != null) 'before': _auditable(existing, _assessmentKeys),
        'after': a.toMap(),
        'by': _actor,
        'at': now,
      });
      return a;
    });
  }

  /// Removes an assessment (the expense is Under Review again): kept as
  /// `isDeleted: true` with its audit history. Allowed for a cancelled or
  /// missing expense too.
  Future<void> deleteAssessment({required String requesterRole, required String transactionId}) async {
    _requireAdmin(requesterRole);
    final ref = _assessments.doc(transactionId);
    await _firestore.runTransaction((txn) async {
      final existing = (await txn.get(ref)).data();
      if (existing == null || existing['isDeleted'] == true) return;
      if ((existing['schoolId']?.toString() ?? schoolId) != schoolId) throw StateError('This assessment belongs to another school.');
      final now = FieldValue.serverTimestamp();
      txn.set(ref, {'isDeleted': true, 'deletedAt': now, 'deletedBy': _actor, 'updatedAt': now, 'updatedBy': _actor}, SetOptions(merge: true));
      txn.set(ref.collection('audit').doc(), {
        'action': 'deleted',
        'before': _auditable(existing, _assessmentKeys),
        'by': _actor,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  static const _assessmentKeys = [
    'transactionId', 'assessmentCategory', 'reason', 'managementNote', 'correctiveAction', 'actionStatus', 'avoidableAmount', 'amountAtAssessment',
  ];
  static const _targetKeys = ['categoryId', 'categoryName', 'monthlyAmount', 'startMonth', 'endMonth', 'note', 'isActive'];
  static Map<String, dynamic> _auditable(Map<String, dynamic> d, List<String> keys) => {for (final k in keys) if (d.containsKey(k)) k: d[k]};

  // ------------------------------------------------ targets

  /// Creates (no [ExpenseTarget.id]) or updates a target. Refused when
  /// invalid, or when an active target of the same category shares a
  /// month with it. Never touches any expense or balance.
  Future<String> saveTarget({required String requesterRole, required ExpenseTarget target}) async {
    _requireAdmin(requesterRole);
    if (target.error case final e?) throw StateError(e);
    final ref = target.id.isEmpty ? _targets.doc() : _targets.doc(target.id);
    final t = ExpenseTarget(
      id: ref.id, schoolId: schoolId, categoryId: target.categoryId, categoryName: target.categoryName, monthlyAmount: target.monthlyAmount,
      startMonth: target.startMonth, endMonth: target.endMonth, note: target.note, isActive: target.isActive,
    );
    final others = await getTargets();
    if (t.isActive) {
      final clash = others.where((o) => o.id != ref.id && o.isActive && o.overlaps(t)).firstOrNull;
      if (clash != null) {
        throw StateError('${t.categoryName.isEmpty ? 'This category' : t.categoryName} already has an active target for ${clash.monthsLabel}. '
            'Deactivate it or change its months first.');
      }
    }
    await _firestore.runTransaction((txn) async {
      final existing = (await txn.get(ref)).data();
      if (target.id.isNotEmpty && (existing == null || existing['isDeleted'] == true)) throw StateError('This target no longer exists.');
      if (existing != null && (existing['schoolId']?.toString() ?? schoolId) != schoolId) throw StateError('This target belongs to another school.');
      final now = FieldValue.serverTimestamp();
      txn.set(ref, {
        ...t.toMap(),
        'createdAt': existing?['createdAt'] ?? now,
        'createdBy': existing?['createdBy'] ?? _actor,
        'updatedAt': now,
        'updatedBy': _actor,
      });
      txn.set(ref.collection('audit').doc(), {
        'action': existing == null ? 'created' : (existing['isActive'] != false && !t.isActive ? 'deactivated' : 'updated'),
        if (existing != null) 'before': _auditable(existing, _targetKeys),
        'after': t.toMap(),
        'by': _actor,
        'at': now,
      });
    });
    return ref.id;
  }

  Future<void> setTargetActive({required String requesterRole, required ExpenseTarget target, required bool active}) => saveTarget(
        requesterRole: requesterRole,
        target: ExpenseTarget(
          id: target.id, schoolId: target.schoolId, categoryId: target.categoryId, categoryName: target.categoryName,
          monthlyAmount: target.monthlyAmount, startMonth: target.startMonth, endMonth: target.endMonth, note: target.note, isActive: active,
        ),
      );

  /// Removes a target: kept as `isDeleted: true` with its audit history.
  Future<void> deleteTarget({required String requesterRole, required String id}) async {
    _requireAdmin(requesterRole);
    final ref = _targets.doc(id);
    await _firestore.runTransaction((txn) async {
      final existing = (await txn.get(ref)).data();
      if (existing == null || existing['isDeleted'] == true) return;
      if ((existing['schoolId']?.toString() ?? schoolId) != schoolId) throw StateError('This target belongs to another school.');
      final now = FieldValue.serverTimestamp();
      txn.set(ref, {'isDeleted': true, 'isActive': false, 'deletedAt': now, 'deletedBy': _actor, 'updatedAt': now, 'updatedBy': _actor}, SetOptions(merge: true));
      txn.set(ref.collection('audit').doc(), {'action': 'deleted', 'before': _auditable(existing, _targetKeys), 'by': _actor, 'at': FieldValue.serverTimestamp()});
    });
  }
}
