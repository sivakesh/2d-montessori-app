// Settings → Public form submissions: the administrator's switch for
// whether the public website accepts form submissions, its closed message,
// and how the public form and the submission service obey it.
//
// Every record here is synthetic test data. The fake Firestore proves the
// app's behaviour, not deployed security rules (the proposed rules are
// exercised by the emulator checks, test/emulator/).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/public_submission_settings_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/ui/admin_settings_screen.dart';
import 'package:montessori_app/modules/admin/settings/ui/public_submissions_settings_screen.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/forms/data/form_submission_service.dart';
import 'package:montessori_app/modules/forms/data/website_forms_service.dart';
import 'package:montessori_app/modules/forms/models/public_submission_settings.dart';
import 'package:montessori_app/modules/forms/models/website_form.dart';
import 'package:montessori_app/modules/forms/public/public_forms_repository.dart';
import 'package:montessori_app/modules/forms/ui/forms_manager_screen.dart';
import 'package:montessori_app/modules/forms/ui/public_website_form.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';

const _school = kDefaultSchoolId;
const _otherSchool = 'other_school';
const _cover = 'media_cover_0001';
final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
final _secondAdmin = AppUser(id: '9000000003', phone: '9000000003', role: 'admin', isActive: true, name: 'Second admin');

Matcher _refused(FormSubmissionErrorCode code) => throwsA(isA<FormSubmissionException>().having((e) => e.code, 'code', code));

class _Harness {
  _Harness([FakeFirebaseFirestore? db]) : db = db ?? FakeFirebaseFirestore();

  final FakeFirebaseFirestore db;
  late final settings = PublicSubmissionSettingsService(firestore: db);
  late final forms = WebsiteFormsService(firestore: db);
  late final trusted = FormSubmissionService(firestore: db);

  Future<PublicSubmissionSettings> load({String school = _school}) => settings.load(schoolId: school, requesterRole: 'admin', requesterSchoolId: school);

  Future<PublicSubmissionSettings> set(bool enabled, {String message = '', String school = _school, AppUser? actor}) async {
    final now = await load(school: school);
    return settings.update(
      schoolId: school,
      requesterRole: 'admin',
      requesterSchoolId: school,
      actor: actor ?? _admin,
      enabled: enabled,
      closedMessage: message,
      expectedRevision: now.revision,
    );
  }

  /// An active General Enquiry of [_school], and answers it accepts.
  Future<({WebsiteForm form, Map<String, Object?> answers})> activeEnquiry() async {
    await db.collection(WebsiteCollections.media).doc(_cover).set({
      'status': 'published',
      'consentConfirmed': true,
      'url': 'https://storage.example.test/m.jpg',
      'alt': {'en': 'Children in the garden'},
      'storagePath': 'website_media/$_cover/x.jpg',
    });
    final created = await forms.createFromTemplate(requesterRole: 'admin', actor: _admin, templateId: 'general_enquiry');
    final form = created.copyWith(coverMediaId: () => _cover);
    await forms.saveDraft(requesterRole: 'admin', actor: _admin, form: form);
    await forms.activate(requesterRole: 'admin', actor: _admin, formId: form.id);
    final f = form.fields;
    return (form: form, answers: <String, Object?>{f[0].id: 'Asha Example', f[1].id: 'asha@example.com', f[2].id: '+91 98765 43210', f[3].id: 'Do you have places?', f[4].id: true});
  }

  FormSubmissionRequest request(String formId, Map<String, Object?> answers) =>
      FormSubmissionRequest(formId: formId, answers: answers, submissionKey: FormIds.submissionKey(), formVersion: 1);

  Future<int> count(String collection) async => (await db.collection(collection).get()).docs.length;

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await db.collection(collection).doc(id).get()).data();
}

/// Fails every change, like a lost connection or a refused write.
class _FailingService extends PublicSubmissionSettingsService {
  _FailingService(FakeFirebaseFirestore db) : super(firestore: db);

  int attempts = 0;

