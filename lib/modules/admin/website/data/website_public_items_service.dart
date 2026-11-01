import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../calendar/models/calendar_event_model.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_public_events.dart';
import '../../../public_website/content/website_public_item.dart';
import '../../notifications/models/admin_notification_model.dart';
import 'website_content_admin_service.dart';

/// What an administrator adds to an item on top of its source: text in
/// languages other than English (English always comes from the source), a
/// website image and a registration link. Null fields in [WebsitePublicItemsService.update] keep
/// what the item already has.
class WebsitePublicItemExtras {
  const WebsitePublicItemExtras({
    this.title = const LocalizedText(),
    this.body = const LocalizedText(),
    this.location = const LocalizedText(),
    this.imageMediaId,
    this.registrationUrl,
  });

  /// Tamil and other languages; any English given here is ignored.
  final LocalizedText title;
  final LocalizedText body;
  final LocalizedText location;

  /// A published website image ([WebsiteMedia]), or none.
  final String? imageMediaId;

  /// Where visitors register ([WebsitePublicItem.registrationUrl]), or none.
  final String? registrationUrl;
}

/// Shows chosen school events and announcements on the public website, as
/// sanitized [WebsitePublicItem]s in [WebsitePublicItem.collection].
///
/// Nothing is ever shown automatically: an administrator publishes each
/// item, saying so explicitly (`approvedForWebsite`), from a source that is
/// Published and meant for everyone (`audience == 'Public'`). "Public" in
/// the app means everyone in the app, so that alone never puts anything on
/// the website.
///
/// Only visitor-facing fields are copied — the source's title, text, dates,
/// location and category. Who created it, who it was sent to (classes,
/// students, staff), its attachment and every other source field stay in
/// the app. Images are website media only.
///
/// Same shape as [WebsiteContentAdminService]: an injectable Firestore and
/// an admin check in every method (security rules must enforce the same;
/// they are deferred to the rules hardening phase).
class WebsitePublicItemsService {
  WebsitePublicItemsService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _items => _firestore.collection(WebsitePublicItem.collection);

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') throw UnauthorizedWebsiteContentException(requesterRole);
  }

  /// Every item on the website, newest first by start; unreadable
  /// documents are left out.
  Future<List<WebsitePublicItem>> listItems({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _items.get();
    final items = [for (final doc in snapshot.docs) ?WebsitePublicItem.tryParse(doc.data())];
    items.sort((a, b) => b.startAt.compareTo(a.startAt));
    return items;
  }

  /// The item for [sourceId] of [kind], or null when it isn't on the
  /// website.
  Future<WebsitePublicItem?> getItem({required String requesterRole, required WebsitePublicItemKind kind, required String sourceId}) async {
    _requireAdmin(requesterRole);
    if (!WebsitePublicItem.isValidSourceId(sourceId)) return null;
    return WebsitePublicItem.tryParse((await _items.doc(WebsitePublicItem.docIdFor(kind, sourceId)).get()).data());
  }

  /// Shows source [sourceId] of [kind] on the website. Refused unless
  /// [approvedForWebsite] and the source is Published for everyone.
  ///
  /// Idempotent: publishing again from the same source and [extras] stores
  /// the same item (its first publication time is kept). With [extras]
  /// null, an item already on the website keeps its translations and image.
  ///
  /// [image] changes only the image, keeping everything else [extras]
  /// leaves as it is: `() => id` shows website image `id` (it must be
  /// published), `() => null` removes the image, and null keeps it. An
  /// image is only ever referenced by its id; nothing is uploaded here.
  Future<WebsitePublicItem> publish({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    required bool approvedForWebsite,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) async {
    _requireAdmin(requesterRole);
    if (!approvedForWebsite) {
      throw WebsiteContentException('Confirm that this should be shown on the public website.');
    }
    return _write(kind, sourceId, extras, mustExist: false, image: image);
  }

  /// Refreshes an item already on the website from its source (which must
  /// still be Published for everyone) and [extras] (null keeps the item's
  /// translations and image). Refused when the item isn't on the website.
  Future<WebsitePublicItem> update({
    required String requesterRole,
    required WebsitePublicItemKind kind,
    required String sourceId,
    WebsitePublicItemExtras? extras,
    String? Function()? image,
  }) async {
    _requireAdmin(requesterRole);
    return _write(kind, sourceId, extras, mustExist: true, image: image);
  }

  /// Takes the item for [sourceId] of [kind] off the website. The source is
  /// untouched. Doing it again (or for an item never shown) changes
  /// nothing.
  Future<void> withdraw({required String requesterRole, required WebsitePublicItemKind kind, required String sourceId}) async {
    _requireAdmin(requesterRole);
    if (!WebsitePublicItem.isValidSourceId(sourceId)) throw WebsiteContentException('This record can’t be identified.');
    await _items.doc(WebsitePublicItem.docIdFor(kind, sourceId)).delete();
  }

  Future<WebsitePublicItem> _write(
    WebsitePublicItemKind kind,
    String sourceId,
    WebsitePublicItemExtras? extras, {
    required bool mustExist,
    String? Function()? image,
  }) async {
    if (!WebsitePublicItem.isValidSourceId(sourceId)) throw WebsiteContentException('This record can’t be identified.');
    final ref = _items.doc(WebsitePublicItem.docIdFor(kind, sourceId));
    final stored = await ref.get();
    final existing = WebsitePublicItem.tryParse(stored.data());
    if (mustExist && !stored.exists) throw WebsiteContentException('This item isn’t on the website. Publish it first.');

    final fromSource = await _fromSource(kind, sourceId);
    var item = _withExtras(fromSource, extras, existing);
    // An image chosen now (rather than kept from before).
    String? chosenImage = extras?.imageMediaId;
    if (image != null) {
      final chosen = image()?.trim();
      chosenImage = chosen == null || chosen.isEmpty ? null : chosen;
      item = item.copyWith(imageMediaId: () => chosenImage);
    }
    final errors = item.validationErrors();
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
    // A newly chosen image must be one visitors may see. One kept from
    // before is never re-checked here: if it has since been hidden or its
    // consent withdrawn, visitors simply don't see it (the public site only
    // shows published, consented images), and the event's text can still
    // be updated.
    if (chosenImage != null && chosenImage == item.imageMediaId) await _requirePublishedImage(chosenImage);

    // The whole document is written, so nothing but the item's own fields
    // can remain in it. The first publication time is kept.
    final firstPublished = stored.data()?['publishedAt'];
    await ref.set({
      ...item.toMap(),
      'publishedAt': firstPublished is Timestamp ? firstPublished : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return WebsitePublicItem.tryParse((await ref.get()).data())!;
  }

  /// The source's visitor-facing fields as an item (English only). Throws
  /// unless the source exists, is Published and is meant for everyone.
  Future<WebsitePublicItem> _fromSource(WebsitePublicItemKind kind, String sourceId) async {
    final doc = await _firestore.collection(kind.sourceCollection).doc(sourceId).get();
    final data = doc.data();
    if (!doc.exists || data == null) throw WebsiteContentException('This record no longer exists.');
    switch (kind) {
      case WebsitePublicItemKind.event:
        return itemForEvent(CalendarEventModel.fromMap(doc.id, data));
      case WebsitePublicItemKind.announcement:
        return itemForAnnouncement(AdminNotificationModel.fromMap(doc.id, data));
    }
  }

  /// Why [event] can't be shown on the website, or null when it can.
  static String? eventIneligibility(CalendarEventModel event) =>
      _shareProblem(published: event.status == CalendarEventStatus.published, audience: event.audience, what: 'event');

  /// What [event] shows on the website (English only, no translations or
  /// image): its day, and its local start and end times on that day. With
  /// no start time it is an all-day item, and an end time alone is left
  /// out. Throws when the event can't be shown ([eventIneligibility]).
  static WebsitePublicItem itemForEvent(CalendarEventModel event) {
    if (eventIneligibility(event) case final problem?) throw WebsiteContentException(problem);
    final day = DateTime(event.date.year, event.date.month, event.date.day);
    final start = _at(day, event.startTime);
    return WebsitePublicItem(
      kind: WebsitePublicItemKind.event,
      sourceId: event.id,
      title: LocalizedText(en: event.title.trim()),
      body: LocalizedText(en: event.description.trim()),
      startAt: start ?? day,
      endAt: start == null ? null : _at(day, event.endTime),
      allDay: start == null,
      location: LocalizedText(en: event.location.trim()),
      category: event.eventType,
    );
  }

  /// Why announcement [notice] can't be shown on the website, or null when
  /// it can: it must be Published, for everyone (audience Public), and not
  /// sent to particular classes, students or staff (a "Public" notice can
  /// still carry such lists, which make it personal).
  static String? announcementIneligibility(AdminNotificationModel notice) {
    if (_shareProblem(published: notice.status == 'Published', audience: notice.audience, what: 'announcement') case final problem?) return problem;
    if (notice.applicableClassIds.isNotEmpty || notice.applicableStudentIds.isNotEmpty || notice.applicableStaffIds.isNotEmpty) {
      return 'This announcement is sent to particular classes, students or staff, so it can’t be shown on the website. Only announcements for everyone can.';
    }
    return null;
  }

  /// What announcement [notice] shows on the website (English only, no
  /// translations or image): its title, full message, category and pin,
  /// shown from its publication date (publish date, else when it was sent,
  /// else when it was created) until its expiry date, if any. Never its
  /// creator, recipients, attachment or any other field. Throws when it
  /// can't be shown ([announcementIneligibility]) or has no date.
  static WebsitePublicItem itemForAnnouncement(AdminNotificationModel notice) {
    if (announcementIneligibility(notice) case final problem?) throw WebsiteContentException(problem);
    final shownFrom = notice.publishDate ?? notice.sentAt ?? notice.createdAt;
    if (shownFrom == null) throw WebsiteContentException('This announcement has no publication date yet.');
    return WebsitePublicItem(
      kind: WebsitePublicItemKind.announcement,
      sourceId: notice.id,
      title: LocalizedText(en: notice.title.trim()),
      body: LocalizedText(en: notice.message.trim()),
      startAt: shownFrom,
      category: notice.category,
      pinned: notice.isPinned,
      expireAt: notice.expiryDate,
    );
  }

  /// Why visitors don't see copy [item] at [now] (default: the current
  /// time), or null when they do, by the public site's own rule
  /// ([isPublicItemAvailable]). Checked in the order an admin can act on:
  /// an invalid copy (updating replaces it), then expiry, then timing.
  static String? visibilityProblem(WebsitePublicItem item, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final errors = item.validationErrors();
    if (errors.isNotEmpty) {
      return 'Visitors don’t see it: its website copy isn’t valid (${errors.first}) Update the website to replace it.';
    }
    if (item.expireAt case final expiry? when !expiry.isAfter(at)) return 'Visitors don’t see it: it has expired on the website.';
    if (!isPublicItemAvailable(item, now: at)) {
      return switch (item.kind) {
        WebsitePublicItemKind.event => 'Visitors don’t see it: the event has ended. Upcoming events and event pages show only events that aren’t over.',
        WebsitePublicItemKind.announcement => 'Visitors don’t see it yet: it is shown from its publication date.',
      };
    }
    return null;
  }

  static String? _shareProblem({required bool published, required String audience, required String what}) {
    if (!published) return 'Only a published $what can be shown on the website.';
    if (audience != 'Public') {
      return 'Only an $what for everyone (audience Public) can be shown on the website; this one is for $audience.';
    }
    return null;
  }

  /// [day] at "HH:mm" [time], or null when there's no valid time.
  static DateTime? _at(DateTime day, String? time) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(time?.trim() ?? '');
    if (match == null) return null;
    return DateTime(day.year, day.month, day.day, int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// [item] (English from its source) with the other languages, image and
  /// registration link from [extras], or — when [extras] is null — from
  /// [existing].
  static WebsitePublicItem _withExtras(WebsitePublicItem item, WebsitePublicItemExtras? extras, WebsitePublicItem? existing) {
    LocalizedText merge(LocalizedText source, LocalizedText? translations) =>
        LocalizedText(en: source.en, ta: translations?.ta ?? '', others: translations?.others ?? const {});
    final title = extras?.title ?? existing?.title;
    final body = extras?.body ?? existing?.body;
    final location = extras?.location ?? existing?.location;
    return item.copyWith(
      title: merge(item.title, title),
      body: merge(item.body, body),
      location: merge(item.location, location),
      imageMediaId: () => extras != null ? extras.imageMediaId : existing?.imageMediaId,
      registrationUrl: () {
        final link = extras != null ? extras.registrationUrl : existing?.registrationUrl;
        return link == null || link.trim().isEmpty ? null : link.trim();
      },
    );
  }

  Future<void> _requirePublishedImage(String mediaId) async {
    final doc = await _firestore.collection(WebsiteCollections.media).doc(mediaId).get();
    final data = doc.data();
    if (!doc.exists || data == null) throw WebsiteContentException('The chosen image no longer exists. Choose a different one.');
    final media = WebsiteMedia.fromMap(mediaId, data);
    // The same test as the public site's (published, consented, with a file).
    if (!media.isPublished || !media.consentConfirmed || media.url.isEmpty) {
      throw WebsiteContentException('Publish the chosen image first (Media library), or choose a published one.');
    }
  }
}
