/// The parent access index (docs/parent_access_security.md): one
/// `parent_access/{userId}` document per parent account, derived only from
/// the admin-maintained `user_student_links` records, that the Firestore and
/// Storage rules read to decide what a signed-in parent may see.
///
/// `userId` is the parent's `users` document id — the 10-digit phone number
/// the OTP login already keys accounts by — so the rules can find it from
/// the signed-in phone number alone, with no change to the login.
///
/// This file is pure (no Firebase): it turns raw link and student data into
/// the access records plus a list of problems for an administrator to
/// resolve. Nothing is guessed: a relationship whose type is missing,
/// unrecognised or contradictory still links the child, but never grants
/// financial access until an administrator resolves it.
library;

/// Shown instead of fees to a linked parent who isn't the child's Father or
/// Mother.
const parentFeesRestrictedMessage = "Fee details are available only to the student's father or mother.";

/// The relationship types the admin forms offer (admin_student_form.dart's
/// `relationOptions`).
abstract final class ParentRelation {
  static const father = 'Father';
  static const mother = 'Mother';
  static const guardian = 'Guardian';
  static const other = 'Other';

  /// Stored in an access record for a child whose relationship couldn't be
  /// resolved; never grants financial access.
  static const unresolved = 'Unresolved';

  static const all = [father, mother, guardian, other];

  /// The canonical relationship for [raw] (any case, surrounding spaces
  /// ignored), or null when it is missing or not one of [all].
  static String? normalize(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    for (final r in all) {
      if (r.toLowerCase() == value) return r;
    }
    return null;
  }

  /// Only a linked Father or Mother may see fees, payments and fee bills.
  static bool allowsFinance(String? relation) => relation == father || relation == mother;
}

/// What one parent account may access.
class ParentAccessRecord {
  ParentAccessRecord({
    required this.userId,
    required Iterable<String> studentIds,
    required Iterable<String> financeStudentIds,
    required Map<String, String> relations,
    Iterable<String> classIds = const [],
  })  : studentIds = (studentIds.toSet().toList()..sort()),
        financeStudentIds = (financeStudentIds.toSet().toList()..sort()),
        relations = Map.unmodifiable(relations),
        classIds = (classIds.where((c) => c.isNotEmpty).toSet().toList()..sort());

  final String userId;

  /// Every linked child (any relationship).
  final List<String> studentIds;

  /// The linked children whose fees this parent may see (Father or Mother).
  final List<String> financeStudentIds;

  /// studentId → relationship ([ParentRelation.unresolved] when unresolved).
  final Map<String, String> relations;

  /// The classes the linked children are in (from their student records),
  /// so the rules can enforce class-targeted notifications.
  final List<String> classIds;

  bool canViewFinance(String studentId) => financeStudentIds.contains(studentId);

  factory ParentAccessRecord.fromMap(String userId, Map<String, dynamic> data) {
    List<String> list(Object? v) => [for (final x in (v as List?) ?? const []) if (x != null && x.toString().isNotEmpty) x.toString()];
    final rawRelations = (data['relations'] as Map?) ?? const {};
    return ParentAccessRecord(
      userId: userId,
      studentIds: list(data['studentIds']),
      financeStudentIds: list(data['financeStudentIds']),
      relations: {for (final e in rawRelations.entries) e.key.toString(): e.value?.toString() ?? ParentRelation.unresolved},
      classIds: list(data['classIds']),
    );
  }

  /// The stored fields (the service adds `updatedAt`/`updatedBy`).
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'studentIds': studentIds,
        'financeStudentIds': financeStudentIds,
        'relations': relations,
        'classIds': classIds,
        'source': 'user_student_links',
        'schemaVersion': 2,
      };

  /// Same access as [other] (so rewriting it would change nothing).
  bool sameAccessAs(ParentAccessRecord other) {
    bool listEq(List<String> a, List<String> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
    if (!listEq(studentIds, other.studentIds) || !listEq(financeStudentIds, other.financeStudentIds) || !listEq(classIds, other.classIds)) return false;
    if (relations.length != other.relations.length) return false;
    return relations.entries.every((e) => other.relations[e.key] == e.value);
  }
}

enum ParentAccessIssueKind {
  /// More than one link record for the same parent and child (harmless;
  /// reported, never deleted).
  duplicateLink(unresolved: false, label: 'Duplicate link records'),

  /// The link record has no relationship; the student record's own
  /// `parentLinks` entry supplied it.
  relationFromStudentRecord(unresolved: false, label: 'Relationship taken from the student record'),

  /// Link records for the same parent and child disagree.
  conflictingRelation(unresolved: true, label: 'Conflicting relationships'),

  /// No relationship anywhere.
  missingRelation(unresolved: true, label: 'Relationship missing'),

  /// A relationship value that isn't Father, Mother, Guardian or Other.
  unrecognizedRelation(unresolved: true, label: 'Unrecognised relationship'),

  /// The link record and the student record name different relationships.
  relationMismatch(unresolved: true, label: 'Link and student record disagree'),

