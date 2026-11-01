import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'website_content_models.dart';
import 'website_custom_page.dart';

/// What a [WebsitePublicItem] is on the website.
enum WebsitePublicItemKind {
  /// A dated school event (from the school calendar).
  event('event', 'school_calendar_events'),

  /// A notice for visitors (from the school's announcements).
  announcement('announcement', 'school_notifications');

  const WebsitePublicItemKind(this.id, this.sourceCollection);

  /// The stored `kind` value.
  final String id;

  /// The app collection items of this kind are made from: the only source
  /// an item of this kind may name.
  final String sourceCollection;

  /// The kind stored as [value], or null for anything else.
  static WebsitePublicItemKind? parse(Object? value) {
    for (final kind in values) {
      if (kind.id == value) return kind;
    }
    return null;
  }
}

/// One event or announcement shown on the public website: a sanitized copy
/// of an app record that an administrator chose to show there.
///
/// Holds visitor-facing fields only — never who created the source, who it
/// was sent to (classes, students, staff), its attachment, or any other
/// field of the source document — so a public read of this collection can't
/// reveal anything private. Images are website media ([WebsiteMedia]),
/// whose consent and alt text the media library checks, never a source's
/// attachment URL.
///
/// Stored in [collection] under [docIdFor] (`<kind>_<sourceId>`), so one
/// source has at most one item, and publishing it again replaces the same
/// document.
@immutable
class WebsitePublicItem {
  const WebsitePublicItem({
    required this.kind,
    required this.sourceId,
    required this.title,
    required this.startAt,
    this.body = const LocalizedText(),
    this.endAt,
    this.allDay = false,
    this.location = const LocalizedText(),
    this.category = '',
    this.imageMediaId,
    this.registrationUrl,
    this.pinned = false,
    this.expireAt,
    this.publishedAt,
    this.updatedAt,
    this.schoolId = defaultSchoolId,
  });

  /// The Firestore collection of published items.
  static const collection = 'website_public_items';

  /// The school whose website shows the item. The app serves one school per
  /// Firebase project; this matches `kDefaultSchoolId` in the school
  /// settings (kept as its own constant so the public website doesn't
  /// depend on the admin modules; a test checks they agree).
  static const defaultSchoolId = 'default_school';

  static const maxTitleLength = 120;
  static const maxBodyLength = 2000;
  static const maxLocationLength = 120;
  static const maxCategoryLength = 60;

  /// The stored fields, and only these: anything else in a document is
  /// ignored when reading and never written.
  static const fields = {
    'kind', 'sourceCollection', 'sourceId', 'title', 'body', 'startAt', 'endAt', 'allDay', 'location', //
    'category', 'imageMediaId', 'registrationUrl', 'pinned', 'expireAt', 'publishedAt', 'updatedAt', 'schoolId',
  };

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final WebsitePublicItemKind kind;

  /// The source record's id in [sourceCollection].
  final String sourceId;
  final LocalizedText title;
  final LocalizedText body;

  /// When the event starts (for an announcement, from when it is shown).
  final DateTime startAt;

  /// When an event ends, if it has an end time.
  final DateTime? endAt;

  /// An event with no start time: [startAt] is only its day (midnight),
  /// which visitors should see as the date alone, never as "00:00".
  final bool allDay;
  final LocalizedText location;

  /// The source's category or event type (English), for display.
  final String category;

  /// A published website image, or none.
  final String? imageMediaId;

  /// Where visitors can register, if anywhere: a page of this website or an
  /// https, mailto or tel link ([SafeLinkTarget]). Added by an admin (it
  /// never comes from the source). A stored link that isn't allowed is
  /// ignored when read, and refused when written.
  final String? registrationUrl;
  final bool pinned;

  /// When the item stops being shown, if ever.
  final DateTime? expireAt;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final String schoolId;

  String get sourceCollection => kind.sourceCollection;

  /// This item's document id.
  String get id => docIdFor(kind, sourceId);

  /// The document id of the item for [sourceId] of [kind].
  static String docIdFor(WebsitePublicItemKind kind, String sourceId) => '${kind.id}_$sourceId';

  /// Whether [sourceId] can name a source (and so form a document id).
  static bool isValidSourceId(String sourceId) => _idPattern.hasMatch(sourceId);

