import 'package:cloud_firestore/cloud_firestore.dart';

import 'parent_access.dart';
import 'parent_access_service.dart';
import 'parent_projection_service.dart';

/// One parent on a student's Parents list.
class ParentLinkEntry {
  const ParentLinkEntry({required this.userId, required this.relation, this.name = '', this.email = '', this.phone = ''});

  final String userId, relation, name, email, phone;
}

/// What a link save changed.
class ParentLinkSaveResult {
  const ParentLinkSaveResult({required this.parentIds, required this.studentIds});

  /// Parents whose access may have changed (added, removed or re-labelled).
  final Set<String> parentIds;

  /// Students whose Parents list may have changed.
  final Set<String> studentIds;
}

/// The single place parent–student links are saved (docs/parent_access_
/// security.md §3). The relationship is stored twice — a
/// `user_student_links` record and an entry on the student's `parentLinks`
/// — and every save here writes both in one atomic batch, so they can't
/// disagree:
/// - [saveLinksForStudent]: a student's whole Parents list (admin student
///   form, student view dialog);
/// - [saveLinksForParent]: one parent's whole list of children (admin
///   parent profile form) — a child that is un-ticked loses this parent in
///   both places; every other parent of that child is kept.
/// Then [refresh] re-derives the affected parents' access and the affected
/// students' parent-safe profiles. Administrators only (the security rules
/// refuse anyone else).
class ParentLinkService {
  ParentLinkService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _links => _firestore.collection(ParentAccessService.linksCollection);
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');

  static String _relation(String raw) => ParentRelation.normalize(raw) ?? ParentRelation.guardian;

  /// Replaces [studentId]'s Parents list with [parents] (one entry per
  /// parent; a repeated parent keeps its first entry).
  Future<ParentLinkSaveResult> saveLinksForStudent({required String studentId, required List<ParentLinkEntry> parents}) async {
    final existing = await _links.where('studentId', isEqualTo: studentId).get();
    final seen = <String>{};
    final entries = [for (final p in parents) if (p.userId.trim().isNotEmpty && seen.add(p.userId.trim())) p];

    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final p in entries) {
      batch.set(_links.doc(), {'userId': p.userId.trim(), 'studentId': studentId, 'relation': _relation(p.relation), 'createdAt': FieldValue.serverTimestamp()});
    }
    batch.set(_students.doc(studentId), {
      'parentLinks': [
        for (final p in entries)
          {'userId': p.userId.trim(), 'name': p.name, 'email': p.email, 'phone': p.phone, 'relation': _relation(p.relation), 'linkedAt': Timestamp.now()},
      ],
    }, SetOptions(merge: true));
    await batch.commit();

    return ParentLinkSaveResult(
      parentIds: {for (final d in existing.docs) d.data()['userId']?.toString() ?? '', for (final p in entries) p.userId.trim()}..remove(''),
      studentIds: {studentId},
    );
  }

  /// Replaces [userId]'s children with [relations] (studentId →
  /// relationship). Un-ticked children lose this parent on both the link
  /// records and their `parentLinks`; other parents are untouched.
  Future<ParentLinkSaveResult> saveLinksForParent({required String userId, required Map<String, String> relations}) async {
    final existing = await _links.where('userId', isEqualTo: userId).get();
    final previous = {for (final d in existing.docs) d.data()['studentId']?.toString() ?? ''}..remove('');
    final selected = {for (final e in relations.entries) if (e.key.trim().isNotEmpty) e.key.trim(): _relation(e.value)};
    final affected = {...previous, ...selected.keys};
    final students = {for (final id in affected) id: (await _students.doc(id).get())};

    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final MapEntry(key: studentId, value: relation) in selected.entries) {
      batch.set(_links.doc(), {'userId': userId, 'studentId': studentId, 'relation': relation, 'createdAt': FieldValue.serverTimestamp()});
    }
    for (final MapEntry(key: studentId, value: snap) in students.entries) {
      if (!snap.exists) continue; // a missing student gets no record created
      final current = [for (final e in ((snap.data()?['parentLinks'] as List?) ?? const []).whereType<Map>()) Map<String, dynamic>.from(e)];
      final mine = current.where((e) => (e['userId'] ?? e['id'])?.toString() == userId).firstOrNull;
      final others = current.where((e) => (e['userId'] ?? e['id'])?.toString() != userId).toList();
      batch.set(_students.doc(studentId), {
        'parentLinks': [
          ...others,
          if (selected[studentId] case final relation?) {...?mine, 'userId': userId, 'relation': relation, 'linkedAt': mine?['linkedAt'] ?? Timestamp.now()},
        ],
      }, SetOptions(merge: true));
    }
    await batch.commit();
    return ParentLinkSaveResult(parentIds: {userId}, studentIds: affected);
  }

  /// Re-derives the affected parents' access and students' parent-safe
  /// profiles. Returns the access problems found (for the admin to fix).
  Future<List<ParentAccessIssue>> refresh(ParentLinkSaveResult result, {required String requesterRole, required String updatedBy}) async {
    final issues = await ParentAccessService(firestore: _firestore).rebuildForParents(result.parentIds, requesterRole: requesterRole, updatedBy: updatedBy);
    final projections = ParentProjectionService(firestore: _firestore);
    for (final id in result.studentIds) {
      await projections.syncStudentQuietly(id, updatedBy: updatedBy);
    }
    return issues;
  }
}
