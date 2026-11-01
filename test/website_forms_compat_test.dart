// Compatibility of stored forms (Phase 0 of the Form Builder upgrade):
// whatever a form, its questions, their options and its content items hold
// that this version doesn't read is kept and written back unchanged, through
// editing, saving, duplicating and activating; ids, Tamil text and older
// forms (questions only, before content items) survive. Synthetic data only;
// the fake Firestore proves the app's behaviour, not deployed rules.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/public_submission_settings_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/forms/data/form_submission_service.dart';
import 'package:montessori_app/modules/forms/data/website_forms_service.dart';
import 'package:montessori_app/modules/forms/models/website_form.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _cover = 'media_cover_0001';

/// What a newer version might have stored: on a question, an option and a
/// content item.
const _fieldExtra = {
  'futureRule': {'when': 'f_aaaaaaaa', 'equals': 'o_bbbbbbbb'},
  'futureFlag': true,
};
const _optionExtra = {'futureColour': '#20302A'};
const _blockExtra = {'futureStyle': 'boxed', 'futureList': [1, 2, 3]};
const _formExtra = {'futureFormSetting': {'theme': 'calm'}};

/// A placeholder stored on a choice question (only text questions show
/// one), as a type change elsewhere might leave it.
const _choicePlaceholder = {'en': 'Choose one', 'ta': 'ஒன்றைத் தேர்ந்தெடுக்கவும்'};

