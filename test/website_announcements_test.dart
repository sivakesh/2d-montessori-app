// School announcements on the public website: explicit publishing from
// Notifications, sanitized copies in website_public_items, images from the
// website media library, the Announcements block (list, grid, compact
// cards) and /announcements/<id>.
//
// Every record here is synthetic test data (no real students, parents or
// staff). The fake Firestore proves the app's behaviour, not deployed
// security rules (deferred).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/notifications/data/announcement_website_publisher.dart';
import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/admin/ui/admin_notifications_screen.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_copy_status.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/data/website_public_items_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_public_events.dart';
import 'package:montessori_app/modules/public_website/content/website_public_item.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_item_cards.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _notices = 'school_notifications';
const _kind = WebsitePublicItemKind.announcement;
final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

/// "Now": 1 February 2027, 10:00 at school (IST).
final _now = DateTime.utc(2027, 2, 1, 4, 30);
DateTime _ist(int month, int day, [int hour = 0]) => DateTime.utc(2027, month, day, hour).subtract(const Duration(hours: 5, minutes: 30));

/// A publication date already past by the real clock too (the admin screens
/// judge visibility by the current time).
final _pastPublish = DateTime.utc(2026, 1, 20, 3, 30);

/// Source values that must never reach the website.
const _privateValues = ['creator-0001', 'Synthetic Creator', 'secret_report.pdf', 'https://storage.example.test/private', '2026-2027', 'internal-0001'];

class _UnusedFilePicker extends FilePicker {}

class _FakeProcessor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async => ProcessedWebsiteImage(
        width: 1600,
        height: 900,
        display: Uint8List.fromList([1, 2, 3]),
        displayContentType: 'image/jpeg',
        thumb: Uint8List.fromList([4]),
        thumbContentType: 'image/jpeg',
      );
}

class _Picker extends FilePicker {
  int picks = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    picks++;
    return FilePickerResult([PlatformFile(name: 'synthetic_notice.jpg', size: 3, bytes: Uint8List.fromList([9, 9, 9]))]);
  }
}

/// Fails its writes while told to.
class _FlakyWebsite extends WebsitePublicItemsService {
  _FlakyWebsite({required super.firestore});

  bool failWrites = false;

  @override
  Future<WebsitePublicItem> publish({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    required bool approvedForWebsite,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) {
    if (failWrites) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.');
    return super.publish(requesterRole: requesterRole, kind: kind, sourceId: sourceId, approvedForWebsite: approvedForWebsite, extras: extras, image: image);
  }

  @override
  Future<void> withdraw({required String requesterRole, required WebsitePublicItemKind kind, required String sourceId}) {
    if (failWrites) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'offline');
    return super.withdraw(requesterRole: requesterRole, kind: kind, sourceId: sourceId);
  }
}

Map<String, dynamic> _notice({
  String title = 'Admissions open',
  String message = 'Admissions for 2027–28 are open.\n\nVisit the office for a form.',
  String status = 'Published',
  String audience = 'Public',
  DateTime? publishDate,
  DateTime? expiryDate,
  bool pinned = false,
  String category = 'Admission',
  List<String> classIds = const [],
  List<String> studentIds = const [],
  List<String> staffIds = const [],
}) =>
    {
      'title': title,
      'message': message,
      'notificationType': 'General Announcement',
      'category': category,
      'priority': 'High',
      'audience': audience,
      'visibility': audience,
      'status': status,
      'academicYear': '2026-2027',
      'publishDate': Timestamp.fromDate(publishDate ?? _pastPublish),
      if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate),
      'isPinned': pinned,
      'requiresAcknowledgement': true,
      'createdBy': 'creator-0001',
      'createdByName': 'Synthetic Creator',
      'attachmentName': 'secret_report.pdf',
      'attachmentUrl': 'https://storage.example.test/private',
      'attachmentSize': 1234,
      'attachmentMimeType': 'pdf',
      'appliesToAllClasses': classIds.isEmpty,
      'applicableClassIds': classIds,
      'applicableClassNames': [for (final _ in classIds) 'Synthetic class'],
      'appliesToAllStudents': studentIds.isEmpty,
      'applicableStudentIds': studentIds,
      'applicableStudentNames': [for (final _ in studentIds) 'Synthetic child'],
      'appliesToAllStaff': staffIds.isEmpty,
      'applicableStaffIds': staffIds,
      'applicableStaffNames': [for (final _ in staffIds) 'Synthetic staff'],
      'isPublic': true,
      'internalNote': 'internal-0001',
    };

WebsitePublicItem _item(
  String id, {
  String title = 'Notice',
  DateTime? start,
  DateTime? expire,
  bool pinned = false,
  String category = 'General',
  String? image,
  LocalizedText? titleText,
  String schoolId = WebsitePublicItem.defaultSchoolId,
}) =>
    WebsitePublicItem(
      kind: _kind,
      sourceId: id,
      title: titleText ?? LocalizedText(en: title),
      body: const LocalizedText(en: 'The full message.'),
      startAt: start ?? _ist(1, 20, 9),
      expireAt: expire,
      pinned: pinned,
      category: category,
      imageMediaId: image,
      schoolId: schoolId,
    );

