// The Form Builder upgrade (Phases 1, 2, 4 and 5): long text settings (rows,
// counter, height), field widths, default answers, hiding questions and
// content from visitors, the builder's grouped settings, error handling
// (summary, focus, required note), completion heading, and multi-step forms
// (page breaks, progress, per-step checks, review). Answer validation is
// unchanged: every new setting is about display, so the submission checks
// (and the endpoint they mirror) are untouched. Synthetic data only.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/forms/data/form_submission_service.dart';
import 'package:montessori_app/modules/forms/data/website_forms_service.dart';
import 'package:montessori_app/modules/forms/models/public_submission_settings.dart';
import 'package:montessori_app/modules/forms/models/website_form.dart';
import 'package:montessori_app/modules/forms/public/public_forms_repository.dart';
import 'package:montessori_app/modules/forms/ui/form_builder_screen.dart';
import 'package:montessori_app/modules/forms/ui/public_website_form.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

WebsiteFormField _field(String id, FormFieldType type, String label, {bool required = false, Map<String, dynamic> extra = const {}}) => WebsiteFormField.fromMap({
      'id': id,
      'type': type.id,
      'label': {'en': label, 'ta': ''},
      'required': required,
      if (type.hasOptions)
        'options': [
          {'id': 'o_prim0001', 'label': {'en': 'Primary', 'ta': ''}},
          {'id': 'o_todd0001', 'label': {'en': 'Toddler', 'ta': ''}},
        ],
      ...extra,
    });

FormContentBlock _break(String id, String title) => FormItem.fromMap({'kind': 'content', 'id': id, 'type': 'page_break', 'title': {'en': title, 'ta': ''}}) as FormContentBlock;

PublicWebsiteForm _form(List<FormItem> items, {bool multiStep = false, bool reviewStep = false, String completion = ''}) => PublicWebsiteForm(
      id: 'form_test_01',
      schoolId: 'default_school',
      title: const LocalizedText(en: 'Admissions enquiry'),
      items: items,
      successMessage: const LocalizedText(en: 'We have your enquiry.'),
      version: 1,
      multiStep: multiStep,
      reviewStep: reviewStep,
      completionTitle: LocalizedText(en: completion),
    );

