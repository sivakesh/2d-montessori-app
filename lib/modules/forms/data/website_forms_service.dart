import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/settings/models/school_settings_model.dart';
import '../../auth/models/app_user.dart';
import '../../public_website/content/blocks/block_registry.dart';
import '../../public_website/content/blocks/website_block.dart';
import '../../public_website/content/built_in_pages.dart';
import '../../public_website/content/website_content_models.dart';
import '../../public_website/content/website_content_repository.dart';
import '../../public_website/content/website_custom_page.dart';
import '../models/website_form.dart';

/// A form and the version visitors see now (null when none is active).
typedef ManagedForm = ({WebsiteForm form, PublicWebsiteForm? live});

/// The Forms Library: create forms from templates, edit, duplicate,
/// activate, deactivate and delete them.
///
/// - Saving a draft never changes what visitors see. Only [activate]
///   writes the visitor-facing copy ([FormCollections.publicForms]), from
///   the definition as stored (never as sent by the browser), after
///   checking the whole schema; [deactivate] removes it. Submissions are
///   never touched.
/// - Each activation of a changed schema gives the form its next
///   [WebsiteForm.version].
/// - Admin only, and scoped to [schoolId]: another school's form is never
///   listed, read or changed. Every method checks (security rules must
///   enforce the same; they are deferred to the rules hardening phase).
class WebsiteFormsService {
  WebsiteFormsService({FirebaseFirestore? firestore, this.schoolId = kDefaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _forms => _db.collection(FormCollections.forms);
  CollectionReference<Map<String, dynamic>> get _public => _db.collection(FormCollections.publicForms);
  CollectionReference<Map<String, dynamic>> get _versions => _db.collection(FormCollections.versions);
  CollectionReference<Map<String, dynamic>> get _deleted => _db.collection(FormCollections.deletedForms);

  void _requireAdmin(String role) {
    if (role.toLowerCase() != 'admin') throw FormsUnauthorizedException(role);
  }

  Map<String, dynamic> _stamp(AppUser actor) => {'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''};

  /// Every form of this school, most recently changed first, with what
  /// visitors see of each.
  Future<List<ManagedForm>> listForms({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final forms = await _forms.where('schoolId', isEqualTo: schoolId).get();
    final live = await _public.where('schoolId', isEqualTo: schoolId).get();
    final liveById = {for (final d in live.docs) d.id: PublicWebsiteForm.tryParse(d.data())};
    final result = [for (final d in forms.docs) (form: WebsiteForm.fromMap(d.id, d.data()), live: liveById[d.id])];
    result.sort((a, b) => (b.form.updatedAt ?? DateTime(0)).compareTo(a.form.updatedAt ?? DateTime(0)));
    return result;
  }

  /// One form of this school, or null.
  Future<ManagedForm?> getForm({required String requesterRole, required String formId}) async {
    _requireAdmin(requesterRole);
    final form = await _ownForm(formId);
    if (form == null) return null;
    return (form: form, live: PublicWebsiteForm.tryParse((await _public.doc(formId).get()).data()));
  }

  Future<WebsiteForm?> _ownForm(String formId) async {
    if (!FormIds.docPattern.hasMatch(formId)) return null;
    final doc = await _forms.doc(formId).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['schoolId'] != schoolId) return null;
    return WebsiteForm.fromMap(doc.id, data);
  }

  Future<WebsiteForm> _requireOwnForm(String formId) async => await _ownForm(formId) ?? (throw FormsException('This form no longer exists.'));

  void _requireStorable(WebsiteForm form) {
    final problems = form.problems(complete: false);
    if (problems.isNotEmpty) throw FormsException(problems.first);
  }

  /// A new draft from starter template [templateId] (not on the website),
  /// with the template's questions and description. A cover image must
  /// still be chosen before it can be activated.
  Future<WebsiteForm> createFromTemplate({required String requesterRole, required AppUser actor, required String templateId, String? title}) async {
    _requireAdmin(requesterRole);
    final template = FormTemplate.byId(templateId) ?? (throw FormsException('Choose one of the starter templates.'));
    final ref = _forms.doc();
    final form = WebsiteForm(
      id: ref.id,
      schoolId: schoolId,
      title: LocalizedText(en: (title ?? template.name).trim()),
      description: template.formDescription,
      fields: template.buildFields(),
      successMessage: template.successMessage,
      template: template.id,
    );
    _requireStorable(form);
    await ref.set({
      ...form.toContentMap(),
      'schoolId': schoolId,
      'status': WebsiteFormStatus.draft.id,
      'version': 0,
      'template': template.id,
      'createdAt': FieldValue.serverTimestamp(),
      ..._stamp(actor),
    });
    return form;
  }

  /// Saves [form]'s title, description, cover image, questions, content
  /// and success message. Its status and version are never taken from
  /// [form]: an active form stays active, and visitors keep seeing its
  /// active version until it is activated again. Refused when the schema
  /// is malformed (unknown field or content types, bad options or
  /// settings, over the limits); a draft may be incomplete.
  Future<void> saveDraft({required String requesterRole, required AppUser actor, required WebsiteForm form}) async {
    _requireAdmin(requesterRole);
    await _requireOwnForm(form.id);
    _requireStorable(form);
    await _forms.doc(form.id).update({...form.toContentMap(), ..._stamp(actor)});
  }

  /// A new draft copy of [formId] ("Copy of …"): the same questions,
  /// content and settings (and any keys this version doesn't read) with
  /// new ids throughout (form, fields, options, content), never active,
  /// version 0. Its submissions stay with the original.
  Future<WebsiteForm> duplicate({required String requesterRole, required AppUser actor, required String formId}) async {
    _requireAdmin(requesterRole);
    final source = await _requireOwnForm(formId);
    final ref = _forms.doc();
    final title = 'Copy of ${source.title.en.trim()}';
    final copy = WebsiteForm(
      id: ref.id,
      schoolId: schoolId,
      title: source.title.copyWith(en: title.length > FormLimits.maxTitle ? title.substring(0, FormLimits.maxTitle) : title),
      description: source.description,
      coverMediaId: source.coverMediaId,
      internalDescription: source.internalDescription,
      items: [for (final i in source.items) i.withFreshIds()],
      successMessage: source.successMessage,
      template: source.template,
      multiStep: source.multiStep,
      reviewStep: source.reviewStep,
      completionTitle: source.completionTitle,
      extra: source.extra,
    );
    _requireStorable(copy);
    await ref.set({
      ...copy.extra,
      ...copy.toContentMap(),
      'schoolId': schoolId,
      'status': WebsiteFormStatus.draft.id,
      'version': 0,
      'template': copy.template,
      'duplicatedFrom': formId,
      'createdAt': FieldValue.serverTimestamp(),
      ..._stamp(actor),
    });
    return copy;
  }

  // ------------------------------------------------------------ images

  /// The whole website media library (any status), for choosing images.
  Future<List<WebsiteMedia>> mediaLibrary({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _db.collection(WebsiteCollections.media).get();
    return [for (final d in snapshot.docs) WebsiteMedia.fromMap(d.id, d.data())];
  }

  /// Why [media] (the image chosen as [what]) can't be shown to visitors,
  /// or null when it can: it must exist, be published with its consent
  /// confirmed and a file, and have English alt text — the media library's
  /// own rules.
  static String? imageProblem(WebsiteMedia? media, {String what = 'image'}) {
    if (media == null) return 'The $what no longer exists in the media library. Choose another.';
    if (!media.consentConfirmed) return 'The $what’s consent isn’t confirmed (or was withdrawn). Choose another, or confirm consent in the media library.';
    if (!media.isPublished || media.url.isEmpty) return 'The $what isn’t published. Publish it in the media library, or choose another.';
    if (media.alt.en.trim().isEmpty) return 'The $what has no English alt text. Add it in the media library.';
    return null;
  }

  /// Throws unless every image [form] uses may be shown to visitors.
  Future<void> _requireEligibleImages(WebsiteForm form) async {
    for (final id in form.mediaIds) {
      final doc = await _db.collection(WebsiteCollections.media).doc(id).get();
      final media = doc.exists && doc.data() != null ? WebsiteMedia.fromMap(id, doc.data()!) : null;
      final problem = imageProblem(media, what: id == form.coverMediaId ? 'cover image' : 'image');
      if (problem != null) throw FormsException(problem);
    }
  }

  // ------------------------------------------------------------ activation

  /// Makes the form as saved now the version visitors see and can submit.
  /// The whole schema must be complete and valid — a title, description
  /// and cover image included — and every image eligible
  /// ([imageProblem]). A changed form gets the next version number (and a
  /// record in [FormCollections.versions]); activating an unchanged one
  /// keeps its number. The visitor copy, the form's status and the version
  /// record are written together.
  Future<PublicWebsiteForm> activate({required String requesterRole, required AppUser actor, required String formId}) async {
    _requireAdmin(requesterRole);
    final form = await _requireOwnForm(formId);
    final problems = form.problems(complete: true);
    if (problems.isNotEmpty) throw FormsException(problems.first);
    await _requireEligibleImages(form);
    // What was last active: the visitor copy, else (after deactivation)
    // the schema kept with the form.
    final last = PublicWebsiteForm.tryParse((await _public.doc(formId).get()).data()) ?? form.activatedSchema;
    final latest = last != null && last.version > form.version ? last.version : form.version;
    final unchanged = last != null && form.toPublic(last.version).sameSchemaAs(last);
    final version = unchanged ? last.version : latest + 1;
    final public = form.toPublic(version);
    final batch = _db.batch();
    // The whole document, so nothing but its visitor-facing fields remain.
    batch.set(_public.doc(formId), {...public.toMap(), 'activatedAt': FieldValue.serverTimestamp()});
    batch.update(_forms.doc(formId), {
      'status': WebsiteFormStatus.active.id,
      'version': version,
      'activatedSchema': public.toMap(),
      'activatedAt': FieldValue.serverTimestamp(),
      ..._stamp(actor),
    });
    if (!unchanged) {
      batch.set(_versions.doc('${formId}_v$version'), {
        'formId': formId,
        'schoolId': schoolId,
        'version': version,
        'schema': public.toMap(),
        'activatedAt': FieldValue.serverTimestamp(),
        'activatedById': actor.id,
        'activatedByName': actor.name ?? '',
      });
    }
    await batch.commit();
    return public;
  }

  /// Takes the form off the website: visitors no longer see it and new
  /// submissions are refused. Its submissions and definition are kept, and
  /// it can be activated again.
  Future<void> deactivate({required String requesterRole, required AppUser actor, required String formId}) async {
    _requireAdmin(requesterRole);
    await _requireOwnForm(formId);
    final batch = _db.batch();
    batch.delete(_public.doc(formId));
    batch.update(_forms.doc(formId), {'status': WebsiteFormStatus.inactive.id, 'deactivatedAt': FieldValue.serverTimestamp(), ..._stamp(actor)});
    await batch.commit();
  }

  /// The form's activated versions, newest first.
  Future<List<FormVersionRecord>> versionHistory({required String requesterRole, required String formId}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _versions.where('formId', isEqualTo: formId).get();
    final list = [
      for (final d in snapshot.docs)
        if (d.data()['schoolId'] == schoolId) FormVersionRecord.fromMap(d.data()),
    ];
    list.sort((a, b) => b.version.compareTo(a.version));
    return list;
  }

  // ------------------------------------------------------------ deletion

  /// The website pages (drafts and published) with a Form block showing
  /// [formId], in words ("the “Open day” page (published)").
  Future<Set<String>> formReferences({required String requesterRole, required String formId}) async {
    _requireAdmin(requesterRole);
    final labels = <String>{};
    for (final (collection, state) in [(WebsiteCollections.pageDrafts, 'draft'), (WebsiteCollections.livePages, 'published')]) {
      final snapshot = await _db.collection(collection).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final custom = CustomPage.isCustomDoc(data);
        final blocks = custom ? CustomPage.fromMap(doc.id, data).blocks : builtInPageBlocks(data);
        final uses = BlockRegistry.flatten(blocks ?? const []).any((b) => b is StructuredBlock && b.type == BlockRegistry.form.type && b.string('formId') == formId);
        if (!uses) continue;
        final name = custom ? 'the “${LocalizedText.fromMap(data['title']).en}” page' : 'the ${BuiltInPage.parse(doc.id)?.label ?? doc.id} page';
        labels.add('$name ($state)');
      }
    }
    return labels;
  }

  /// What the admin must type to confirm deleting [form].
  static String deleteConfirmation(WebsiteForm form) => form.title.en.trim().isEmpty ? 'Untitled form' : form.title.en.trim();

  /// Deletes form [formId], after [confirmTitle] repeats its title
  /// ([deleteConfirmation]).
  ///
  /// 1. Visitors stop seeing it: its visitor copy is removed (and it is
  ///    marked inactive) first. If that fails, nothing is deleted.
  /// 2. Then, together: an immutable record of it in
  ///    [FormCollections.deletedForms] (title, versions, questions), and
  ///    the definition is deleted.
  ///
  /// Submissions, their notes and snapshots, version records and images
  /// are never touched. Pages with a Form block for it show visitors
  /// nothing. Safe to repeat: a form already deleted is reported as done.
  Future<void> deleteForm({required String requesterRole, required AppUser actor, required String formId, required String confirmTitle}) async {
    _requireAdmin(requesterRole);
    final form = await _ownForm(formId);
    if (form == null) {
      final deleted = FormIds.docPattern.hasMatch(formId) ? await _deleted.doc(formId).get() : null;
      if (deleted != null && deleted.exists && deleted.data()?['schoolId'] == schoolId) return;
      throw FormsException('This form no longer exists.');
    }
    if (confirmTitle.trim() != deleteConfirmation(form)) throw FormsException('Type the form’s title exactly as shown to confirm.');
    try {
      final off = _db.batch();
      off.delete(_public.doc(formId));
      off.update(_forms.doc(formId), {'status': WebsiteFormStatus.inactive.id, 'deactivatedAt': FieldValue.serverTimestamp(), ..._stamp(actor)});
      await off.commit();
    } catch (_) {
      throw FormsException('The form couldn’t be taken off the website, so it wasn’t deleted. Try again.');
    }
    try {
      final batch = _db.batch();
      batch.set(_deleted.doc(formId), {
        'formId': formId,
        'schoolId': schoolId,
        'title': form.title.toMap(),
        'template': form.template,
        'version': form.version,
        'lastActiveSchema': form.activatedSchema?.toMap(),
        'items': [for (final i in form.items) i.toMap()],
        'fields': [for (final f in form.fields) f.toMap()],
        'createdAt': form.createdAt == null ? null : Timestamp.fromDate(form.createdAt!),
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedById': actor.id,
        'deletedByName': actor.name ?? '',
      });
      batch.delete(_forms.doc(formId));
      await batch.commit();
    } catch (_) {
      throw FormsException('The form was taken off the website but couldn’t be deleted. Try again.');
    }
  }

  /// The deleted forms of this school.
  Future<List<DeletedForm>> deletedForms({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _deleted.where('schoolId', isEqualTo: schoolId).get();
    return [for (final d in snapshot.docs) DeletedForm.fromMap(d.id, d.data())];
  }
}

/// One activated version of a form (in [FormCollections.versions]).
class FormVersionRecord {
  const FormVersionRecord({required this.version, required this.title, required this.fieldCount, this.activatedAt, this.activatedByName = ''});

  factory FormVersionRecord.fromMap(Map<String, dynamic> map) {
    final schema = map['schema'] is Map ? Map<String, dynamic>.from(map['schema'] as Map) : const <String, dynamic>{};
    final fields = schema['fields'];
    return FormVersionRecord(
      version: map['version'] is int ? map['version'] as int : 0,
      title: LocalizedText.fromMap(schema['title']).en,
      fieldCount: fields is List ? fields.length : 0,
      activatedAt: map['activatedAt'] is Timestamp ? (map['activatedAt'] as Timestamp).toDate() : null,
      activatedByName: map['activatedByName']?.toString() ?? '',
    );
  }

  final int version;
  final String title;
  final int fieldCount;
  final DateTime? activatedAt;
  final String activatedByName;
}

/// What remains of a deleted form (in [FormCollections.deletedForms]).
class DeletedForm {
  const DeletedForm({required this.formId, required this.title, required this.version, this.deletedAt});

  factory DeletedForm.fromMap(String id, Map<String, dynamic> map) => DeletedForm(
        formId: id,
        title: LocalizedText.fromMap(map['title']).en,
        version: map['version'] is int ? map['version'] as int : 0,
        deletedAt: map['deletedAt'] is Timestamp ? (map['deletedAt'] as Timestamp).toDate() : null,
      );

  final String formId;
  final String title;
  final int version;
  final DateTime? deletedAt;
}