const _published = WebsiteMedia(
  id: 'pub1',
  url: 'https://example.test/pub1.jpg',
  storagePath: 'website_media/pub1/123_display.jpg',
  alt: LocalizedText(en: 'Children at the gate'),
  status: WebsiteMediaStatus.published,
  consentConfirmed: true,
  inGallery: false,
);

StructuredBlock _feed({String layout = 'grid', String desktop = '3', String tablet = '2', String mobile = '1', String max = '6', bool images = true, bool category = true, bool pinned = true}) {
  final b = BlockRegistry.create(BlockRegistry.announcementsFeed);
  return b.copyWith(values: {
    ...b.values,
    'heading': const LocalizedText(en: 'Announcements', ta: 'அறிவிப்புகள்'),
    'layout': layout,
    'desktopColumns': desktop,
    'tabletColumns': tablet,
    'mobileColumns': mobile,
    'maxItems': max,
    'showImages': images,
    'showCategory': category,
    'highlightPinned': pinned,
  });
}

Future<void> _pumpFeed(
  WidgetTester tester,
  StructuredBlock block, {
  List<WebsitePublicItem>? items,
  Future<List<WebsitePublicItem>> Function()? load,
  double width = 1400,
  PublicLanguage language = PublicLanguage.english,
  List<WebsiteMedia> media = const [_published],
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh scope each time, so these overrides apply.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      publicClockProvider.overrideWithValue(() => _now),
      publicAnnouncementItemsProvider.overrideWith((ref) => load != null ? load() : Future.value(items ?? const [])),
      publishedWebsiteMediaProvider.overrideWith((ref) async => media),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WebsiteBlocksView(blocks: [block], media: const {}, language: language)),
        ),
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