class _Gateway implements FormSubmissionGateway {
  final requests = <FormSubmissionRequest>[];

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) async {
    requests.add(request);
    return const FormSubmissionReceipt(submissionId: 'abc', reference: 'WF-TEST0001');
  }
}

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<_Gateway> pump(WidgetTester tester, PublicWebsiteForm form, {double width = 900, bool interactive = true}) async {
    final gateway = _Gateway();
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        formSubmissionGatewayProvider.overrideWithValue(gateway),
        publicSubmissionStatusProvider.overrideWith((ref) => Stream.value(const PublicSubmissionStatus(schoolId: 'default_school', open: true))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: PublicWebsiteFormView(form: form, language: PublicLanguage.english, interactive: interactive, media: const {})),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return gateway;
  }

  TextField textField(WidgetTester tester, String id) => tester.widget<TextField>(find.descendant(of: key('website-form-field-$id'), matching: find.byType(TextField)));
  String? focused(WidgetTester tester) => tester.binding.focusManager.primaryFocus?.debugLabel;

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------ model
  group('the model', () {
    test('new settings are stored only when set; a question from before is written back exactly', () {
      const old = {'id': 'f_message1', 'type': 'long_text', 'label': {'en': 'Message', 'ta': 'செய்தி'}, 'required': true, 'placeholder': {'en': '', 'ta': ''}};
      expect(WebsiteFormField.fromMap(old).toMap(), old);
      final set = WebsiteFormField.fromMap(old).copyWith(rows: () => 8, counter: () => 'hide', resize: () => 'fixed', width: () => 'half', defaultValue: () => 'Hello', hidden: true);
      expect(set.toMap(), {...old, 'rows': 8, 'counter': 'hide', 'resize': 'fixed', 'width': 'half', 'defaultValue': 'Hello', 'hidden': true});
      expect(WebsiteFormField.fromMap(set.toMap()), set, reason: 'saved and reloaded');
      expect(set.problems(complete: true), isEmpty);
    });

    test('settings that don’t apply, or are out of range, are refused', () {
      List<String> p(FormFieldType type, Map<String, dynamic> extra) => _field('f_question', type, 'Q', extra: extra).problems(complete: true);
      expect(p(FormFieldType.longText, {'rows': 1}), ['show 2 to 12 rows']);
      expect(p(FormFieldType.shortText, {'rows': 4}), ['only long text has rows']);
      expect(p(FormFieldType.shortText, {'resize': 'fixed'}), ['only long text has a height setting']);
      expect(p(FormFieldType.email, {'counter': 'show'}), ['only short and long text have a character counter']);
      expect(p(FormFieldType.longText, {'counter': 'blink'}), ['its counter setting “blink” isn’t supported']);
      expect(p(FormFieldType.shortText, {'width': 'quarter'}), ['its width “quarter” isn’t supported']);
      expect(p(FormFieldType.checkbox, {'defaultValue': 'true'}), ['a checkbox has no default answer'], reason: 'consent is never given in advance');
      expect(p(FormFieldType.email, {'defaultValue': 'not an email'}), ['its default answer isn’t one it accepts']);
      expect(p(FormFieldType.dropdown, {'defaultValue': 'o_missing1'}), ['its default answer isn’t one it accepts']);
      expect(p(FormFieldType.dropdown, {'defaultValue': 'o_todd0001'}), isEmpty);
      expect(p(FormFieldType.number, {'defaultValue': '4', 'min': 3, 'max': 6}), isEmpty);
      expect(p(FormFieldType.date, {'defaultValue': '2027-06-01'}), isEmpty);
    });

    test('hidden questions and content are left out of the version visitors see; never every question', () {
      final form = WebsiteForm(
        id: 'form_test_01',
        schoolId: 'default_school',
        title: const LocalizedText(en: 'T'),
        items: [
          _field('f_visible1', FormFieldType.shortText, 'Name', required: true),
          _field('f_hidden01', FormFieldType.shortText, 'Old question', required: true, extra: {'hidden': true}),
          FormItem.fromMap({'kind': 'content', 'id': 'c_hidden01', 'type': 'text', 'body': {'en': 'Old note'}, 'hidden': true}),
        ],
        successMessage: const LocalizedText(en: 'Thanks'),
      );
      final public = form.toPublic(1);
      expect([for (final i in public.items) i.id], ['f_visible1']);
      expect(validateFormAnswers(public.fields, {'f_visible1': 'Asha'}).errors, isEmpty, reason: 'a hidden required question never blocks sending');
      expect([for (final i in form.toPublic(1, includeHidden: true).items) i.id], ['f_visible1', 'f_hidden01', 'c_hidden01'], reason: 'the builder’s canvas');
      final allHidden = form.copyWith(fields: [for (final f in form.fields) f.copyWith(hidden: true)]);
      expect(allHidden.problems(complete: false), isEmpty);
      expect(formSchemaProblems(title: allHidden.title, items: allHidden.items, successMessage: allHidden.successMessage, complete: true),
          contains('Every field is hidden: show at least one to visitors.'));
    });

    test('a duplicated question keeps its default option, under the option’s new id', () {
      final field = _field('f_programm', FormFieldType.radio, 'Programme', extra: {'defaultValue': 'o_todd0001'});
      final copy = field.withFreshIds();
      expect(copy.defaultValue, copy.options[1].id);
      expect(copy.problems(complete: true), isEmpty);
    });

    test('a single-page form’s visitor copy has exactly the keys it had; steps and a completion heading only when set', () {
      final plain = _form([_field('f_name0001', FormFieldType.shortText, 'Name')]);
      expect(plain.toMap().keys.toSet(), PublicWebsiteForm.storedFields.difference({'activatedAt'}));
      final stepped = _form([_field('f_name0001', FormFieldType.shortText, 'Name')], multiStep: true, reviewStep: true, completion: 'Thank you');
      expect(stepped.toMap().keys.toSet().difference(plain.toMap().keys.toSet()), PublicWebsiteForm.optionalStoredFields);
      final parsed = PublicWebsiteForm.tryParse({...stepped.toMap(), 'description': {'en': 'D'}, 'coverMediaId': 'media_cover_0001'})!;
      expect((parsed.multiStep, parsed.reviewStep, parsed.completionTitle.en), (true, true, 'Thank you'));
    });

    test('answer validation is unchanged by display settings', () {
      final plain = _field('f_message1', FormFieldType.longText, 'Message', required: true, extra: {'minLength': 5, 'maxLength': 20});
      final styled = plain.copyWith(rows: () => 9, counter: () => 'hide', resize: () => 'fixed', width: () => 'third');
      for (final answer in <Object?>[null, '', 'hey', 'hello there', 'x' * 21]) {
        final a = validateFormAnswers([plain], {'f_message1': answer});
        final b = validateFormAnswers([styled], {'f_message1': answer});
        expect(b.values, a.values, reason: '$answer');
        expect(b.errors, a.errors, reason: '$answer');
      }
    });
  });

  // ------------------------------------------------------------ public form
  group('long text', () {
    testWidgets('a growing answer box reaches 10 rows, as before, or its own rows if more', (tester) async {
      final plain = _field('f_plain001', FormFieldType.longText, 'Message');
      final tall = _field('f_tall0001', FormFieldType.longText, 'Story', extra: {'rows': 12});
      await pump(tester, _form([plain, tall]));
      expect((textField(tester, 'f_plain001').minLines, textField(tester, 'f_plain001').maxLines), (4, 10), reason: 'unchanged for existing questions');
      expect((textField(tester, 'f_tall0001').minLines, textField(tester, 'f_tall0001').maxLines), (12, 12), reason: 'rows above 10 kept');
    });

    testWidgets('rows, height and counter as set; the counter stays beside an error; the text is kept', (tester) async {
      final message = _field('f_message1', FormFieldType.longText, 'Message', required: true, extra: {'rows': 6, 'minLength': 20, 'maxLength': 500});
      final fixed = _field('f_notes001', FormFieldType.longText, 'Notes', extra: {'rows': 3, 'resize': 'fixed', 'counter': 'hide'});
      await pump(tester, _form([message, fixed]));
      expect(textField(tester, 'f_message1').minLines, 6);
      expect(textField(tester, 'f_message1').maxLines, 10, reason: 'grows, to 10 rows');
      expect((textField(tester, 'f_notes001').minLines, textField(tester, 'f_notes001').maxLines), (3, 3), reason: 'fixed');
      expect(textField(tester, 'f_message1').keyboardType, TextInputType.multiline);
      expect(find.text('0 / 500'), findsOneWidget);
      expect(key('website-form-counter-f_notes001'), findsNothing, reason: 'hidden');

      await tester.enterText(key('website-form-field-f_message1'), 'Too short');
      await tester.pump();
      expect(find.text('9 / 500'), findsOneWidget, reason: 'live');
      await tap(tester, 'website-form-submit');
      expect(find.text('This answer is too short.'), findsWidgets);
      expect(find.text('9 / 500'), findsOneWidget, reason: 'the counter is still shown with the error');
      expect(find.text('Too short'), findsOneWidget, reason: 'what was typed is kept');
      expect(find.bySemanticsLabel('9 of 500 characters'), findsOneWidget);
    });

    testWidgets('long answers wrap at every width without overflow', (tester) async {
      final long = List.filled(60, 'Our daughter loves practical life activities and the garden.').join(' ');
      for (final width in [1200.0, 768.0, 390.0, 320.0]) {
        await pump(tester, _form([_field('f_message1', FormFieldType.longText, 'Message', extra: {'maxLength': 3000})]), width: width);
        await tester.enterText(key('website-form-field-f_message1'), long);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width');
        expect(tester.getRect(key('website-form-field-f_message1')).right, lessThanOrEqualTo(width));
      }
    });
  });

  group('layout, defaults and visibility', () {
    testWidgets('widths share rows on wider screens; phones stack; automatic as before', (tester) async {
      final items = [
        _field('f_first001', FormFieldType.shortText, 'First name', extra: {'width': 'half'}),
        _field('f_last0001', FormFieldType.shortText, 'Last name', extra: {'width': 'half'}),
        _field('f_day00001', FormFieldType.number, 'Day', extra: {'width': 'third'}),
        _field('f_month001', FormFieldType.number, 'Month', extra: {'width': 'third'}),
        _field('f_year0001', FormFieldType.number, 'Year', extra: {'width': 'third'}),
        _field('f_email001', FormFieldType.email, 'Email'),
        _field('f_phone001', FormFieldType.phone, 'Phone'),
      ];
      await pump(tester, _form(items));
      Rect r(String id) => tester.getRect(key('website-form-field-$id'));
      expect(r('f_first001').top, r('f_last0001').top);
      expect(r('f_first001').width, closeTo(r('f_last0001').width, 1));
      expect({r('f_day00001').top, r('f_month001').top, r('f_year0001').top}, hasLength(1));
      expect(r('f_day00001').width, closeTo(r('f_first001').width * 2 / 3, 12));
      expect(r('f_email001').top, r('f_phone001').top, reason: 'automatic: two short questions to a row, as before');
      await pump(tester, _form(items), width: 390);
      expect(r('f_last0001').top, greaterThan(r('f_first001').bottom), reason: 'stacked on phones');
      expect(tester.takeException(), isNull);
    });

    testWidgets('default answers are filled in and sent unless changed', (tester) async {
      final gateway = await pump(tester, _form([
        _field('f_name0001', FormFieldType.shortText, 'Name', extra: {'defaultValue': 'Synthetic Parent'}),
        _field('f_program1', FormFieldType.dropdown, 'Programme', extra: {'defaultValue': 'o_todd0001'}),
        _field('f_start001', FormFieldType.date, 'Start', extra: {'defaultValue': '2027-06-01'}),
      ]));
      expect(find.text('Synthetic Parent'), findsOneWidget);
      expect(find.text('Toddler'), findsOneWidget);
      expect(find.text('2027-06-01'), findsOneWidget);
      await tap(tester, 'website-form-submit');
      expect(gateway.requests.single.answers, {'f_name0001': 'Synthetic Parent', 'f_program1': 'o_todd0001', 'f_start001': '2027-06-01'});
    });
  });

  group('errors and accessibility', () {
    testWidgets('a required note; a summary of what to fix, each a link; the first invalid answer focused', (tester) async {
      await pump(tester, _form([
        _field('f_name0001', FormFieldType.shortText, 'Name', required: true),
        _field('f_email001', FormFieldType.email, 'Email', required: true),
        _field('f_consent1', FormFieldType.checkbox, 'I agree', required: true),
      ]));
      expect(find.text('Fields marked * are required.'), findsOneWidget);
      await tester.enterText(key('website-form-field-f_email001'), 'not-an-email');
      await tap(tester, 'website-form-submit');
      expect(key('website-form-error-summary'), findsOneWidget);
      expect(find.text('There are 3 answers to check:'), findsOneWidget);
      expect(find.text('Email: Enter a valid email address.'), findsOneWidget);
      expect(focused(tester), 'form-f_name0001', reason: 'the first invalid answer');
      await tap(tester, 'website-form-error-link-f_consent1');
      expect(focused(tester), 'form-f_consent1');
      await tester.enterText(key('website-form-field-f_name0001'), 'Asha');
      await tester.pump();
      expect(find.text('There are 2 answers to check:'), findsOneWidget, reason: 'updated as answers are fixed');
    });

    testWidgets('a completion heading above the success message', (tester) async {
      await pump(tester, _form([_field('f_name0001', FormFieldType.shortText, 'Name')], completion: 'Thank you'));
      await tap(tester, 'website-form-submit');
      expect(tester.widget<Text>(key('website-form-completion-title')).data, 'Thank you');
      expect(find.text('We have your enquiry.'), findsOneWidget);
    });
  });

  group('multi-step forms', () {
    List<FormItem> items() => [
          _field('f_name0001', FormFieldType.shortText, 'Your name', required: true),
          _break('c_page0001', 'About your child'),
          _field('f_child001', FormFieldType.shortText, 'Child’s name', required: true),
          _field('f_program1', FormFieldType.radio, 'Programme', required: true),
          _break('c_page0002', 'Anything else'),
          _field('f_message1', FormFieldType.longText, 'Message'),
        ];

    testWidgets('steps with progress; Next checks only this step; answers kept going back; review then send', (tester) async {
      final gateway = await pump(tester, _form(items(), multiStep: true, reviewStep: true));
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(key('website-form-field-f_child001'), findsNothing, reason: 'one step at a time');
      expect(key('website-form-submit'), findsNothing);
      await tap(tester, 'website-form-next');
      expect(find.text('This is required.'), findsOneWidget, reason: 'this step is checked');
      expect(focused(tester), 'form-f_name0001');
      await tester.enterText(key('website-form-field-f_name0001'), 'Synthetic Parent');
      await tap(tester, 'website-form-next');
      expect(find.text('Step 2 of 4 · About your child'), findsOneWidget, reason: 'the next step, though step 2 is still empty');

      await tester.enterText(key('website-form-field-f_child001'), 'Synthetic Child');
      await tap(tester, 'website-form-option-f_program1-o_prim0001');
      await tap(tester, 'website-form-previous');
      expect(find.text('Synthetic Parent'), findsOneWidget, reason: 'kept');
      await tap(tester, 'website-form-next');
      expect(find.text('Synthetic Child'), findsOneWidget, reason: 'kept');
      await tap(tester, 'website-form-next');
      await tester.enterText(key('website-form-field-f_message1'), 'We visit in June.');
      await tap(tester, 'website-form-next');

      expect(find.text('Step 4 of 4 · Review your answers'), findsOneWidget);
      expect(find.descendant(of: key('website-form-review-f_program1'), matching: find.text('Primary')), findsOneWidget);
      await tap(tester, 'website-form-review-edit-f_child001');
      expect(find.text('Step 2 of 4 · About your child'), findsOneWidget, reason: 'Change goes back to its step');
      await tester.enterText(key('website-form-field-f_child001'), 'Synthetic Child B');
      await tap(tester, 'website-form-next');
      await tap(tester, 'website-form-next');
      await tap(tester, 'website-form-submit');
      expect(gateway.requests.single.answers, {'f_name0001': 'Synthetic Parent', 'f_child001': 'Synthetic Child B', 'f_program1': 'o_prim0001', 'f_message1': 'We visit in June.'});
      expect(key('website-form-success'), findsOneWidget);
    });

    testWidgets('without review, the last step sends; the whole form is checked again', (tester) async {
      final gateway = await pump(tester, _form(items(), multiStep: true));
      expect(find.text('Step 1 of 3'), findsOneWidget);
      await tester.enterText(key('website-form-field-f_name0001'), 'Synthetic Parent');
      await tap(tester, 'website-form-next');
      await tester.enterText(key('website-form-field-f_child001'), 'Synthetic Child');
      await tap(tester, 'website-form-option-f_program1-o_todd0001');
      await tap(tester, 'website-form-next');
      expect(key('website-form-next'), findsNothing);
      await tap(tester, 'website-form-submit');
      expect(gateway.requests, hasLength(1));
    });

    testWidgets('single page (the default): page breaks show nothing; every question at once', (tester) async {
      await pump(tester, _form(items()));
      expect(key('website-form-progress'), findsNothing);
      expect(key('website-form-next'), findsNothing);
      expect(key('website-form-field-f_message1'), findsOneWidget);
      expect(find.text('About your child'), findsNothing);
    });

    testWidgets('the preview steps through without sending anything', (tester) async {
      final gateway = await pump(tester, _form([_field('f_name0001', FormFieldType.shortText, 'Name'), _break('c_page0001', 'Two'), _field('f_child001', FormFieldType.shortText, 'Child')], multiStep: true), interactive: false);
      await tap(tester, 'website-form-next');
      await tap(tester, 'website-form-submit');
      expect(gateway.requests, isEmpty);
      expect(find.text('Preview: responses aren’t sent from here.'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ builder
  group('the builder', () {
    late FakeFirebaseFirestore db;
    late WebsiteFormsService forms;

    setUp(() {
      db = FakeFirebaseFirestore();
      forms = WebsiteFormsService(firestore: db);
    });

    Future<String> open(WidgetTester tester) async {
      late String id;
      await tester.runAsync(() async {
        await db.collection(WebsiteCollections.media).doc('media_cover_0001').set({
          'status': 'published',
          'consentConfirmed': true,
          'url': 'https://storage.example.test/m.jpg',
          'alt': {'en': 'Children reading'},
          'storagePath': 'website_media/media_cover_0001/x.jpg',
        });
        id = (await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: 'general_enquiry')).id;
      });
      tester.view.physicalSize = const Size(1500, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: FormBuilderScreen(service: forms, user: _admin, formId: id)),
      ));
      await tester.pumpAndSettle();
      return id;
    }

    String last(WidgetTester tester) => [
          for (final e in find.byWidgetPredicate((w) => w is InkWell && w.key is ValueKey<String> && RegExp(r'^form-structure-[fc]_[a-z0-9]{8}$').hasMatch((w.key as ValueKey<String>).value)).evaluate())
            (e.widget.key as ValueKey<String>).value.substring('form-structure-'.length),
        ].last;

    Future<void> pick(WidgetTester tester, String dropdown, String option) async {
      await tap(tester, dropdown);
      await tester.tap(key('$dropdown-$option').last);
      await tester.pumpAndSettle();
    }

    testWidgets('Advanced shows the question’s ID, read-only, with what keeps it', (tester) async {
      await open(tester);
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-short_text');
      final f = last(tester);
      final k = 'builder-field-$f';
      expect(key('$k-id'), findsNothing, reason: 'Advanced starts closed');
      await tap(tester, '$k-group-advanced');
      expect(tester.widget<SelectableText>(key('$k-id')).data, 'Field ID: $f');
      expect(tester.widget<EditableText>(find.descendant(of: key('$k-id'), matching: find.byType(EditableText))).readOnly, isTrue);
      expect(tester.widget<Text>(key('$k-id-note')).data, 'This question’s ID stays the same when you edit, move or save it. A duplicate gets its own ID.');
      final note = tester.getRect(key('$k-id-note'));
      final group = tester.getRect(key('$k-group-advanced'));
      expect(group.bottom - note.bottom, greaterThanOrEqualTo(8), reason: 'space below the note (6) and the group’s own (4)');
    });

    testWidgets('Long text from the menu; only its settings, grouped; rows, counter, height, width; saved', (tester) async {
      final id = await open(tester);
      await tap(tester, 'builder-add-field');
      expect(find.text('Long text (multiline)'), findsOneWidget);
      await tap(tester, 'builder-add-long_text');
      final f = last(tester);
      final k = 'builder-field-$f';
      for (final g in ['basic', 'help', 'validation', 'display', 'advanced']) {
        expect(key('$k-group-$g'), findsOneWidget, reason: g);
      }
      expect(key('$k-rows'), findsNothing, reason: 'Display and layout starts closed');
      await tap(tester, '$k-group-display');
      await pick(tester, '$k-rows', '7');
      await pick(tester, '$k-resize', 'fixed');
      await pick(tester, '$k-counter', 'show');
      await pick(tester, '$k-width', 'half');
      expect(textField(tester, f).minLines, 7, reason: 'the canvas updates');
      await tester.enterText(find.byKey(Key('$k-label-en-1')), 'Tell us about your child');
      await tester.pump();
      await tap(tester, 'builder-save');
      final saved = (await tester.runAsync(() => forms.getForm(requesterRole: 'admin', formId: id)))!.form.fields.last;
      expect((saved.rows, saved.resize, saved.counter, saved.width), (7, 'fixed', 'show', 'half'));
      expect(saved.id, f, reason: 'its id stays');
    });

    testWidgets('settings that don’t apply aren’t offered', (tester) async {
      await open(tester);
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-checkbox');
      final c = 'builder-field-${last(tester)}';
      await tap(tester, '$c-group-display');
      expect(key('$c-rows'), findsNothing);
      expect(key('$c-counter'), findsNothing);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('$c-default')), findsNothing, reason: 'consent is never ticked in advance');
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-email');
      final e = 'builder-field-${last(tester)}';
      await tap(tester, '$e-group-display');
      expect(key('$e-rows'), findsNothing);
      expect(key('$e-counter'), findsNothing);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('$e-default')), findsOneWidget);
    });

    testWidgets('hiding marks it in the structure and on the canvas; removing asks first; consent preset; steps', (tester) async {
      final id = await open(tester);
      final first = last(tester);
      await tap(tester, 'form-structure-$first');
      await tap(tester, 'builder-field-$first-group-display');
      await tap(tester, 'builder-field-$first-visible');
      expect(key('form-structure-$first-hidden'), findsOneWidget);
      expect(key('form-canvas-hidden-$first'), findsOneWidget);

      await tap(tester, 'form-structure-$first-menu');
      await tap(tester, 'form-structure-$first-remove');
      expect(key('builder-remove-dialog'), findsOneWidget);
      await tap(tester, 'builder-remove-cancel');
      expect(key('form-structure-$first'), findsOneWidget, reason: 'kept');

      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-consent');
      final consent = last(tester);
      expect(key('form-structure-$consent-required'), findsOneWidget);

      await tap(tester, 'form-structure-settings');
      await tap(tester, 'builder-group-steps');
      await tap(tester, 'builder-multi-step');
      expect(key('builder-review-step'), findsOneWidget);
      expect(key('builder-steps-hint'), findsOneWidget);
      await tap(tester, 'builder-add-field');
      await tap(tester, 'builder-add-content-page_break');
      final pageBreak = last(tester);
      await tester.enterText(find.byKey(Key('builder-content-$pageBreak-title-en-1')), 'About your child');
      await tester.pump();
      expect(find.text('Page break · step 2: About your child'), findsOneWidget);
      await tap(tester, 'builder-save');
      final saved = (await tester.runAsync(() => forms.getForm(requesterRole: 'admin', formId: id)))!.form;
      expect(saved.multiStep, isTrue);
      expect(saved.fields.firstWhere((f) => f.id == first).hidden, isTrue);
      expect(saved.fields.firstWhere((f) => f.id == consent).required, isTrue);
      expect(saved.toPublic(1).items.any((i) => i.id == first), isFalse);
    });
  });
}
