// The Website Publishing Manager: every website page, calendar event and
// school announcement with where it stands on the public website, and
// individual or bulk publish, update and remove through the existing
// publishing services.
//
// Every record here is synthetic test data (no real students, parents or
// staff). The fake Firestore proves the app's behaviour, not deployed
// security rules (deferred).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_publishing_manager.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_publishing_manager_screen.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/models/calendar_event_model.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';

const _events = 'school_calendar_events';
const _notices = 'school_notifications';
const _copies = WebsitePublicItem.collection;
final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

/// "Now": 1 February 2027, 10:00 at school (IST).
final _now = DateTime.utc(2027, 2, 1, 4, 30);

/// Source values that must never reach the website.
const _privateValues = ['creator-0001', 'Synthetic Creator', 'secret_report.pdf', 'https://storage.example.test/private', 'internal-0001'];

class _UnusedFilePicker extends FilePicker {}

Map<String, dynamic> _event({
  String title = 'Annual Day',
  String status = CalendarEventStatus.published,
  String audience = 'Public',
  DateTime? date,
  String description = 'Performances by every class.',
}) =>
    {
      'title': title,
      'date': Timestamp.fromDate(date ?? DateTime(2027, 2, 14)),
      'startTime': '09:30',
      'endTime': '12:00',
      'eventType': CalendarEventType.event,
      'description': description,
      'location': 'School hall',
      'audience': audience,
      'status': status,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'internalNote': 'internal-0001',
    };

Map<String, dynamic> _notice({
  String title = 'Admissions open',
  String status = 'Published',
  String audience = 'Public',
  DateTime? publishDate,
  DateTime? expiryDate,
  List<String> classIds = const [],
  List<String> studentIds = const [],
  List<String> staffIds = const [],
}) =>
    {
      'title': title,
      'message': 'Admissions are open. Visit the office for a form.',
      'notificationType': 'General Announcement',
      'category': 'Admission',
      'priority': 'High',
      'audience': audience,
      'visibility': audience,
      'status': status,
      'academicYear': '2026-2027',
      'publishDate': Timestamp.fromDate(publishDate ?? DateTime.utc(2027, 1, 20, 3, 30)),
      if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate),
      'isPinned': false,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'createdAt': Timestamp.fromDate(DateTime.utc(2027, 1, 19)),
      'attachmentName': 'secret_report.pdf',
      'attachmentUrl': 'https://storage.example.test/private',
      'applicableClassIds': classIds,
      'applicableStudentIds': studentIds,
      'applicableStaffIds': staffIds,
      'isPublic': true,
      'internalNote': 'internal-0001',
    };

/// A Text block visitors see.
StructuredBlock _text(String body) {
  final b = BlockRegistry.create(BlockRegistry.text);
  return b.copyWith(values: {...b.values, 'body': LocalizedText(en: body)});
}

/// Fails publishing, updating or removing chosen sources while told to.
class _FlakyWebsite extends WebsitePublicItemsService {
  _FlakyWebsite({required super.firestore});

  final Set<String> failing = {};

  /// Reports success without writing anything.
  bool silentlyDrop = false;