Finder _imageIn(String id) => find.descendant(of: find.byKey(Key('public-announcement-announcement_$id')), matching: find.byType(Image));
String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  late FakeFirebaseFirestore firestore;
  late _FlakyWebsite website;
  late WebsiteContentAdminService media;
  late AdminNotificationService notifications;
  late AnnouncementWebsitePublisher publisher;
  late _Picker picker;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    website = _FlakyWebsite(firestore: firestore);
    picker = _Picker();
    media = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor(), filePicker: picker);
    notifications = AdminNotificationService(firestore: firestore, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
    publisher = AnnouncementWebsitePublisher(firestore: firestore, website: website, media: media, notifications: notifications);
  });

  Future<AdminNotificationModel> notice(String id) async => AdminNotificationModel.fromMap(id, (await firestore.collection(_notices).doc(id).get()).data()!);

  Future<AdminNotificationModel> seed(String id, Map<String, dynamic> data) async {
    await firestore.collection(_notices).doc(id).set(data);
    return notice(id);
  }

  Future<WebsitePublicItem> show(String id, {String? Function()? image}) async =>
      publisher.show(requesterRole: 'admin', notice: await notice(id), approvedForWebsite: true, image: image);
  Future<Map<String, dynamic>?> copy(String id) async => (await firestore.collection(WebsitePublicItem.collection).doc('announcement_$id').get()).data();
  Future<int> copies() async => (await firestore.collection(WebsitePublicItem.collection).get()).docs.length;

  // ------------------------------------------------- publishing and privacy

  group('publishing', () {
    test('only admins can list, show or withdraw', () async {
      final n = await seed('n1', _notice());
      for (final role in ['staff', 'parent', '']) {
        await expectLater(publisher.show(requesterRole: role, notice: n, approvedForWebsite: true), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(publisher.withdraw(requesterRole: role, noticeId: 'n1'), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(publisher.loadItems(requesterRole: role), throwsA(isA<UnauthorizedWebsiteContentException>()));
      }
      expect(await copies(), 0);
    });

    test('only an explicitly approved, Published announcement for everyone, sent to nobody in particular', () async {
      final ok = await seed('ok', _notice());
      await expectLater(publisher.show(requesterRole: 'admin', notice: ok, approvedForWebsite: false), throwsA(isA<WebsiteContentException>()));
      const targeted = 'This announcement is sent to particular classes, students or staff, so it can’t be shown on the website. Only announcements for everyone can.';
      for (final (id, data, reason) in [
        ('draft', _notice(status: 'Draft'), 'Only a published announcement can be shown on the website.'),
        ('scheduled', _notice(status: 'Scheduled'), 'Only a published announcement can be shown on the website.'),
        ('archived', _notice(status: 'Archived'), 'Only a published announcement can be shown on the website.'),
        ('parents', _notice(audience: 'Parents'), 'Only an announcement for everyone (audience Public) can be shown on the website; this one is for Parents.'),
        ('staff', _notice(audience: 'Staff'), 'Only an announcement for everyone (audience Public) can be shown on the website; this one is for Staff.'),
        ('admins', _notice(audience: 'Admin Only'), 'Only an announcement for everyone (audience Public) can be shown on the website; this one is for Admin Only.'),
        ('classes', _notice(classIds: ['class-0001']), targeted),
        ('students', _notice(studentIds: ['student-0001']), targeted),
        ('staffList', _notice(staffIds: ['staff-0001']), targeted),
      ]) {
        final n = await seed(id, data);
        expect(AnnouncementWebsitePublisher.ineligibility(n), reason, reason: id);
        await expectLater(show(id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', reason)), reason: id);
      }
      expect(await copies(), 0, reason: 'nothing is shown automatically, and nothing ineligible at all');
    });

    test('the copy: title, full message, dates, category and pin only; never the creator, recipients, attachment or other fields', () async {
      await seed('n1', _notice(pinned: true, publishDate: _ist(1, 20, 9), expiryDate: _ist(3, 31)));
      final item = await show('n1');
      final stored = (await copy('n1'))!;
      expect(stored.keys.toSet().difference(WebsitePublicItem.fields), isEmpty);
      final json = jsonEncode(stored, toEncodable: (o) => o.toString());
      for (final value in _privateValues) {
        expect(json, isNot(contains(value)), reason: value);
      }
      expect(item.title.en, 'Admissions open');
      expect(item.body.en, 'Admissions for 2027–28 are open.\n\nVisit the office for a form.');
      expect(item.startAt.toUtc(), _ist(1, 20, 9));
      expect(item.expireAt!.toUtc(), _ist(3, 31));
      expect(item.category, 'Admission');
      expect(item.pinned, isTrue);
      expect(item.schoolId, WebsitePublicItem.defaultSchoolId);
      expect(stored.containsKey('imageMediaId'), isFalse, reason: 'an attachment is never used as the image');
    });

    test('idempotent: showing again keeps one copy and its first publication time', () async {
      await seed('n1', _notice());
      final first = await show('n1');
      final again = await show('n1');
      expect(await copies(), 1);
      expect(again.publishedAt, first.publishedAt);
    });

    test('edited after being shown: out of date (saying what differs) until updated; translations kept', () async {
      await seed('n1', _notice());
      await show('n1');
      await firestore.collection(WebsitePublicItem.collection).doc('announcement_n1').update({'title.ta': 'சேர்க்கை தொடக்கம்'});
      await firestore.collection(_notices).doc('n1').update({'title': 'Admissions now open', 'message': 'Updated.'});
      final edited = await notice('n1');
      var items = await publisher.loadItems(requesterRole: 'admin');
      expect(AnnouncementWebsitePublisher.stateOf(edited, items['n1'], now: _now), WebsiteCopyState.outOfDate);
      expect(AnnouncementWebsitePublisher.differences(edited, items['n1']!), ['title', 'message']);
      expect(items['n1']!.title.en, 'Admissions open', reason: 'an edit alone never changes the website');

      final updated = await show('n1');
      expect(updated.title.en, 'Admissions now open');
      expect(updated.title.ta, 'சேர்க்கை தொடக்கம்');
      items = await publisher.loadItems(requesterRole: 'admin');
      expect(AnnouncementWebsitePublisher.stateOf(edited, items['n1'], now: _now), WebsiteCopyState.current);
    });

    test('eligibility lost after being shown: "no longer eligible"; the copy stays until removed', () async {
      await seed('n1', _notice());
      final item = await show('n1');
      await firestore.collection(_notices).doc('n1').update({'applicableStudentIds': ['student-0001']});
      expect(AnnouncementWebsitePublisher.stateOf(await notice('n1'), item, now: _now), WebsiteCopyState.noLongerEligible);
      await expectLater(show('n1'), throwsA(isA<WebsiteContentException>()));
    });

    test('withdraw: off the website, the announcement untouched; again changes nothing', () async {
      await seed('n1', _notice());
      await show('n1');
      await publisher.withdraw(requesterRole: 'admin', noticeId: 'n1');
      expect(await copy('n1'), isNull);
      expect((await notice('n1')).status, 'Published');
      await publisher.withdraw(requesterRole: 'admin', noticeId: 'n1');
      expect(await copies(), 0);
    });

    test('archive removes the copy first; if that fails while it is on the website, nothing is archived', () async {
      await seed('n1', _notice());
      await show('n1');
      website.failWrites = true;
      await expectLater(publisher.archive(requesterRole: 'admin', notice: await notice('n1'), onWebsite: true), throwsA(isA<WebsiteContentException>()));
      expect((await notice('n1')).status, 'Published');
      expect(await copy('n1'), isNotNull);
      website.failWrites = false;
      expect(await publisher.archive(requesterRole: 'admin', notice: await notice('n1'), onWebsite: true), isTrue);
      expect(await copy('n1'), isNull);
      expect((await notice('n1')).status, 'Archived');
    });

    test('dates: shown from its publication date until expiry; an expired one can’t be shown; not yet due is said so', () async {
      final expired = await seed('expired', _notice(publishDate: _ist(1, 2), expiryDate: _ist(1, 10)));
      expect(AnnouncementWebsitePublisher.endedReason(expired, now: _now), 'This announcement has expired, so visitors wouldn’t see it on the website.');
      final current = await seed('current', _notice());
      expect(AnnouncementWebsitePublisher.endedReason(current, now: _now), isNull);

      final soon = _item('soon', start: _ist(2, 10));
      expect(isPublicAnnouncementAvailable(soon, now: _now), isFalse);
      expect(AnnouncementWebsitePublisher.visibilityProblem(soon, now: _now), 'Visitors don’t see it yet: it is shown from its publication date.');
      final gone = _item('gone', start: _ist(1, 2), expire: _ist(1, 10));
      expect(AnnouncementWebsitePublisher.visibilityProblem(gone, now: _now), 'Visitors don’t see it: it has expired on the website.');
      expect(currentPublicAnnouncements([soon, gone, _item('now')], now: _now, limit: 6).map((i) => i.sourceId), ['now']);
    });

    test('only this school’s announcements, newest first, pinned first when chosen; events never listed', () {
      final items = [
        _item('old', start: _ist(1, 5)),
        _item('new', start: _ist(1, 25)),
        _item('pinnedOld', start: _ist(1, 3), pinned: true),
        _item('elsewhere', schoolId: 'other_school'),
        WebsitePublicItem(kind: WebsitePublicItemKind.event, sourceId: 'ev', title: const LocalizedText(en: 'Event'), startAt: _ist(2, 5)),
      ];
      expect(currentPublicAnnouncements(items, now: _now, limit: 6).map((i) => i.sourceId), ['pinnedOld', 'new', 'old']);
      expect(currentPublicAnnouncements(items, now: _now, limit: 6, pinnedFirst: false).map((i) => i.sourceId), ['new', 'old', 'pinnedOld']);
      expect(currentPublicAnnouncements(items, now: _now, limit: 2), hasLength(2));
    });

    test('malformed copies are skipped; only announcements are read', () async {
      await firestore.collection(WebsitePublicItem.collection).doc('announcement_good').set(_item('good').toMap());
      await firestore.collection(WebsitePublicItem.collection).doc('announcement_bad').set({'kind': 'announcement', 'sourceCollection': 'school_notifications', 'sourceId': 'bad', 'startAt': 'soon'});
      await firestore.collection(WebsitePublicItem.collection).doc('announcement_wrong').set({..._item('wrong').toMap(), 'sourceCollection': 'school_calendar_events'});
      await firestore.collection(WebsitePublicItem.collection).doc('event_ev').set(WebsitePublicItem(kind: WebsitePublicItemKind.event, sourceId: 'ev', title: const LocalizedText(en: 'E'), startAt: _ist(2, 5)).toMap());
      final repo = WebsiteContentRepository(firestore: firestore);
      expect((await repo.publicAnnouncements()).map((i) => i.sourceId), ['good']);
      expect(await repo.publicAnnouncement('bad'), isNull);
      expect(await repo.publicAnnouncement('ev'), isNull, reason: 'an event is never read as an announcement');
      expect(await repo.publicAnnouncement('a b'), isNull);
    });
  });

  // ------------------------------------------------------------- images

  group('images', () {
    Future<WebsiteMedia> uploadAndPublish({bool alt = true, bool consent = true, bool publish = true}) async {
      final uploaded = await media.uploadMedia(requesterRole: 'admin', actor: _admin, image: (await media.pickImage())!, inGallery: false);
      if (alt || consent) {
        await media.updateMediaDetails(
          requesterRole: 'admin', actor: _admin, mediaId: uploaded.id, alt: LocalizedText(en: alt ? 'The school gate' : ''), caption: const LocalizedText(),
          category: GalleryCategory.general, inGallery: false, focalX: 0.5, focalY: 0.5, consentConfirmed: consent,
        );
      }
      if (publish) await media.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: uploaded.id);
      return (await media.getMedia(requesterRole: 'admin', mediaId: uploaded.id))!;
    }

    test('an existing published image is associated by id; never a URL or storage path', () async {
      await firestore.collection(WebsiteCollections.media).doc('pub1').set({
        'url': _published.url, 'storagePath': _published.storagePath, 'status': 'published', 'consentConfirmed': true, 'alt': {'en': 'x'}, 'caption': {'en': ''},
      });
      await seed('n1', _notice());
      final item = await show('n1', image: () => 'pub1');
      expect(item.imageMediaId, 'pub1');
      final stored = jsonEncode((await copy('n1'))!, toEncodable: (o) => o.toString());
      expect(stored, isNot(contains('website_media/')));
      expect(stored, isNot(contains('https://')));
    });

    test('upload, alt text and consent, publish, then associate; missing alt text or consent blocks publishing the image', () async {
      await seed('n1', _notice());
      final noAlt = await uploadAndPublish(alt: false, publish: false);
      await expectLater(media.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noAlt.id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', 'Add English alt text describing the image.')));
      final noConsent = await uploadAndPublish(consent: false, publish: false);
      await expectLater(
        media.publishMedia(requesterRole: 'admin', actor: _admin, mediaId: noConsent.id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', 'Confirm the photograph is approved and consent has been obtained.')),
      );
      await expectLater(show('n1', image: () => noConsent.id), throwsA(isA<WebsiteContentException>()), reason: 'not publishable, so not attachable');

      final ok = await uploadAndPublish();
      expect((await show('n1', image: () => ok.id)).imageMediaId, ok.id);
    });

    test('replace and remove change only the image; republishing keeps it and uploads nothing', () async {
      await seed('n1', _notice());
      final first = await uploadAndPublish();
      final second = await uploadAndPublish();
      await show('n1', image: () => first.id);
      await firestore.collection(WebsitePublicItem.collection).doc('announcement_n1').update({'title.ta': 'சேர்க்கை'});
      final picks = picker.picks;
      final mediaCount = (await firestore.collection(WebsiteCollections.media).get()).docs.length;

      expect((await show('n1')).imageMediaId, first.id, reason: 'kept when not changed');
      expect(picker.picks, picks);
      expect((await firestore.collection(WebsiteCollections.media).get()).docs.length, mediaCount, reason: 'no duplicate uploads');

      final replaced = await show('n1', image: () => second.id);
      expect(replaced.imageMediaId, second.id);
      expect(replaced.title.ta, 'சேர்க்கை');
      final removed = await show('n1', image: () => null);
      expect(removed.imageMediaId, isNull);
      expect(removed.title.ta, 'சேர்க்கை');
      expect((await notice('n1')).title, 'Admissions open', reason: 'the announcement itself is untouched');
    });

    test('in use: delete and hide refused (naming the announcement and Notifications); consent withdrawal hides it at once', () async {
      await seed('n1', _notice());
      final image = await uploadAndPublish();
      await show('n1', image: () => image.id);
      expect(await media.pagesUsing(requesterRole: 'admin', mediaId: image.id), {'the “Admissions open” announcement'});
      await expectLater(media.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id), throwsA(isA<WebsiteContentException>()));
      await expectLater(
        media.hideMedia(requesterRole: 'admin', actor: _admin, mediaId: image.id),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('in the Notifications first'))),
      );
      await media.updateMediaDetails(
        requesterRole: 'admin', actor: _admin, mediaId: image.id, alt: image.alt, caption: image.caption,
        category: image.category, inGallery: false, focalX: 0.5, focalY: 0.5, consentConfirmed: false,
      );
      expect((await WebsiteContentRepository(firestore: firestore).publishedMedia()).where((m) => m.id == image.id), isEmpty);
    });
  });

  // ------------------------------------------------------------ the block

  group('block and layouts', () {
    test('registered, valid as created, with the shared defaults; Announcements preset valid', () {
      expect(BlockRegistry.definition('announcements_feed'), same(BlockRegistry.announcementsFeed));
      expect(BlockRegistry.nestable, contains(BlockRegistry.announcementsFeed));
      final block = BlockRegistry.create(BlockRegistry.announcementsFeed);
      expect(BlockRegistry.validate([block]), isEmpty);
      expect([block.string('layout'), block.string('desktopColumns'), block.string('tabletColumns'), block.string('mobileColumns'), block.string('maxItems')], ['grid', '3', '2', '1', '6']);
      expect([block.flag('showImages'), block.flag('showCategory'), block.flag('highlightPinned')], [true, true, true]);
      final section = SectionPreset.byId('announcements')!.create();
      expect(BlockRegistry.validate([section]), isEmpty);
      expect(BlockRegistry.flatten([section]).whereType<StructuredBlock>().any((b) => b.type == 'announcements_feed'), isTrue);
    });

    for (final (name, width, expected) in [('desktop', 1400.0, 3), ('tablet', 900.0, 2), ('mobile', 400.0, 1)]) {
      testWidgets('grid on $name: $expected columns', (tester) async {
        await _pumpFeed(tester, _feed(), items: [for (var d = 2; d <= 7; d++) _item('a$d', start: _ist(1, d))], width: width);
        expect(find.byKey(Key('public-announcements-columns-$expected')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('chosen columns, compact cards and list; the maximum; no message in previews; no overflow at 360 px', (tester) async {
      final items = [for (var d = 2; d <= 9; d++) _item('a$d', start: _ist(1, d), image: d == 2 ? 'pub1' : null, title: 'A long announcement title that wraps on a phone $d')];
      for (final (width, expected) in [(1400.0, 4), (900.0, 3), (400.0, 2)]) {
        await _pumpFeed(tester, _feed(layout: 'compact_cards', desktop: '4', tablet: '3', mobile: '2'), items: items, width: width);
        expect(find.byKey(Key('public-announcements-columns-$expected')), findsOneWidget, reason: '$width');
      }
      for (final layout in ['list', 'grid', 'compact_cards']) {
        await _pumpFeed(tester, _feed(layout: layout, max: '4', mobile: '2'), items: items, width: 360);
        expect(tester.takeException(), isNull, reason: layout);
        expect(find.byKey(const Key('public-announcement-announcement_a6')), findsOneWidget, reason: '$layout: newest four');
        expect(find.byKey(const Key('public-announcement-announcement_a5')), findsNothing, reason: layout);
        expect(find.text('The full message.'), findsNothing, reason: '$layout: previews never show the message');
      }
    });

    testWidgets('images on and off; only approved images; missing ones hidden gracefully', (tester) async {
      final items = [_item('pic', image: 'pub1'), _item('draft', image: 'draft1', start: _ist(1, 19)), _item('none', start: _ist(1, 18))];
      for (final layout in ['list', 'grid', 'compact_cards']) {
        await _pumpFeed(tester, _feed(layout: layout), items: items);
        expect(_imageIn('pic'), findsWidgets, reason: layout);
        expect(_imageIn('draft'), findsNothing, reason: '$layout: not published');
        expect(find.byKey(const Key('public-announcement-announcement_draft')), findsOneWidget);
        await _pumpFeed(tester, _feed(layout: layout, images: false), items: items);
        expect(_imageIn('pic'), findsNothing, reason: '$layout: images off');
      }
    });

    testWidgets('pinned first and labelled, category shown; both can be turned off', (tester) async {
      final items = [_item('new', start: _ist(1, 25), category: 'Admission'), _item('pinned', start: _ist(1, 3), pinned: true)];
      await _pumpFeed(tester, _feed(layout: 'list'), items: items);
      expect(tester.getTopLeft(find.byKey(const Key('public-announcement-announcement_pinned'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('public-announcement-announcement_new'))).dy));
      expect(find.byKey(const Key('public-announcement-pinned-announcement_pinned')), findsOneWidget);
      expect(find.byKey(const Key('public-announcement-category-announcement_new')), findsOneWidget);
      await _pumpFeed(tester, _feed(layout: 'list', category: false, pinned: false), items: items);
      expect(find.byKey(const Key('public-announcement-pinned-announcement_pinned')), findsNothing);
      expect(find.byKey(const Key('public-announcement-category-announcement_new')), findsNothing);
      expect(tester.getTopLeft(find.byKey(const Key('public-announcement-announcement_new'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('public-announcement-announcement_pinned'))).dy), reason: 'newest first');
    });

    testWidgets('empty, loading and error with retry', (tester) async {
      await _pumpFeed(tester, _feed(), items: const []);
      expect(find.text('No announcements right now.'), findsOneWidget);

      var fail = true;
      await _pumpFeed(tester, _feed(), load: () async {
        if (fail) throw StateError('offline');
        return [_item('a')];
      });
      expect(find.byKey(const Key('public-announcements-error')), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('public-announcements-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-announcement-announcement_a')), findsOneWidget);

      await _pumpFeed(tester, _feed(), load: () => Future.delayed(const Duration(seconds: 5), () => [_item('a')]), settle: false);
      await tester.pump();
      expect(find.byKey(const Key('public-announcements-loading')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('Tamil: Tamil title and labels; English where there is no Tamil', (tester) async {
      await _pumpFeed(tester, _feed(), items: [_item('ta', titleText: const LocalizedText(en: 'Holiday', ta: 'விடுமுறை'), pinned: true), _item('en', title: 'Sports day', start: _ist(1, 19))], language: PublicLanguage.tamil);
      expect(find.text('அறிவிப்புகள்'), findsOneWidget);
      expect(_text(tester, 'public-announcement-title-announcement_ta'), 'விடுமுறை');
      expect(_text(tester, 'public-announcement-title-announcement_en'), 'Sports day');
      expect(find.text('முக்கியமானது'), findsOneWidget);
      expect(_text(tester, 'public-announcement-date-announcement_ta'), 'புதன் 20 ஜனவரி 2027 அன்று வெளியிடப்பட்டது');
    });

    testWidgets('a whole card is one labelled button; not clickable in the editor’s canvas', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpFeed(tester, _feed(), items: [_item('a', title: 'Holiday')]);
      expect(find.byKey(const Key('public-announcement-open-announcement_a')), findsOneWidget);
      expect(find.bySemanticsLabel('Holiday, published Wed 20 January 2027. Opens the announcement.'), findsOneWidget);
      semantics.dispose();

      tester.view.physicalSize = const Size(1400, 2400);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicClockProvider.overrideWithValue(() => _now),
          publicAnnouncementItemsProvider.overrideWith((ref) async => [_item('a')]),
          publishedWebsiteMediaProvider.overrideWith((ref) async => const <WebsiteMedia>[]),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlocksView(blocks: [_feed()], media: const {}, language: PublicLanguage.english, interactive: false)))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-announcement-announcement_a')), findsOneWidget);
      expect(find.byKey(const Key('public-announcement-open-announcement_a')), findsNothing);
    });

    test('the layouts and column rule are the ones Upcoming events use', () {
      expect(PublicItemsLayout.parse('compact_cards'), PublicItemsLayout.compactCards);
      expect(publicItemColumns(screenWidth: 360, available: 328, desktop: 3, tablet: 2, mobile: 2, gap: 12), 2);
    });
  });

  // ------------------------------------------------------- detail pages

  group('details page', () {
    Future<void> pumpApp(WidgetTester tester, {String route = PublicRoutes.home, PublicLanguage language = PublicLanguage.english}) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
          publicClockProvider.overrideWithValue(() => _now),
          publicLanguageProvider.overrideWith((ref) => language),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
      if (route != PublicRoutes.home) {
        tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
        await tester.pumpAndSettle();
      }
    }

    Future<void> addCopy(WebsitePublicItem item, {Map<String, dynamic> raw = const {}}) =>
        firestore.collection(WebsitePublicItem.collection).doc(item.id).set({...item.toMap(), ...raw});

    String? currentRoute(WidgetTester tester) => ModalRoute.of(tester.element(find.byType(Scaffold).last))?.settings.name;

    testWidgets('from a card (keyboard too) to /announcements/<id>: title, date, category, image, full message; Back returns', (tester) async {
      await firestore.collection(WebsiteCollections.media).doc('pub1').set({
        'url': _published.url, 'storagePath': _published.storagePath, 'status': 'published', 'consentConfirmed': true, 'alt': {'en': 'Gate'}, 'caption': {'en': ''},
      });
      await addCopy(WebsitePublicItem(
        kind: _kind, sourceId: 'Ab1', title: const LocalizedText(en: 'Admissions open'), category: 'Admission', imageMediaId: 'pub1',
        body: const LocalizedText(en: 'First paragraph.\n\nSecond paragraph.'), startAt: _ist(1, 20, 9),
      ));
      final b = BlockRegistry.create(BlockRegistry.announcementsFeed);
      await WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage())
          .publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.programs, blocks: [b]);
      await pumpApp(tester, route: PublicRoutes.programs);

      final target = find.byKey(const Key('public-announcement-open-announcement_Ab1'));
      var reached = false;
      for (var i = 0; i < 60 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        reached = focused != null && find.descendant(of: target, matching: find.byWidget(focused.widget)).evaluate().isNotEmpty;
      }
      expect(reached, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(currentRoute(tester), '/announcements/Ab1');
      expect(_text(tester, 'public-announcement-title'), 'Admissions open');
      expect(_text(tester, 'public-announcement-date'), 'Published Wed 20 January 2027');
      expect(_text(tester, 'public-announcement-category'), 'ADMISSION');
      expect(find.byKey(const Key('public-announcement-image')), findsOneWidget);
      expect(_text(tester, 'public-announcement-body'), 'First paragraph.');
      expect(find.text('Second paragraph.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('public-announcement-back')));
      await tester.pumpAndSettle();
      expect(currentRoute(tester), PublicRoutes.programs);
    });

    testWidgets('direct link: Tamil with English fallback; Back goes Home', (tester) async {
      await addCopy(_item('n1', titleText: const LocalizedText(en: 'Holiday', ta: 'விடுமுறை')));
      await pumpApp(tester, route: '/announcements/n1', language: PublicLanguage.tamil);
      expect(_text(tester, 'public-announcement-title'), 'விடுமுறை');
      expect(_text(tester, 'public-announcement-body'), 'The full message.', reason: 'no Tamil: English');
      await tester.tap(find.byKey(const Key('public-announcement-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-announcement-details')), findsNothing);
    });

    for (final (name, setUpCopy, route) in <(String, Future<void> Function(Future<void> Function(WebsitePublicItem, {Map<String, dynamic> raw})), String)>[
      ('withdrawn', (add) async {}, '/announcements/n1'),
      ('expired', (add) => add(_item('n1', start: _ist(1, 2), expire: _ist(1, 10))), '/announcements/n1'),
      ('not yet due', (add) => add(_item('n1', start: _ist(3, 1))), '/announcements/n1'),
      ('another school', (add) => add(_item('n1', schoolId: 'other_school')), '/announcements/n1'),
      ('malformed', (add) => add(_item('n1'), raw: {'title': 'plain'}), '/announcements/n1'),
      ('an event in its place', (add) => add(_item('n1'), raw: {'kind': 'event', 'sourceCollection': 'school_calendar_events'}), '/announcements/n1'),
      ('a deeper address', (add) => add(_item('n1')), '/announcements/n1/x'),
    ]) {
      testWidgets('$name: not available, with ways back', (tester) async {
        await setUpCopy(addCopy);
        await pumpApp(tester, route: route);
        expect(find.byKey(const Key('public-announcement-unavailable')), findsOneWidget, reason: name);
        expect(find.byKey(const Key('public-announcement-details')), findsNothing);
        await tester.tap(find.byKey(const Key('public-back-home')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('public-announcement-unavailable')), findsNothing);
      });
    }

    testWidgets('only the website’s own collections are read: never notifications or other private records', (tester) async {
      await addCopy(_item('n1', title: 'Public notice'));
      await firestore.collection(_notices).doc('n1').set(_notice(title: 'Private notice'));
      firestore.securityRules = FakeFirebaseFirestore(securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /${WebsitePublicItem.collection}/{id} { allow read: if true; }
    match /${WebsiteCollections.media}/{id} { allow read: if true; }
    match /${WebsiteCollections.livePages}/{id} { allow read: if true; }
  }
}''').securityRules;
      await expectLater(firestore.collection(_notices).doc('n1').get(), throwsA(anything), reason: 'the rules really refuse it');
      await pumpApp(tester, route: '/announcements/n1');
      expect(_text(tester, 'public-announcement-title'), 'Public notice');
      expect(find.text('Private notice'), findsNothing);
    });

    test('announcement addresses', () {
      expect(PublicRoutes.announcement('Ab1'), '/announcements/Ab1');
      expect(PublicRoutes.announcementIdFromRoute('/announcements/Ab1/'), 'Ab1');
      expect(PublicRoutes.announcementIdFromRoute('/announcements/a/b'), isNull);
      expect(PublicRoutes.announcementIdFromRoute('/events/Ab1'), isNull);
    });
  });

  // -------------------------------------------------- Notifications (admin)

  group('Notifications → Public website', () {
    Future<void> pumpScreen(WidgetTester tester, {String role = 'admin'}) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: _admin.id, phone: _admin.phone, role: role, isActive: true, name: 'Test admin'))],
        child: MaterialApp(home: AdminNotificationsScreen(service: notifications, websitePublisher: publisher)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openWebsite(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('announcement-website-open-$id')));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    testWidgets('saving an announcement never shows it; showing it is explicit, with what will be public', (tester) async {
      await seed('n1', _notice());
      await pumpScreen(tester);
      expect(await copies(), 0);
      await openWebsite(tester, 'n1');
      expect(text(tester, 'announcement-website-status'), 'Not on the public website.');
      await tester.tap(find.byKey(const Key('announcement-website-switch')));
      await tester.pumpAndSettle();
      expect(text(tester, 'announcement-website-explanation'), contains('to anyone on the internet'));
      expect(find.byKey(const Key('announcement-website-image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect(await copy('n1'), isNotNull);
      expect(find.text('Shown on the public website'), findsOneWidget);
      expect(find.byKey(const Key('announcement-website-chip-n1')), findsOneWidget);
      expect(find.text('On website'), findsOneWidget);
    });

    testWidgets('an image chosen in the dialog is saved with it; removing it keeps the announcement', (tester) async {
      await firestore.collection(WebsiteCollections.media).doc('pub1').set({
        'url': _published.url, 'storagePath': _published.storagePath, 'status': 'published', 'consentConfirmed': true, 'alt': {'en': 'Gate'}, 'caption': {'en': ''},
      });
      await seed('n1', _notice());
      await show('n1');
      await pumpScreen(tester);
      await openWebsite(tester, 'n1');
      await tester.tap(find.byKey(const Key('announcement-website-image-choose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('website-choose-pub1')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('announcement-website-image-status')), matching: find.byType(Text))).data, 'Published');
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect((await copy('n1'))!['imageMediaId'], 'pub1');

      await openWebsite(tester, 'n1');
      await tester.tap(find.byKey(const Key('announcement-website-image-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect((await copy('n1'))!.containsKey('imageMediaId'), isFalse);
      expect(await notice('n1'), isNotNull);
    });

    testWidgets('a failed publish is reported as a failure, never as shown; the dialog stays open', (tester) async {
      await seed('n1', _notice());
      website.failWrites = true;
      await pumpScreen(tester);
      await openWebsite(tester, 'n1');
      await tester.tap(find.byKey(const Key('announcement-website-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect(text(tester, 'announcement-website-error'), startsWith('The public website wasn’t changed:'));
      expect(find.text('Shown on the public website'), findsNothing);
      expect(await copy('n1'), isNull);
    });

    testWidgets('ineligible: the switch is unavailable with the reason (Parents, targeted, expired)', (tester) async {
      await seed('parents', _notice(title: 'For parents', audience: 'Parents'));
      await seed('targeted', _notice(title: 'For one class', classIds: ['class-0001']));
      await seed('expired', _notice(title: 'Old news', publishDate: DateTime(2020, 1, 1), expiryDate: DateTime(2020, 2, 1)));
      await pumpScreen(tester);
      for (final (id, reason) in [
        ('parents', 'this one is for Parents'),
        ('targeted', 'sent to particular classes, students or staff'),
        ('expired', 'has expired'),
      ]) {
        await openWebsite(tester, id);
        expect(tester.widget<SwitchListTile>(find.byKey(const Key('announcement-website-switch'))).onChanged, isNull, reason: id);
        expect(text(tester, 'announcement-website-explanation'), contains(reason), reason: id);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('out of date after an edit, then updated; no longer eligible, then removed', (tester) async {
      await seed('n1', _notice());
      await show('n1');
      await firestore.collection(_notices).doc('n1').update({'title': 'Admissions now open'});
      await pumpScreen(tester);
      expect(find.text('Website out of date'), findsOneWidget);
      await openWebsite(tester, 'n1');
      expect(text(tester, 'announcement-website-status'), contains('(its title differs)'));
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect((await copy('n1'))!['title']['en'], 'Admissions now open');
      expect(find.text('Public website updated'), findsOneWidget);

      await firestore.collection(_notices).doc('n1').update({'audience': 'Parents'});
      await pumpScreen(tester);
      expect(find.text('Remove from website'), findsOneWidget);
      await openWebsite(tester, 'n1');
      expect(text(tester, 'announcement-website-explanation'), startsWith('Saving removes it from the website.'));
      await tester.tap(find.byKey(const Key('announcement-website-save')));
      await tester.pumpAndSettle();
      expect(await copy('n1'), isNull);
      expect(find.text('Removed from the public website'), findsOneWidget);
    });

    testWidgets('archiving says the copy goes too, and removes it', (tester) async {
      await seed('n1', _notice());
      await show('n1');
      await pumpScreen(tester);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.archive_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('It will also be removed from the public website.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(await copy('n1'), isNull);
      expect((await notice('n1')).status, 'Archived');
    });

    testWidgets('not an admin: no website actions or status at all', (tester) async {
      await seed('n1', _notice());
      await pumpScreen(tester, role: 'staff');
      expect(find.byKey(const Key('announcement-website-open-n1')), findsNothing);
      expect(find.byKey(const Key('announcement-website-chip-n1')), findsNothing);
    });
  });
}
