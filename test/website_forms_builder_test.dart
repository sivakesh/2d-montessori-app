// The visual Forms Manager: required title, description and cover image,
// content blocks (headings, text, images, dividers) anywhere in a form,
// field settings, document attachment fields (configurable, never
// uploadable yet), duplicate with fresh ids, version history, safe
// deletion that keeps every submission, media protection and the visual
// builder.
//
// Every record here is synthetic test data (no real students, parents or
// staff). The fake Firestore proves the app's behaviour, not deployed
// security rules (deferred).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/forms/data/form_submission_service.dart';
import 'package:montessori_app/modules/forms/data/form_submissions_inbox_service.dart';
import 'package:montessori_app/modules/forms/data/website_forms_service.dart';
import 'package:montessori_app/modules/admin/settings/data/public_submission_settings_service.dart';
import 'package:montessori_app/modules/forms/models/public_submission_settings.dart';
import 'package:montessori_app/modules/forms/models/website_form.dart';
import 'package:montessori_app/modules/forms/public/public_forms_repository.dart';
import 'package:montessori_app/modules/forms/ui/form_builder_screen.dart';
import 'package:montessori_app/modules/forms/ui/forms_manager_screen.dart';
import 'package:montessori_app/modules/forms/ui/public_website_form.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _cover = 'media_cover_0001';
const _photo = 'media_photo_0002';

class _UnusedFilePicker extends FilePicker {}

class _Harness {
  final db = FakeFirebaseFirestore();
  late final forms = WebsiteFormsService(firestore: db);
  late final inbox = FormSubmissionsInboxService(firestore: db);
  late final submissions = FormSubmissionService(firestore: db);
  late final settings = PublicSubmissionSettingsService(firestore: db);
  bool _opened = false;

  Future<void> image(String id, {String status = 'published', bool consent = true, String alt = 'Children reading', String url = 'https://storage.example.test/m.jpg'}) =>
      db.collection(WebsiteCollections.media).doc(id).set({
        'status': status,
        'consentConfirmed': consent,
        'url': url,
        'alt': {'en': alt},
        'storagePath': 'website_media/$id/x.jpg',
      });

  /// A General Enquiry with a cover image, saved.
  Future<WebsiteForm> create({String template = 'general_enquiry'}) async {
    await image(_cover);
    final form = await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: template);
    return save(form.copyWith(coverMediaId: () => _cover));
  }

  Future<WebsiteForm> save(WebsiteForm form) async {
    await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: form);
    return stored(form.id);
  }

  Future<WebsiteForm> stored(String id) async => (await forms.getForm(requesterRole: 'admin', formId: id))!.form;

  /// Activates form [id]; the first time, also switches public
  /// submissions on (off until an administrator does), as tests here send
  /// it.
  Future<PublicWebsiteForm> activate(String id) async {
    if (!_opened) {
      _opened = true;
      await settings.update(schoolId: 'default_school', requesterRole: 'admin', requesterSchoolId: 'default_school', actor: _admin, enabled: true, closedMessage: '', expectedRevision: 0);
    }
    return forms.activate(requesterRole: 'admin', actor: _admin, formId: id);
  }

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await db.collection(collection).doc(id).get()).data();

  Map<String, Object?> answers(WebsiteForm form) {
    final f = form.fields;
    return {f[0].id: 'Synthetic Parent', f[1].id: 'parent@example.com', f[3].id: 'A synthetic question', f[4].id: true};
  }

  Future<FormSubmissionReceipt> submit(WebsiteForm form, [Map<String, Object?>? answers]) =>
      submissions.submit(FormSubmissionRequest(formId: form.id, answers: answers ?? this.answers(form), submissionKey: FormIds.submissionKey()));
}

Matcher _refusedWith(String text) => throwsA(isA<FormsException>().having((e) => e.message, 'message', contains(text)));

