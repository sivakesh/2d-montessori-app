// The Forms Manager: the Forms Library and builder, the Form block, public
// rendering and validation, the trusted submission service and the
// private Submissions Inbox.
//
// Every record here is synthetic test data (no real students, parents or
// staff). The fake Firestore proves the app's behaviour, not deployed
// security rules (deferred: public submission stays closed until a
// protected endpoint exists).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/config/deploy_target.dart';
import 'package:montessori_app/core/config/firestore_emulator.dart';
import 'package:montessori_app/modules/admin/settings/data/public_submission_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/ui/admin_settings_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/forms/data/form_submission_service.dart';
import 'package:montessori_app/modules/forms/data/form_submissions_inbox_service.dart';
import 'package:montessori_app/modules/forms/data/website_forms_service.dart';
import 'package:montessori_app/modules/forms/models/public_submission_settings.dart';
import 'package:montessori_app/modules/forms/models/website_form.dart';
import 'package:montessori_app/modules/forms/public/public_forms_repository.dart';
import 'package:montessori_app/modules/forms/ui/forms_manager_screen.dart';
import 'package:montessori_app/modules/forms/ui/public_website_form.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _coverId = 'media_cover_0001';
final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _school = 'default_school';

/// Answers no submission may leak to a public read.
const _privateNote = 'Called back, synthetic note 0001';

class _Harness {
  final db = FakeFirebaseFirestore();
  late final forms = WebsiteFormsService(firestore: db);
  late final inbox = FormSubmissionsInboxService(firestore: db);
  late final submissions = FormSubmissionService(firestore: db);
  late final public = PublicFormsRepository(firestore: db);
  late final settings = PublicSubmissionSettingsService(firestore: db);
  bool _opened = false;

  /// Public submissions switched on or off, as an administrator does
  /// (they're off until then).
  Future<void> setSubmissions(bool open) async {
    final now = await settings.load(schoolId: _school, requesterRole: 'admin', requesterSchoolId: _school);
    await settings.update(schoolId: _school, requesterRole: 'admin', requesterSchoolId: _school, actor: _admin, enabled: open, closedMessage: now.closedMessage, expectedRevision: now.revision);
  }

  /// A new form from [template], with an eligible cover image (every form
  /// needs one before it can be activated).
  Future<WebsiteForm> create([String template = 'general_enquiry']) async {
    final form = await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: template);
    await image(_coverId);
    final withCover = form.copyWith(coverMediaId: () => _coverId);
    await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: withCover);
    return withCover;
  }

  /// A website image (synthetic): published with consent, a file and alt
  /// text unless told otherwise.
  Future<void> image(String id, {String status = 'published', bool consent = true, String alt = 'Children in the garden', String url = 'https://storage.example.test/m.jpg'}) =>
      db.collection(WebsiteCollections.media).doc(id).set({
        'status': status,
        'consentConfirmed': consent,
        'url': url,
        'alt': {'en': alt},
        'storagePath': 'website_media/$id/x.jpg',
      });

  /// Activates form [id]; the first time, also switches public
  /// submissions on, as most tests here send it.
  Future<PublicWebsiteForm> activate(String id) async {
    if (!_opened) {
      _opened = true;
      await setSubmissions(true);
    }
    return forms.activate(requesterRole: 'admin', actor: _admin, formId: id);
  }

  Future<WebsiteForm> stored(String id) async => (await forms.getForm(requesterRole: 'admin', formId: id))!.form;

  Future<Map<String, dynamic>?> publicDoc(String id) async => (await db.collection(FormCollections.publicForms).doc(id).get()).data();

  Future<int> submissionCount() async => (await db.collection(FormCollections.submissions).get()).docs.length;

  /// An active General Enquiry, and answers it accepts.
  Future<({WebsiteForm form, Map<String, Object?> answers})> activeEnquiry() async {
    final form = await create();
    await activate(form.id);
    final f = form.fields;
    return (form: form, answers: <String, Object?>{f[0].id: 'Asha Example', f[1].id: 'asha@example.com', f[2].id: '+91 98765 43210', f[3].id: 'Do you have places?', f[4].id: true});
  }

  Future<FormSubmissionReceipt> submit(String formId, Map<String, Object?> answers, {String? key, int? version, String honeypot = ''}) => submissions.submit(
        FormSubmissionRequest(formId: formId, answers: answers, submissionKey: key ?? FormIds.submissionKey(), formVersion: version, honeypot: honeypot),
      );
}

WebsiteFormField _field(FormFieldType type, {bool required = false, List<String> options = const []}) => WebsiteFormField.create(type, '${type.label} question', required: required, options: options);

/// The school accepts submissions (what an administrator's switch says).
const _open = PublicSubmissionStatus(schoolId: _school, open: true, revision: 1);

Matcher _refused(FormSubmissionErrorCode code) => throwsA(isA<FormSubmissionException>().having((e) => e.code, 'code', code));

