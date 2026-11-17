import 'package:cloud_firestore/cloud_firestore.dart';

import 'parent_access.dart';

/// Thrown when someone other than an administrator tries to change parent
/// access. The security rules refuse it too; this stops it in the app first.
class ParentAccessDeniedException implements Exception {
  const ParentAccessDeniedException();
  @override
  String toString() => 'Only an administrator can change parent access.';
}

/// What [ParentAccessService.apply] wrote.
class ParentAccessApplyResult {
  const ParentAccessApplyResult({required this.written, required this.unchanged, required this.cleared});

  /// Access records created or changed.
  final int written;

  /// Records already correct (not rewritten).
  final int unchanged;

  /// Records of parents with no remaining links, emptied (never deleted).
  final int cleared;
}

/// How the stored access records compare with a reconciliation plan
/// ([ParentAccessService.compare]): parents with no record yet, records
/// that no longer match their links, and those already correct.
class ParentAccessComparison {
  const ParentAccessComparison({required this.missing, required this.outdated, required this.current});

  /// User ids of linked parents with no `parent_access` record: until Apply
  /// runs, their dashboard uses the older direct reads (no fee bills).
  final List<String> missing;
  final List<String> outdated;
  final int current;
}

/// Reads and maintains the `parent_access` index (see parent_access.dart and
/// docs/parent_access_security.md). Only administrators write it: after a
/// parent link changes (both admin link editors call [rebuildForParents]),
/// and through the reconciliation in Settings → Parent access
/// ([preview] then [apply]). Every write is idempotent: the record is
/// derived again from `user_student_links` and rewritten only if it changed.
class ParentAccessService {
  ParentAccessService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const collection = 'parent_access';
  static const linksCollection = 'user_student_links';
  static const _batchLimit = 400;

  CollectionReference<Map<String, dynamic>> get _access => _firestore.collection(collection);
  CollectionReference<Map<String, dynamic>> get _links => _firestore.collection(linksCollection);

  /// The signed-in parent's own access record, or null before the
  /// reconciliation has created one.
  Future<ParentAccessRecord?> getForParent(String userId) async {
    if (userId.isEmpty) return null;
    final snap = await _access.doc(userId).get();
    final data = snap.data();
    return data == null ? null : ParentAccessRecord.fromMap(snap.id, data);
  }

  static void _requireAdmin(String requesterRole) {
    if (requesterRole.trim().toLowerCase() != 'admin') throw const ParentAccessDeniedException();
  }