void main() {
  group('required title, description and cover image', () {
    test('drafts may be incomplete; activation needs all three', () async {
      final h = _Harness();
      final form = await h.forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: 'custom');
      final saved = await h.save(form.copyWith(title: const LocalizedText(), description: const LocalizedText()));
      expect(saved.coverMediaId, isNull, reason: 'a draft saves without them');
      await expectLater(h.activate(form.id), _refusedWith('title'));
      await h.save(saved.copyWith(title: const LocalizedText(en: 'Open day')));
      await expectLater(h.activate(form.id), _refusedWith('description'));
      await h.save((await h.stored(form.id)).copyWith(description: const LocalizedText(en: 'Join us on Saturday.')));
      await expectLater(h.activate(form.id), _refusedWith('cover image'));
      await h.image(_cover);
      await h.save((await h.stored(form.id)).copyWith(coverMediaId: () => _cover));
      final live = await h.activate(form.id);
      expect((live.title.en, live.description.en, live.coverMediaId), ('Open day', 'Join us on Saturday.', _cover));
      final doc = (await h.doc(FormCollections.publicForms, form.id))!;
      expect(doc['coverMediaId'], _cover, reason: 'an id only, never a URL');
      expect(doc.toString(), isNot(contains('storage.example.test')));
    });

    test('only an image visitors may see can be used', () async {
      final h = _Harness();
      final form = await h.create();
      for (final (name, setUp, expected) in <(String, Future<void> Function(), String)>[
        ('missing', () => h.db.collection(WebsiteCollections.media).doc(_photo).delete(), 'no longer exists'),
        ('a draft', () => h.image(_photo, status: 'draft'), 'isn’t published'),
        ('hidden', () => h.image(_photo, status: 'hidden'), 'isn’t published'),
        ('consent withdrawn', () => h.image(_photo, consent: false), 'consent'),
        ('no file', () => h.image(_photo, url: ''), 'isn’t published'),
        ('no alt text', () => h.image(_photo, alt: ''), 'alt text'),
      ]) {
        await setUp();
        await h.save(form.copyWith(coverMediaId: () => _photo));
        await expectLater(h.activate(form.id), _refusedWith(expected), reason: name);
      }
      expect(await h.doc(FormCollections.publicForms, form.id), isNull);
      // An image block is checked the same way.
      final block = FormContentBlock.create(FormBlockType.image).copyWith(mediaId: _photo);
      await h.save(form.copyWith(coverMediaId: () => _cover, items: [...form.items, block]));
      await expectLater(h.activate(form.id), _refusedWith('alt text'));
      await h.save((await h.stored(form.id)).copyWith(items: form.items));
      await expectLater(h.save(form.copyWith(coverMediaId: () => 'not an id/../x')), _refusedWith('can’t be identified'), reason: 'ids only, never paths or URLs');
    });

    test('a published image that later disappears: visitors see the form without it, and the admin is warned', () async {
      final h = _Harness();
      final form = await h.create();
      await h.activate(form.id);
      final live = PublicWebsiteForm.tryParse(await h.doc(FormCollections.publicForms, form.id))!;
      expect(live.coverMediaId, _cover, reason: 'the copy still names it');
      expect(WebsiteFormsService.imageProblem(null, what: 'cover image'), contains('no longer exists'));
      final hidden = WebsiteMedia.fromMap(_cover, {'status': 'hidden', 'consentConfirmed': true, 'url': 'x', 'alt': {'en': 'a'}});
      expect(WebsiteFormsService.imageProblem(hidden), contains('isn’t published'));
    });
  });

  group('content blocks and stable ids', () {
    test('insert, move, edit and remove content anywhere; ids never change', () async {
      final h = _Harness();
      final form = await h.create();
      final heading = FormContentBlock.create(FormBlockType.heading).copyWith(title: const LocalizedText(en: 'About you'), body: const LocalizedText(en: 'So we can reply.'));
      final photo = FormContentBlock.create(FormBlockType.image).copyWith(mediaId: _photo, body: const LocalizedText(en: 'Our garden'));
      final divider = FormContentBlock.create(FormBlockType.divider);
      final note = FormContentBlock.create(FormBlockType.text).copyWith(body: const LocalizedText(en: 'Fields marked * are required.'));
      final f = form.fields;
      await h.image(_photo);
      var saved = await h.save(form.copyWith(items: [heading, f[0], photo, f[1], f[2], divider, f[3], note, f[4]]));
      expect(saved.items.map((i) => i.id), [heading.id, f[0].id, photo.id, f[1].id, f[2].id, divider.id, f[3].id, note.id, f[4].id]);
      expect(saved.fields.map((x) => x.id), f.map((x) => x.id), reason: 'the questions, in order');
      final stored = (await h.doc(FormCollections.forms, form.id))!;
      expect((stored['fields'] as List).length, 5, reason: 'questions are also stored alone, for older readers');
      expect(stored['mediaIds'], unorderedEquals([_cover, _photo]));

      // Move the image to the end and edit the heading: same ids.
      saved = await h.save(saved.copyWith(items: [...saved.items.where((i) => i.id != photo.id), saved.items[2]]));
      saved = await h.save(saved.copyWith(items: [for (final i in saved.items) i.id == heading.id ? (i as FormContentBlock).copyWith(title: const LocalizedText(en: 'Your details')) : i]));
      expect(saved.items.last.id, photo.id);
      expect((saved.items.first as FormContentBlock).title.en, 'Your details');
      expect(saved.items.first.id, heading.id);

      // Remove the divider.
      saved = await h.save(saved.copyWith(items: [for (final i in saved.items) if (i.id != divider.id) i]));
      expect(saved.items.any((i) => i.id == divider.id), isFalse);

      final live = await h.activate(form.id);
      expect(live.items.map((i) => i.id), saved.items.map((i) => i.id));
      final doc = (await h.doc(FormCollections.publicForms, form.id))!;
      expect(doc.keys.toSet(), PublicWebsiteForm.storedFields.difference({'activatedAt'}).union({'activatedAt'}));
      expect(PublicWebsiteForm.tryParse(doc)!.sameSchemaAs(live), isTrue);
    });

    test('content needs its text or image before activation; unknown content is refused', () async {
      List<String> problems(FormContentBlock b) => b.problems(complete: true);
      expect(problems(FormContentBlock.create(FormBlockType.heading)), contains('enter the heading in English'));
      expect(problems(FormContentBlock.create(FormBlockType.text)), contains('enter the text in English'));
      expect(problems(FormContentBlock.create(FormBlockType.image)), contains('choose its image'));
      expect(problems(FormContentBlock.create(FormBlockType.divider)), isEmpty);
      final unknown = FormItem.fromMap({'kind': 'content', 'id': 'c_abcdefgh', 'type': 'video'});
      expect(unknown.problems(complete: false).join(), contains('isn’t supported'));
      expect(FormContentBlock.create(FormBlockType.heading).copyWith(title: LocalizedText(en: 'x' * 121)).problems(complete: false).join(), contains('120'));
    });

    test('earlier submissions keep their snapshot when content is added and questions move', () async {
      final h = _Harness();
      final form = await h.create();
      await h.activate(form.id);
      final r = await h.submit(form);
      final moved = await h.save(form.copyWith(items: [FormContentBlock.create(FormBlockType.divider), ...form.items.reversed]));
      await h.activate(form.id);
      final s = await h.inbox.getSubmission(requesterRole: 'admin', submissionId: r.submissionId);
      expect(s.formVersion, 1);
      expect(s.fields.map((f) => f.id), form.fields.map((f) => f.id), reason: 'the order and questions as answered');
      expect(s.answerText(s.fields[0]), 'Synthetic Parent');
      expect(moved.fields.map((f) => f.id).toSet(), form.fields.map((f) => f.id).toSet(), reason: 'moving never changes ids');
      final data = (await h.doc(FormCollections.submissions, r.submissionId))!;
      expect((data['fields'] as List).every((f) => (f as Map)['kind'] == null), isTrue, reason: 'questions only, no content');
    });

    test('visitor copies saved before content blocks still work; inconsistent ones are refused', () {
      final f = WebsiteFormField.create(FormFieldType.shortText, 'Name', required: true);
      final old = {
        'formId': 'old_form',
        'schoolId': 'default_school',
        'title': {'en': 'Old form'},
        'fields': [f.toMap()],
        'successMessage': {'en': 'Thanks'},
        'version': 2,
      };
      final parsed = PublicWebsiteForm.tryParse(old)!;
      expect(parsed.items.single.id, f.id);
      expect(parsed.coverMediaId, isNull, reason: 'shown without a cover');
      final other = WebsiteFormField.create(FormFieldType.email, 'Email');
      expect(PublicWebsiteForm.tryParse({...old, 'items': [other.toMap()]}), isNull, reason: 'items and fields must agree');
    });
  });

  group('field settings and validation', () {
    final short = WebsiteFormField.create(FormFieldType.shortText, 'Name', required: true).copyWith(minLength: () => 3, maxLength: () => 10);
    final age = WebsiteFormField.create(FormFieldType.number, 'Age').copyWith(min: () => 2, max: () => 12);
    final start = WebsiteFormField.create(FormFieldType.date, 'Start date').copyWith(minDate: () => '2027-06-01', maxDate: () => '2027-08-31');
    final fields = [short, age, start];

    test('lengths, numbers and dates', () {
      Map<String, FormAnswerError> errors(Map<String, Object?> a) => validateFormAnswers(fields, a).errors;
      expect(errors({short.id: 'Al'})[short.id], FormAnswerError.tooShort);
      expect(errors({short.id: 'Alexander the Great'})[short.id], FormAnswerError.tooLong);
      expect(errors({short.id: 'Asha'}), isEmpty);
      for (final (v, e) in [('two', FormAnswerError.number), ('1e3', FormAnswerError.number), ('1', FormAnswerError.outOfRange), ('13', FormAnswerError.outOfRange)]) {
        expect(errors({short.id: 'Asha', age.id: v})[age.id], e, reason: v);
      }
      expect(errors({short.id: 'Asha', age.id: '4.5'}), isEmpty);
      expect(errors({short.id: 'Asha', start.id: '2027-05-31'})[start.id], FormAnswerError.outOfRange);
      expect(errors({short.id: 'Asha', start.id: '2027-07-15'}), isEmpty);
    });

    test('settings that contradict themselves are refused', () {
      List<String> p(WebsiteFormField f) => f.problems(complete: true);
      expect(p(short.copyWith(minLength: () => 11)).join(), contains('minimum length is more than the maximum'));
      expect(p(short.copyWith(maxLength: () => 500)).join(), contains('between 1 and 200'));
      expect(p(age.copyWith(min: () => 20)).join(), contains('smallest value is more than the largest'));
      expect(p(start.copyWith(minDate: () => '2027-09-01')).join(), contains('earliest date is after the latest'));
      expect(p(start.copyWith(maxDate: () => '31/08/2027')).join(), contains('YYYY-MM-DD'));
      expect(p(WebsiteFormField.create(FormFieldType.email, 'Email').copyWith(minLength: () => 3)).join(), contains('only short and long text'));
      expect(WebsiteFormField.fromMap({'id': 'f_abcdefgh', 'type': 'number', 'label': {'en': 'Age'}, 'min': 'two'}).problems(complete: false).join(), contains('can’t be read'));
    });

    testWidgets('help text and custom error messages are shown; required fields are marked', (tester) async {
      final email = WebsiteFormField.create(FormFieldType.email, 'Email', required: true)
          .copyWith(helpText: const LocalizedText(en: 'We only use it to reply.'), errorMessage: const LocalizedText(en: 'Please give an email we can reply to.'));
      final form = PublicWebsiteForm(id: 'f1', schoolId: 'default_school', title: const LocalizedText(en: 'Contact'), items: [email, age], successMessage: const LocalizedText(en: 'Thanks'), version: 1);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formSubmissionGatewayProvider.overrideWithValue(TrustedServiceGateway(FormSubmissionService(firestore: FakeFirebaseFirestore()))),
          publicSubmissionStatusProvider.overrideWith((ref) => Stream.value(const PublicSubmissionStatus(schoolId: 'default_school', open: true))),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PublicWebsiteFormView(form: form, language: PublicLanguage.english, media: const {})))),
      ));
      expect(find.text('We only use it to reply.'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      expect(find.text('Age (optional)'), findsOneWidget);
      await tester.enterText(find.byKey(Key('website-form-field-${email.id}')), 'nope');
      await tester.enterText(find.byKey(Key('website-form-field-${age.id}')), '40');
      await tester.tap(find.byKey(const Key('website-form-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Please give an email we can reply to.'), findsOneWidget);
      expect(find.text('This is outside the accepted range.'), findsOneWidget);
    });
  });

  group('document attachment fields', () {
    final doc = WebsiteFormField.create(FormFieldType.attachment, 'Birth certificate', required: true).copyWith(allowedFileTypes: ['pdf', 'jpg'], maxFileSizeMb: 4, maxFiles: 2);

    test('configured and validated, but visitors can’t upload', () {
      expect(FormAttachments.publicUploadsEnabled, isFalse);
      expect(doc.problems(complete: true), isEmpty);
      expect(doc.toMap(), containsPair('allowedFileTypes', ['pdf', 'jpg']));
      expect(FormAttachments.mimeTypesFor(doc.allowedFileTypes), ['application/pdf', 'image/jpeg']);
      expect(doc.copyWith(allowedFileTypes: ['exe']).problems(complete: true).join(), contains('isn’t supported'));
      expect(doc.copyWith(allowedFileTypes: []).problems(complete: true).join(), contains('at least one file type'));
      expect(doc.copyWith(maxFileSizeMb: 50).problems(complete: true).join(), contains('1 to 10 MB'));
      expect(doc.copyWith(maxFiles: 9).problems(complete: true).join(), contains('1 to 5 files'));
      // Never required while uploads are off; any answer is refused.
      expect(validateFormAnswers([doc], {}).errors, isEmpty);
      expect(validateFormAnswers([doc], {doc.id: 'https://files.example.test/x.pdf'}).errors[doc.id], FormAnswerError.invalid);
    });

    testWidgets('shown disabled to visitors, with its limits', (tester) async {
      final form = PublicWebsiteForm(id: 'f1', schoolId: 'default_school', title: const LocalizedText(en: 'Admissions'), items: [doc], successMessage: const LocalizedText(en: 'Thanks'), version: 1);
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: PublicWebsiteFormView(form: form, language: PublicLanguage.english, media: const {})))));
      expect(find.byKey(Key('website-form-attachment-${doc.id}')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(Key('website-form-attachment-${doc.id}')), matching: find.byType(OutlinedButton))).onPressed, isNull);
      expect(find.text('PDF, JPG · up to 4 MB · up to 2 files'), findsOneWidget);
      expect(find.byKey(Key('website-form-attachment-note-${doc.id}')), findsOneWidget);
    });

    test('a removed attachment field leaves earlier submissions readable', () async {
      final h = _Harness();
      final form = await h.create();
      final withDoc = await h.save(form.copyWith(items: [...form.items, doc]));
      await h.activate(form.id);
      final r = await h.submit(withDoc);
      await h.save(withDoc.copyWith(items: form.items));
      await h.activate(form.id);
      final s = await h.inbox.getSubmission(requesterRole: 'admin', submissionId: r.submissionId);
      expect(s.fields.last.type, FormFieldType.attachment);
      expect(s.answerText(s.fields.last), '');
      expect(FormSubmissionsInboxService.toCsv([s]), contains('Birth certificate'));
    });
  });

  group('duplicate and version history', () {
    test('a duplicate has fresh form, field, option and content ids', () async {
      final h = _Harness();
      final form = await h.create(template: 'admission_enquiry');
      final withContent = await h.save(form.copyWith(items: [FormContentBlock.create(FormBlockType.heading).copyWith(title: const LocalizedText(en: 'Child')), ...form.items]));
      final copy = await h.stored((await h.forms.duplicate(requesterRole: 'admin', actor: _admin, formId: form.id)).id);
      Set<String> ids(WebsiteForm f) => {f.id, for (final i in f.items) i.id, for (final x in f.fields) for (final o in x.options) o.id};
      expect(ids(copy).intersection(ids(withContent)), isEmpty);
      expect(copy.items.map((i) => i.displayLabel), withContent.items.map((i) => i.displayLabel));
      expect((copy.coverMediaId, copy.description, copy.status, copy.version), (_cover, withContent.description, WebsiteFormStatus.draft, 0));
    });

    test('each changed activation is recorded, never an unchanged one', () async {
      final h = _Harness();
      final form = await h.create();
      await h.activate(form.id);
      await h.activate(form.id);
      await h.save(form.copyWith(title: const LocalizedText(en: 'Write to us')));
      await h.activate(form.id);
      final history = await h.forms.versionHistory(requesterRole: 'admin', formId: form.id);
      expect(history.map((v) => (v.version, v.title)), [(2, 'Write to us'), (1, 'General Enquiry')]);
      expect(history.first.activatedByName, 'Test admin');
      await expectLater(h.forms.versionHistory(requesterRole: 'teacher', formId: form.id), throwsA(isA<FormsUnauthorizedException>()));
    });
  });

  group('deleting a form', () {
    test('takes it off the website and keeps every submission, note and version', () async {
      final h = _Harness();
      final form = await h.create();
      await h.activate(form.id);
      final r = await h.submit(form);
      await h.inbox.addNote(requesterRole: 'admin', actor: _admin, submissionId: r.submissionId, text: 'Synthetic follow-up');
      await expectLater(
        h.forms.deleteForm(requesterRole: 'admin', actor: _admin, formId: form.id, confirmTitle: 'general enquiry'),
        _refusedWith('Type the form’s title'),
      );
      expect(await h.doc(FormCollections.forms, form.id), isNotNull, reason: 'nothing deleted without the exact title');

      await h.forms.deleteForm(requesterRole: 'admin', actor: _admin, formId: form.id, confirmTitle: 'General Enquiry');
      expect(await h.doc(FormCollections.forms, form.id), isNull);
      expect(await h.doc(FormCollections.publicForms, form.id), isNull);
      final tombstone = (await h.doc(FormCollections.deletedForms, form.id))!;
      expect((tombstone['schoolId'], tombstone['version'], (tombstone['title'] as Map)['en']), ('default_school', 1, 'General Enquiry'));
      expect((tombstone['fields'] as List).length, form.fields.length);
      expect(tombstone['deletedByName'], 'Test admin');

      final s = await h.inbox.getSubmission(requesterRole: 'admin', submissionId: r.submissionId);
      expect(s.answerText(s.fields.first), 'Synthetic Parent');
      expect((await h.inbox.listNotes(requesterRole: 'admin', submissionId: r.submissionId)).single.text, 'Synthetic follow-up');
      expect(SubmissionsQuery(search: 'synthetic parent').apply(await h.inbox.listSubmissions(requesterRole: 'admin')).single.id, r.submissionId);
      expect((await h.forms.deletedForms(requesterRole: 'admin')).single.formId, form.id);
      expect(await h.forms.versionHistory(requesterRole: 'admin', formId: form.id), hasLength(1), reason: 'version records are kept');
      expect((await h.db.collection(WebsiteCollections.media).doc(_cover).get()).exists, isTrue, reason: 'images are never removed');
      await expectLater(h.submit(form), throwsA(isA<FormSubmissionException>()), reason: 'no new submissions');

      // Retrying is safe.
      await h.forms.deleteForm(requesterRole: 'admin', actor: _admin, formId: form.id, confirmTitle: 'General Enquiry');
    });

    test('if the visitor copy can’t be removed, nothing is deleted', () async {
      final h = _Harness();
      final form = await h.create();
      await h.activate(form.id);
      h.db.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${FormCollections.forms}/{id} { allow read, write: if true; }
    match /${FormCollections.deletedForms}/{id} { allow read, write: if true; }
    match /${FormCollections.publicForms}/{id} { allow read: if true; }
  }
}''').securityRules;
      await expectLater(
        h.forms.deleteForm(requesterRole: 'admin', actor: _admin, formId: form.id, confirmTitle: 'General Enquiry'),
        _refusedWith('couldn’t be taken off the website, so it wasn’t deleted'),
      );
      expect(await h.doc(FormCollections.forms, form.id), isNotNull);
      expect(await h.doc(FormCollections.publicForms, form.id), isNotNull);
      expect(await h.doc(FormCollections.deletedForms, form.id), isNull);
    });

    test('pages showing it are reported; another school or role can’t delete it', () async {
      final h = _Harness();
      final form = await h.create();
      final block = BlockRegistry.create(BlockRegistry.form).withValue('formId', form.id);
      await h.db.collection(WebsiteCollections.livePages).doc('admissions').set({'schemaVersion': 2, 'blocks': BlockRegistry.toMapList([block])});
      await h.db.collection(WebsiteCollections.pageDrafts).doc('page1').set({
        'kind': 'custom',
        'slug': 'open-day',
        'title': {'en': 'Open day'},
        'schemaVersion': 2,
        'blocks': BlockRegistry.toMapList([block]),
      });
      expect(await h.forms.formReferences(requesterRole: 'admin', formId: form.id), {'the Admissions page (published)', 'the “Open day” page (draft)'});
      expect(await h.forms.formReferences(requesterRole: 'admin', formId: 'other'), isEmpty);
      await expectLater(h.forms.deleteForm(requesterRole: 'teacher', actor: _admin, formId: form.id, confirmTitle: 'General Enquiry'), throwsA(isA<FormsUnauthorizedException>()));
      await h.db.collection(FormCollections.forms).doc(form.id).update({'schoolId': 'other_school'});
      await expectLater(h.forms.deleteForm(requesterRole: 'admin', actor: _admin, formId: form.id, confirmTitle: 'General Enquiry'), _refusedWith('no longer exists'));
      expect(await h.doc(FormCollections.forms, form.id), isNotNull);
    });

    testWidgets('the library asks for the title, lists pages showing it, and the inbox marks the deleted form', (tester) async {
      final h = _Harness();
      late WebsiteForm form;
      await tester.runAsync(() async {
        form = await h.create();
        await h.activate(form.id);
        await h.submit(form);
        final block = BlockRegistry.create(BlockRegistry.form).withValue('formId', form.id);
        await h.db.collection(WebsiteCollections.livePages).doc('admissions').set({'schemaVersion': 2, 'blocks': BlockRegistry.toMapList([block])});
      });
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: FormsManagerScreen(forms: h.forms, inbox: h.inbox)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('forms-delete-${form.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forms-delete-dialog')), findsOneWidget);
      expect(find.textContaining('the Admissions page (published)'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('forms-delete-confirm'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('forms-delete-confirm-input')), 'General Enquiry');
      await tester.pump();
      await tester.tap(find.byKey(const Key('forms-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('forms-card-${form.id}')), findsNothing);
      expect(await tester.runAsync(() => h.doc(FormCollections.forms, form.id)), isNull);

      await tester.tap(find.byKey(const Key('forms-tab-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('Form deleted'), findsOneWidget);
      expect(find.textContaining('General Enquiry'), findsWidgets, reason: 'still readable and searchable');
    });
  });

  group('forms saved with Tamil text', () {
    test('still load, save, duplicate, activate and render; their Tamil is kept, never required', () async {
      final h = _Harness();
      final form = await h.create();
      // As saved before editing became English only.
      final f = form.fields;
      await h.db.collection(FormCollections.forms).doc(form.id).update({
        'title': {'en': 'General Enquiry', 'ta': 'பொது விசாரணை'},
        'items': [
          {...f[0].toMap(), 'label': {'en': 'Your name', 'ta': 'உங்கள் பெயர்'}},
          for (final x in f.skip(1)) x.toMap(),
        ],
      });
      final stored = await h.stored(form.id);
      expect(stored.title.ta, 'பொது விசாரணை');
      expect(stored.problems(complete: true), isEmpty);
      final edited = await h.save(stored.copyWith(title: stored.title.withText('en', 'Ask us anything')));
      expect((edited.title.en, edited.title.ta), ('Ask us anything', 'பொது விசாரணை'), reason: 'editing English keeps the Tamil');
      expect(edited.fields.first.label.ta, 'உங்கள் பெயர்');
      final live = await h.activate(form.id);
      expect(live.fields.first.label.resolve(PublicLanguage.english), 'Your name');
      final copy = await h.stored((await h.forms.duplicate(requesterRole: 'admin', actor: _admin, formId: form.id)).id);
      expect(copy.fields.first.label.ta, 'உங்கள் பெயர்');

      // A new form never needs Tamil.
      final fresh = await h.create(template: 'event_registration');
      expect([for (final i in fresh.items) ...i.toMap().values.whereType<Map>().map((m) => m['ta'] ?? '')].every((t) => t == ''), isTrue);
      expect((await h.activate(fresh.id)).version, 1);
    });
  });

  group('media protection', () {
    test('an image a form uses can’t be deleted; one an active form shows can’t be hidden', () async {
      final h = _Harness();
      final media = WebsiteContentAdminService(firestore: h.db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
      final form = await h.create();
      await expectLater(media.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: _cover), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'm', contains('“General Enquiry” form'))));
      await media.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: _cover);
      await h.image(_cover);
      await h.activate(form.id);
      await expectLater(media.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: _cover), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'm', contains('active'))));
      expect((await h.doc(WebsiteCollections.media, _cover))!['status'], 'published');
    });
  });

  group('school isolation and access', () {
    test('every new operation is admin-only and school-scoped', () async {
      final h = _Harness();
      final form = await h.create();
      for (final role in ['teacher', 'parent', '']) {
        await expectLater(h.forms.mediaLibrary(requesterRole: role), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.formReferences(requesterRole: role, formId: form.id), throwsA(isA<FormsUnauthorizedException>()));
        await expectLater(h.forms.deletedForms(requesterRole: role), throwsA(isA<FormsUnauthorizedException>()));
      }
      await h.db.collection(FormCollections.deletedForms).doc('theirs').set({'schoolId': 'other_school', 'title': {'en': 'Theirs'}});
      expect(await h.forms.deletedForms(requesterRole: 'admin'), isEmpty);
      await h.db.collection(FormCollections.versions).doc('theirs_v1').set({'formId': form.id, 'schoolId': 'other_school', 'version': 9});
      expect(await h.forms.versionHistory(requesterRole: 'admin', formId: form.id), isEmpty);
    });

    test('every build writes submissions directly to its own project’s Firestore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(formSubmissionGatewayProvider), isA<DirectFirestoreSubmissionGateway>());
    });
  });

  group('visual builder', () {
    Future<_Harness> open(WidgetTester tester, {double width = 1400, void Function(_Harness h)? setUp}) async {
      final h = _Harness();
      late WebsiteForm form;
      await tester.runAsync(() async {
        form = await h.create();
        await h.image(_photo);
      });
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-builder'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FormBuilderScreen(service: h.forms, user: _admin, formId: form.id))),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open-builder')));
      await tester.pumpAndSettle();
      return h;
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    List<String> structure(WidgetTester tester) => [
          for (final e in find.byWidgetPredicate((w) => w is InkWell && (w.key as ValueKey<String>?)?.value.startsWith('form-structure-') == true).evaluate())
            ((e.widget.key as ValueKey<String>).value).substring('form-structure-'.length),
        ];

    testWidgets('three panels; content inserted after the selection, moved and removed; ids kept', (tester) async {
      final h = await open(tester);
      expect(find.byKey(const Key('builder-structure')), findsOneWidget);
      expect(find.byKey(const Key('form-builder-canvas')), findsOneWidget);
      expect(find.byKey(const Key('builder-properties')), findsOneWidget);
      final before = structure(tester);
      expect(before, hasLength(5));

      // Select the first question on the canvas, then add a heading after it.
      await tap(tester, 'form-canvas-item-${before[0]}');
      expect(find.text('Short text'), findsWidgets, reason: 'its settings are shown');
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-content-heading');
      final withHeading = structure(tester);
      expect(withHeading, hasLength(6));
      final heading = withHeading[1];
      expect(heading, startsWith('c_'));
      await tester.enterText(find.byKey(Key('builder-content-$heading-title-en-1')), 'About you');
      await tester.pump();
      expect(find.descendant(of: find.byKey(const Key('form-builder-canvas')), matching: find.text('About you')), findsOneWidget, reason: 'the canvas updates live');
      expect(find.byKey(const Key('builder-unsaved')), findsOneWidget);

      // An image between questions.
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-content-image');
      final image = structure(tester)[2];
      await tap(tester, 'builder-content-$image-image-choose');
      await tap(tester, 'website-choose-$_photo');
      expect(find.byKey(Key('website-form-content-$image')), findsOneWidget);

      // Move the heading down, then remove it.
      await tap(tester, 'form-structure-$heading-menu');
      await tap(tester, 'form-structure-$heading-down');
      expect(structure(tester).indexOf(heading), 2);
      await tap(tester, 'builder-save');
      final saved = (await tester.runAsync(() => h.forms.listForms(requesterRole: 'admin')))!.single.form;
      expect(saved.items[2].id, heading, reason: 'saved where it was moved, with the same id');
      expect((saved.items[2] as FormContentBlock).title.en, 'About you');
      expect(find.byKey(const Key('builder-unsaved')), findsNothing);
      await tap(tester, 'form-structure-$heading-menu');
      await tap(tester, 'form-structure-$heading-remove');
      await tap(tester, 'builder-remove-confirm');
      expect(structure(tester).contains(heading), isFalse);
      expect(structure(tester).where((id) => before.contains(id)), before, reason: 'questions keep their ids and order');
    });

    testWidgets('English only: no Tamil field anywhere in the builder', (tester) async {
      await open(tester);
      bool tamil(Widget w) =>
          (w is TextFormField && (w.key as ValueKey?)?.value.toString().contains('-ta-') == true) || (w is Text && (w.data ?? '').contains('Tamil'));
      expect(find.byWidgetPredicate(tamil), findsNothing, reason: 'form settings');
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-dropdown');
      expect(find.byWidgetPredicate(tamil), findsNothing, reason: 'a question');
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-content-heading');
      expect(find.byWidgetPredicate(tamil), findsNothing, reason: 'a section heading');
      expect(find.text('Title'), findsNothing, reason: 'labels say what, not which language');
    });

    testWidgets('leaving with unsaved edits asks first', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('builder-title-en-1')), 'Changed');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('builder-leave-dialog')), findsOneWidget);
      await tap(tester, 'builder-leave-cancel');
      expect(find.byKey(const Key('builder-structure')), findsOneWidget, reason: 'still editing');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'builder-leave-confirm');
      expect(find.byKey(const Key('open-builder')), findsOneWidget);
    });

    testWidgets('device widths, and one panel at a time on a phone', (tester) async {
      await open(tester);
      double canvasWidth() => tester.getSize(find.byKey(const Key('form-builder-canvas'))).width;
      expect(canvasWidth(), lessThanOrEqualTo(960));
      await tap(tester, 'builder-device-phone');
      expect(canvasWidth(), 390);
      await tap(tester, 'builder-device-tablet');
      expect(canvasWidth(), 768);
      await tap(tester, 'builder-preview');
      await tap(tester, 'forms-preview-device-phone');
      expect(tester.getSize(find.byKey(const Key('forms-preview-frame-phone'))).width, 390);
      await tap(tester, 'forms-preview-close');

      await open(tester, width: 600);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('builder-tab-canvas')), findsOneWidget);
      expect(find.byKey(const Key('builder-structure')), findsNothing);
      await tap(tester, 'builder-tab-structure');
      expect(find.byKey(const Key('builder-structure')), findsOneWidget);
      await tap(tester, 'builder-tab-edit');
      expect(find.byKey(const Key('builder-properties')), findsOneWidget);
    });

    testWidgets('a form with content renders at 320 px without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = FormTemplate.byId('admission_enquiry')!.buildFields();
      final form = PublicWebsiteForm(
        id: 'f1',
        schoolId: 'default_school',
        title: const LocalizedText(en: 'Admissions'),
        description: const LocalizedText(en: 'Tell us about your child.'),
        coverMediaId: _cover,
        items: [FormContentBlock.create(FormBlockType.heading).copyWith(title: const LocalizedText(en: 'Parent')), ...f.take(3), FormContentBlock.create(FormBlockType.divider), ...f.skip(3)],
        successMessage: const LocalizedText(en: 'Thanks'),
        version: 1,
      );
      final media = {_cover: WebsiteMedia.fromMap(_cover, {'status': 'published', 'consentConfirmed': true, 'url': 'https://storage.example.test/c.jpg', 'alt': {'en': 'A classroom'}})};
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: PublicWebsiteFormView(form: form, language: PublicLanguage.english, media: media))))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('website-form-cover')), findsOneWidget);
      expect(find.text('Tell us about your child.'), findsOneWidget);
      expect(find.text('Parent'), findsOneWidget);
    });
  });
}