  void _check(String sourceId) {
    if (failing.contains(sourceId)) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'The service is unavailable.');
  }

  @override
  Future<WebsitePublicItem> publish({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    required bool approvedForWebsite,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) async {
    _check(sourceId);
    if (silentlyDrop) return WebsitePublicItem(kind: kind, sourceId: sourceId, title: const LocalizedText(en: 'x'), startAt: _now);
    return super.publish(requesterRole: requesterRole, kind: kind, sourceId: sourceId, approvedForWebsite: approvedForWebsite, extras: extras, image: image);
  }

  @override
  Future<WebsitePublicItem> update({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) async {
    _check(sourceId);
    return super.update(requesterRole: requesterRole, kind: kind, sourceId: sourceId, extras: extras, image: image);
  }

  @override
  Future<void> withdraw({required String requesterRole, required WebsitePublicItemKind kind, required String sourceId}) async {
    _check(sourceId);
    return super.withdraw(requesterRole: requesterRole, kind: kind, sourceId: sourceId);
  }
}

class _Harness {
  _Harness() {
    final storage = MockFirebaseStorage();
    notifications = AdminNotificationService(firestore: db, storage: storage, filePicker: _UnusedFilePicker());
    content = WebsiteContentAdminService(firestore: db, storage: storage, filePicker: _UnusedFilePicker());
    website = _FlakyWebsite(firestore: db);
    manager = WebsitePublishingManager(
      content: content,
      website: website,
      calendar: CalendarService(firestore: db, notificationService: notifications),
      notifications: notifications,
      clock: () => clock,
    );
  }

  final db = FakeFirebaseFirestore();
  late final AdminNotificationService notifications;
  late final WebsiteContentAdminService content;
  late final _FlakyWebsite website;
  late final WebsitePublishingManager manager;
  DateTime clock = _now;

  Future<void> event(String id, Map<String, dynamic> data) => db.collection(_events).doc(id).set(data);
  Future<void> notice(String id, Map<String, dynamic> data) => db.collection(_notices).doc(id).set(data);

  Future<PublishingSnapshot> load() => manager.load(requesterRole: 'admin');

  Future<PublishingRunResult> run(PublishingAction action, Iterable<String> keys) =>
      manager.run(requesterRole: 'admin', actor: _admin, action: action, keys: keys);

  /// Shows an item through the existing service, as Calendar or
  /// Notifications would.
  Future<void> show(WebsitePublicItemKind kind, String id) =>
      WebsitePublicItemsService(firestore: db).publish(requesterRole: 'admin', kind: kind, sourceId: id, approvedForWebsite: true);

  Future<int> copyCount() async => (await db.collection(_copies).get()).docs.length;

  Future<String> customPage(String slug, {List<WebsiteBlock>? blocks, bool archived = false}) async {
    final page = await content.createCustomPage(requesterRole: 'admin', actor: _admin, title: LocalizedText(en: 'Page $slug'), slug: slug);
    if (blocks != null) await content.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(blocks: () => blocks));
    if (archived) await content.archiveCustomPage(requesterRole: 'admin', actor: _admin, pageId: page.id);
    return page.id;
  }

  Future<void> builtInDraft(BuiltInPage page, List<WebsiteBlock> blocks) =>
      content.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: page, blocks: blocks);
}

/// A school with something of each kind, eligible or not.
Future<_Harness> _school() async {
  final h = _Harness();
  await h.event('e_ok', _event());
  await h.event('e_draft', _event(title: 'Draft event', status: CalendarEventStatus.draft));
  await h.event('e_staff', _event(title: 'Staff meeting', audience: 'Staff'));
  await h.event('e_ended', _event(title: 'Last month', date: DateTime(2027, 1, 10)));
  await h.event('e_archived', _event(title: 'Old fair', status: CalendarEventStatus.archived));
  await h.notice('n_ok', _notice());
  await h.notice('n_class', _notice(title: 'Class trip', classIds: const ['class-1']));
  await h.notice('n_student', _notice(title: 'Your child', studentIds: const ['student-1']));
  await h.notice('n_staff', _notice(title: 'Staff rota', staffIds: const ['staff-1']));
  await h.notice('n_expired', _notice(title: 'Expired', expiryDate: DateTime.utc(2027, 1, 25)));
  await h.notice('n_scheduled', _notice(title: 'Sports day notice', publishDate: DateTime.utc(2027, 3, 1)));
  await h.notice('n_draft', _notice(title: 'Draft notice', status: 'Draft'));
  await h.notice('n_private', _notice(title: 'Parents only', audience: 'Parents'));
  return h;
}

