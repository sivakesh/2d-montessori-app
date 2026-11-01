import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../admin/settings/models/school_settings_model.dart';
import '../../auth/models/app_user.dart';
import '../models/website_form.dart';

/// An administrator's note on a submission (never shown to visitors, never
/// exported).
@immutable
class SubmissionNote {
  const SubmissionNote({required this.id, required this.text, required this.authorName, this.createdAt});

  final String id;
  final String text;
  final String authorName;
  final DateTime? createdAt;
}

/// The inbox filters, applied independently of the UI.
@immutable
class SubmissionsQuery {
  const SubmissionsQuery({this.search = '', this.formId, this.status, this.from, this.to});

  final String search;
  final String? formId;
  final FormSubmissionStatus? status;

  /// Submitted on or after [from] and before [to].
  final DateTime? from;
  final DateTime? to;

  List<FormSubmission> apply(Iterable<FormSubmission> submissions) {
    final words = search.trim().toLowerCase();
    return [
      for (final s in submissions)
        if ((formId == null || s.formId == formId) &&
            (status == null || s.status == status) &&
            (from == null || (s.createdAt != null && !s.createdAt!.isBefore(from!))) &&
            (to == null || (s.createdAt != null && s.createdAt!.isBefore(to!))) &&
            (words.isEmpty || s.searchText.contains(words)))
          s,
    ];
  }
}

/// The private Submissions Inbox: list, read, change the status of and
/// note submissions, and export them.
///
/// Admin only and scoped to [schoolId] in every method: another school's
/// submission is never listed, read or changed, whatever id is asked for.
/// (Security rules must enforce the same; they are deferred to the rules
/// hardening phase.) Nothing here logs answers.
class FormSubmissionsInboxService {
  FormSubmissionsInboxService({FirebaseFirestore? firestore, this.schoolId = kDefaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _submissions => _db.collection(FormCollections.submissions);

  void _requireAdmin(String role) {
    if (role.toLowerCase() != 'admin') throw FormsUnauthorizedException(role);
  }

  /// Every submission of this school, newest first.
  Future<List<FormSubmission>> listSubmissions({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _submissions.where('schoolId', isEqualTo: schoolId).get();
    final list = [for (final d in snapshot.docs) FormSubmission.fromMap(d.id, d.data())];
    list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return list;
  }

  Future<DocumentReference<Map<String, dynamic>>> _own(String submissionId) async {
    if (!FormIds.docPattern.hasMatch(submissionId)) throw FormsException('This submission no longer exists.');
    final ref = _submissions.doc(submissionId);
    final doc = await ref.get();
    if (!doc.exists || doc.data()?['schoolId'] != schoolId) throw FormsException('This submission no longer exists.');
    return ref;
  }

  Future<FormSubmission> getSubmission({required String requesterRole, required String submissionId}) async {
    _requireAdmin(requesterRole);
    final doc = await (await _own(submissionId)).get();
    return FormSubmission.fromMap(doc.id, doc.data()!);
  }

  /// Sets the submission's status. The answers are never changed.
  Future<void> setStatus({required String requesterRole, required AppUser actor, required String submissionId, required FormSubmissionStatus status}) async {
    _requireAdmin(requesterRole);
    final ref = await _own(submissionId);
    await ref.update({
      'status': status.id,
      'updatedAt': FieldValue.serverTimestamp(),
      'statusChangedById': actor.id,
      'statusChangedByName': actor.name ?? '',
    });
  }

  /// The submission's notes, oldest first.
  Future<List<SubmissionNote>> listNotes({required String requesterRole, required String submissionId}) async {
    _requireAdmin(requesterRole);
    final ref = await _own(submissionId);
    final notes = await ref.collection(FormCollections.notes).get();
    final list = [
      for (final d in notes.docs)
        SubmissionNote(
          id: d.id,
          text: d.data()['text']?.toString() ?? '',
          authorName: d.data()['authorName']?.toString() ?? '',
          createdAt: d.data()['createdAt'] is Timestamp ? (d.data()['createdAt'] as Timestamp).toDate() : null,
        ),
    ];
    list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    return list;
  }

  Future<void> addNote({required String requesterRole, required AppUser actor, required String submissionId, required String text}) async {
    _requireAdmin(requesterRole);
    final clean = text.trim();
    if (clean.isEmpty) throw FormsException('Write the note first.');
    if (clean.length > FormLimits.maxNote) throw FormsException('Notes must be ${FormLimits.maxNote} characters or fewer.');
    final ref = await _own(submissionId);
    await ref.collection(FormCollections.notes).add({
      'text': clean,
      'authorId': actor.id,
      'authorName': actor.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.update({'updatedAt': FieldValue.serverTimestamp()});
  }

  /// [submissions] as CSV: reference, time, form, version, status, then a
  /// column per question (by form and field id, headed by its label as
  /// submitted). Internal notes are never included. Cells that a
  /// spreadsheet would run as a formula are prefixed with `'`.
  static String toCsv(List<FormSubmission> submissions) {
    final columns = <String, String>{};
    for (final s in submissions) {
      for (final f in s.fields) {
        columns.putIfAbsent('${s.formId}/${f.id}', () => submissions.map((x) => x.formId).toSet().length > 1 ? '${s.formTitle}: ${f.label.en}' : f.label.en);
      }
    }
    String cell(String value) {
      var v = value;
      if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
      return '"${v.replaceAll('"', '""')}"';
    }

    final rows = [
      ['Reference', 'Submitted (UTC)', 'Form', 'Form version', 'Status', ...columns.values],
      for (final s in submissions)
        [
          s.reference,
          s.createdAt?.toUtc().toIso8601String() ?? '',
          s.formTitle,
          '${s.formVersion}',
          s.status.label,
          for (final key in columns.keys)
            if (s.formId == key.split('/').first)
              s.fields.where((f) => f.id == key.split('/').last).map(s.answerText).firstOrNull ?? ''
            else
              '',
        ],
    ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }
}