  /// The full reconciliation, read-only: every link record, every student
  /// and every user id, compared. Nothing is written.
  Future<ParentAccessPlan> preview({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final links = await _links.get();
    final students = await _firestore.collection('students').get();
    final users = await _firestore.collection('users').get();
    final plan = buildParentAccessPlan(
      links: [for (final d in links.docs) d.data()],
      students: {for (final d in students.docs) d.id: d.data()},
      userIds: {for (final d in users.docs) d.id},
      checkParentLinksOnly: true,
    );
    return ParentAccessPlan(
      records: plan.records,
      issues: [...plan.issues, ...auditAccounts({for (final d in users.docs) d.id: d.data()})],
      linkCount: plan.linkCount,
    );
  }

  /// Compares [plan] with the stored access records, read-only
  /// (administrators only).
  Future<ParentAccessComparison> compare(ParentAccessPlan plan, {required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final existing = {for (final d in (await _access.get()).docs) d.id: ParentAccessRecord.fromMap(d.id, d.data())};
    final missing = <String>[], outdated = <String>[];
    var current = 0;
    for (final record in plan.records.values) {
      final stored = existing[record.userId];
      if (stored == null) {
        missing.add(record.userId);
      } else if (!stored.sameAccessAs(record)) {
        outdated.add(record.userId);
      } else {
        current++;
      }
    }
    return ParentAccessComparison(missing: missing..sort(), outdated: outdated..sort(), current: current);
  }

  /// Writes [plan]'s records (only those that changed) and empties the
  /// records of parents who no longer have any link. Safe to run again.
  Future<ParentAccessApplyResult> apply(ParentAccessPlan plan, {required String requesterRole, required String updatedBy}) async {
    _requireAdmin(requesterRole);
    final existing = {for (final d in (await _access.get()).docs) d.id: ParentAccessRecord.fromMap(d.id, d.data())};
    final writes = <ParentAccessRecord>[];
    var unchanged = 0, cleared = 0;
    for (final record in plan.records.values) {
      final current = existing[record.userId];
      if (current != null && current.sameAccessAs(record)) {
        unchanged++;
      } else {
        writes.add(record);
      }
    }
    for (final MapEntry(key: userId, value: current) in existing.entries) {
      if (plan.records.containsKey(userId) || current.studentIds.isEmpty) continue;
      writes.add(ParentAccessRecord(userId: userId, studentIds: const [], financeStudentIds: const [], relations: const {}));
      cleared++;
    }
    await _write(writes, updatedBy);
    return ParentAccessApplyResult(written: writes.length - cleared, unchanged: unchanged, cleared: cleared);
  }

  /// Re-derives the access records of [userIds] from their current link
  /// records. Called after an administrator saves parent links; returns the
  /// problems found (for example a missing relationship) for the caller to
  /// show.
  Future<List<ParentAccessIssue>> rebuildForParents(Iterable<String> userIds, {required String requesterRole, required String updatedBy}) async {
    _requireAdmin(requesterRole);
    return _rebuild(userIds, updatedBy);
  }

  /// Re-derives the access of every parent linked to [studentId] — called
  /// after an administrator changes a student record, so a class change
  /// reaches the parents' `classIds` (class-targeted notifications). Runs
  /// from admin write paths that don't carry a role; the security rules
  /// refuse the write to anyone but an administrator.
  Future<void> refreshParentsOfStudent(String studentId, {String updatedBy = ''}) async {
    if (studentId.trim().isEmpty) return;
    final links = await _links.where('studentId', isEqualTo: studentId.trim()).get();
    await _rebuild({for (final d in links.docs) d.data()['userId']?.toString() ?? ''}, updatedBy);
  }

  Future<List<ParentAccessIssue>> _rebuild(Iterable<String> userIds, String updatedBy) async {
    final ids = {for (final id in userIds) if (id.trim().isNotEmpty) id.trim()};
    if (ids.isEmpty) return const [];
    final links = <Map<String, dynamic>>[];
    for (final id in ids) {
      links.addAll((await _links.where('userId', isEqualTo: id).get()).docs.map((d) => d.data()));
    }
    final studentIds = {for (final l in links) l['studentId']?.toString().trim() ?? ''}..remove('');
    final students = <String, Map<String, dynamic>?>{
      for (final id in studentIds) id: (await _firestore.collection('students').doc(id).get()).data(),
    };
    final plan = buildParentAccessPlan(links: links, students: students);
    final writes = <ParentAccessRecord>[];
    for (final id in ids) {
      final record = plan.records[id] ?? ParentAccessRecord(userId: id, studentIds: const [], financeStudentIds: const [], relations: const {}, classIds: const []);
      final current = await getForParent(id);
      if (current == null && record.studentIds.isEmpty) continue;
      if (current != null && current.sameAccessAs(record)) continue;
      writes.add(record);
    }
    await _write(writes, updatedBy);
    return plan.issues;
  }

  Future<void> _write(List<ParentAccessRecord> records, String updatedBy) async {
    for (var i = 0; i < records.length; i += _batchLimit) {
      final batch = _firestore.batch();
      for (final r in records.skip(i).take(_batchLimit)) {
        batch.set(_access.doc(r.userId), {...r.toMap(), 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': updatedBy});
      }
      await batch.commit();
    }
  }
}