  /// The item in [data], or null when it can't be shown safely: an unknown
  /// kind, a source that doesn't match the kind, a missing title or start,
  /// or the wrong shapes. Fields other than [fields] are ignored.
  static WebsitePublicItem? tryParse(Object? data) {
    try {
      if (data is! Map) return null;
      final kind = WebsitePublicItemKind.parse(data['kind']);
      if (kind == null) return null;
      if (data['sourceCollection'] != kind.sourceCollection) return null;
      final sourceId = data['sourceId'];
      if (sourceId is! String || !isValidSourceId(sourceId)) return null;
      final startAt = _date(data['startAt']);
      if (startAt == null) return null;
      for (final key in ['title', 'body', 'location']) {
        if (data[key] != null && data[key] is! Map) return null;
      }
      final title = LocalizedText.fromMap(data['title']);
      if (title.en.trim().isEmpty) return null;
      final image = data['imageMediaId'];
      final registration = data['registrationUrl'];
      final school = data['schoolId'];
      return WebsitePublicItem(
        kind: kind,
        sourceId: sourceId,
        title: title,
        body: LocalizedText.fromMap(data['body']),
        startAt: startAt,
        endAt: _date(data['endAt']),
        allDay: data['allDay'] == true,
        location: LocalizedText.fromMap(data['location']),
        category: data['category'] is String ? data['category'] as String : '',
        imageMediaId: image is String && image.isNotEmpty ? image : null,
        registrationUrl: registration is String && registration.trim().isNotEmpty && SafeLinkTarget.validate(registration) == null
            ? registration.trim()
            : null,
        pinned: data['pinned'] == true,
        expireAt: _date(data['expireAt']),
        publishedAt: _date(data['publishedAt']),
        updatedAt: _date(data['updatedAt']),
        schoolId: school is String && school.isNotEmpty ? school : defaultSchoolId,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _date(Object? value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        _ => null,
      };

  /// Every problem that would stop this item being shown: limits and
  /// "English first" in every language, an end before the start, an
  /// unusable source id.
  List<String> validationErrors() => [
        if (!isValidSourceId(sourceId)) 'The source record can’t be identified.',
        if (title.en.trim().isEmpty) 'Enter an English title.',
        ...title.problems(maxTitleLength, 'The title'),
        ...body.problems(maxBodyLength, 'The text'),
        ...location.problems(maxLocationLength, 'The location'),
        if (registrationUrl case final link? when SafeLinkTarget.validate(link) != null)
          'The registration link: ${SafeLinkTarget.validate(link)}',
        if (category.trim().length > maxCategoryLength) 'The category must be $maxCategoryLength characters or fewer.',
        if (endAt case final end? when end.isBefore(startAt)) 'An event can’t end before it starts.',
        if (expireAt case final expiry? when !expiry.isAfter(startAt)) 'The item must be shown before it expires.',
        if (schoolId.trim().isEmpty) 'The school is missing.',
      ];

  /// The stored document (timestamps are set by the service). Only
  /// [fields]; optional values are left out when absent.
  Map<String, dynamic> toMap() => {
        'kind': kind.id,
        'sourceCollection': kind.sourceCollection,
        'sourceId': sourceId,
        'title': title.toMap(),
        'body': body.toMap(),
        'startAt': Timestamp.fromDate(startAt),
        if (endAt case final end?) 'endAt': Timestamp.fromDate(end),
        if (allDay) 'allDay': true,
        'location': location.toMap(),
        'category': category.trim(),
        'imageMediaId': ?imageMediaId,
        if (registrationUrl case final link?) 'registrationUrl': link.trim(),
        'pinned': pinned,
        if (expireAt case final expiry?) 'expireAt': Timestamp.fromDate(expiry),
        'schoolId': schoolId,
      };

  /// Whether this item shows the same thing from its source as [other]:
  /// the same source, English text, dates, category, pin and expiry.
  /// Translations, image and timestamps aren't compared (they don't come
  /// from the source), so a copy whose source has changed since it was
  /// published can be told apart from one that is still current.
  bool sameSourceContentAs(WebsitePublicItem other) =>
      kind == other.kind &&
      sourceId == other.sourceId &&
      title.en == other.title.en &&
      body.en == other.body.en &&
      location.en == other.location.en &&
      startAt == other.startAt &&
      endAt == other.endAt &&
      allDay == other.allDay &&
      category.trim() == other.category.trim() &&
      pinned == other.pinned &&
      expireAt == other.expireAt;

  WebsitePublicItem copyWith({
    LocalizedText? title,
    LocalizedText? body,
    LocalizedText? location,
    String? Function()? imageMediaId,
    String? Function()? registrationUrl,
    DateTime? publishedAt,
  }) =>
      WebsitePublicItem(
        kind: kind,
        sourceId: sourceId,
        title: title ?? this.title,
        body: body ?? this.body,
        startAt: startAt,
        endAt: endAt,
        allDay: allDay,
        location: location ?? this.location,
        category: category,
        imageMediaId: imageMediaId == null ? this.imageMediaId : imageMediaId(),
        registrationUrl: registrationUrl == null ? this.registrationUrl : registrationUrl(),
        pinned: pinned,
        expireAt: expireAt,
        publishedAt: publishedAt ?? this.publishedAt,
        updatedAt: updatedAt,
        schoolId: schoolId,
      );
}
