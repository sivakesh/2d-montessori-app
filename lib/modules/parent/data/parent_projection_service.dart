import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../fees/models/student_fee_assignment_model.dart';
import 'parent_access_service.dart';
import 'parent_projections.dart';

/// The parent-safe copies, by what they are built from.
enum ParentProjectionKind {
  profile('Student profiles', ParentStudentProfileFields.collection),
  details('Father/Mother student details', ParentStudentDetailsFields.collection),
  feeAssignments('Fee assignments', ParentFeeAssignmentFields.collection),
  payments('Payments', ParentPaymentFields.collection),
  feeBills('Fee bills', ParentFeeBillFields.collection),
  notices('Notices', ParentNoticeFields.collection);

  const ParentProjectionKind(this.label, this.collection);
  final String label, collection;
}

/// How the copies of one kind compare with what their originals produce.
class ParentProjectionHealth {
  const ParentProjectionHealth({required this.kind, required this.expected, required this.missing, required this.outdated, required this.orphaned, this.error = ''});
  final ParentProjectionKind kind;

  /// Originals that call for a copy (e.g. fee bills found).
  final int expected, missing, outdated, orphaned;

  /// Copies that already match their original.
  int get current => expected - missing - (outdated > expected ? expected : outdated);

  /// Why this kind couldn't be compared (e.g. `permission-denied` reading
  /// the originals or the copies); '' when it was.
  final String error;
  bool get isCurrent => error.isEmpty && missing == 0 && outdated == 0 && orphaned == 0;
}

/// Short, actionable text for a failed Firestore call: its code (e.g.
/// `permission-denied`) and message, never record contents.
String describeFirestoreError(Object e) => e is FirebaseException ? '${e.code}${(e.message ?? '').isEmpty ? '' : ': ${e.message}'}' : e.toString();

/// What a backfill of every fee-bill copy did ([ParentProjectionService.
/// syncAllFeeBillsReport]).
class ParentFeeBillBackfillReport {
  const ParentFeeBillBackfillReport({required this.originals, required this.written, required this.unchanged, required this.removed, required this.failed, this.error = ''});
  final int originals, written, unchanged, removed, failed;

  /// The first error met ('' when none), e.g. `permission-denied: …`.
  final String error;
  bool get ok => failed == 0 && error.isEmpty;
}

/// One linked child, as an administrator's diagnosis of a parent account
/// sees it (ids, relationship and counts only — no amounts or contacts).
class ParentChildDiagnosis {
  const ParentChildDiagnosis({
    required this.studentId,
    required this.relation,
    required this.inAccessRecord,
    required this.financeAccess,
    required this.profileCopy,
    required this.billOriginals,
    required this.billCopies,
    this.errors = const [],
  });
  final String studentId, relation;
  final bool inAccessRecord, financeAccess, profileCopy;

  /// Bills issued for the child, and their parent copies (null: couldn't
  /// be read — see [errors]).
  final int? billOriginals, billCopies;
  final List<String> errors;
}

/// Why a parent account does or doesn't see its children's bills
/// ([ParentProjectionService.diagnoseParent]).
class ParentAccountDiagnosis {
  const ParentAccountDiagnosis({required this.userId, required this.userRecord, required this.accessRecord, required this.links, required this.children, this.errors = const []});
  final String userId;

  /// `users/{userId}` exists; `parent_access/{userId}` exists.
  final bool userRecord, accessRecord;

  /// Link records (`user_student_links`) for this user id.
  final int links;
  final List<ParentChildDiagnosis> children;
  final List<String> errors;
}

/// A refresh that failed, as recorded for administrators
/// (`parent_projection_failures`; never readable by parents).
class ParentProjectionFailure {
  const ParentProjectionFailure({required this.scope, required this.sourceId, required this.error, required this.at, required this.attempts});
  final String scope, sourceId, error;
  final DateTime? at;
  final int attempts;
}

/// What [ParentProjectionService.syncAll] did, per kind.
class ParentProjectionSyncResult {
  const ParentProjectionSyncResult({required this.written, required this.unchanged, required this.removed, required this.failed});
  final Map<ParentProjectionKind, int> written, unchanged, removed, failed;
  int get totalWritten => written.values.fold(0, (a, b) => a + b);
  int get totalUnchanged => unchanged.values.fold(0, (a, b) => a + b);
  int get totalRemoved => removed.values.fold(0, (a, b) => a + b);
  int get totalFailed => failed.values.fold(0, (a, b) => a + b);
}