void main() {
  group('the model', () {
    test('a question keeps keys it doesn’t read, through editing, copying and fresh ids', () {
      final raw = {
        'id': 'f_abcdefgh',
        'type': 'dropdown',
        'label': {'en': 'Programme', 'ta': 'திட்டம்'},
        'required': true,
        'options': [
          {'id': 'o_aaaaaaaa', 'label': {'en': 'Primary', 'ta': 'தொடக்க'}, ..._optionExtra},
          {'id': 'o_bbbbbbbb', 'label': {'en': 'Toddler', 'ta': ''}},
        ],
        ..._fieldExtra,
      };
      final field = WebsiteFormField.fromMap(raw);
      expect(field.problems(complete: true), isEmpty, reason: 'unknown keys are not problems');
      expect(field.toMap(), raw, reason: 'written back exactly');
      final edited = field.copyWith(label: field.label.withText('en', 'Programme of interest'));
      expect(edited.toMap()['futureRule'], _fieldExtra['futureRule']);
      expect(edited.toMap()['label'], {'en': 'Programme of interest', 'ta': 'திட்டம்'}, reason: 'Tamil kept');
      expect((edited.toMap()['options'] as List).first, {'id': 'o_aaaaaaaa', 'label': {'en': 'Primary', 'ta': 'தொடக்க'}, ..._optionExtra});
      final option = edited.options.first.copyWith(label: const LocalizedText(en: 'Primary (3–6)', ta: 'தொடக்க'));
      expect(option.toMap()['futureColour'], '#20302A');
      final copy = field.withFreshIds();
      expect(copy.id, isNot(field.id));
      expect(copy.toMap()['futureFlag'], isTrue);
      expect(field == WebsiteFormField.fromMap({...raw, 'futureFlag': false}), isFalse, reason: 'a change to them is a change');
      expect(field == WebsiteFormField.fromMap(Map.of(raw)), isTrue);
    });

    test('a content item keeps keys it doesn’t read; a known key never moves into them', () {
      final raw = {'kind': 'content', 'id': 'c_abcdefgh', 'type': 'heading', 'title': {'en': 'About you', 'ta': 'உங்களைப் பற்றி'}, 'body': {'en': '', 'ta': ''}, ..._blockExtra};
      final block = FormItem.fromMap(raw) as FormContentBlock;
      expect(block.toMap(), raw);
      expect(block.copyWith(title: const LocalizedText(en: 'About your child', ta: 'உங்களைப் பற்றி')).toMap()['futureStyle'], 'boxed');
      expect(block.extra.keys, unorderedEquals(['futureStyle', 'futureList']));
      expect(WebsiteFormField.fromMap(const {'id': 'f_abcdefgh', 'type': 'short_text', 'label': {'en': 'Name'}, 'required': false}).extra, isEmpty);
    });

    test('a dropdown or radio question keeps a stored placeholder, through editing and type changes', () {
      for (final type in ['dropdown', 'radio']) {
        final raw = {
          'id': 'f_abcdefgh',
          'type': type,
          'label': {'en': 'Programme', 'ta': 'திட்டம்'},
          'required': false,
          'placeholder': _choicePlaceholder,
          'options': [
            {'id': 'o_aaaaaaaa', 'label': {'en': 'Primary', 'ta': ''}},
            {'id': 'o_bbbbbbbb', 'label': {'en': 'Toddler', 'ta': ''}},
          ],
        };
        final field = WebsiteFormField.fromMap(raw);
        expect(field.toMap(), raw, reason: '$type: written back exactly');
        expect(field.problems(complete: true), isEmpty);
        expect(field.copyWith(label: field.label.withText('en', 'Programme of interest')).toMap()['placeholder'], _choicePlaceholder);
        expect(field.withFreshIds().toMap()['placeholder'], _choicePlaceholder);
        // Back to short text: the placeholder is there to show and edit.
        final text = field.copyWith(type: FormFieldType.shortText);
        expect(text.toMap()['placeholder'], _choicePlaceholder);
        expect(text.copyWith(placeholder: text.placeholder.withText('en', 'Your programme')).toMap()['placeholder'], {'en': 'Your programme', 'ta': _choicePlaceholder['ta']});
        // A stored placeholder in an unexpected shape is kept as it was.
        expect(WebsiteFormField.fromMap({...raw, 'placeholder': 'Choose'}).toMap()['placeholder'], 'Choose');
      }
      // Short text to dropdown (in memory): its placeholder isn't lost.
      final text = WebsiteFormField.create(FormFieldType.shortText, 'Programme', placeholder: 'Type one');
      expect(text.copyWith(type: FormFieldType.dropdown, options: [FormFieldOption.create('Primary')]).toMap()['placeholder'], {'en': 'Type one', 'ta': ''});
      // None stored, none written (as before).
      final plain = WebsiteFormField.create(FormFieldType.dropdown, 'Programme', options: ['Primary']).toMap();
      expect(plain.containsKey('placeholder'), isFalse);
    });

    test('a form keeps top-level keys it doesn’t read; known keys never move into them', () {
      final form = WebsiteForm.fromMap('form_1', {
        'schoolId': 'default_school',
        'title': {'en': 'Enquiries', 'ta': 'விசாரணைகள்'},
        'status': 'draft',
        'version': 0,
        'updatedById': '9000000002',
        'duplicatedFrom': 'form_0',
        'deactivatedAt': null,
        'items': const [],
        ..._formExtra,
      });
      expect(form.extra, _formExtra);
      expect(form.copyWith(title: const LocalizedText(en: 'Questions')).extra, _formExtra);
      expect(form.toContentMap().keys.toSet().difference(WebsiteForm.knownKeys), isEmpty, reason: 'everything it writes is known');
      expect(form.toPublic(1).toMap().containsKey('futureFormSetting'), isFalse, reason: 'visitors only see their copy’s fields');
    });
  });

  group('through the forms service', () {
    late FakeFirebaseFirestore db;
    late WebsiteFormsService forms;

    setUp(() async {
      db = FakeFirebaseFirestore();
      forms = WebsiteFormsService(firestore: db);
      await db.collection(WebsiteCollections.media).doc(_cover).set({
        'status': 'published',
        'consentConfirmed': true,
        'url': 'https://storage.example.test/m.jpg',
        'alt': {'en': 'Children reading'},
        'storagePath': 'website_media/$_cover/x.jpg',
      });
    });

    Future<Map<String, dynamic>> raw(String id) async => (await db.collection(FormCollections.forms).doc(id).get()).data()!;

    /// A General Enquiry whose stored draft also holds what a newer version
    /// might have written, at every level.
    Future<WebsiteForm> seeded() async {
      final created = await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: 'general_enquiry');
      await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: created.copyWith(coverMediaId: () => _cover));
      final stored = await raw(created.id);
      Map<String, dynamic> extend(Map item) {
        final m = Map<String, dynamic>.from(item);
        if (m['kind'] == 'content') return {...m, ..._blockExtra};
        if (m['options'] is List) {
          m['options'] = [for (final o in m['options'] as List) {...Map<String, dynamic>.from(o as Map), ..._optionExtra}];
        }
        return {...m, ..._fieldExtra, 'label': {'en': (m['label'] as Map)['en'], 'ta': 'தமிழ் ${(m['label'] as Map)['en']}'}};
      }

      final items = [
        for (final i in stored['items'] as List) extend(i as Map),
        for (final (id, type) in [('f_dddddddd', 'dropdown'), ('f_rrrrrrrr', 'radio')])
          extend({
            'id': id,
            'type': type,
            'label': {'en': 'Programme ($type)'},
            'required': false,
            'placeholder': _choicePlaceholder,
            'options': [
              {'id': 'o_${id.substring(2)}', 'label': {'en': 'Primary', 'ta': 'தொடக்க'}},
              {'id': 'o_${id.substring(3)}x', 'label': {'en': 'Toddler', 'ta': ''}},
            ],
          }),
      ];
      await db.collection(FormCollections.forms).doc(created.id).update({
        'items': [
          ...items,
          {'kind': 'content', 'id': 'c_zzzzzzzz', 'type': 'heading', 'title': {'en': 'Your details', 'ta': ''}, 'body': {'en': '', 'ta': ''}, ..._blockExtra},
        ],
        'fields': [for (final i in items) if (i['kind'] != 'content') i],
        ..._formExtra,
        'multiStep': true,
        'reviewStep': true,
        'completionTitle': {'en': 'Thank you', 'ta': 'நன்றி'},
      });
      return (await forms.getForm(requesterRole: 'admin', formId: created.id))!.form;
    }

    void expectKept(Map<String, dynamic> doc, {bool topLevel = true}) {
      for (final item in (doc['items'] as List).cast<Map>()) {
        if (item['kind'] == 'content') {
          expect(item['futureStyle'], 'boxed', reason: '${item['id']}');
          expect(item['futureList'], [1, 2, 3]);
        } else {
          expect(item['futureRule'], _fieldExtra['futureRule'], reason: '${item['id']}');
          expect(item['futureFlag'], isTrue);
          expect((item['label'] as Map)['ta'], startsWith('தமிழ்'), reason: 'Tamil kept');
          for (final o in (item['options'] as List? ?? const []).cast<Map>()) {
            expect(o['futureColour'], '#20302A');
          }
          if (item['type'] == 'dropdown' || item['type'] == 'radio') expect(item['placeholder'], _choicePlaceholder, reason: '${item['id']}');
        }
      }
      for (final f in (doc['fields'] as List).cast<Map>()) {
        expect(f['futureRule'], _fieldExtra['futureRule']);
      }
      if (topLevel) {
        expect(doc['futureFormSetting'], _formExtra['futureFormSetting']);
      } else {
        expect(doc.containsKey('futureFormSetting'), isFalse, reason: 'never in what visitors read');
      }
    }

    test('editing and saving a draft keeps everything it doesn’t read, at every level; ids stay', () async {
      final form = await seeded();
      final ids = [for (final i in form.items) i.id];
      final first = form.fields.first;
      final edited = form.copyWith(
        title: const LocalizedText(en: 'Enquiries'),
        fields: [first.copyWith(label: first.label.withText('en', 'Your full name')), ...form.fields.skip(1)],
      );
      await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: edited);
      final doc = await raw(form.id);
      expectKept(doc);
      expect([for (final i in doc['items'] as List) (i as Map)['id']], ids, reason: 'stable ids, same order');
      expect(((doc['items'] as List).first as Map)['label'], {'en': 'Your full name', 'ta': 'தமிழ் ${first.label.en}'});

      // Reopened and saved again without changes: identical.
      final again = (await forms.getForm(requesterRole: 'admin', formId: form.id))!.form;
      expect(again.items, edited.items, reason: 'equal, so no unsaved changes are reported');
      await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: again);
      final second = await raw(form.id);
      expect(second['items'], doc['items']);
      expect(second['fields'], doc['fields']);
    });

    test('activating carries them into the visitor copy, the version record and submission snapshots', () async {
      final form = await seeded();
      await PublicSubmissionSettingsService(firestore: db)
          .update(schoolId: 'default_school', requesterRole: 'admin', requesterSchoolId: 'default_school', actor: _admin, enabled: true, closedMessage: '', expectedRevision: 0);
      final public = await forms.activate(requesterRole: 'admin', actor: _admin, formId: form.id);
      final copy = (await db.collection(FormCollections.publicForms).doc(form.id).get()).data()!;
      expectKept(copy, topLevel: false);
      expect(PublicWebsiteForm.tryParse(copy), isNotNull, reason: 'the website still reads it');
      expect(copy['multiStep'], isTrue);
      expect(copy['completionTitle'], {'en': 'Thank you', 'ta': 'நன்றி'});
      expectKept(await raw(form.id)); // the draft keeps everything after activation
      final versions = await db.collection(FormCollections.versions).get();
      expect(versions.docs, hasLength(1));
      expectKept(Map<String, dynamic>.from(versions.docs.single.data()['schema'] as Map), topLevel: false);

      // Edited, saved and activated again: a second version, still complete.
      final reopened = (await forms.getForm(requesterRole: 'admin', formId: form.id))!.form;
      await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: reopened.copyWith(successMessage: const LocalizedText(en: 'Thanks, we will reply soon.')));
      final second = await forms.activate(requesterRole: 'admin', actor: _admin, formId: form.id);
      expect(second.version, public.version + 1);
      final v2 = (await db.collection(FormCollections.versions).doc('${form.id}_v${second.version}').get()).data()!;
      expectKept(Map<String, dynamic>.from(v2['schema'] as Map), topLevel: false);
      expectKept(await raw(form.id));

      final f = public.fields;
      final key = FormIds.submissionKey();
      await FormSubmissionService(firestore: db).submit(FormSubmissionRequest(
        formId: form.id,
        answers: {f[0].id: 'Synthetic Parent', f[1].id: 'parent@example.com', f[3].id: 'A synthetic question', f[4].id: true},
        submissionKey: key,
      ));
      final submission = (await db.collection(FormCollections.submissions).doc(key).get()).data()!;
      expect(((submission['fields'] as List).first as Map)['futureRule'], _fieldExtra['futureRule'], reason: 'the snapshot is the visitor copy’s');
    });

    test('duplicating keeps them and the form’s settings, with fresh ids', () async {
      final form = await seeded();
      final copy = await forms.duplicate(requesterRole: 'admin', actor: _admin, formId: form.id);
      final doc = await raw(copy.id);
      expectKept(doc);
      expect(doc['multiStep'], isTrue);
      expect(doc['reviewStep'], isTrue);
      expect(doc['completionTitle'], {'en': 'Thank you', 'ta': 'நன்றி'});
      expect(doc['duplicatedFrom'], form.id);
      expect(doc['status'], 'draft');
      expect({for (final i in doc['items'] as List) (i as Map)['id']}.intersection({for (final i in form.items) i.id}), isEmpty);
    });

    test('a form stored before content items (questions only) loads, edits and saves', () async {
      final created = await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: 'general_enquiry');
      final stored = await raw(created.id);
      final fields = [for (final f in stored['items'] as List) if ((f as Map)['kind'] != 'content') {...Map<String, dynamic>.from(f), ..._fieldExtra}];
      await db.collection(FormCollections.forms).doc(created.id).set({...stored, 'fields': fields}..remove('items'));
      final old = (await forms.getForm(requesterRole: 'admin', formId: created.id))!.form;
      expect([for (final f in old.fields) f.id], [for (final f in fields) f['id']]);
      await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: old.copyWith(title: const LocalizedText(en: 'Older form')));
      final doc = await raw(created.id);
      expect([for (final f in doc['fields'] as List) (f as Map)['futureFlag']], everyElement(isTrue));
      expect([for (final f in doc['items'] as List) (f as Map)['id']], [for (final f in fields) f['id']]);
    });
  });
}
