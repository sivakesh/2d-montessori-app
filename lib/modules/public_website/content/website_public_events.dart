import 'package:flutter/foundation.dart';

import 'website_public_item.dart';

/// The school's clock: where event dates and times are shown.
///
/// No time zone is configured anywhere in the app (school settings have
/// none), so the school's is fixed here: India Standard Time, UTC+05:30,
/// which has no daylight saving. Every visitor sees an event at the same
/// school time, labelled [label], whatever their own device's time zone
/// is. Times are stored as instants ([WebsitePublicItem.startAt]),
/// entered in the admin's browser, so an admin entering events from
/// another time zone would shift them; when a school time zone setting is
/// added, it replaces [india] here.
@immutable
class SchoolTimeZone {
  const SchoolTimeZone({required this.offset, required this.label});

  static const india = SchoolTimeZone(offset: Duration(hours: 5, minutes: 30), label: 'IST');

  /// The school's offset from UTC (fixed: no daylight saving).
  final Duration offset;

  /// Shown after times, e.g. "9:30 AM IST".
  final String label;

  /// [instant] as the school's wall-clock time. The result is a UTC
  /// [DateTime] whose fields are the school's date and time; use only its
  /// fields (year … minute), never as an instant.
  DateTime wallClock(DateTime instant) => instant.toUtc().add(offset);

  /// The instant the school's day containing [instant] ends (the next
  /// school midnight).
  DateTime endOfDay(DateTime instant) {
    final wall = wallClock(instant);
    return DateTime.utc(wall.year, wall.month, wall.day + 1).subtract(offset);
  }

  /// Whether [a] and [b] fall on the same school day.
  bool sameDay(DateTime a, DateTime b) {
    final x = wallClock(a);
    final y = wallClock(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

/// Which published events visitors see, and in what order.
///
/// An event is upcoming until it is over:
/// - with an end ([WebsitePublicItem.endAt]): until it ends;
/// - otherwise (all-day, or a start time only): until the end of its
///   school day, so today's events stay listed for the rest of the day.
///
/// Anything with an expiry ([WebsitePublicItem.expireAt]) at or before
/// [now] is left out too. Only well-formed event items for this school
/// are shown ([WebsitePublicItem.validationErrors] empty), earliest first
/// (ties by English title), at most [limit].
/// Whether visitors may see [item] at [now]: a well-formed event item for
/// this school that isn't over and hasn't expired (see
/// [upcomingPublicEvents]). An event's details page uses the same rule, so
/// a shared link stops working when the event leaves the list.
bool isPublicEventAvailable(WebsitePublicItem item, {required DateTime now, SchoolTimeZone zone = SchoolTimeZone.india}) =>
    item.kind == WebsitePublicItemKind.event &&
    item.schoolId == WebsitePublicItem.defaultSchoolId &&
    item.validationErrors().isEmpty &&
    (item.endAt ?? zone.endOfDay(item.startAt)).isAfter(now) &&
    (item.expireAt == null || item.expireAt!.isAfter(now));

/// Whether visitors may see announcement [item] at [now]: a well-formed
/// announcement for this school, from its publication date
/// ([WebsitePublicItem.startAt]) until its expiry, if any.
bool isPublicAnnouncementAvailable(WebsitePublicItem item, {required DateTime now}) =>
    item.kind == WebsitePublicItemKind.announcement &&
    item.schoolId == WebsitePublicItem.defaultSchoolId &&
    item.validationErrors().isEmpty &&
    !item.startAt.isAfter(now) &&
    (item.expireAt == null || item.expireAt!.isAfter(now));

/// Whether visitors may see [item] at [now], by its kind's rule
/// ([isPublicEventAvailable], [isPublicAnnouncementAvailable]): what the
/// lists, the detail pages and the admin's status all use.
bool isPublicItemAvailable(WebsitePublicItem item, {required DateTime now, SchoolTimeZone zone = SchoolTimeZone.india}) => switch (item.kind) {
      WebsitePublicItemKind.event => isPublicEventAvailable(item, now: now, zone: zone),
      WebsitePublicItemKind.announcement => isPublicAnnouncementAvailable(item, now: now),
    };

/// The announcements visitors see at [now] ([isPublicAnnouncementAvailable]),
/// newest first, with pinned ones first when [pinnedFirst] (ties by English
/// title), at most [limit].
List<WebsitePublicItem> currentPublicAnnouncements(Iterable<WebsitePublicItem> items, {required DateTime now, required int limit, bool pinnedFirst = true}) {
  final current = [
    for (final item in items)
      if (isPublicAnnouncementAvailable(item, now: now)) item,
  ];
  current.sort((a, b) {
    if (pinnedFirst && a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byDate = b.startAt.compareTo(a.startAt);
    return byDate != 0 ? byDate : a.title.en.compareTo(b.title.en);
  });
  return current.take(limit < 0 ? 0 : limit).toList();
}

List<WebsitePublicItem> upcomingPublicEvents(
  Iterable<WebsitePublicItem> items, {
  required DateTime now,
  required int limit,
  SchoolTimeZone zone = SchoolTimeZone.india,
}) {
  final upcoming = [
    for (final item in items)
      if (isPublicEventAvailable(item, now: now, zone: zone)) item,
  ];
  upcoming.sort((a, b) {
    final byStart = a.startAt.compareTo(b.startAt);
    return byStart != 0 ? byStart : a.title.en.compareTo(b.title.en);
  });
  return upcoming.take(limit < 0 ? 0 : limit).toList();
}