  /// The student record lists a parent with no link record (not granted).
  parentLinksOnly(unresolved: true, label: 'Listed on the student record only (not granted)'),

  /// The linked student record doesn't exist (not granted).
  missingStudent(unresolved: true, label: 'Student record missing (not granted)'),

  /// The linked parent has no `users` record.
  missingUser(unresolved: true, label: 'Parent account missing'),

  /// The parent id isn't a 10-digit phone number, so the security rules
  /// can never match it to a signed-in parent.
  userIdNotPhone(unresolved: true, label: 'Parent id is not a phone number'),

  /// A link record with no parent id or no student id (ignored).
  incompleteLink(unresolved: true, label: 'Link record missing a parent or student id'),

  /// An account whose `users` id isn't a 10-digit phone number: the rules
  /// can't match it to a signed-in phone, so an admin or staff account would
  /// lose its access.
  accountIdNotPhone(unresolved: true, label: 'Account id is not a phone number'),

  /// An account whose stored phone number differs from its id (for example
  /// after the phone was edited); the signed-in phone reaches a different
  /// record.
  accountPhoneMismatch(unresolved: true, label: 'Account phone differs from its id'),

  /// Two or more accounts with the same phone number.
  duplicateAccountPhone(unresolved: true, label: 'Several accounts share a phone number');

  const ParentAccessIssueKind({required this.unresolved, required this.label});

  /// Needs an administrator's decision (vs. informational).
  final bool unresolved;
  final String label;
}

class ParentAccessIssue {
  const ParentAccessIssue(this.kind, {this.userId = '', this.studentId = '', this.detail = ''});

  final ParentAccessIssueKind kind;
  final String userId, studentId, detail;

  @override
  String toString() => '${kind.label}: parent "$userId", student "$studentId"${detail.isEmpty ? '' : ' ($detail)'}';
}

/// The access records to write, and what needs an administrator.
class ParentAccessPlan {
  ParentAccessPlan({required this.records, required this.issues, required this.linkCount});

  /// userId → access record.
  final Map<String, ParentAccessRecord> records;
  final List<ParentAccessIssue> issues;

  /// Link records read.
  final int linkCount;

  List<ParentAccessIssue> get unresolved => [for (final i in issues) if (i.kind.unresolved) i];
}

final _phoneId = RegExp(r'^[0-9]{10}$');