void main() {
  group('authorization and school scoping', () {
    test('only an admin can list or act', () async {
      final h = await _school();
      for (final role in ['teacher', 'parent', 'staff', '']) {
        await expectLater(h.manager.load(requesterRole: role), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(
          h.manager.run(requesterRole: role, actor: _admin, action: PublishingAction.publish, keys: const ['event:e_ok']),
          throwsA(isA<UnauthorizedWebsiteContentException>()),
        );
      }
      expect(await h.copyCount(), 0);
      expect((await h.manager.load(requesterRole: 'Admin')).entries, isNotEmpty, reason: 'the role check ignores case, like the services');
    });

    test('another school’s website copies are never listed or changed', () async {
      final h = await _school();
      await h.show(WebsitePublicItemKind.event, 'e_ok');
      await h.db.collection(_copies).doc('event_e_ok').update({'schoolId': 'other_school'});
      await h.db.collection(_copies).doc('announcement_foreign').set({
        ...WebsitePublicItem(kind: WebsitePublicItemKind.announcement, sourceId: 'foreign', title: const LocalizedText(en: 'Elsewhere'), startAt: _now, schoolId: 'other_school').toMap(),
      });

      final s = await h.load();
      expect(s.schoolId, 'default_school');
      expect(s.byKey['announcement:foreign'], isNull, reason: 'another school’s copy without a source here is not listed');
      final e = s.byKey['event:e_ok']!;
      expect(e.copy, isNull, reason: 'the other school’s copy isn’t this school’s');
      expect(e.problem, contains('another school'));
      expect(e.can(PublishingAction.publish), isFalse);
      expect({for (final e in s.entries) e.schoolId}, {'default_school'});

      final r = await h.run(PublishingAction.publish, ['event:e_ok', 'announcement:foreign']);
      expect(r.succeeded, isEmpty);
      expect(r.skipped, hasLength(2));
      expect((await h.db.collection(_copies).doc('event_e_ok').get()).data()!['schoolId'], 'other_school', reason: 'untouched');
    });

    testWidgets('the screen is locked for anyone but an admin', (tester) async {
      final h = await _school();
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 't', phone: 't', role: 'teacher', isActive: true, name: 'Teacher'))],
        child: MaterialApp(home: WebsitePublishingManagerScreen(manager: h.manager)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('publishing-tab-unpublished')), findsNothing);
      expect(find.text('Website Publishing Manager'), findsOneWidget);
    });
  });

  group('listing and eligibility', () {
    test('unpublished items, with the existing rules’ reasons', () async {
      final h = await _school();
      final s = await h.load();
      final unpublished = const PublishingQuery().apply(s.entries, PublishingTab.unpublished);
      String? problem(String key) => s.byKey[key]!.problem;

      expect(s.byKey['event:e_ok']!.can(PublishingAction.publish), isTrue);
      expect(s.byKey['event:e_ok']!.status, PublishingStatus.unpublished);
      expect(problem('event:e_draft'), 'Only a published event can be shown on the website.');
      expect(problem('event:e_archived'), 'Only a published event can be shown on the website.');
      expect(problem('event:e_staff'), contains('audience Public'));
      expect(problem('event:e_ended'), contains('has ended'));

      expect(s.byKey['announcement:n_ok']!.can(PublishingAction.publish), isTrue);
      for (final targeted in ['n_class', 'n_student', 'n_staff']) {
        expect(problem('announcement:$targeted'), contains('particular classes, students or staff'), reason: targeted);
      }
      expect(problem('announcement:n_expired'), contains('expired'));
      expect(problem('announcement:n_scheduled'), contains('scheduled'));
      expect(problem('announcement:n_draft'), 'Only a published announcement can be shown on the website.');
      expect(problem('announcement:n_private'), contains('audience Public'));

      expect(unpublished, hasLength(s.entries.length), reason: 'nothing is on the website yet');
      expect(PublishingSelection.allEligible(unpublished, const [PublishingAction.publish]), {'event:e_ok', 'announcement:n_ok'});
    });

    test('an event that can’t be copied is ineligible, whatever its status says', () async {
      final h = _Harness();
      await h.event('e_long', _event(title: 'x' * 130));
      final e = (await h.load()).byKey['event:e_long']!;
      expect(e.sourceStatus, 'Published');
      expect(e.problem, isNotNull, reason: 'the copy’s own validation (title too long)');
      expect(e.can(PublishingAction.publish), isFalse);
    });

    test('pages: drafts that pass the page rules can be published; others say why', () async {
      final h = _Harness();
      final ok = await h.customPage('open-day', blocks: [_text('Come and visit.')]);
      final empty = await h.customPage('empty');
      final hiddenOnly = await h.customPage('hidden', blocks: [_text('Secret').copyWith(hidden: true)]);
      final archived = await h.customPage('old', blocks: [_text('Old page')], archived: true);
      final image = BlockRegistry.create(BlockRegistry.image);
      final withImage = await h.customPage('pictures', blocks: [_text('Pictures'), image.copyWith(values: {...image.values, 'mediaId': 'missing-image'})]);
      await h.builtInDraft(BuiltInPage.contact, [_text('Call us.')]);
      await h.builtInDraft(BuiltInPage.admissions, [_text('Apply now.')]);
      // Visitors already see a published Admissions heading.
      await h.db.collection(WebsiteCollections.livePages).doc('admissions').set({'headline': {'en': 'Welcome to admissions'}});

      final s = await h.load();
      expect(s.byKey['page:custom:$ok']!.can(PublishingAction.publish), isTrue);
      expect(s.byKey['page:custom:$ok']!.route, '/pages/open-day');
      expect(s.byKey['page:custom:$empty']!.problem, WebsiteContentAdminService.nothingVisibleMessage);
      expect(s.byKey['page:custom:$hiddenOnly']!.problem, WebsiteContentAdminService.nothingVisibleMessage);
      expect(s.byKey['page:custom:$archived']!.problem, contains('archived'));
      expect(s.byKey['page:custom:$withImage']!.problem, contains('isn’t published'));
      expect(s.byKey['page:builtin:contact']!.can(PublishingAction.publish), isTrue);
      expect(s.byKey['page:builtin:admissions']!.problem, contains('asks before replacing it'));
      expect(s.byKey['page:builtin:home'], isNull, reason: 'no blocks anywhere: nothing to publish');
    });

    test('published items: on website, out of date, not visible, to be removed', () async {
      final h = await _school();
      await h.event('e_edit', _event(title: 'Sports day'));
      await h.event('e_soon_over', _event(title: 'Concert', date: DateTime(2027, 2, 3)));
      await h.notice('n_later', _notice(title: 'Later', publishDate: DateTime.utc(2027, 3, 1)));
      await h.notice('n_soon_expired', _notice(title: 'Soon expired', expiryDate: DateTime.utc(2027, 2, 10)));
      for (final id in ['e_ok', 'e_edit', 'e_soon_over']) {
        await h.show(WebsitePublicItemKind.event, id);
      }
      for (final id in ['n_ok', 'n_later', 'n_soon_expired', 'n_private']) {
        if (id == 'n_private') {
          await h.db.collection(_notices).doc(id).update({'audience': 'Public', 'visibility': 'Public'});
          await h.show(WebsitePublicItemKind.announcement, id);
          await h.db.collection(_notices).doc(id).update({'audience': 'Parents', 'visibility': 'Parents'});
        } else {
          await h.show(WebsitePublicItemKind.announcement, id);
        }
      }
      await h.db.collection(_events).doc('e_edit').update({'title': 'Sports day (moved)'});
      await h.db.collection(_copies).doc('event_gone').set(
            WebsitePublicItem(kind: WebsitePublicItemKind.event, sourceId: 'gone', title: const LocalizedText(en: 'Deleted fair'), startAt: DateTime.utc(2027, 3, 1)).toMap(),
          );
      h.clock = DateTime.utc(2027, 2, 12, 4, 30); // after the concert, before the expiry

      final s = await h.load();
      expect(s.byKey['event:e_ok']!.status, PublishingStatus.onWebsite);
      expect(s.byKey['event:e_ok']!.image?.label, 'No image');
      final edited = s.byKey['event:e_edit']!;
      expect(edited.status, PublishingStatus.outOfDate);
      expect(edited.differences, ['title']);
      expect(edited.can(PublishingAction.update), isTrue);
      final over = s.byKey['event:e_soon_over']!;
      expect(over.status, PublishingStatus.notVisible, reason: 'a copy exists, but visitors don’t see an event that is over');
      expect(over.visibilityProblem, contains('ended'));
      expect(s.byKey['announcement:n_later']!.status, PublishingStatus.notVisible);
      expect(s.byKey['announcement:n_later']!.visibilityProblem, contains('publication date'));
      expect(s.byKey['announcement:n_ok']!.status, PublishingStatus.onWebsite);
      final privateNow = s.byKey['announcement:n_private']!;
      expect(privateNow.status, PublishingStatus.shouldRemove);
      expect(privateNow.can(PublishingAction.update), isFalse);
      expect(privateNow.can(PublishingAction.remove), isTrue);
      final orphan = s.byKey['event:gone']!;
      expect(orphan.sourceStatus, 'Deleted');
      expect(orphan.status, PublishingStatus.shouldRemove);

      h.clock = DateTime.utc(2027, 2, 9, 4, 30);
      expect((await h.load()).byKey['announcement:n_soon_expired']!.status, PublishingStatus.onWebsite);
      h.clock = DateTime.utc(2027, 2, 10, 4, 30);
      final expired = (await h.load()).byKey['announcement:n_soon_expired']!;
      expect(expired.status, PublishingStatus.notVisible, reason: 'expired on the website');
      expect(expired.visibilityProblem, contains('expired'));
    });
  });

  group('filters and selection', () {
    test('type, search and status filters, per tab', () async {
      final h = await _school();
      await h.customPage('open-day', blocks: [_text('Come and visit.')]);
      await h.show(WebsitePublicItemKind.event, 'e_ok');
      final s = await h.load();
      List<String> keys(PublishingQuery q, PublishingTab tab, {Set<String> failed = const {}}) => [for (final e in q.apply(s.entries, tab, failed: failed)) e.key];

      for (final type in PublishingType.values) {
        final rows = PublishingQuery(types: {type}).apply(s.entries, PublishingTab.unpublished);
        expect(rows, isNotEmpty, reason: type.name);
        expect(rows.every((e) => e.type == type), isTrue, reason: type.name);
      }
      expect(PublishingQuery(types: const {PublishingType.event, PublishingType.page}).apply(s.entries, PublishingTab.unpublished).map((e) => e.type).toSet(),
          {PublishingType.event, PublishingType.page});
      expect(keys(const PublishingQuery(search: 'admissions OPEN'), PublishingTab.unpublished), ['announcement:n_ok']);
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.eligible), PublishingTab.unpublished).toSet(),
          {'announcement:n_ok', for (final e in s.entries) if (e.isPage) e.key});
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.ineligible), PublishingTab.unpublished), contains('event:e_draft'));
      expect(keys(const PublishingQuery(), PublishingTab.unpublished), isNot(contains('event:e_ok')), reason: 'on the website now');

      expect(keys(const PublishingQuery(), PublishingTab.published), ['event:e_ok'], reason: 'All: what has a website copy');
      expect(keys(const PublishingQuery(types: {PublishingType.announcement}), PublishingTab.published), isEmpty);
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.onWebsite), PublishingTab.published), ['event:e_ok']);
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.unpublished), PublishingTab.published), contains('announcement:n_ok'));
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.unpublished), PublishingTab.published).any((k) => k.startsWith('page:')), isFalse,
          reason: 'pages are managed in their own editors');
      expect(keys(const PublishingQuery(status: PublishingStatusFilter.failed), PublishingTab.published, failed: {'announcement:n_ok'}), ['announcement:n_ok']);
      expect(keys(const PublishingQuery(), PublishingTab.published, failed: {'announcement:n_ok'}), ['event:e_ok', 'announcement:n_ok'],
          reason: 'a failed item stays listed until it succeeds');
    });

    test('select all covers every eligible match, not only the first page; mixed selections split', () async {
      final h = _Harness();
      for (var i = 0; i < 45; i++) {
        await h.event('e$i', _event(title: 'Open morning $i'));
      }
      for (var i = 0; i < 5; i++) {
        await h.event('d$i', _event(title: 'Open morning draft $i', status: CalendarEventStatus.draft));
      }
      final s = await h.load();
      final matching = const PublishingQuery(search: 'open morning').apply(s.entries, PublishingTab.unpublished);
      expect(matching, hasLength(50));
      final all = PublishingSelection.allEligible(matching, const [PublishingAction.publish]);
      expect(all, hasLength(45), reason: 'more than one page of $publishingPageSize');
      expect(all.any((k) => k.startsWith('event:d')), isFalse);

      final plan = PublishingSelection.plan({...all, 'event:d0', 'event:d1', 'event:missing'}, s, PublishingAction.publish);
      expect(plan.eligible, hasLength(45));
      expect(plan.ineligible.map((i) => i.entry.key), unorderedEquals(['event:d0', 'event:d1']));
      expect(plan.ineligible.first.reason, 'Only a published event can be shown on the website.');
      expect(plan.missing, 1);
    });
  });

  group('bulk actions', () {
    test('publishing a mixed selection publishes the eligible items through the existing services', () async {
      final h = await _school();
      final page = await h.customPage('open-day', blocks: [_text('Come and visit.')]);
      await h.builtInDraft(BuiltInPage.contact, [_text('Call us.')]);
      final s = await h.load();
      final selected = {for (final e in const PublishingQuery().apply(s.entries, PublishingTab.unpublished)) e.key};

      final progress = <int>[];
      final r = await h.manager.run(
        requesterRole: 'admin',
        actor: _admin,
        action: PublishingAction.publish,
        keys: selected,
        onProgress: (done, total) => progress.add(done),
      );
      expect(r.succeeded.map((o) => o.key), unorderedEquals(['event:e_ok', 'announcement:n_ok', 'page:custom:$page', 'page:builtin:contact']));
      expect(r.failed, isEmpty);
      expect(r.skipped, hasLength(selected.length - 4), reason: 'every ineligible item is skipped, never published');
      expect(r.complete, isFalse, reason: 'not everything selected was published');
      expect(progress.last, selected.length);

      expect(await h.copyCount(), 2);
      for (final doc in (await h.db.collection(_copies).get()).docs) {
        final text = doc.data().toString();
        for (final value in _privateValues) {
          expect(text, isNot(contains(value)), reason: '${doc.id} must not hold $value');
        }
      }
      expect((await h.db.collection(WebsiteCollections.livePages).doc(page).get()).exists, isTrue);
      expect((await h.db.collection(WebsiteCollections.livePages).doc('contact').get()).data()!['blocks'], isNotEmpty);
      expect(r.snapshot!.byKey['event:e_ok']!.status, PublishingStatus.onWebsite, reason: 'statuses re-read afterwards');
      expect(r.snapshot!.byKey['page:custom:$page']!.status, PublishingStatus.onWebsite);
    });

    test('a partial failure is reported per item, kept selected, and succeeds on retry', () async {
      final h = await _school();
      await h.event('e_two', _event(title: 'Science fair'));
      h.website.failing.add('e_two');
      final keys = {'event:e_ok', 'event:e_two', 'announcement:n_ok', 'event:e_draft'};

      final r = await h.run(PublishingAction.publish, keys);
      expect(r.succeeded.map((o) => o.key), unorderedEquals(['event:e_ok', 'announcement:n_ok']));
      expect(r.failed.single.key, 'event:e_two');
      expect(r.failed.single.message, contains('The service is unavailable.'));
      expect(r.skipped.single.key, 'event:e_draft');
      expect(r.complete, isFalse);
      expect(r.snapshot!.byKey['event:e_two']!.status, PublishingStatus.unpublished, reason: 're-read: nothing was written');
      final kept = PublishingSelection.afterRun(keys, r);
      expect(kept, {'event:e_two', 'event:e_draft'});

      h.website.failing.clear();
      final retry = await h.run(PublishingAction.publish, kept);
      expect(retry.succeeded.single.key, 'event:e_two');
      expect(retry.skipped.single.key, 'event:e_draft');
      expect(await h.copyCount(), 3);
    });

    test('publishing again never duplicates; repeated keys run once', () async {
      final h = await _school();
      final first = await h.run(PublishingAction.publish, ['event:e_ok', 'event:e_ok', 'announcement:n_ok']);
      expect(first.outcomes, hasLength(2));
      expect(first.complete, isTrue);
      final copy = (await h.db.collection(_copies).doc('event_e_ok').get()).data()!;

      final again = await h.run(PublishingAction.publish, ['event:e_ok', 'announcement:n_ok']);
      expect(again.succeeded, isEmpty);
      expect(again.skipped.map((o) => o.message).toSet(), {'It is already on the website.'});
      expect(await h.copyCount(), 2);
      expect((await h.db.collection(_copies).doc('event_e_ok').get()).data()!['publishedAt'], copy['publishedAt'], reason: 'untouched');
    });

    test('a success the website doesn’t show is reported as failed', () async {
      final h = await _school();
      h.website.silentlyDrop = true;
      final r = await h.run(PublishingAction.publish, ['event:e_ok']);
      expect(r.succeeded, isEmpty);
      expect(r.failed.single.message, contains('doesn’t show the change'));
      expect(r.complete, isFalse);
    });

    test('out-of-date copies are updated; current ones are skipped', () async {
      final h = await _school();
      await h.event('e_two', _event(title: 'Science fair'));
      await h.show(WebsitePublicItemKind.event, 'e_ok');
      await h.show(WebsitePublicItemKind.event, 'e_two');
      await h.db.collection(_events).doc('e_ok').update({'title': 'Annual Day (new time)', 'startTime': '10:00'});
      final before = await h.load();
      expect(before.byKey['event:e_ok']!.differences, ['title', 'date or time']);

      final r = await h.run(PublishingAction.update, ['event:e_ok', 'event:e_two', 'event:e_draft']);
      expect(r.succeeded.single.key, 'event:e_ok');
      expect(r.skipped.map((o) => o.key), unorderedEquals(['event:e_two', 'event:e_draft']));
      expect(r.skipped.firstWhere((o) => o.key == 'event:e_two').message, 'Its website copy is already up to date.');
      expect(r.snapshot!.byKey['event:e_ok']!.status, PublishingStatus.onWebsite);
      expect((await h.db.collection(_copies).doc('event_e_ok').get()).data()!['title'], {'en': 'Annual Day (new time)', 'ta': ''});
    });

    test('removing takes copies off the website; a failure leaves the copy and says so', () async {
      final h = await _school();
      await h.show(WebsitePublicItemKind.event, 'e_ok');
      await h.show(WebsitePublicItemKind.announcement, 'n_ok');
      h.website.failing.add('n_ok');

      final r = await h.run(PublishingAction.remove, ['event:e_ok', 'announcement:n_ok', 'announcement:n_draft']);
      expect(r.succeeded.single.key, 'event:e_ok');
      expect(r.failed.single.key, 'announcement:n_ok');
      expect(r.failed.single.message, contains('unavailable'));
      expect(r.skipped.single.message, 'It isn’t on the website.');
      expect((await h.db.collection(_copies).doc('event_e_ok').get()).exists, isFalse);
      expect((await h.db.collection(_copies).doc('announcement_n_ok').get()).exists, isTrue);
      expect(r.snapshot!.byKey['announcement:n_ok']!.status, PublishingStatus.onWebsite, reason: 're-read: still on the website');
      expect((await h.db.collection(_events).doc('e_ok').get()).exists, isTrue, reason: 'the event itself is untouched');
    });

    test('pages: never replaces a published version, never publishes an empty page', () async {
      final h = _Harness();
      final empty = await h.customPage('empty');
      final ok = await h.customPage('open-day', blocks: [_text('Come and visit.')]);
      await h.builtInDraft(BuiltInPage.admissions, [_text('Apply now.')]);
      await h.db.collection(WebsiteCollections.livePages).doc('admissions').set({'headline': {'en': 'Welcome to admissions'}});
      await h.builtInDraft(BuiltInPage.contact, [_text('Call us.')]);

      final r = await h.run(PublishingAction.publish, ['page:custom:$empty', 'page:builtin:admissions', 'page:builtin:contact']);
      expect(r.succeeded.single.key, 'page:builtin:contact');
      expect(r.skipped.firstWhere((o) => o.key == 'page:custom:$empty').message, WebsiteContentAdminService.nothingVisibleMessage);
      expect(r.skipped.firstWhere((o) => o.key == 'page:builtin:admissions').message, contains('asks before replacing it'));
      expect((await h.db.collection(WebsiteCollections.livePages).doc('admissions').get()).data(), {'headline': {'en': 'Welcome to admissions'}}, reason: 'unchanged');
      expect((await h.db.collection(WebsiteCollections.livePages).doc(empty).get()).exists, isFalse);

      // Published meanwhile from its editor: not published again from here.
      final draft = (await h.content.getCustomPage(requesterRole: 'admin', pageId: ok))!.draft;
      await h.content.publishCustomPage(requesterRole: 'admin', actor: _admin, page: draft);
      final again = await h.run(PublishingAction.publish, ['page:custom:$ok']);
      expect(again.skipped.single.message, 'It is already on the website.');
      expect(PublishingAction.values.where((a) => a != PublishingAction.publish).every((a) => !again.snapshot!.byKey['page:custom:$ok']!.can(a)), isTrue,
          reason: 'pages are updated and unpublished from their own editor');
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, _Harness h, {double width = 1200}) async {
      // Tall enough for a whole page of results.
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: WebsitePublishingManagerScreen(manager: h.manager)),
      ));
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));

    Future<void> tap(WidgetTester tester, String k) async {
      await tester.ensureVisible(key(k));
      await tester.tap(key(k));
      await tester.pumpAndSettle();
    }

    testWidgets('Website Content opens the manager', (tester) async {
      final h = await _school();
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: WebsiteContentScreen(service: h.content, publishingManager: h.manager)),
      ));
      await tester.pumpAndSettle();
      await tap(tester, 'website-open-publishing-manager');
      expect(key('publishing-tab-unpublished'), findsOneWidget);
      expect(key('publishing-tab-published'), findsOneWidget);
      expect(key('publishing-row-event:e_ok'), findsOneWidget);
    });

    testWidgets('select all spans pages; bulk publish confirms, reports and refreshes', (tester) async {
      final h = _Harness();
      for (var i = 0; i < 25; i++) {
        await h.event('e$i', _event(title: 'Open morning $i'));
      }
      await h.event('d0', _event(title: 'Draft morning', status: CalendarEventStatus.draft));
      await h.event('e_fail', _event(title: 'Failing fair'));
      h.website.failing.add('e_fail');
      await pump(tester, h);

      expect(find.text('1–20 of 27'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Card && (w.key as ValueKey<String>?)?.value.startsWith('publishing-row-') == true), findsNWidgets(20));
      await tap(tester, 'publishing-select-all-unpublished');
      expect(find.text('26 selected'), findsOneWidget, reason: 'every eligible match, on every page');
      await tap(tester, 'publishing-next-unpublished');
      expect(find.text('21–27 of 27'), findsOneWidget);
      expect(find.descendant(of: key('publishing-eligibility-event:d0'), matching: find.text('Can’t be published')), findsOneWidget);
      expect(find.text('Only a published event can be shown on the website.'), findsOneWidget);
      await tap(tester, 'publishing-select-event:d0');
      expect(find.text('26 selected'), findsOneWidget, reason: 'an ineligible row can’t be selected');
      await tap(tester, 'publishing-prev-unpublished');

      await tap(tester, 'publishing-bulk-publish-unpublished');
      expect(key('publishing-confirm-dialog'), findsOneWidget);
      expect(find.text('Selected: 26'), findsOneWidget);
      expect(find.text('Will be published: 26'), findsOneWidget);
      expect(find.text('Skipped (not eligible): 0'), findsOneWidget);
      await tap(tester, 'publishing-confirm-cancel');
      expect(await h.copyCount(), 0, reason: 'Cancel changes nothing');

      await tap(tester, 'publishing-bulk-publish-unpublished');
      await tap(tester, 'publishing-confirm-go');
      expect(key('publishing-result-dialog'), findsOneWidget);
      expect(find.text('Finished with problems'), findsOneWidget);
      expect(find.text('25 published, 1 failed.'), findsOneWidget);
      expect(find.textContaining('Failing fair: The website couldn’t be changed'), findsOneWidget);
      await tap(tester, 'publishing-result-close');

      expect(await h.copyCount(), 25);
      expect(find.text('1 selected'), findsOneWidget, reason: 'the failed item stays selected');
      expect(key('publishing-failed-event:e_fail'), findsOneWidget);
      expect(find.text('1–2 of 2'), findsOneWidget, reason: 'refreshed: only what is still unpublished');

      h.website.failing.clear();
      await tap(tester, 'publishing-publish-event:e_fail');
      await tap(tester, 'publishing-confirm-go');
      expect(find.text('All done'), findsOneWidget);
      await tap(tester, 'publishing-result-close');
      expect(key('publishing-failed-event:e_fail'), findsNothing);
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('published tab: statuses, filters, update and confirmed removal', (tester) async {
      final h = await _school();
      await h.event('e_edit', _event(title: 'Sports day'));
      await h.show(WebsitePublicItemKind.event, 'e_ok');
      await h.show(WebsitePublicItemKind.event, 'e_edit');
      await h.show(WebsitePublicItemKind.announcement, 'n_ok');
      await h.db.collection(_events).doc('e_edit').update({'location': 'Playground'});
      await pump(tester, h, width: 420);

      await tap(tester, 'publishing-tab-published');
      expect(find.descendant(of: key('publishing-status-event:e_ok'), matching: find.text('On website')), findsOneWidget);
      expect(find.descendant(of: key('publishing-status-event:e_edit'), matching: find.text('Website out of date')), findsOneWidget);
      expect(find.text('Changed since it was published: location.'), findsOneWidget);
      expect(key('publishing-row-event:e_draft'), findsNothing, reason: 'no website copy');

      await tap(tester, 'publishing-type-announcement-published');
      expect(key('publishing-row-event:e_ok'), findsNothing);
      expect(key('publishing-row-announcement:n_ok'), findsOneWidget);
      await tap(tester, 'publishing-type-announcement-published');

      await tap(tester, 'publishing-update-event:e_edit');
      expect(find.text('Update 1 website copy?'), findsOneWidget);
      await tap(tester, 'publishing-confirm-go');
      expect(find.text('All done'), findsOneWidget);
      await tap(tester, 'publishing-result-close');
      expect(find.descendant(of: key('publishing-status-event:e_edit'), matching: find.text('On website')), findsOneWidget);

      await tap(tester, 'publishing-select-all-published');
      expect(find.text('3 selected'), findsOneWidget);
      await tap(tester, 'publishing-bulk-remove-published');
      expect(find.text('Remove 3 items from the website?'), findsOneWidget);
      await tap(tester, 'publishing-confirm-cancel');
      expect(await h.copyCount(), 3, reason: 'removal only once confirmed');
      await tap(tester, 'publishing-bulk-remove-published');
      await tap(tester, 'publishing-confirm-go');
      expect(find.text('3 removed.'), findsOneWidget);
      await tap(tester, 'publishing-result-close');
      expect(await h.copyCount(), 0);
      expect(key('publishing-empty-published'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final h = _Harness();
      final failing = WebsitePublishingManager(
        content: h.content,
        website: h.website,
        calendar: _FailingCalendar(h.db),
        notifications: h.notifications,
        clock: () => _now,
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: WebsitePublishingManagerScreen(manager: failing)),
      ));
      await tester.pumpAndSettle();
      expect(key('publishing-load-error'), findsOneWidget);
      expect(key('publishing-retry'), findsOneWidget);
    });
  });
}

class _FailingCalendar extends CalendarService {
  _FailingCalendar(FirebaseFirestore db) : super(firestore: db);

  @override
  Future<List<CalendarEventModel>> getAllEvents() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}