  @override
  Future<PublicSubmissionSettings> update({
    required String schoolId,
    required String requesterRole,
    required String requesterSchoolId,
    required AppUser actor,
    required bool enabled,
    required String closedMessage,
    required int expectedRevision,
  }) async {
    attempts++;
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

/// Can't read the setting at all.
class _UnreadableService extends PublicSubmissionSettingsService {
  _UnreadableService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<PublicSubmissionSettings> load({required String schoolId, required String requesterRole, required String requesterSchoolId}) async =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
}

void main() {
  group('the setting', () {
    test('is OFF for a school that has never saved it, and when unreadable', () async {
      final h = _Harness();
      final saved = await h.load();
      expect((saved.enabled, saved.revision, saved.closedMessage, saved.updatedAt), (false, 0, '', null));
      expect(PublicSubmissionStatus.fromMap(_school, null).open, isFalse);
      expect(PublicSubmissionStatus.fromMap(_school, {'schoolId': _school}).open, isFalse);
      expect(PublicSubmissionStatus.fromMap(_school, {'schoolId': _school, 'submissionsOpen': 'yes'}).open, isFalse, reason: 'only true opens');
      expect(PublicSubmissionSettings.fromMap(_school, 'garbage').enabled, isFalse);
      expect(await h.count(PublicSubmissionSettings.publicCollection), 0, reason: 'reading writes nothing');
    });

    test('an admin turns it on and off: the record, the visitor copy and an audit entry change together', () async {
      final h = _Harness();
      await h.db.collection(PublicSubmissionSettings.schoolSettingsCollection).doc(_school).set({'schoolId': _school, 'name': 'Synthetic School', 'phone': '0000000000'});

      final on = await h.set(true, message: '  Closed for the holidays.  ');
      expect((on.enabled, on.revision, on.closedMessage, on.updatedByName, on.updatedById), (true, 1, 'Closed for the holidays.', 'Test admin', _admin.id));
      expect(on.updatedAt, isNotNull);
      final record = (await h.doc(PublicSubmissionSettings.schoolSettingsCollection, _school))!;
      expect((record['name'], record['phone']), ('Synthetic School', '0000000000'), reason: 'the rest of School Settings is kept');
      expect(await h.doc(PublicSubmissionSettings.publicCollection, _school),
          allOf(containsPair('schoolId', _school), containsPair('submissionsOpen', true), containsPair('closedMessage', 'Closed for the holidays.'), containsPair('revision', 1)));
      expect((await h.doc(PublicSubmissionSettings.publicCollection, _school))!.keys, isNot(contains('updatedByName')), reason: 'no administrator details for visitors');

      final off = await h.set(false, message: 'Closed for the holidays.', actor: _secondAdmin);
      expect((off.enabled, off.revision, off.updatedByName), (false, 2, 'Second admin'));
      expect(PublicSubmissionStatus.fromMap(_school, await h.doc(PublicSubmissionSettings.publicCollection, _school)).open, isFalse);

      final audit = (await h.db.collection(PublicSubmissionSettings.schoolSettingsCollection).doc(_school).collection(PublicSubmissionSettings.auditCollection).get()).docs.map((d) => d.data()).toList()
        ..sort((a, b) => (a['revision'] as int).compareTo(b['revision'] as int));
      expect(audit.map((a) => (a['enabled'], a['previousEnabled'], a['byName'], a['closedMessageChanged'])).toList(), [(true, false, 'Test admin', true), (false, true, 'Second admin', false)]);
    });

    test('persists across reloads: a new session reads what was saved', () async {
      final db = FakeFirebaseFirestore();
      await _Harness(db).set(true, message: 'See you soon.');
      final reloaded = await _Harness(db).load();
      expect((reloaded.enabled, reloaded.closedMessage, reloaded.revision), (true, 'See you soon.', 1));
    });

    test('only admins of the school may read or change it; nothing is written otherwise', () async {
      final h = _Harness();
      for (final role in ['teacher', 'staff', 'parent', '']) {
        await expectLater(h.settings.load(schoolId: _school, requesterRole: role, requesterSchoolId: _school), throwsA(isA<UnauthorizedSchoolSettingsException>()), reason: role);
        await expectLater(
          h.settings.update(schoolId: _school, requesterRole: role, requesterSchoolId: _school, actor: _admin, enabled: true, closedMessage: '', expectedRevision: 0),
          throwsA(isA<UnauthorizedSchoolSettingsException>()),
          reason: role,
        );
      }
      await expectLater(
        h.settings.update(schoolId: _school, requesterRole: 'admin', requesterSchoolId: _otherSchool, actor: _admin, enabled: true, closedMessage: '', expectedRevision: 0),
        throwsA(isA<UnauthorizedSchoolSettingsException>()),
        reason: 'another school’s admin',
      );
      expect(await h.count(PublicSubmissionSettings.schoolSettingsCollection), 0);
      expect(await h.count(PublicSubmissionSettings.publicCollection), 0);
    });

    test('schools are isolated: one school’s switch never opens another’s', () async {
      final h = _Harness();
      await h.set(true);
      expect((await h.load(school: _otherSchool)).enabled, isFalse);
      expect(PublicSubmissionStatus.fromMap(_otherSchool, await h.doc(PublicSubmissionSettings.publicCollection, _otherSchool)).open, isFalse);
      // A copy that claims another school is not this school's.
      expect(PublicSubmissionStatus.fromMap(_otherSchool, await h.doc(PublicSubmissionSettings.publicCollection, _school)).open, isFalse);

      final e = await h.activeEnquiry();
      final otherSchoolsService = FormSubmissionService(firestore: h.db, schoolId: _otherSchool);
      await expectLater(otherSchoolsService.submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.unavailable));
      await h.set(true, school: _otherSchool);
      await expectLater(otherSchoolsService.submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.notAvailable), reason: 'open, but not its form');
      expect(await h.count(FormCollections.submissions), 0);
    });

    test('a change from an out-of-date screen is refused, and says what is saved now', () async {
      final h = _Harness();
      final seen = await h.load();
      await h.set(true, actor: _secondAdmin);
      await expectLater(
        h.settings.update(schoolId: _school, requesterRole: 'admin', requesterSchoolId: _school, actor: _admin, enabled: false, closedMessage: 'Mine', expectedRevision: seen.revision),
        throwsA(isA<PublicSubmissionSettingsConflict>().having((c) => (c.current.enabled, c.current.revision), 'current', (true, 1))),
      );
      final now = await h.load();
      expect((now.enabled, now.closedMessage, now.updatedByName), (true, '', 'Second admin'), reason: 'nothing of the refused change was saved');
    });

    test('the closed message is limited in length', () async {
      final h = _Harness();
      await expectLater(h.set(false, message: 'x' * 301), throwsArgumentError);
      expect((await h.set(false, message: 'x' * 300)).closedMessage, hasLength(300));
    });
  });