/// Maintains and reads the parent-safe projections (parent_projections.dart;
/// docs/parent_access_security.md §3a).
///
/// **Writing** happens only on the administrator side: right after an admin
/// changes a student, a fee or payment, or a notification (each such write
/// path calls the matching `sync…Quietly`), and in full through Settings →
/// Parent access ([syncAll]). Every sync re-derives copies from the original
/// records and writes only copies (and failure records) — never an original.
///
/// **Reliability (Phase 0.2):** a refresh that fails never fails the admin's
/// own change, but it is not treated as success either: it is recorded in
/// `parent_projection_failures` (scope, record id, error, time, attempts)
/// and cleared by the next successful refresh. [health] compares every copy
/// with what its original produces (missing, outdated, orphaned), and
/// [syncAll] repairs all of it — batch by batch, so one failure never stops
/// the rest, and running it again changes nothing.
///
/// **Reading** is what the parent screens use.
class ParentProjectionService {
  ParentProjectionService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const _batchLimit = 400;
  /// One student's copies written at the same time (see [_reconcile]).
  static const _concurrentWrites = 10;
  static const failuresCollection = 'parent_projection_failures';

  CollectionReference<Map<String, dynamic>> _copies(ParentProjectionKind k) => _firestore.collection(k.collection);
  CollectionReference<Map<String, dynamic>> get _failures => _firestore.collection(failuresCollection);

  static void _requireAdmin(String requesterRole) {
    if (requesterRole.trim().toLowerCase() != 'admin') throw const ParentAccessDeniedException();
  }

  // ---- Building copies ----------------------------------------------------

  Future<List<Map<String, dynamic>>> _uploadedDocuments(String? studentId) async {
    Query<Map<String, dynamic>> q = _firestore.collection('documents').where('entityType', isEqualTo: 'student');
    if (studentId != null) q = q.where('entityId', isEqualTo: studentId);
    return [for (final d in (await q.get()).docs) d.data()];
  }

  /// Profile and details of one student, with the `documents` collection's
  /// uploads for it.
  static (Map<String, dynamic>, Map<String, dynamic>) _studentCopies(String id, Map<String, dynamic> data, List<Map<String, dynamic>> uploads) {
    final merged = {
      ...data,
      'documents': [
        ...((data['documents'] as List?) ?? const []),
        for (final d in uploads)
          if (d['entityId'] == id) {'name': d['fileName'], 'type': d['documentType'], 'fileName': d['fileName'], 'url': d['fileUrl'], 'uploadedAt': d['uploadedAt']},
      ],
    };
    return (parentStudentProfile(id, merged), parentStudentDetails(id, merged));
  }

  Future<Map<String, List<(String, double)>>> _structureComponents() async {
    // Within one refresh operation (e.g. a bulk Fees operation's students)
    // the fee structures are read once.
    if (_operation?.components case final cached?) return cached;
    final snap = await _firestore.collection('fee_structures').get();
    final components = {
      for (final d in snap.docs)
        d.id: [
          for (final c in ((d.data()['components'] as List?) ?? const []).whereType<Map>())
            (c['name']?.toString() ?? 'Component', (c['amount'] as num?)?.toDouble() ?? 0),
        ],
    };
    _operation?.components = components;
    return components;
  }

  static Map<String, dynamic>? _feeCopy(String id, Map<String, dynamic> data, Map<String, List<(String, double)>> components) => parentFeeAssignment(
        StudentFeeAssignmentModel.fromMap(id, data),
        isDeleted: data['isDeleted'] == true,
        structureComponents: components[data['feeStructureId']?.toString() ?? ''] ?? const [],
        dueDate: data['dueDate'],
      );