void main() {
  group('templates and schema', () {
    test('every starter template is a complete, valid form with stable, fresh ids', () {
      expect(FormTemplate.all.map((t) => t.name), ['Admission Enquiry', 'General Enquiry', 'Event Registration', 'Custom Form']);
      for (final t in FormTemplate.all) {
        final a = t.buildFields();
        final b = t.buildFields();
        expect(formSchemaProblems(title: LocalizedText(en: t.name), fields: a, successMessage: t.successMessage, complete: true), isEmpty, reason: t.id);
        expect(a.every((f) => FormIds.fieldPattern.hasMatch(f.id)), isTrue);
        expect({...a.map((f) => f.id), ...b.map((f) => f.id)}, hasLength(a.length * 2), reason: 'each new form gets its own ids');
      }
      final admission = FormTemplate.byId('admission_enquiry')!.buildFields();
      expect(admission.map((f) => f.type).toSet(), containsAll([FormFieldType.shortText, FormFieldType.email, FormFieldType.phone, FormFieldType.date, FormFieldType.dropdown, FormFieldType.longText, FormFieldType.checkbox]));
    });

    test('invalid definitions are refused, with where the problem is', () {
      List<String> problems(List<WebsiteFormField> fields, {bool complete = true}) =>
          formSchemaProblems(title: const LocalizedText(en: 'Form'), fields: fields, successMessage: const LocalizedText(en: 'Thanks'), complete: complete);
      final unknown = WebsiteFormField.fromMap({'id': 'f_abcdefgh', 'type': 'file_upload', 'label': {'en': 'Upload'}});
      expect(problems([unknown]).single, contains('isn’t supported'));
      expect(problems([unknown], complete: false), isNotEmpty, reason: 'unknown types can’t even be saved');
      final badOptions = WebsiteFormField.fromMap({'id': 'f_abcdefgh', 'type': 'dropdown', 'label': {'en': 'Pick'}, 'options': 'yes,no'});
      expect(problems([badOptions]).join(), contains('options can’t be read'));
      final badOption = WebsiteFormField.fromMap({'id': 'f_abcdefgh', 'type': 'radio', 'label': {'en': 'Pick'}, 'options': [{'label': 'no id'}, {'id': 'o_aaaaaaaa', 'label': {'en': 'A'}}]});
      expect(problems([badOption]).join(), contains('an option can’t be read'));
      expect(problems([_field(FormFieldType.dropdown, options: ['Only one'])]).join(), contains('at least two options'));
      expect(problems([_field(FormFieldType.radio, options: ['Same', 'same'])]).join(), contains('same label'));
      expect(problems([_field(FormFieldType.dropdown, options: [for (var i = 0; i < 21; i++) 'O$i'])]).join(), contains('at most 20 options'));
      expect(problems([_field(FormFieldType.checkbox).copyWith(options: [FormFieldOption.create('x')])]).join(), contains('only dropdowns and radio buttons'));
      final dup = _field(FormFieldType.email);
      expect(problems([dup, dup]).join(), contains('used by another field'));
      expect(problems([for (var i = 0; i < 31; i++) _field(FormFieldType.shortText)]).join(), contains('at most 30 fields'));
      expect(problems([_field(FormFieldType.shortText).copyWith(label: LocalizedText(en: 'x' * 201))]).join(), contains('200 characters or fewer'));
      expect(problems([WebsiteFormField.fromMap({'id': 'bad id', 'type': 'email', 'label': {'en': 'Email'}})]).join(), contains('id isn’t valid'));
      expect(problems([_field(FormFieldType.shortText).copyWith(label: const LocalizedText())]).join(), contains('enter its label'));
      expect(problems([_field(FormFieldType.shortText).copyWith(label: const LocalizedText())], complete: false), isEmpty, reason: 'drafts may be incomplete');
      expect(formSchemaProblems(title: const LocalizedText(), fields: const [], successMessage: const LocalizedText(), complete: true),
          containsAll(['Enter the form’s title in English.', 'Enter the success message in English.', 'Add at least one field.']));
      expect(WebsiteFormField.fromMap('not a map').problems(complete: false), contains('it can’t be read'));
    });
  });

  group('answer validation', () {
    final short = _field(FormFieldType.shortText, required: true);
    final email = _field(FormFieldType.email, required: true);
    final phone = _field(FormFieldType.phone);
    final dropdown = _field(FormFieldType.dropdown, required: true, options: ['Toddler', 'Primary']);
    final radio = _field(FormFieldType.radio, options: ['1', '2']);
    final checkbox = _field(FormFieldType.checkbox, required: true);
    final long = _field(FormFieldType.longText);
    final date = _field(FormFieldType.date, required: true);
    final fields = [short, email, phone, dropdown, radio, checkbox, long, date];

    Map<String, FormAnswerError> errors(Map<String, Object?> answers) => validateFormAnswers(fields, answers).errors;
    Map<String, Object?> valid() => {short.id: ' Asha ', email.id: 'asha@example.com', dropdown.id: dropdown.options[1].id, checkbox.id: true, date.id: '2021-06-15'};

    test('every field type, and required fields', () {
      final ok = validateFormAnswers(fields, valid());
      expect(ok.errors, isEmpty);
      expect(ok.values[short.id], 'Asha', reason: 'trimmed');
      expect(ok.values.containsKey(phone.id), isFalse, reason: 'empty optional answers are left out');
      expect(errors({}), {short.id: FormAnswerError.required, email.id: FormAnswerError.required, dropdown.id: FormAnswerError.required, checkbox.id: FormAnswerError.required, date.id: FormAnswerError.required});
      expect(errors({...valid(), checkbox.id: false})[checkbox.id], FormAnswerError.required, reason: 'a required checkbox must be ticked');
      expect(errors({...valid(), short.id: '   '})[short.id], FormAnswerError.required);
    });

    test('type-specific checks', () {
      for (final bad in ['asha', 'asha@', '@example.com', 'a b@example.com', 'asha@example']) {
        expect(errors({...valid(), email.id: bad})[email.id], FormAnswerError.email, reason: bad);
      }
      for (final good in ['+91 98765 43210', '(044) 2345-6789', '9876543210']) {
        expect(errors({...valid(), phone.id: good}), isEmpty, reason: good);
      }
      for (final bad in ['12345', 'call me', '+91 98765 43210 1234567', '98765abc43']) {
        expect(errors({...valid(), phone.id: bad})[phone.id], FormAnswerError.phone, reason: bad);
      }
      for (final bad in ['2021-02-30', '15/06/2021', '2021-6-15', '1800-01-01']) {
        expect(errors({...valid(), date.id: bad})[date.id], FormAnswerError.date, reason: bad);
      }
      expect(errors({...valid(), long.id: 'x' * 3001})[long.id], FormAnswerError.tooLong);
      expect(errors({...valid(), short.id: 'x' * 201})[short.id], FormAnswerError.tooLong);
    });

    test('dropdown and radio answers must be the saved options', () {
      expect(errors({...valid(), dropdown.id: 'Primary'})[dropdown.id], FormAnswerError.option, reason: 'a label, not an option id');
      expect(errors({...valid(), dropdown.id: 'o_zzzzzzzz'})[dropdown.id], FormAnswerError.option);
      expect(errors({...valid(), radio.id: radio.options[0].id}), isEmpty);
      expect(errors({...valid(), radio.id: dropdown.options[0].id})[radio.id], FormAnswerError.option, reason: 'another field’s option');
    });

    test('unknown fields and wrong value types are refused', () {
      expect(errors({...valid(), 'f_zzzzzzzz': 'extra'})['_form'], FormAnswerError.invalid);
      expect(errors({...valid(), short.id: 42})[short.id], FormAnswerError.invalid);
      expect(errors({...valid(), checkbox.id: 'yes'})[checkbox.id], FormAnswerError.invalid);
    });
  });

  group('forms library', () {
    test('create, edit and save never make a form public', () async {
      final h = _Harness();
      for (final t in FormTemplate.all) {
        final form = await h.create(t.id);
        final stored = await h.stored(form.id);
        expect(stored.status, WebsiteFormStatus.draft);
        expect(stored.version, 0);
        expect(stored.schoolId, _school);
        expect(stored.template, t.id);
        expect(stored.createdAt, isNotNull);
        expect(stored.title.en, t.name);
        expect(stored.fields.map((f) => f.id), form.fields.map((f) => f.id), reason: 'stable ids');
      }
      expect((await h.db.collection(FormCollections.publicForms).get()).docs, isEmpty);

      final form = await h.create();
      final edited = form.copyWith(title: const LocalizedText(en: 'Contact us'), internalDescription: 'For the office');
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: edited);
      expect((await h.stored(form.id)).title.en, 'Contact us');
      expect(await h.publicDoc(form.id), isNull);

      // Status and version are never taken from what is sent.
      await h.db.collection(FormCollections.forms).doc(form.id).update({'status': 'draft'});
      final forged = WebsiteForm.fromMap(form.id, {...edited.toContentMap(), 'schoolId': 'other', 'status': 'active', 'version': 9});
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: forged);
      final after = await h.stored(form.id);
      expect((after.status, after.version, after.schoolId), (WebsiteFormStatus.draft, 0, _school));
    });

    test('activation publishes visitor fields only, versioned; edits wait for the next activation', () async {
      final h = _Harness();
      final form = await h.create();
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: form.copyWith(internalDescription: 'Internal: route to office'));
      final v1 = await h.activate(form.id);
      expect(v1.version, 1);
      final doc = (await h.publicDoc(form.id))!;
      expect(doc.keys.toSet(), PublicWebsiteForm.storedFields);
      expect(doc.toString(), isNot(contains('Internal: route to office')));
      expect(doc.toString(), isNot(contains(_admin.id)));
      expect((await h.stored(form.id)).status, WebsiteFormStatus.active);

      expect((await h.activate(form.id)).version, 1, reason: 'unchanged: same version');

      final changed = (await h.stored(form.id)).copyWith(title: const LocalizedText(en: 'Write to us'));
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: changed);
      expect(PublicWebsiteForm.tryParse(await h.publicDoc(form.id))!.title.en, 'General Enquiry', reason: 'visitors keep the active version');
      final v2 = await h.activate(form.id);
      expect(v2.version, 2);
      expect(v2.title.en, 'Write to us');
      expect((await h.stored(form.id)).version, 2);
    });

    test('incomplete or malformed forms can’t be activated', () async {
      final h = _Harness();
      final form = await h.create();
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: form.copyWith(fields: const []));
      await expectLater(h.activate(form.id), throwsA(isA<FormsException>().having((e) => e.message, 'message', 'Add at least one field.')));
      // Tampered stored data: an unknown field type (items are what is
      // read; the questions-only list is derived from them).
      await h.db.collection(FormCollections.forms).doc(form.id).update({
        'items': [
          {'id': 'f_abcdefgh', 'type': 'payment', 'label': {'en': 'Pay'}},
        ],
      });
      await expectLater(h.activate(form.id), throwsA(isA<FormsException>()));
      await expectLater(h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: await h.stored(form.id)), throwsA(isA<FormsException>()));
      expect(await h.publicDoc(form.id), isNull);
    });

    test('duplicate makes an inactive copy; the original is unchanged', () async {
      final h = _Harness();
      final form = await h.create('event_registration');
      await h.activate(form.id);
      final copy = await h.forms.duplicate(requesterRole: 'admin', actor: _admin, formId: form.id);
      final stored = await h.stored(copy.id);
      expect(copy.id, isNot(form.id));
      expect(stored.title.en, 'Copy of Event Registration');
      expect((stored.status, stored.version), (WebsiteFormStatus.draft, 0));
      expect(stored.fields.map((f) => f.label), form.fields.map((f) => f.label), reason: 'the same questions');
      expect(stored.fields.map((f) => f.id).toSet().intersection(form.fields.map((f) => f.id).toSet()), isEmpty, reason: 'with fresh field ids');
      expect(await h.publicDoc(copy.id), isNull);
      expect((await h.stored(form.id)).status, WebsiteFormStatus.active);
    });

    test('deactivation removes the visitor copy and keeps the responses', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await h.submit(e.form.id, e.answers);
      await h.forms.deactivate(requesterRole: 'admin', actor: _admin, formId: e.form.id);
      expect(await h.publicDoc(e.form.id), isNull);
      expect((await h.stored(e.form.id)).status, WebsiteFormStatus.inactive);
      expect(await h.submissionCount(), 1);
      await expectLater(h.submit(e.form.id, e.answers), _refused(FormSubmissionErrorCode.notAvailable));
      expect(await h.submissionCount(), 1);
      expect((await h.activate(e.form.id)).version, 1, reason: 'reactivated unchanged');
    });

    test('admins only, and only this school’s forms', () async {
      final h = _Harness();
      final form = await h.create();
      for (final role in ['teacher', 'parent', 'staff', '']) {
        await expectLater(h.forms.listForms(requesterRole: role), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.createFromTemplate(requesterRole: role, actor: _admin, templateId: 'custom'), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.activate(requesterRole: role, actor: _admin, formId: form.id), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.deactivate(requesterRole: role, actor: _admin, formId: form.id), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.saveDraft(requesterRole: role, actor: _admin, form: form), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.duplicate(requesterRole: role, actor: _admin, formId: form.id), throwsA(isA<FormsUnauthorizedException>()));
      }
      await h.db.collection(FormCollections.forms).doc('other_form').set({...form.toContentMap(), 'schoolId': 'other_school', 'status': 'draft', 'version': 0});
      expect((await h.forms.listForms(requesterRole: 'admin')).map((f) => f.form.id), [form.id]);
      expect(await h.forms.getForm(requesterRole: 'admin', formId: 'other_form'), isNull);
      await expectLater(h.activate('other_form'), throwsA(isA<FormsException>()));
      await expectLater(h.forms.deactivate(requesterRole: 'admin', actor: _admin, formId: 'other_form'), throwsA(isA<FormsException>()));
      expect(await h.publicDoc('other_form'), isNull);
    });
  });

  group('submissions', () {
    test('stored with the form’s version, school and field snapshot, from trusted data', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final receipt = await h.submit(e.form.id, e.answers, version: 1);
      expect(receipt.reference, matches(RegExp(r'^WF-[A-Z0-9]{8}$')));
      expect(receipt.duplicate, isFalse);
      final data = (await h.db.collection(FormCollections.submissions).doc(receipt.submissionId).get()).data()!;
      expect(data['formId'], e.form.id);
      expect(data['formVersion'], 1);
      expect(data['schoolId'], _school);
      expect(data['status'], 'new');
      expect(data['reference'], receipt.reference);
      expect(data['createdAt'], isA<Timestamp>());
      expect((data['fields'] as List).map((f) => (f as Map)['id']), e.form.fields.map((f) => f.id));
      expect((data['answers'] as Map)[e.form.fields[0].id], 'Asha Example');
    });

    test('a double submit stores one submission', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final key = FormIds.submissionKey();
      final first = await h.submit(e.form.id, e.answers, key: key);
      final again = await h.submit(e.form.id, e.answers, key: key);
      expect(again.duplicate, isTrue);
      expect(again.reference, first.reference);
      expect(await h.submissionCount(), 1);
      final other = await h.create('custom');
      await h.activate(other.id);
      await expectLater(h.submit(other.id, {other.fields.single.id: 'X'}, key: key), _refused(FormSubmissionErrorCode.badRequest), reason: 'a key can’t be reused for another form');
      await expectLater(h.submit(e.form.id, e.answers, key: 'short'), _refused(FormSubmissionErrorCode.badRequest));
    });

    test('drafts, inactive, changed, tampered or another school’s forms refuse submissions', () async {
      final h = _Harness();
      await h.setSubmissions(true);
      final draft = await h.create();
      await expectLater(h.submit(draft.id, {}), _refused(FormSubmissionErrorCode.notAvailable));
      await expectLater(h.submit('missing', {}), _refused(FormSubmissionErrorCode.notAvailable));

      final e = await h.activeEnquiry();
      await expectLater(h.submit(e.form.id, e.answers, version: 7), _refused(FormSubmissionErrorCode.formChanged));

      // A visitor copy that doesn't match the stored form is not trusted.
      await h.db.collection(FormCollections.publicForms).doc(e.form.id).update({'version': 5});
      await expectLater(h.submit(e.form.id, e.answers), _refused(FormSubmissionErrorCode.notAvailable));
      await h.activate(e.form.id);
      await h.db.collection(FormCollections.publicForms).doc(e.form.id).update({'schoolId': 'other_school'});
      await expectLater(h.submit(e.form.id, e.answers), _refused(FormSubmissionErrorCode.notAvailable));
      await h.db.collection(FormCollections.publicForms).doc(e.form.id).update({'schoolId': _school});
      await h.db.collection(FormCollections.forms).doc(e.form.id).update({'status': 'inactive'});
      await expectLater(h.submit(e.form.id, e.answers), _refused(FormSubmissionErrorCode.notAvailable));
      expect(await h.submissionCount(), 0);
    });

    test('invalid answers are refused with per-field reasons; nothing is stored', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final f = e.form.fields;
      final bad = {...e.answers, f[1].id: 'not-an-email', f[4].id: false, 'f_injected0': 'x'};
      await expectLater(
        h.submit(e.form.id, bad),
        throwsA(isA<FormSubmissionException>().having((x) => x.fieldErrors, 'errors', {f[1].id: FormAnswerError.email, f[4].id: FormAnswerError.required, '_form': FormAnswerError.invalid})),
      );
      expect(await h.submissionCount(), 0);
    });

    test('the honeypot marks spam', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final r = await h.submit(e.form.id, e.answers, honeypot: 'http://spam.example');
      expect((await h.db.collection(FormCollections.submissions).doc(r.submissionId).get()).data()!['status'], 'spam');
    });

    test('older responses stay readable after the form is edited and deactivated', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final r = await h.submit(e.form.id, e.answers);
      final edited = (await h.stored(e.form.id)).copyWith(fields: [e.form.fields[0].copyWith(label: const LocalizedText(en: 'Full name')), e.form.fields[1]]);
      await h.forms.saveDraft(requesterRole: 'admin', actor: _admin, form: edited);
      await h.activate(e.form.id);
      await h.forms.deactivate(requesterRole: 'admin', actor: _admin, formId: e.form.id);
      final s = await h.inbox.getSubmission(requesterRole: 'admin', submissionId: r.submissionId);
      expect(s.formVersion, 1);
      expect(s.fields.map((f) => f.label.en), ['Your name', 'Email', 'Phone', 'Your message', startsWith('I agree')]);
      expect(s.answerText(s.fields[4]), 'Yes');
      expect(s.answerText(s.fields[3]), 'Do you have places?');
    });

    test('the website writes submissions straight to Firestore, in the project the build uses', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(formSubmissionGatewayProvider), isA<DirectFirestoreSubmissionGateway>());
      expect((container.read(formSubmissionGatewayProvider) as DirectFirestoreSubmissionGateway).service.source, FormSubmissionSource.visitorCopy);
    });
  });

  group('direct submissions from a visitor’s browser', () {
    /// Rules like a visitor's under the proposal: the form's visitor copy,
    /// the setting's visitor copy and new submissions only; never the
    /// admins' definitions or the school's settings record.
    String visitorRules() => '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${FormCollections.publicForms}/{id} { allow read: if true; }
    match /${PublicSubmissionSettings.publicCollection}/{id} { allow read: if true; }
    match /${FormCollections.submissions}/{id} { allow read, write: if true; }
  }
}''';

    test('need only what a visitor can read, store the inbox’s shape, and check the school', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final other = await h.create('custom');
      await h.activate(other.id);
      await h.db.collection(FormCollections.publicForms).doc(other.id).update({'schoolId': 'other_school'});
      h.db.securityRules = FakeFirebaseFirestore(securityRules: visitorRules()).securityRules;
      await expectLater(h.db.collection(FormCollections.forms).doc(e.form.id).get(), throwsA(anything), reason: 'definitions stay private');
      await expectLater(h.db.collection(PublicSubmissionSettings.schoolSettingsCollection).doc(_school).get(), throwsA(anything), reason: 'so does the school’s record');

      final gateway = DirectFirestoreSubmissionGateway(firestore: h.db);
      final r = await gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey(), formVersion: 1));
      expect(r.reference, startsWith('WF-'));
      final stored = (await h.db.collection(FormCollections.submissions).doc(r.submissionId).get()).data()!;
      expect(stored.keys.toSet(), {'reference', 'formId', 'formVersion', 'formTitle', 'schoolId', 'fields', 'answers', 'status', 'createdAt', 'updatedAt'});
      expect((stored['formId'], stored['formVersion'], stored['schoolId'], stored['status']), (e.form.id, 1, _school, 'new'));
      expect(stored['fields'], [for (final f in e.form.fields) f.toMap()], reason: 'the version’s snapshot');

      await expectLater(
        gateway.submit(FormSubmissionRequest(formId: other.id, answers: {other.fields.single.id: 'X'}, submissionKey: FormIds.submissionKey())),
        _refused(FormSubmissionErrorCode.notAvailable),
      );
      await expectLater(
        gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: {...e.answers, e.form.fields[1].id: 'nope'}, submissionKey: FormIds.submissionKey())),
        _refused(FormSubmissionErrorCode.invalid),
      );
      await expectLater(
        gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: {...e.answers, e.form.fields[0].id: ''}, submissionKey: FormIds.submissionKey())),
        throwsA(isA<FormSubmissionException>().having((x) => x.fieldErrors[e.form.fields[0].id], 'name', FormAnswerError.required)),
        reason: 'required fields',
      );
      expect(await h.submissionCount(), 1);
    });

    test('are refused while off; the setting is checked again right before the write', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await h.setSubmissions(false);
      final gateway = DirectFirestoreSubmissionGateway(firestore: h.db);
      await expectLater(gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.unavailable));
      // A copy that isn't this school's, or is malformed: closed.
      await h.db.collection(PublicSubmissionSettings.publicCollection).doc(_school).set({'schoolId': 'other_school', 'submissionsOpen': true});
      await expectLater(gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.unavailable));
      await h.db.collection(PublicSubmissionSettings.publicCollection).doc(_school).set({'schoolId': _school, 'submissionsOpen': 'true'});
      await expectLater(gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.unavailable));
      await h.db.collection(PublicSubmissionSettings.publicCollection).doc(_school).delete();
      await expectLater(gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.unavailable));
      expect(await h.submissionCount(), 0);
    });

    // The fake doesn't apply rules to transactions, so a refused write is
    // simulated here; the emulator checks (test/emulator/) refuse real
    // writes with the proposed rules.
    test('a write Firestore refuses is reported as such, never as stored; permission-denied is told apart', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final gateway = DirectFirestoreSubmissionGateway(firestore: _RefusingFirestore(h.db, 'permission-denied'));
      await expectLater(gateway.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.permissionDenied));
      final offline = DirectFirestoreSubmissionGateway(firestore: _RefusingFirestore(h.db, 'unavailable'));
      await expectLater(offline.submit(FormSubmissionRequest(formId: e.form.id, answers: e.answers, submissionKey: FormIds.submissionKey())), _refused(FormSubmissionErrorCode.failed));
      expect(await h.submissionCount(), 0);
    });
  });

  group('local development', () {
    test('only a loopback emulator, never production', () {
      expect(FirestoreEmulatorConfig.parse(''), isNull);
      final local = FirestoreEmulatorConfig.parse('127.0.0.1:8086')!;
      expect((local.host, local.port), ('127.0.0.1', 8086));
      expect(FirestoreEmulatorConfig.parse('localhost:8080')!.host, 'localhost');
      for (final bad in ['example.com:8080', '10.0.0.5:8080', '127.0.0.1', '127.0.0.1:0', '127.0.0.1:99999', 'firestore.googleapis.com:443']) {
        expect(() => FirestoreEmulatorConfig.parse(bad), throwsStateError, reason: bad);
      }
      expect(() => FirestoreEmulatorConfig.parse('127.0.0.1:8086', target: DeployTarget.prod), throwsStateError, reason: 'a production build can’t be pointed anywhere else');
      expect(firestoreEmulator, isNull, reason: 'this build has no emulator setting: it uses its project (DEV)');
    });
  });

  group('public reads', () {
    test('only the visitor copy of an active form of this school is read', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final draft = await h.create('custom');
      await h.submit(e.form.id, e.answers);
      await h.db.collection(FormCollections.publicForms).doc('elsewhere').set({...(await h.publicDoc(e.form.id))!, 'formId': 'elsewhere', 'schoolId': 'other_school'});
      await h.db.collection(FormCollections.publicForms).doc('broken').set({'formId': 'broken', 'version': 1, 'schoolId': _school, 'fields': 'x'});
      h.db.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${FormCollections.publicForms}/{id} { allow read: if true; }
  }
}''').securityRules;
      await expectLater(h.db.collection(FormCollections.submissions).get(), throwsA(anything), reason: 'the rules really refuse it');
      await expectLater(h.db.collection(FormCollections.forms).doc(e.form.id).get(), throwsA(anything));

      final form = await h.public.activeForm(e.form.id);
      expect(form!.fields, e.form.fields);
      expect(await h.public.activeForm(draft.id), isNull, reason: 'never activated');
      expect(await h.public.activeForm('elsewhere'), isNull, reason: 'another school');
      expect(await h.public.activeForm('broken'), isNull, reason: 'malformed');
      expect((await h.public.activeForms()).map((f) => f.id), [e.form.id]);
    });
  });

  group('inbox', () {
    Future<(_Harness, List<String>)> withSubmissions() async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      final ids = [for (var i = 0; i < 3; i++) (await h.submit(e.form.id, {...e.answers, e.form.fields[0].id: 'Parent $i'})).submissionId];
      return (h, ids);
    }

    test('admins only', () async {
      final (h, ids) = await withSubmissions();
      for (final role in ['teacher', 'parent', 'staff', '']) {
        await expectLater(h.inbox.listSubmissions(requesterRole: role), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.inbox.getSubmission(requesterRole: role, submissionId: ids[0]), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.inbox.setStatus(requesterRole: role, actor: _admin, submissionId: ids[0], status: FormSubmissionStatus.closed), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.inbox.addNote(requesterRole: role, actor: _admin, submissionId: ids[0], text: 'x'), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.inbox.listNotes(requesterRole: role, submissionId: ids[0]), throwsA(isA<FormsUnauthorizedException>()));
      }
      expect((await h.inbox.getSubmission(requesterRole: 'admin', submissionId: ids[0])).status, FormSubmissionStatus.newSubmission, reason: 'unchanged');
    });

    test('another school’s submissions are never listed or changed', () async {
      final (h, _) = await withSubmissions();
      await h.db.collection(FormCollections.submissions).doc('theirs').set({'schoolId': 'other_school', 'formId': 'x', 'status': 'new', 'answers': {}});
      expect(await h.inbox.listSubmissions(requesterRole: 'admin'), hasLength(3));
      await expectLater(h.inbox.getSubmission(requesterRole: 'admin', submissionId: 'theirs'), throwsA(isA<FormsException>()));
      await expectLater(h.inbox.setStatus(requesterRole: 'admin', actor: _admin, submissionId: 'theirs', status: FormSubmissionStatus.spam), throwsA(isA<FormsException>()));
      await expectLater(h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: 'theirs', text: 'x'), throwsA(isA<FormsException>()));
      expect((await h.db.collection(FormCollections.submissions).doc('theirs').get()).data()!['status'], 'new');
    });

    test('status changes and internal notes, kept apart from the answers', () async {
      final (h, ids) = await withSubmissions();
      for (final status in FormSubmissionStatus.values) {
        await h.inbox.setStatus(requesterRole: 'admin', actor: _admin, submissionId: ids[0], status: status);
        expect((await h.inbox.getSubmission(requesterRole: 'admin', submissionId: ids[0])).status, status);
      }
      await h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: ids[0], text: '  $_privateNote  ');
      final notes = await h.inbox.listNotes(requesterRole: 'admin', submissionId: ids[0]);
      expect(notes.single.text, _privateNote);
      expect(notes.single.authorName, 'Test admin');
      await expectLater(h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: ids[0], text: '   '), throwsA(isA<FormsException>()));
      await expectLater(h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: ids[0], text: 'x' * 2001), throwsA(isA<FormsException>()));
      final doc = (await h.db.collection(FormCollections.submissions).doc(ids[0]).get()).data()!;
      expect(doc.toString(), isNot(contains(_privateNote)), reason: 'notes live in their own subcollection');
      expect((doc['answers'] as Map).length, 5, reason: 'answers untouched');
      for (final d in (await h.db.collection(FormCollections.publicForms).get()).docs) {
        expect(d.data().toString(), isNot(contains(_privateNote)));
      }
    });

    test('filters by form, status, date and search', () {
      FormSubmission s(String id, String form, FormSubmissionStatus status, DateTime at, String name) => FormSubmission(
            id: id,
            reference: formSubmissionReference(id),
            formId: form,
            formVersion: 1,
            formTitle: form == 'a' ? 'Admissions' : 'Contact',
            schoolId: _school,
            fields: [WebsiteFormField(id: 'f_name0000', type: FormFieldType.shortText, label: const LocalizedText(en: 'Name'))],
            answers: {'f_name0000': name},
            status: status,
            createdAt: at,
          );
      final all = [
        s('aaaa1111', 'a', FormSubmissionStatus.newSubmission, DateTime(2027, 1, 5), 'Asha'),
        s('bbbb2222', 'b', FormSubmissionStatus.closed, DateTime(2027, 1, 20), 'Ravi'),
        s('cccc3333', 'a', FormSubmissionStatus.spam, DateTime(2027, 2, 1), 'Meena'),
      ];
      List<String> ids(SubmissionsQuery q) => [for (final x in q.apply(all)) x.id];
      expect(ids(const SubmissionsQuery(formId: 'a')), ['aaaa1111', 'cccc3333']);
      expect(ids(const SubmissionsQuery(status: FormSubmissionStatus.closed)), ['bbbb2222']);
      expect(ids(SubmissionsQuery(from: DateTime(2027, 1, 10), to: DateTime(2027, 1, 31))), ['bbbb2222']);
      expect(ids(const SubmissionsQuery(search: 'meena')), ['cccc3333']);
      expect(ids(const SubmissionsQuery(search: 'WF-AAAA')), ['aaaa1111']);
    });

    test('CSV export: labels as submitted, safe cells, no internal notes', () async {
      final (h, ids) = await withSubmissions();
      await h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: ids[0], text: _privateNote);
      final e = await h.activeEnquiry();
      await h.submit(e.form.id, {...e.answers, e.form.fields[0].id: '=HYPERLINK("http://evil.example")', e.form.fields[3].id: 'He said "hello"'});
      final csv = FormSubmissionsInboxService.toCsv(await h.inbox.listSubmissions(requesterRole: 'admin'));
      final lines = csv.trim().split('\r\n');
      expect(lines.first, startsWith('"Reference","Submitted (UTC)","Form","Form version","Status"'));
      expect(lines, hasLength(5));
      expect(csv, contains('"\'=HYPERLINK(""http://evil.example"")"'), reason: 'formulas neutralised, quotes doubled');
      expect(csv, contains('"He said ""hello"""'));
      expect(csv, contains('"Yes"'));
      expect(csv, isNot(contains(_privateNote)));
    });
  });

  group('form block', () {
    test('stores only the form id and presentation; validates the choice', () {
      expect(BlockRegistry.definition('form'), same(BlockRegistry.form));
      final b = BlockRegistry.create(BlockRegistry.form);
      expect(BlockRegistry.blockProblems(b), contains('choose a form'));
      expect(BlockRegistry.blockProblems(b.withValue('formId', 'bad id!')), contains('the chosen form can’t be identified'));
      final ok = b.withValue('formId', 'form123').withValue('heading', const LocalizedText(en: 'Enquire'));
      expect(BlockRegistry.blockProblems(ok), isEmpty);
      final stored = BlockRegistry.toMapList([ok]).single! as Map;
      expect(stored.keys.toSet(), {'id', 'type', 'v', 'formId', 'heading', 'intro'});
      expect((BlockRegistry.parseList([stored]).single as StructuredBlock).string('formId'), 'form123');
      // No ready-made section: every preset must be valid as created, and
      // a Form block needs a form chosen first (Add block → Form).
      expect(SectionPreset.all.any((p) => p.id == 'form'), isFalse);
    });

    PublicWebsiteForm sample() => FormTemplate.byId('admission_enquiry')!.let((t) => WebsiteForm(
          id: 'form123',
          schoolId: _school,
          title: const LocalizedText(en: 'Admissions'),
          fields: t.buildFields(),
          successMessage: t.successMessage,
        ).toPublic(3));

    Future<void> pumpBlock(WidgetTester tester, {required double width, PublicWebsiteForm? form, bool interactive = true, FormSubmissionGateway? gateway, PublicSubmissionStatus status = _open}) async {
      tester.view.physicalSize = Size(width, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final block = BlockRegistry.create(BlockRegistry.form)
          .withValue('formId', 'form123')
          .withValue('heading', const LocalizedText(en: 'Enquire now'))
          .withValue('intro', const LocalizedText(en: 'We reply within two days.'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicWebsiteFormProvider.overrideWith((ref, id) async => id == 'form123' ? form : null),
          if (gateway != null) formSubmissionGatewayProvider.overrideWithValue(gateway),
          publicSubmissionStatusProvider.overrideWith((ref) => Stream.value(status)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WebsiteBlocksView(blocks: [block], media: const {}, language: PublicLanguage.english, interactive: interactive)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders every field type; pairs short fields on wide screens only', (tester) async {
      final form = sample();
      await pumpBlock(tester, width: 1200, form: form);
      expect(find.text('Enquire now'), findsOneWidget);
      expect(find.text('We reply within two days.'), findsOneWidget);
      for (final f in form.fields) {
        expect(find.byKey(Key('website-form-field-${f.id}')), findsOneWidget, reason: f.type!.id);
      }
      expect(find.byKey(Key('website-form-row-${form.fields[0].id}')), findsOneWidget, reason: 'name beside email');

      for (final width in [700.0, 360.0, 320.0]) {
        await pumpBlock(tester, width: width, form: form);
        expect(tester.takeException(), isNull, reason: 'no overflow at $width');
        expect(find.byKey(const Key('website-form-submit')), findsOneWidget);
      }
      expect(find.byKey(Key('website-form-row-${form.fields[0].id}')), findsNothing, reason: 'one column on phones');
    });

    testWidgets('a form that isn’t active shows visitors nothing; the editor says why', (tester) async {
      await pumpBlock(tester, width: 1000);
      expect(find.text('Enquire now'), findsNothing);
      expect(find.byKey(const Key('website-form-submit')), findsNothing);
      await pumpBlock(tester, width: 1000, interactive: false);
      expect(find.byKey(const Key('website-form-inactive-note')), findsOneWidget);
    });

    Future<void> fill(WidgetTester tester, PublicWebsiteForm form) async {
      final f = form.fields;
      await tester.enterText(find.byKey(Key('website-form-field-${f[0].id}')), 'Asha Example');
      await tester.enterText(find.byKey(Key('website-form-field-${f[1].id}')), 'asha@example.com');
      await tester.enterText(find.byKey(Key('website-form-field-${f[2].id}')), '9876543210');
      await tester.enterText(find.byKey(Key('website-form-field-${f[3].id}')), 'Kavin');
      await tester.enterText(find.byKey(Key('website-form-field-${f[4].id}')), '2023-04-01');
      await tester.ensureVisible(find.byKey(Key('website-form-field-${f[5].id}')));
      await tester.tap(find.byKey(Key('website-form-field-${f[5].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Primary').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('website-form-field-${f[7].id}')));
      await tester.tap(find.byKey(Key('website-form-field-${f[7].id}')));
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('website-form-submit')));
      await tester.tap(find.byKey(const Key('website-form-submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('required and invalid answers are explained before anything is sent', (tester) async {
      final gateway = _RecordingGateway();
      final form = sample();
      await pumpBlock(tester, width: 1000, form: form, gateway: gateway);
      await send(tester);
      expect(find.text('Please check the highlighted answers.'), findsOneWidget);
      expect(find.text('This is required.'), findsWidgets);
      await tester.enterText(find.byKey(Key('website-form-field-${form.fields[1].id}')), 'asha@');
      await send(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(gateway.requests, isEmpty);
    });

    testWidgets('submission through the trusted service: success, reference, one record per click', (tester) async {
      final h = _Harness();
      final created = await tester.runAsync(() async {
        final f = await h.create('admission_enquiry');
        await h.activate(f.id);
        return (await h.public.activeForm(f.id))!;
      });
      final gateway = _RecordingGateway(inner: TrustedServiceGateway(h.submissions));
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [formSubmissionGatewayProvider.overrideWithValue(gateway), publicSubmissionStatusProvider.overrideWith((ref) => h.public.submissionStatus())],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PublicWebsiteFormView(form: created!, language: PublicLanguage.english)))),
      ));
      await fill(tester, created);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('website-form-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('website-form-success')), findsOneWidget);
      expect(find.textContaining('Your reference: WF-'), findsOneWidget);
      expect(await tester.runAsync(h.submissionCount), 1);
      expect(gateway.requests.single.formVersion, 1);
    });

    testWidgets('Send is disabled while sending: a double click sends once', (tester) async {
      final form = sample();
      final gateway = _RecordingGateway(hold: true);
      await pumpBlock(tester, width: 1000, form: form, gateway: gateway);
      await fill(tester, form);
      await tester.ensureVisible(find.byKey(const Key('website-form-submit')));
      await tester.tap(find.byKey(const Key('website-form-submit')));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('website-form-submit')), warnIfMissed: false);
      await tester.pump();
      gateway.release();
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(1));
      expect(find.byKey(const Key('website-form-success')), findsOneWidget);
    });

    testWidgets('closed submissions are said up front with Send disabled; a failure is retried with the same key', (tester) async {
      final form = sample();
      // The school has public submissions switched off.
      await pumpBlock(tester, width: 1000, form: form, status: const PublicSubmissionStatus(schoolId: _school, open: false));
      expect(find.byKey(const Key('website-form-closed')), findsOneWidget, reason: 'before anything is pressed');
      expect(find.text('Online submissions aren’t open yet. Please contact the school directly.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('website-form-submit'))).onPressed, isNull);
      await fill(tester, form);
      expect(tester.widget<FilledButton>(find.byKey(const Key('website-form-submit'))).onPressed, isNull, reason: 'still disabled when filled in');

      // Switched on: no closed message, Send enabled (in every build).
      await pumpBlock(tester, width: 1000, form: form);
      expect(find.byKey(const Key('website-form-closed')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('website-form-submit'))).onPressed, isNotNull);
      await pumpBlock(tester, width: 1000, form: form, gateway: _RecordingGateway());
      expect(find.byKey(const Key('website-form-closed')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('website-form-submit'))).onPressed, isNotNull);

      final flaky = _RecordingGateway(failFirst: true);
      await pumpBlock(tester, width: 1000, form: form, gateway: flaky);
      await fill(tester, form);
      await send(tester);
      expect(find.text('Your response couldn’t be sent. Check your connection and try again.'), findsOneWidget);
      await send(tester);
      expect(find.byKey(const Key('website-form-success')), findsOneWidget);
      expect(flaky.requests.map((r) => r.submissionKey).toSet(), hasLength(1), reason: 'a retry can’t store a second submission');
    });

    testWidgets('the editor preview never sends', (tester) async {
      final gateway = _RecordingGateway();
      final form = sample();
      await pumpBlock(tester, width: 1000, form: form, interactive: false, gateway: gateway);
      await fill(tester, form);
      await send(tester);
      expect(find.text('Preview: responses aren’t sent from here.'), findsOneWidget);
      expect(gateway.requests, isEmpty);
    });

    testWidgets('the page editor chooses among active forms, and flags an inactive choice', (tester) async {
      final form = sample();
      WebsiteBlock? changed;
      Future<void> pumpEditor(StructuredBlock block) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(ProviderScope(
          overrides: [activeWebsiteFormsProvider.overrideWith((ref) async => [form])],
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: WebsiteBlockForm(block: block, library: const [], generation: 0, onChanged: (b) => changed = b))),
          ),
        ));
        await tester.pumpAndSettle();
      }

      final block = BlockRegistry.create(BlockRegistry.form);
      await pumpEditor(block);
      final key = 'website-block-${block.id}-formId';
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admissions').last);
      await tester.pumpAndSettle();
      expect((changed! as StructuredBlock).string('formId'), 'form123', reason: 'only the id is stored');

      await pumpEditor(block.withValue('formId', 'retired'));
      expect(find.byKey(Key('$key-inactive')), findsOneWidget);
    });

    testWidgets('Tamil visitors see Tamil labels and messages', (tester) async {
      final form = sample();
      final ta = PublicWebsiteForm(
        id: form.id,
        schoolId: form.schoolId,
        title: form.title,
        fields: [form.fields[0].copyWith(label: const LocalizedText(en: 'Name', ta: 'பெயர்'))],
        successMessage: form.successMessage,
        version: 3,
      );
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: PublicWebsiteFormView(form: ta, language: PublicLanguage.tamil)))));
      expect(find.text('பெயர் *'), findsOneWidget);
      expect(find.text('அனுப்பு'), findsOneWidget);
    });
  });

  group('admin screens', () {
    Future<void> pump(WidgetTester tester, _Harness h, {String role = 'admin', Widget? home}) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: _admin.id, phone: _admin.phone, role: role, isActive: true, name: 'Test admin'))],
        child: MaterialApp(home: home ?? FormsManagerScreen(forms: h.forms, inbox: h.inbox)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('locked for anyone but an admin', (tester) async {
      await pump(tester, _Harness(), role: 'teacher');
      expect(find.byKey(const Key('forms-tab-library')), findsNothing);
      expect(find.text('Website forms'), findsOneWidget);
    });

    testWidgets('Settings opens Website forms', (tester) async {
      final h = _Harness();
      await pump(tester, h, home: AdminSettingsScreen(formsService: h.forms, formsInbox: h.inbox));
      await tap(tester, 'settings-website-forms');
      expect(find.byKey(const Key('forms-tab-library')), findsOneWidget);
      expect(find.byKey(const Key('forms-tab-inbox')), findsOneWidget);
    });

    testWidgets('library: template, build, preview, save, activate, deactivate', (tester) async {
      final h = _Harness();
      await tester.runAsync(() => h.image(_coverId));
      await pump(tester, h);
      await tap(tester, 'forms-new');
      await tap(tester, 'forms-template-custom');
      expect(find.byKey(const Key('builder')), findsOneWidget);
      final id = (await tester.runAsync(() => h.forms.listForms(requesterRole: 'admin')))!.single.form.id;

      await tester.enterText(find.byKey(const Key('builder-title-en-1')), 'Open day sign-up');
      await tester.pump();
      expect(find.textContaining('Choose the form’s cover image'), findsWidgets, reason: 'a cover image is required');
      await tap(tester, 'builder-cover-choose');
      await tap(tester, 'website-choose-$_coverId');
      expect(find.text('Visitors see this image (Children in the garden).'), findsOneWidget);
      expect(find.byKey(const Key('builder-problems')), findsNothing);

      // Let the “Draft created” message go (it covers + Add).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-radio');
      expect(find.byKey(const Key('builder-problems')), findsOneWidget, reason: 'the new field has no label yet');
      expect(tester.widget<FilledButton>(find.byKey(const Key('builder-activate'))).onPressed, isNull);
      final radio = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey<String>?)?.value.endsWith('-label-en-1') == true && (w.key as ValueKey<String>).value.startsWith('builder-field-'));
      await tester.enterText(radio, 'Which session?');
      await tester.pump();
      expect(find.byKey(const Key('builder-problems')), findsNothing);

      await tap(tester, 'builder-preview');
      expect(find.byKey(const Key('forms-preview-dialog')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('forms-preview-dialog')), matching: find.text('Which session? (optional)')), findsOneWidget);
      await tap(tester, 'forms-preview-close');

      await tap(tester, 'builder-save');
      expect(await tester.runAsync(() => h.publicDoc(id)), isNull, reason: 'saving never publishes');
      await tap(tester, 'builder-activate');
      await tap(tester, 'forms-activate-confirm');
      final live = PublicWebsiteForm.tryParse(await tester.runAsync<Map<String, dynamic>?>(() => h.publicDoc(id)));
      expect(live!.title.en, 'Open day sign-up');
      expect(live.fields.map((f) => f.type), [FormFieldType.shortText, FormFieldType.radio]);
      expect(find.byKey(const Key('builder-deactivate')), findsOneWidget);
      await tap(tester, 'builder-deactivate');
      expect(await tester.runAsync(() => h.publicDoc(id)), isNull);
    });

    testWidgets('inbox: paginated list, detail, status and notes', (tester) async {
      final h = _Harness();
      await tester.runAsync(() async {
        final e = await h.activeEnquiry();
        for (var i = 0; i < 23; i++) {
          await h.submit(e.form.id, {...e.answers, e.form.fields[0].id: 'Parent $i'});
        }
      });
      await pump(tester, h);
      await tap(tester, 'forms-tab-inbox');
      expect(find.text('1–20 of 23'), findsOneWidget);
      await tap(tester, 'inbox-next');
      expect(find.text('21–23 of 23'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('inbox-search')), 'Parent 7');
      await tester.pumpAndSettle();
      expect(find.text('1–1 of 1'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is Card && (w.key as ValueKey<String>?)?.value.startsWith('inbox-row-') == true).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submission-detail')), findsOneWidget);
      expect(find.text('Parent 7'), findsOneWidget);
      await tester.tap(find.byKey(const Key('submission-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contacted').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('submission-note-input')), 'Rang back');
      await tap(tester, 'submission-note-add');
      expect(find.text('Rang back'), findsOneWidget);
      final all = await tester.runAsync(() => h.inbox.listSubmissions(requesterRole: 'admin'));
      expect(all!.where((s) => s.status == FormSubmissionStatus.contacted), hasLength(1));
    });
  });
}

/// Records what the form sends; optionally fails the first time, or
/// passes it on.
class _RecordingGateway implements FormSubmissionGateway {
  _RecordingGateway({this.inner, this.failFirst = false, bool hold = false}) : _hold = hold ? Completer<void>() : null;

  final FormSubmissionGateway? inner;
  bool failFirst;

  final Completer<void>? _hold;
  final requests = <FormSubmissionRequest>[];

  void release() => _hold?.complete();

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) async {
    requests.add(request);
    await _hold?.future;
    if (failFirst) {
      failFirst = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (inner case final g?) return g.submit(request);
    return FormSubmissionReceipt(submissionId: request.submissionKey, reference: formSubmissionReference(request.submissionKey));
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// [inner], except that running a transaction fails with Firestore error
/// [code].
class _RefusingFirestore extends Fake implements FirebaseFirestore {
  _RefusingFirestore(this.inner, this.code);

  final FirebaseFirestore inner;
  final String code;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => inner.collection(path);

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler, {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async =>
      throw FirebaseException(plugin: 'cloud_firestore', code: code);
}