  group('submissions', () {
    test('are refused while OFF (never switched on, or switched off), by the service itself', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await expectLater(h.trusted.submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.unavailable));
      await expectLater(TrustedServiceGateway(h.trusted).submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.unavailable), reason: 'an open gateway doesn’t bypass it');

      await h.set(true);
      await h.set(false);
      await expectLater(h.trusted.submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.unavailable));
      expect(await h.count(FormCollections.submissions), 0);
    });

    test('are accepted while ON', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await h.set(true);
      final receipt = await TrustedServiceGateway(h.trusted).submit(h.request(e.form.id, e.answers));
      expect(receipt.reference, startsWith('WF-'));
      expect(await h.count(FormCollections.submissions), 1);
    });

    test('an unreadable setting refuses them as closed', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await h.set(true);
      h.db.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${FormCollections.publicForms}/{id} { allow read: if true; }
    match /${FormCollections.forms}/{id} { allow read: if true; }
    match /${FormCollections.submissions}/{id} { allow read, write: if true; }
  }
}''').securityRules;
      await expectLater(h.trusted.submit(h.request(e.form.id, e.answers)), _refused(FormSubmissionErrorCode.unavailable));
      expect(await h.count(FormCollections.submissions), 0);
    });

    test('switching OFF and ON keeps every form, version, submission and note', () async {
      final h = _Harness();
      final e = await h.activeEnquiry();
      await h.set(true);
      final r = await h.trusted.submit(h.request(e.form.id, e.answers));
      await h.db.collection(FormCollections.submissions).doc(r.submissionId).collection(FormCollections.notes).add({'text': 'Synthetic note'});
      Future<Map<String, Object?>> snapshot() async => {
            for (final c in [FormCollections.forms, FormCollections.publicForms, FormCollections.submissions, FormCollections.versions])
              c: [for (final d in (await h.db.collection(c).get()).docs) d.data().toString()],
            'notes': (await h.db.collection(FormCollections.submissions).doc(r.submissionId).collection(FormCollections.notes).get()).docs.length,
          };
      final before = await snapshot();
      await h.set(false, message: 'Closed for now.');
      expect(await snapshot(), before);
      await h.set(true);
      expect(await snapshot(), before);
    });
  });

  group('the public form', () {
    final form = PublicWebsiteForm(
      id: 'form123',
      schoolId: _school,
      title: const LocalizedText(en: 'Contact us'),
      items: [WebsiteFormField.create(FormFieldType.shortText, 'Your name', required: true)],
      successMessage: const LocalizedText(en: 'Thanks'),
      version: 1,
    );

    Future<void> pump(WidgetTester tester, {required Stream<PublicSubmissionStatus> Function() status, FormSubmissionGateway gateway = const _AcceptingGateway(), PublicLanguage language = PublicLanguage.english}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formSubmissionGatewayProvider.overrideWithValue(gateway),
          publicSubmissionStatusProvider.overrideWith((ref) => status()),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PublicWebsiteFormView(form: form, language: language, media: const {})))),
      ));
      await tester.pump();
    }

    VoidCallback? send(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('website-form-submit'))).onPressed;
    const open = PublicSubmissionStatus(schoolId: _school, open: true, revision: 1);

    testWidgets('OFF: the form is shown with the school’s closed message, and Send is disabled', (tester) async {
      await pump(tester, status: () => Stream.value(const PublicSubmissionStatus(schoolId: _school, open: false, closedMessage: 'Admissions reopen in June. Call the office.', revision: 2)));
      expect(find.text('Your name *'), findsOneWidget, reason: 'the form is still rendered');
      expect(find.text('Admissions reopen in June. Call the office.'), findsOneWidget);
      expect(send(tester), isNull);

      // No message of its own: the website's wording, in the visitor's language.
      await pump(tester, status: () => Stream.value(const PublicSubmissionStatus(schoolId: _school, open: false)));
      expect(find.text('Online submissions aren’t open yet. Please contact the school directly.'), findsOneWidget);
      await pump(tester, status: () => Stream.value(const PublicSubmissionStatus(schoolId: _school, open: false)), language: PublicLanguage.tamil);
      expect(find.textContaining('இணைய வழிச் சமர்ப்பிப்புகள்'), findsOneWidget);
    });

    testWidgets('loading: Send waits; unreadable: closed', (tester) async {
      final pending = StreamController<PublicSubmissionStatus>();
      addTearDown(pending.close);
      await pump(tester, status: () => pending.stream);
      expect(send(tester), isNull);
      expect(find.byKey(const Key('website-form-closed')), findsNothing, reason: 'nothing said before it is known');

      await pump(tester, status: () => Stream.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')));
      expect(find.byKey(const Key('website-form-closed')), findsOneWidget);
      expect(send(tester), isNull);
    });

    testWidgets('ON: Send is offered; a write Firestore refuses is said as such, never as closed or sent', (tester) async {
      await pump(tester, status: () => Stream.value(open));
      expect(find.byKey(const Key('website-form-closed')), findsNothing);
      expect(send(tester), isNotNull);

      await pump(tester, status: () => Stream.value(open), gateway: const _FailingGateway(FormSubmissionErrorCode.permissionDenied));
      await tester.enterText(find.byType(TextField), 'Asha Example');
      await tester.tap(find.byKey(const Key('website-form-submit')));
      await tester.pump();
      expect(find.text('The website couldn’t save your response. Please contact the school directly.'), findsOneWidget);
      expect(find.byKey(const Key('website-form-success')), findsNothing);
      expect(find.byKey(const Key('website-form-closed')), findsNothing, reason: 'the school’s setting is still on');
      expect(send(tester), isNotNull, reason: 'they can try again');

      await pump(tester, status: () => Stream.value(open), gateway: const _FailingGateway(FormSubmissionErrorCode.failed));
      await tester.enterText(find.byType(TextField), 'Asha Example');
      await tester.tap(find.byKey(const Key('website-form-submit')));
      await tester.pump();
      expect(find.text('Your response couldn’t be sent. Check your connection and try again.'), findsOneWidget);
    });

    testWidgets('an open form closes when an administrator switches submissions off', (tester) async {
      final live = StreamController<PublicSubmissionStatus>();
      addTearDown(live.close);
      await pump(tester, status: () => live.stream);
      // The event, then the rebuild it causes.
      Future<void> hear(PublicSubmissionStatus status) async {
        live.add(status);
        await tester.pump();
        await tester.pump();
      }

      await hear(open);
      expect(send(tester), isNotNull);
      await tester.enterText(find.byType(TextField), 'Asha Example');

      await hear(const PublicSubmissionStatus(schoolId: _school, open: false, closedMessage: 'Closed for the holidays.', revision: 2));
      expect(find.text('Closed for the holidays.'), findsOneWidget);
      expect(send(tester), isNull);
      expect(find.text('Asha Example'), findsOneWidget, reason: 'what the visitor typed stays');

      await hear(const PublicSubmissionStatus(schoolId: _school, open: true, revision: 3));
      expect(send(tester), isNotNull);
    });

    testWidgets('switched off before the page heard of it: the service refuses, and the form says it is closed', (tester) async {
      final h = _Harness();
      final e = await tester.runAsync(() async {
        final e = await h.activeEnquiry();
        await h.set(true);
        await h.set(false, message: 'Closed for the holidays.');
        return e;
      });
      final active = (await tester.runAsync(() => PublicFormsRepository(firestore: h.db).activeForm(e!.form.id)))!;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          formSubmissionGatewayProvider.overrideWithValue(TrustedServiceGateway(h.trusted)),
          // The page still believes it is open.
          publicSubmissionStatusProvider.overrideWith((ref) => Stream.value(open)),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PublicWebsiteFormView(form: active, language: PublicLanguage.english, media: const {})))),
      ));
      await tester.pump();
      final f = active.fields;
      await tester.enterText(find.byKey(Key('website-form-field-${f[0].id}')), 'Asha Example');
      await tester.enterText(find.byKey(Key('website-form-field-${f[1].id}')), 'asha@example.com');
      await tester.enterText(find.byKey(Key('website-form-field-${f[3].id}')), 'Do you have places?');
      await tester.ensureVisible(find.byKey(Key('website-form-field-${f[4].id}')));
      await tester.tap(find.byKey(Key('website-form-field-${f[4].id}')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('website-form-submit')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('website-form-submit')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.byKey(const Key('website-form-closed')), findsOneWidget);
      expect(find.byKey(const Key('website-form-message')), findsNothing, reason: 'said once');
      expect(send(tester), isNull);
      expect(await tester.runAsync(() => h.count(FormCollections.submissions)), 0);
    });
  });

  group('the settings screen', () {
    Future<void> pump(WidgetTester tester, PublicSubmissionSettingsService service, {String role = 'admin', Widget? home, FormSubmissionGateway gateway = const _AcceptingGateway()}) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => AppUser(id: _admin.id, phone: _admin.phone, role: role, isActive: true, name: 'Test admin')),
          formSubmissionGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(home: home ?? PublicSubmissionsSettingsScreen(service: service)),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    bool switchOn(WidgetTester tester) => tester.widget<Switch>(find.byKey(const Key('public-submissions-switch'))).value;

    Future<void> toggle(WidgetTester tester, {bool confirm = true}) async {
      await tester.tap(find.byKey(const Key('public-submissions-switch')));
      await tester.pumpAndSettle();
      if (confirm) {
        await tester.tap(find.byKey(const Key('public-submissions-confirm')));
      } else {
        await tester.tap(find.text('Cancel'));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }

    testWidgets('Settings lists it; it opens OFF with no history', (tester) async {
      final h = _Harness();
      await pump(tester, h.settings, home: AdminSettingsScreen(publicSubmissions: h.settings));
      await tester.tap(find.byKey(const Key('settings-public-submissions')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(switchOn(tester), isFalse);
      expect(find.text('Off: visitors can’t send forms'), findsOneWidget);
      expect(find.text('Never changed: off by default.'), findsOneWidget);
    });

    testWidgets('turning on and off asks first, then shows only what was saved', (tester) async {
      final h = _Harness();
      await pump(tester, h.settings);
      await toggle(tester, confirm: false);
      expect(switchOn(tester), isFalse, reason: 'cancelled');
      expect(await tester.runAsync(() => h.count(PublicSubmissionSettings.publicCollection)), 0);

      await toggle(tester);
      expect(switchOn(tester), isTrue);
      expect(find.text('Public submissions turned on'), findsOneWidget);
      expect(find.text('On: visitors can send forms'), findsOneWidget);
      expect(find.textContaining('Last changed by Test admin'), findsOneWidget);
      expect((await tester.runAsync(h.load))!.enabled, isTrue);

      await toggle(tester);
      expect(switchOn(tester), isFalse);
      expect((await tester.runAsync(h.load))!.enabled, isFalse);
    });

    testWidgets('the closed message is saved, and kept after a reload', (tester) async {
      final h = _Harness();
      await pump(tester, h.settings);
      await tester.enterText(find.byKey(const Key('public-submissions-message')), 'Admissions reopen in June.');
      await tester.pump();
      await tester.tap(find.byKey(const Key('public-submissions-save-message')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.text('Message saved'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, PublicSubmissionSettingsService(firestore: h.db));
      expect(tester.widget<TextField>(find.byKey(const Key('public-submissions-message'))).controller!.text, 'Admissions reopen in June.');
      expect(switchOn(tester), isFalse);
    });

    testWidgets('a failed change leaves the saved state showing', (tester) async {
      final db = FakeFirebaseFirestore();
      final failing = _FailingService(db);
      await pump(tester, failing);
      await toggle(tester);
      expect(failing.attempts, 1);
      expect(switchOn(tester), isFalse);
      expect(find.text('The change couldn’t be saved. The setting is unchanged.'), findsOneWidget);
      expect(find.text('Public submissions turned on'), findsNothing);
      expect(await tester.runAsync(() => db.collection(PublicSubmissionSettings.publicCollection).get().then((s) => s.docs.length)), 0);
    });

    testWidgets('another administrator’s change is shown instead of overwritten', (tester) async {
      final h = _Harness();
      await pump(tester, h.settings);
      await tester.runAsync(() => h.set(true, message: 'Theirs', actor: _secondAdmin));
      await toggle(tester);
      expect(find.text('Another administrator changed this setting. Review it and try again.'), findsOneWidget);
      expect(switchOn(tester), isTrue, reason: 'what is saved now');
      expect(find.textContaining('Last changed by Second admin'), findsOneWidget);
      expect((await tester.runAsync(h.load))!.closedMessage, 'Theirs');
    });

    testWidgets('unreadable: treated as off, with a retry; locked for anyone but an admin', (tester) async {
      await pump(tester, _UnreadableService());
      expect(find.byKey(const Key('public-submissions-load-error')), findsOneWidget);
      expect(find.byKey(const Key('public-submissions-switch')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, _Harness().settings, role: 'teacher');
      expect(find.byKey(const Key('public-submissions-switch')), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('the Forms Manager says whether submissions are open, and links here', (tester) async {
      final h = _Harness();
      await tester.runAsync(() => h.set(true));
      await pump(tester, h.settings, home: FormsManagerScreen(forms: h.forms, publicSubmissions: h.settings));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Public submissions are on: visitors can send the active forms.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('forms-public-submissions-change')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-submissions-switch')), findsOneWidget);
    });
  });
}

class _AcceptingGateway implements FormSubmissionGateway {
  const _AcceptingGateway();

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) async =>
      FormSubmissionReceipt(submissionId: request.submissionKey, reference: formSubmissionReference(request.submissionKey));
}

/// Every submission refused with [code].
class _FailingGateway implements FormSubmissionGateway {
  const _FailingGateway(this.code);

  final FormSubmissionErrorCode code;

  @override
  Future<FormSubmissionReceipt> submit(FormSubmissionRequest request) async => throw FormSubmissionException(code);
}