  /// Every copy of [kind] the originals call for: id → copy, plus the ids
  /// whose original couldn't be turned into a copy (malformed data). Those
  /// are recorded as failures and their existing copies left as they are —
  /// one bad record never stops the others.
  Future<(Map<String, Map<String, dynamic>>, Set<String>)> _desired(ParentProjectionKind kind, {String? studentId, bool record = true}) async {
    Future<List<(String, Map<String, dynamic>)>> source(String collection) async => [
          for (final d in (studentId == null
                  ? await _firestore.collection(collection).get()
                  : await _firestore.collection(collection).where('studentId', isEqualTo: studentId).get())
              .docs)
            (d.id, d.data()),
        ];
    final List<(String, Map<String, dynamic>)> originals;
    final Map<String, dynamic>? Function(String id, Map<String, dynamic> data) build;
    switch (kind) {
      case ParentProjectionKind.profile || ParentProjectionKind.details:
        originals = studentId == null
            ? [for (final d in (await _firestore.collection('students').get()).docs) (d.id, d.data())]
            : [if ((await _firestore.collection('students').doc(studentId).get()).data() case final d?) (studentId, d)];
        final uploads = await _uploadedDocuments(studentId);
        build = (id, data) => kind == ParentProjectionKind.profile ? _studentCopies(id, data, uploads).$1 : _studentCopies(id, data, uploads).$2;
      case ParentProjectionKind.feeAssignments:
        originals = await source('student_fee_assignments');
        final components = await _structureComponents();
        build = (id, data) => _feeCopy(id, data, components);
      case ParentProjectionKind.payments:
        originals = await source('fee_receipts');
        build = parentPayment;
      case ParentProjectionKind.feeBills:
        originals = await source('fee_issued_bills');
        build = parentFeeBill;
      case ParentProjectionKind.notices:
        originals = [for (final d in (await _firestore.collection('school_notifications').get()).docs) (d.id, d.data())];
        build = parentNotice;
    }
    final desired = <String, Map<String, dynamic>>{};
    final failed = <String>{};
    for (final (id, data) in originals) {
      try {
        if (build(id, data) case final copy?) desired[id] = copy;
      } catch (e) {
        failed.add(id);
        if (record) await _recordFailure(kind.name, id, e);
      }
    }
    return (desired, failed);
  }

  Future<Map<String, Map<String, dynamic>>> _existing(ParentProjectionKind kind, {String? studentId}) async {
    if (studentId == null) return {for (final d in (await _copies(kind).get()).docs) d.id: d.data()};
    if (kind == ParentProjectionKind.profile || kind == ParentProjectionKind.details) {
      final snap = await _copies(kind).doc(studentId).get();
      return {snap.id: ?snap.data()};
    }
    return {for (final d in (await _copies(kind).where('studentId', isEqualTo: studentId).get()).docs) d.id: d.data()};
  }

  /// Comparable form of a stored value (timestamps by instant, numbers as
  /// doubles; the bookkeeping `syncedAt` ignored).
  static Object? _norm(Object? v) => switch (v) {
        Timestamp t => t.microsecondsSinceEpoch,
        DateTime t => t.microsecondsSinceEpoch,
        num n => n.toDouble(),
        Map m => {for (final e in m.entries) if (e.key != 'syncedAt') e.key.toString(): _norm(e.value)},
        List l => [for (final x in l) _norm(x)],
        _ => v,
      };