/// Builds the access records from the `user_student_links` documents
/// ([links]: maps with `userId`, `studentId`, optional `relation`) and the
/// student records they name ([students]: id → data, or null when the
/// record doesn't exist).
///
/// [userIds], when given, is every existing `users` document id (to report
/// links to missing accounts). [checkParentLinksOnly] reports parents listed
/// on a student record without a link record — only meaningful when
/// [students] holds every student (the full reconciliation), not one
/// parent's children.
ParentAccessPlan buildParentAccessPlan({
  required List<Map<String, dynamic>> links,
  required Map<String, Map<String, dynamic>?> students,
  Set<String>? userIds,
  bool checkParentLinksOnly = false,
}) {
  final issues = <ParentAccessIssue>[];
  // (userId, studentId) → raw relation values, one per link record.
  final pairs = <String, Map<String, List<Object?>>>{};
  for (final link in links) {
    final userId = link['userId']?.toString().trim() ?? '';
    final studentId = link['studentId']?.toString().trim() ?? '';
    if (userId.isEmpty || studentId.isEmpty) {
      issues.add(ParentAccessIssue(ParentAccessIssueKind.incompleteLink, userId: userId, studentId: studentId));
      continue;
    }
    pairs.putIfAbsent(userId, () => {}).putIfAbsent(studentId, () => []).add(link['relation']);
  }

  // studentId → userId → relation on the student record's parentLinks.
  String? parentLinkRelation(String studentId, String userId, {required void Function(String raw) onUnrecognized}) {
    final raw = (students[studentId]?['parentLinks'] as List?) ?? const [];
    for (final entry in raw.whereType<Map>()) {
      final id = (entry['userId'] ?? entry['id'])?.toString().trim() ?? '';
      if (id != userId) continue;
      final r = entry['relation'];
      final normalized = ParentRelation.normalize(r);
      if (normalized == null && (r?.toString().trim() ?? '').isNotEmpty) onUnrecognized(r.toString());
      return normalized;
    }
    return null;
  }

  final records = <String, ParentAccessRecord>{};
  for (final MapEntry(key: userId, value: children) in pairs.entries) {
    if (!_phoneId.hasMatch(userId)) issues.add(ParentAccessIssue(ParentAccessIssueKind.userIdNotPhone, userId: userId));
    if (userIds != null && !userIds.contains(userId)) issues.add(ParentAccessIssue(ParentAccessIssueKind.missingUser, userId: userId));
    final studentIds = <String>[];
    final classIds = <String>[];
    final finance = <String>[];
    final relations = <String, String>{};
    for (final MapEntry(key: studentId, value: rawRelations) in children.entries) {
      if (students[studentId] == null) {
        issues.add(ParentAccessIssue(ParentAccessIssueKind.missingStudent, userId: userId, studentId: studentId));
        continue;
      }
      if (rawRelations.length > 1) {
        issues.add(ParentAccessIssue(ParentAccessIssueKind.duplicateLink, userId: userId, studentId: studentId, detail: '${rawRelations.length} records'));
      }
      final linkRelations = <String>{};
      var problem = false;
      for (final raw in rawRelations) {
        final normalized = ParentRelation.normalize(raw);
        if (normalized != null) {
          linkRelations.add(normalized);
        } else if ((raw?.toString().trim() ?? '').isNotEmpty) {
          problem = true;
          issues.add(ParentAccessIssue(ParentAccessIssueKind.unrecognizedRelation, userId: userId, studentId: studentId, detail: '"$raw" on the link record'));
        }
      }
      final fromStudent = parentLinkRelation(studentId, userId, onUnrecognized: (raw) {
        problem = true;
        issues.add(ParentAccessIssue(ParentAccessIssueKind.unrecognizedRelation, userId: userId, studentId: studentId, detail: '"$raw" on the student record'));
      });

      String? relation;
      if (linkRelations.length > 1) {
        problem = true;
        issues.add(ParentAccessIssue(ParentAccessIssueKind.conflictingRelation, userId: userId, studentId: studentId, detail: (linkRelations.toList()..sort()).join(' / ')));
      } else if (linkRelations.length == 1) {
        relation = linkRelations.single;
        if (fromStudent != null && fromStudent != relation) {
          problem = true;
          issues.add(ParentAccessIssue(ParentAccessIssueKind.relationMismatch, userId: userId, studentId: studentId, detail: 'link: $relation, student record: $fromStudent'));
        }
      } else if (fromStudent != null && !problem) {
        relation = fromStudent;
        issues.add(ParentAccessIssue(ParentAccessIssueKind.relationFromStudentRecord, userId: userId, studentId: studentId, detail: fromStudent));
      } else if (!problem) {
        problem = true;
        issues.add(ParentAccessIssue(ParentAccessIssueKind.missingRelation, userId: userId, studentId: studentId));
      }

      studentIds.add(studentId);
      classIds.add(students[studentId]?['classId']?.toString().trim() ?? '');
      final resolved = problem ? null : relation;
      relations[studentId] = resolved ?? ParentRelation.unresolved;
      if (ParentRelation.allowsFinance(resolved)) finance.add(studentId);
    }
    records[userId] = ParentAccessRecord(userId: userId, studentIds: studentIds, financeStudentIds: finance, relations: relations, classIds: classIds);
  }

  if (checkParentLinksOnly) {
    for (final MapEntry(key: studentId, value: data) in students.entries) {
      for (final entry in ((data?['parentLinks'] as List?) ?? const []).whereType<Map>()) {
        final id = (entry['userId'] ?? entry['id'])?.toString().trim() ?? '';
        if (id.isEmpty || (pairs[id]?.containsKey(studentId) ?? false)) continue;
        issues.add(ParentAccessIssue(ParentAccessIssueKind.parentLinksOnly, userId: id, studentId: studentId));
      }
    }
  }

  return ParentAccessPlan(records: records, issues: issues, linkCount: links.length);
}

/// The account checks of the reconciliation (read-only): every `users`
/// record ([users]: id → data) whose shape the rules can't rely on. The
/// rules find an account at `users/{last 10 digits of the signed-in phone}`,
/// exactly as the OTP login keys it. [ParentAccessIssue.detail] names the
/// account's role.
List<ParentAccessIssue> auditAccounts(Map<String, Map<String, dynamic>> users) {
  String digits(Object? v) {
    final d = (v?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  final issues = <ParentAccessIssue>[];
  final byPhone = <String, List<String>>{};
  for (final MapEntry(key: id, value: data) in users.entries) {
    final role = (data['role']?.toString() ?? 'parent').trim().toLowerCase();
    final phones = {for (final k in ['phoneNumber', 'phone']) digits(data[k])}..remove('');
    if (!_phoneId.hasMatch(id)) {
      issues.add(ParentAccessIssue(ParentAccessIssueKind.accountIdNotPhone, userId: id, detail: 'role: $role'));
    } else if (phones.any((p) => p != id)) {
      issues.add(ParentAccessIssue(ParentAccessIssueKind.accountPhoneMismatch, userId: id, detail: 'role: $role, phone: ${phones.join(', ')}'));
    }
    for (final p in phones.isEmpty && _phoneId.hasMatch(id) ? {id} : phones) {
      byPhone.putIfAbsent(p, () => []).add(id);
    }
  }
  for (final MapEntry(key: phone, value: ids) in byPhone.entries) {
    if (ids.length > 1) {
      issues.add(ParentAccessIssue(ParentAccessIssueKind.duplicateAccountPhone, userId: phone, detail: 'accounts: ${(ids..sort()).join(', ')}'));
    }
  }
  return issues;
}
