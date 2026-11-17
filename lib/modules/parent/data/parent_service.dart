import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/students/models/admin_student_model.dart';
import 'parent_access.dart';
import 'parent_access_service.dart';
import 'parent_projection_service.dart';

/// A file on a child's profile, downloaded by Storage path through the
/// Storage rules (never by URL).
class ParentChildDocument {
  const ParentChildDocument({required this.name, required this.type, required this.storagePath});
  final String name, type, storagePath;
}

/// A parent or guardian named on a child's profile (name and relationship
/// only — no contact details).
class ParentChildGuardian {
  const ParentChildGuardian({required this.name, required this.relation});
  final String name, relation;
}

/// A child linked to the signed-in parent, with the relationship that
/// decides what the parent may see.
class LinkedChild {
  const LinkedChild({
    required this.student,
    required this.relation,
    required this.canViewFinance,
    this.photoPath = '',
    this.documents = const [],
    this.guardians = const [],
    this.fromProjection = false,
  });

  /// The child's details. From the parent-safe profile once it exists: no
  /// fee discount, no other parents' contact details, no download URLs
  /// (`profileImageUrl` and document URLs are empty — use [photoPath] and
  /// [documents]).
  final AdminStudentModel student;

  /// The child's photo in Storage ('' when none).
  final String photoPath;

  /// The child's documents — only for a Father or Mother (empty for a
  /// Guardian or Other).
  final List<ParentChildDocument> documents;
  final List<ParentChildGuardian> guardians;

  /// Read from the parent-safe profile (vs. the legacy full record, before
  /// the reconciliation has run).
  final bool fromProjection;

  /// Father, Mother, Guardian, Other, Unresolved — or '' when only the
  /// legacy link records exist (before the reconciliation has run).
  final String relation;

  /// true: Father or Mother. false: any other or an unresolved relationship.
  /// null: unknown (legacy links only) — the screen may try, and the
  /// security rules decide.
  final bool? canViewFinance;
}

/// The signed-in parent's linked children, plus how many linked children
/// could not be shown because their profile isn't available (not yet copied
/// by the reconciliation, or the student record is missing). Inactive
/// students are left out on purpose and are not counted.
class ParentFamily {
  const ParentFamily({required this.children, this.unavailable = 0});
  final List<LinkedChild> children;
  final int unavailable;
}

/// Read-only composition service for the Parent dashboard: resolves "which
/// students belong to this parent" and hands back their existing
/// [AdminStudentModel] records. Attendance, fees and notifications are each
/// fetched by their own services, scoped to these students.
///
/// The children come from the parent's `parent_access/{userId}` record — the
/// same record the security rules check (docs/parent_access_security.md), so
/// the app never offers a child the server would refuse — and their details
/// from the parent-safe profiles (`parent_student_profiles`). Until an
/// administrator has run the reconciliation (Settings → Parent access) and
/// that record exists, the parent's own `user_student_links` records and the
/// student records are used instead, exactly as before.
class ParentService {
  ParentService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// The database this service reads (so the dashboard's other read-only
  /// lookups, e.g. the calendar, use the same one).
  FirebaseFirestore get firestore => _firestore;

  /// The parent-safe projections, on the same database (payments, notices).
  ParentProjectionService get projections => ParentProjectionService(firestore: _firestore);

  CollectionReference<Map<String, dynamic>> get _links => _firestore.collection(ParentAccessService.linksCollection);
  CollectionReference<Map<String, dynamic>> get _students => _firestore.collection('students');

  /// Students linked to [parentUserId]. Never queries the `students`
  /// collection broadly: resolves the linked student ids first, then fetches
  /// exactly those documents by id. Inactive (soft-deleted) students are
  /// excluded, matching how the Admin Students list treats `isActive`.
  Future<List<AdminStudentModel>> getLinkedStudents(String parentUserId) async =>
      [for (final c in await getLinkedChildren(parentUserId)) c.student];

  /// [getLinkedStudents] with each child's relationship and whether the
  /// parent may see that child's fees.
  Future<List<LinkedChild>> getLinkedChildren(String parentUserId) async => (await getFamily(parentUserId)).children;

  /// [getLinkedChildren], and the number of linked children whose profile
  /// is unavailable (see [ParentFamily]).
  Future<ParentFamily> getFamily(String parentUserId) async {
    if (parentUserId.isEmpty) return const ParentFamily(children: []);

    final access = await ParentAccessService(firestore: _firestore).getForParent(parentUserId);
    final Map<String, (String, bool?)> linked; // studentId → (relation, canViewFinance)
    if (access != null) {
      linked = {for (final id in access.studentIds) id: (access.relations[id] ?? ParentRelation.unresolved, access.canViewFinance(id))};
    } else {
      final linkSnap = await _links.where('userId', isEqualTo: parentUserId).get();
      linked = {
        for (final doc in linkSnap.docs)
          if ((doc.data()['studentId']?.toString() ?? '').isNotEmpty) doc.data()['studentId'].toString(): ('', null),
      };
    }
    if (linked.isEmpty) return const ParentFamily(children: []);

    if (access != null) {
      // The parent-safe profiles — the only student data the security rules
      // give a parent (docs/parent_access_security.md §3a).
      final projections = ParentProjectionService(firestore: _firestore);
      // Blood group, home address and documents come from the Father/
      // Mother details copy, read only for a Father or Mother (owner
      // decision; a Guardian's child has them empty).
      final profiles = await Future.wait(linked.keys.map((id) async {
        final profile = await projections.getProfile(id);
        final details = profile != null && linked[id]!.$2 == true ? await projections.getDetails(id) : null;
        return (id, profile, details);
      }));
      return ParentFamily(unavailable: profiles.where((p) => p.$2 == null).length, children: [
        for (final (id, profile, details) in profiles)
          if (profile != null)
            if (AdminStudentModel.fromMap(id, {...profile, ...?details, 'documents': const []}) case final student when student.isActive)
              LinkedChild(
                student: student,
                relation: linked[id]!.$1,
                canViewFinance: linked[id]!.$2,
                photoPath: profile['photoPath']?.toString() ?? '',
                documents: [
                  for (final d in ((details?['documents'] as List?) ?? const []).whereType<Map>())
                    ParentChildDocument(name: d['name']?.toString() ?? '', type: d['type']?.toString() ?? '', storagePath: d['storagePath']?.toString() ?? ''),
                ],
                guardians: [
                  for (final g in ((profile['guardians'] as List?) ?? const []).whereType<Map>())
                    ParentChildGuardian(name: g['name']?.toString() ?? '', relation: g['relation']?.toString() ?? ''),
                ],
                fromProjection: true,
              ),
      ]);
    }

    final studentDocs = await Future.wait(linked.keys.map((id) => _students.doc(id).get()));
    return ParentFamily(unavailable: studentDocs.where((d) => !d.exists || d.data() == null).length, children: [
      for (final doc in studentDocs)
        if (doc.exists && doc.data() != null)
          if (AdminStudentModel.fromMap(doc.id, doc.data()!) case final student when student.isActive)
            LinkedChild(student: student, relation: linked[doc.id]!.$1, canViewFinance: linked[doc.id]!.$2),
    ]);
  }
}