  static bool _deepEq(Object? a, Object? b) {
    if (a is Map && b is Map) return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _deepEq(a[k], b[k]));
    if (a is List && b is List) return a.length == b.length && [for (var i = 0; i < a.length; i++) _deepEq(a[i], b[i])].every((x) => x);
    return a == b;
  }

  static bool _same(Map<String, dynamic>? a, Map<String, dynamic>? b) => a != null && b != null && _deepEq(_norm(a), _norm(b));

  /// Rewrites the copies of [kind] (all, or one student's) to match the
  /// originals. Returns (written, unchanged, removed, failed); a batch that
  /// fails is recorded per item and the rest continue.
  Future<(int, int, int, int)> _reconcile(ParentProjectionKind kind, {String? studentId}) async {
    final (desired, unbuildable) = await _desired(kind, studentId: studentId);
    final existing = await _existing(kind, studentId: studentId);
    final writes = <(String, Map<String, dynamic>?)>[];
    var unchanged = 0;
    for (final MapEntry(key: id, value: copy) in desired.entries) {
      if (_same(copy, existing[id])) {
        unchanged++;
      } else {
        writes.add((id, copy));
      }
    }
    for (final id in existing.keys) {
      if (!desired.containsKey(id) && !unbuildable.contains(id)) writes.add((id, null));
    }
    var written = 0, removed = 0, failed = unbuildable.length;
    if (studentId != null) {
      // One student's copies (after an admin write): a handful of documents,
      // each written on its own (up to [_concurrentWrites] at a time) so one
      // that fails is recorded on its own and never takes the others with
      // it, as one batch would. Only copies that differ are written, so the
      // number of writes is that of a batch; the admin's own operation's
      // writes are left exactly as they were.
      Future<void> write(String id, Map<String, dynamic>? copy) async {
        final ref = _copies(kind).doc(id);
        try {
          copy == null ? await ref.delete() : await ref.set({...copy, 'syncedAt': FieldValue.serverTimestamp()});
          copy == null ? removed++ : written++;
          await _clearFailure(kind.name, id);
        } catch (e) {
          failed++;
          await _recordFailure(kind.name, id, e);
        }
      }
      for (var i = 0; i < writes.length; i += _concurrentWrites) {
        await Future.wait([for (final (id, copy) in writes.skip(i).take(_concurrentWrites)) write(id, copy)]);
      }
      return (written, unchanged, removed, failed);
    }
    for (var i = 0; i < writes.length; i += _batchLimit) {
      final chunk = writes.skip(i).take(_batchLimit).toList();
      final batch = _firestore.batch();
      for (final (id, copy) in chunk) {
        copy == null ? batch.delete(_copies(kind).doc(id)) : batch.set(_copies(kind).doc(id), {...copy, 'syncedAt': FieldValue.serverTimestamp()});
      }
      try {
        await batch.commit();
        for (final (id, copy) in chunk) {
          copy == null ? removed++ : written++;
          await _clearFailure(kind.name, id);
        }
      } catch (e) {
        failed += chunk.length;
        for (final (id, _) in chunk) {
          await _recordFailure(kind.name, id, e);
        }
      }
    }
    return (written, unchanged, removed, failed);
  }

  // ---- Failure records ------------------------------------------------------

  static String _failureId(String scope, String id) => '${scope}_$id'.replaceAll('/', '_');

  Future<void> _recordFailure(String scope, String id, Object error) async {
    final text = describeFirestoreError(error);
    debugPrint('Parent copy not refreshed ($scope $id): $text');
    _operation?.openFailures?.add(_failureId(scope, id));
    final op = _operation;
    if (op != null && op.firstError.isEmpty) op.firstError = describeFirestoreError(error);
    try {
      await _failures.doc(_failureId(scope, id)).set({
        'scope': scope,
        'sourceId': id,
        'error': text.length > 300 ? text.substring(0, 300) : text,
        'at': FieldValue.serverTimestamp(),
        'attempts': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      // Recording itself failed (often the same outage); the stale copy is
      // still found by health() and repaired by syncAll().
      debugPrint('Could not record the parent copy failure ($scope $id): $e');
    }
  }

  Future<void> _clearFailure(String scope, String id) async {
    final fid = _failureId(scope, id);
    // Within an operation only recorded failures are deleted: a refresh
    // with nothing to repair writes no failure records at all.
    final open = _operation?.openFailures;
    if (open != null && !open.remove(fid)) return;
    try {
      await _failures.doc(fid).delete();
    } catch (_) {}
  }

  /// The refresh operation in progress (see [_inOperation]).
  _Operation? _operation;

  /// Runs [body] as one refresh operation: the recorded failures and the fee
  /// structures are read once for it (instead of a delete per written copy
  /// and a structures read per student). Nested calls share the outer one.
  /// If the failures can't be read, clearing falls back to plain deletes.
  Future<T> _inOperation<T>(Future<T> Function() body) async {
    if (_operation != null) return body();
    Set<String>? open;
    try {
      open = {for (final d in (await _failures.get()).docs) d.id};
    } catch (_) {}
    _operation = _Operation(open);
    try {
      return await body();
    } finally {
      _operation = null;
    }
  }

  /// Runs [sync] for the copies of [scope]/[id]; true when it succeeded.
  /// A failure is recorded (never thrown), and cleared by a later success.
  Future<bool> _attempt(String scope, String id, Future<void> Function() sync) => _inOperation(() async {
        try {
          await sync();
          await _clearFailure(scope, id);
          return true;
        } catch (e) {
          // Per-record failures are already recorded where they happened.
          if (e is! _AlreadyRecorded) await _recordFailure(scope, id, e);
          return false;
        }
      });

  /// Refreshes that failed and haven't been repaired since, newest first
  /// (administrators only).
  Future<List<ParentProjectionFailure>> failures({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final list = [
      for (final d in (await _failures.get()).docs)
        ParentProjectionFailure(
          scope: d.data()['scope']?.toString() ?? '',
          sourceId: d.data()['sourceId']?.toString() ?? '',
          error: d.data()['error']?.toString() ?? '',
          at: (d.data()['at'] as Timestamp?)?.toDate(),
          attempts: (d.data()['attempts'] as num?)?.toInt() ?? 1,
        ),
    ];
    return list..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  }

  // ---- Admin side -----------------------------------------------------------

  /// Rewrites [studentId]'s profile and Father/Mother details (removes them
  /// when the student record is gone) and refreshes the access of the
  /// student's parents (their children's classes).
  Future<void> syncStudent(String studentId, {String updatedBy = ''}) async {
    if (studentId.trim().isEmpty) return;
    await _reconcileOrThrow(ParentProjectionKind.profile, studentId);
    await _reconcileOrThrow(ParentProjectionKind.details, studentId);
    await ParentAccessService(firestore: _firestore).refreshParentsOfStudent(studentId, updatedBy: updatedBy);
  }

  /// Rewrites [studentId]'s fee, payment and fee-bill copies.
  Future<void> syncFeesForStudent(String studentId) async {
    if (studentId.trim().isEmpty) return;
    for (final k in [ParentProjectionKind.feeAssignments, ParentProjectionKind.payments, ParentProjectionKind.feeBills]) {
      await _reconcileOrThrow(k, studentId);
    }
  }

  /// Phase 0.1 name; refreshes all of the student's fee copies.
  Future<void> syncPaymentsForStudent(String studentId) => syncFeesForStudent(studentId);

  Future<void> _reconcileOrThrow(ParentProjectionKind kind, String studentId) async {
    final (_, _, _, failed) = await _reconcile(kind, studentId: studentId);
    if (failed > 0) throw _AlreadyRecorded('${kind.label}: $failed cop${failed == 1 ? 'y' : 'ies'} not written');
  }

  /// Rewrites (or removes) the parent copy of notification [noticeId].
  Future<void> syncNotice(String noticeId) async {
    if (noticeId.trim().isEmpty) return;
    final data = (await _firestore.collection('school_notifications').doc(noticeId).get()).data();
    final notice = data == null ? null : parentNotice(noticeId, data);
    final ref = _copies(ParentProjectionKind.notices).doc(noticeId);
    if (notice == null) {
      await ref.delete();
    } else {
      await ref.set({...notice, 'syncedAt': FieldValue.serverTimestamp()});
    }
  }

  /// [syncStudent] for admin write paths: never throws; a failure is
  /// recorded. True when it succeeded.
  Future<bool> syncStudentQuietly(String studentId, {String updatedBy = ''}) => _attempt('student', studentId, () => syncStudent(studentId, updatedBy: updatedBy));

  /// [syncFeesForStudent] for admin write paths (never throws).
  Future<bool> syncFeesQuietly(String studentId) => _inOperation(() async {
        final ok = await _attempt('fees', studentId, () => syncFeesForStudent(studentId));
        // The student's bill copies were refreshed too.
        if (ok) await _clearFailure('bills', studentId);
        return ok;
      });

  /// Several students' fee copies (after a bulk Fees operation).
  Future<bool> syncFeesForStudentsQuietly(Iterable<String> studentIds) => _inOperation(() async {
        var ok = true;
        for (final id in {for (final s in studentIds) if (s.trim().isNotEmpty) s.trim()}) {
          ok = await syncFeesQuietly(id) && ok;
        }
        return ok;
      });

  /// Rewrites [studentId]'s fee-bill copies only: the Fee Bill Issuance
  /// hook after a bill was issued or cancelled (registerParentFeeBillRefresh).
  /// Never throws; a failure is recorded (scope `bills`) and cleared by the
  /// next successful bill or fees refresh of the student, or by [syncAll].
  Future<bool> syncFeeBillsQuietly(String studentId) =>
      _attempt('bills', studentId.trim(), () => _reconcileOrThrow(ParentProjectionKind.feeBills, studentId.trim()));

  /// Rewrites every fee-bill copy to match the original bills: missing
  /// copies are written (bills issued before the automatic refresh existed,
  /// or whose refresh failed), changed ones updated, orphans removed; copies
  /// that already match are not rewritten, so running it again writes
  /// nothing. Never writes an original bill and never throws; a failure is
  /// recorded (scope `bills`, id `all`) and repaired by a later run or by
  /// [syncAll]. Fee Bill Issuance runs it when an administrator opens the
  /// page (registerParentFeeBillRefresh).
  Future<bool> syncAllFeeBillsQuietly() async => (await syncAllFeeBillsReport()).ok;

  /// [syncAllFeeBillsQuietly] with what it did: bills found, copies
  /// written, already current, removed, failed, and the first error (for
  /// the administrator). Never throws.
  Future<ParentFeeBillBackfillReport> syncAllFeeBillsReport() => _inOperation(() async {
        var report = const ParentFeeBillBackfillReport(originals: 0, written: 0, unchanged: 0, removed: 0, failed: 0);
        await _attempt('bills', 'all', () async {
          // Active bills: the ones parents get a copy of.
          final originals = (await _firestore.collection('fee_issued_bills').where('status', isEqualTo: 'issued').count().get()).count ?? 0;
          final (written, unchanged, removed, failed) = await _reconcile(ParentProjectionKind.feeBills);
          report = ParentFeeBillBackfillReport(originals: originals, written: written, unchanged: unchanged, removed: removed, failed: failed, error: _operation?.firstError ?? '');
          if (failed > 0) throw _AlreadyRecorded('Fee bills: $failed cop${failed == 1 ? 'y' : 'ies'} not written');
        });
        if (report.originals == 0 && report.written == 0 && report.unchanged == 0 && (_operation?.firstError ?? '').isNotEmpty) {
          // Reading the bills or the copies failed before anything ran.
          report = ParentFeeBillBackfillReport(originals: 0, written: 0, unchanged: 0, removed: 0, failed: 1, error: _operation!.firstError);
        }
        return report;
      });

  /// Why parent [userId] does or doesn't see their children's fee bills:
  /// the user and access records, the link records, and per child the
  /// relationship, fee access, profile copy, bills issued and bill copies.
  /// Read-only; administrators only. Each read that fails is reported with
  /// its error code instead of being taken as "none".
  Future<ParentAccountDiagnosis> diagnoseParent(String userId, {required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final id = userId.trim();
    final errors = <String>[];
    Future<T?> read<T>(String what, Future<T> Function() f, List<String> into) async {
      try {
        return await f();
      } catch (e) {
        into.add('$what: ${describeFirestoreError(e)}');
        return null;
      }
    }

    final user = await read('users/$id', () => _firestore.collection('users').doc(id).get(), errors);
    final accessSnap = await read('parent_access/$id', () => _firestore.collection('parent_access').doc(id).get(), errors);
    final access = accessSnap?.data();
    final links = await read('user_student_links', () => _firestore.collection(ParentAccessService.linksCollection).where('userId', isEqualTo: id).get(), errors);
    final linkRelations = <String, String>{
      for (final d in links?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        if ((d.data()['studentId']?.toString() ?? '').isNotEmpty) d.data()['studentId'].toString(): d.data()['relation']?.toString() ?? '',
    };
    List<String> ids(Object? v) => [for (final x in (v as List?) ?? const []) x.toString()];
    final accessStudents = ids(access?['studentIds']);
    final finance = ids(access?['financeStudentIds']).toSet();
    final relations = (access?['relations'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const <String, String>{};
    final children = <ParentChildDiagnosis>[];
    for (final studentId in {...linkRelations.keys, ...accessStudents}) {
      final childErrors = <String>[];
      final profile = await read('profile copy', () => _copies(ParentProjectionKind.profile).doc(studentId).get(), childErrors);
      final originals = await read('fee bills', () => _firestore.collection('fee_issued_bills').where('studentId', isEqualTo: studentId).where('status', isEqualTo: 'issued').count().get(), childErrors);
      final copies = await read('bill copies', () => _copies(ParentProjectionKind.feeBills).where('studentId', isEqualTo: studentId).count().get(), childErrors);
      children.add(ParentChildDiagnosis(
        studentId: studentId,
        relation: relations[studentId] ?? linkRelations[studentId] ?? '',
        inAccessRecord: accessStudents.contains(studentId),
        financeAccess: finance.contains(studentId),
        profileCopy: profile?.exists ?? false,
        billOriginals: originals?.count,
        billCopies: copies?.count,
        errors: childErrors,
      ));
    }
    return ParentAccountDiagnosis(
      userId: id,
      userRecord: user?.exists ?? false,
      accessRecord: accessSnap?.exists ?? false,
      links: links?.docs.length ?? 0,
      children: children,
      errors: errors,
    );
  }

  /// Phase 0.1 name for [syncFeesQuietly].
  Future<bool> syncPaymentsQuietly(String studentId) => syncFeesQuietly(studentId);

  /// [syncNotice] for admin write paths (never throws).
  Future<bool> syncNoticeQuietly(String noticeId) => _attempt('notice', noticeId, () => syncNotice(noticeId));

  /// How every kind of copy compares with its originals (read-only;
  /// administrators only).
  Future<List<ParentProjectionHealth>> health({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final out = <ParentProjectionHealth>[];
    for (final kind in ParentProjectionKind.values) {
      final Map<String, Map<String, dynamic>> desired, existing;
      final Set<String> unbuildable;
      try {
        (desired, unbuildable) = await _desired(kind, record: false);
        existing = await _existing(kind);
      } catch (e) {
        // This kind couldn't be compared (e.g. the rules refuse a read);
        // reported as such, never as "all current".
        out.add(ParentProjectionHealth(kind: kind, expected: 0, missing: 0, outdated: 0, orphaned: 0, error: describeFirestoreError(e)));
        continue;
      }
      var missing = 0, outdated = unbuildable.length;
      for (final MapEntry(key: id, value: copy) in desired.entries) {
        if (!existing.containsKey(id)) {
          missing++;
        } else if (!_same(copy, existing[id])) {
          outdated++;
        }
      }
      out.add(ParentProjectionHealth(
        kind: kind,
        expected: desired.length,
        missing: missing,
        outdated: outdated,
        orphaned: existing.keys.where((id) => !desired.containsKey(id) && !unbuildable.contains(id)).length,
      ));
    }
    return out;
  }

  /// Rebuilds every copy from the originals: writes only what differs,
  /// removes orphans, continues past failures (recorded), and clears the
  /// failure records it repaired. Administrators only; safe to run again.
  /// Never writes an original record.
  Future<ParentProjectionSyncResult> syncAll({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    return _inOperation(_syncAll);
  }

  Future<ParentProjectionSyncResult> _syncAll() async {
    final written = <ParentProjectionKind, int>{}, unchanged = <ParentProjectionKind, int>{}, removed = <ParentProjectionKind, int>{}, failed = <ParentProjectionKind, int>{};
    for (final kind in ParentProjectionKind.values) {
      try {
        final (w, u, r, f) = await _reconcile(kind);
        written[kind] = w;
        unchanged[kind] = u;
        removed[kind] = r;
        failed[kind] = f;
      } catch (e) {
        // Reading the originals failed: nothing of this kind was written.
        failed[kind] = 1;
        await _recordFailure('rebuild', kind.name, e);
      }
    }
    if (failed.values.every((f) => f == 0)) {
      // Everything now matches its original: earlier failures are repaired.
      try {
        for (final d in (await _failures.get()).docs) {
          await d.reference.delete();
        }
      } catch (_) {}
    }
    return ParentProjectionSyncResult(written: written, unchanged: unchanged, removed: removed, failed: failed);
  }

  // ---- Parent side ----------------------------------------------------------

  /// A linked child's parent-safe profile, or null before it was synced.
  Future<Map<String, dynamic>?> getProfile(String studentId) async => (await _copies(ParentProjectionKind.profile).doc(studentId).get()).data();

  /// The Father/Mother details (blood group, address, documents). Callers
  /// read it only for a Father or Mother.
  Future<Map<String, dynamic>?> getDetails(String studentId) async => (await _copies(ParentProjectionKind.details).doc(studentId).get()).data();

  static DateTime _when(Map<String, dynamic> d, String key) {
    final v = d[key];
    return v is Timestamp ? v.toDate() : v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// A child's payments (Father/Mother only), newest first.
  Future<List<Map<String, dynamic>>> getPayments(String studentId) async {
    final snap = await _copies(ParentProjectionKind.payments).where('studentId', isEqualTo: studentId).get();
    return [for (final d in snap.docs) d.data()]..sort((a, b) => _when(b, 'paymentDate').compareTo(_when(a, 'paymentDate')));
  }

  /// A child's fees (Father/Mother only), as the existing assignment model —
  /// every amount is the stored one.
  Future<List<StudentFeeAssignmentModel>> getFeeAssignments(String studentId) async {
    final snap = await _copies(ParentProjectionKind.feeAssignments).where('studentId', isEqualTo: studentId).get();
    return [for (final d in snap.docs) StudentFeeAssignmentModel.fromMap(d.id, d.data())];
  }

  /// A child's fee-bill copies (Father/Mother only), newest first.
  Future<List<Map<String, dynamic>>> getFeeBills(String studentId) async {
    final snap = await _copies(ParentProjectionKind.feeBills).where('studentId', isEqualTo: studentId).get();
    return [for (final d in snap.docs) d.data()]..sort((a, b) => _when(b, 'issuedAt').compareTo(_when(a, 'issuedAt')));
  }

  /// Before the reconciliation (no access record yet): one student's
  /// payments from its own receipt records, through the same parent-safe
  /// builder.
  Future<List<Map<String, dynamic>>> getLegacyPayments(String studentId) async {
    final snap = await _firestore.collection('fee_receipts').where('studentId', isEqualTo: studentId).get();
    return [for (final d in snap.docs) ?parentPayment(d.id, d.data())]..sort((a, b) => _when(b, 'paymentDate').compareTo(_when(a, 'paymentDate')));
  }

  /// The notices a parent of [studentIds] (in [classIds]) may receive.
  Future<List<Map<String, dynamic>>> getNotices({required Set<String> studentIds, required Set<String> classIds}) async {
    final notices = _copies(ParentProjectionKind.notices);
    final parents = notices.where('audience', isEqualTo: 'Parents');
    final queries = <Query<Map<String, dynamic>>>[
      notices.where('audience', isEqualTo: 'Public'),
      parents.where('appliesToAllClasses', isEqualTo: true),
      parents.where('appliesToAllStudents', isEqualTo: true),
    ];
    void addChunks(String field, Set<String> values) {
      final list = values.where((v) => v.isNotEmpty).toList()..sort();
      for (var i = 0; i < list.length; i += 30) {
        queries.add(parents.where(field, arrayContainsAny: list.sublist(i, i + 30 > list.length ? list.length : i + 30)));
      }
    }

    addChunks('applicableClassIds', classIds);
    addChunks('applicableStudentIds', studentIds);
    final byId = <String, Map<String, dynamic>>{};
    for (final snap in await Future.wait(queries.map((q) => q.get()))) {
      for (final d in snap.docs) {
        byId[d.id] = d.data();
      }
    }
    return byId.values.toList();
  }
}

/// A sync failure whose records were already written (one per copy).
/// What one refresh operation has read once: the ids of the recorded
/// failures (null when they couldn't be read) and the fee structures.
class _Operation {
  _Operation(this.openFailures);
  final Set<String>? openFailures;
  Map<String, List<(String, double)>>? components;

  /// The first failure recorded during the operation.
  String firstError = '';
}

class _AlreadyRecorded implements Exception {
  const _AlreadyRecorded(this.message);
  final String message;
  @override
  String toString() => message;
}
