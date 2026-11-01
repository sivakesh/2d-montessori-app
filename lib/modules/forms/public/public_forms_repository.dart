import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../public_website/content/website_public_item.dart';
import '../models/public_submission_settings.dart';
import '../models/website_form.dart';

/// What the public website reads of forms: the active versions in
/// [FormCollections.publicForms], and whether the school accepts
/// submissions ([PublicSubmissionStatus]) only. Form definitions being edited,
/// submissions and notes are never read here.
class PublicFormsRepository {
  PublicFormsRepository({FirebaseFirestore? firestore, this.schoolId = WebsitePublicItem.defaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Form [formId]'s active version, or null when it isn't active (or is
  /// another school's, or can't be used).
  Future<PublicWebsiteForm?> activeForm(String formId) async {
    if (!FormIds.docPattern.hasMatch(formId)) return null;
    final form = PublicWebsiteForm.tryParse((await _db.collection(FormCollections.publicForms).doc(formId).get()).data());
    return form != null && form.schoolId == schoolId && form.id == formId ? form : null;
  }

  /// Every active form, by title (for choosing one in the page editor).
  Future<List<PublicWebsiteForm>> activeForms() async {
    final snapshot = await _db.collection(FormCollections.publicForms).where('schoolId', isEqualTo: schoolId).get();
    final forms = [for (final d in snapshot.docs) ?PublicWebsiteForm.tryParse(d.data())];
    forms.sort((a, b) => a.title.en.toLowerCase().compareTo(b.title.en.toLowerCase()));
    return forms;
  }

  /// Whether the school accepts submissions, as it changes (an open form
  /// closes when an administrator switches submissions off).
  Stream<PublicSubmissionStatus> submissionStatus() =>
      _db.collection(PublicSubmissionSettings.publicCollection).doc(schoolId).snapshots().map((s) => PublicSubmissionStatus.fromMap(schoolId, s.data()));
}

final publicFormsRepositoryProvider = Provider<PublicFormsRepository>((ref) => PublicFormsRepository());

/// One form's active version, read again each time a page shows it.
final publicWebsiteFormProvider = FutureProvider.autoDispose.family<PublicWebsiteForm?, String>(
  (ref, formId) => ref.watch(publicFormsRepositoryProvider).activeForm(formId),
);

/// Whether the school accepts submissions, live. Loading or failing to
/// load counts as closed (see `PublicWebsiteFormView`).
final publicSubmissionStatusProvider = StreamProvider.autoDispose<PublicSubmissionStatus>(
  (ref) => ref.watch(publicFormsRepositoryProvider).submissionStatus(),
);

/// The active forms, for the page editor's Form block.
final activeWebsiteFormsProvider = FutureProvider.autoDispose<List<PublicWebsiteForm>>(
  (ref) => ref.watch(publicFormsRepositoryProvider).activeForms(),
);
