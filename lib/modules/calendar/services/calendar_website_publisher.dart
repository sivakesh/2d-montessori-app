export '../../admin/website/data/website_copy_status.dart' show WebsiteCopyState;

import '../../admin/website/data/website_content_admin_service.dart';
import '../../admin/website/data/website_copy_status.dart';
import '../../admin/website/data/website_public_items_service.dart';
import '../../public_website/content/website_public_events.dart';
import '../../public_website/content/website_public_item.dart';
import '../models/calendar_event_model.dart';
import 'calendar_service.dart';

/// Where a calendar event stands on the public website (the states shared
/// with announcements, [WebsiteCopyState]).
typedef CalendarWebsiteState = WebsiteCopyState;

/// Archiving or deleting was stopped because the event's copy couldn't be
/// removed from the website first; the event is unchanged.
class CalendarWebsiteRemovalException implements Exception {
  CalendarWebsiteRemovalException(this.action, this.cause);

  /// 'archived' or 'deleted'.
  final String action;
  final Object cause;

  @override
  String toString() => 'Its copy on the public website couldn’t be removed, so it wasn’t $action. $cause';
}

/// What saving the calendar dialog did on the website.
enum CalendarWebsiteChange { none, shown, updated, withdrawn }

/// Puts chosen calendar events on the public website, and takes them off
/// again, through [WebsitePublicItemsService] (which copies visitor-facing
/// fields only, and checks the requester is an admin).
///
/// The calendar event itself is never changed for the website: whether an
/// event is shown is the existence of its item (one per event, at a fixed
/// document id, so it can't be duplicated). No flag is kept on the event,
/// so the two can't disagree.
///
/// Nothing is shown automatically, and an edit never changes the website
/// by itself: an admin shows, updates or removes the copy explicitly (the
/// event dialog's "Show on website", or the calendar's actions). Archiving
/// or deleting an event removes its copy first, so it can't stay visible.
class CalendarWebsitePublisher {
  CalendarWebsitePublisher({required CalendarService calendar, WebsitePublicItemsService? website, WebsiteContentAdminService? media})
      : _calendar = calendar,
        _website = website ?? WebsitePublicItemsService(firestore: calendar.firestore),
        _media = media;

  final CalendarService _calendar;
  final WebsitePublicItemsService _website;
  final WebsiteContentAdminService? _media;

  /// The website's media library (Settings → Website), for an event's image:
  /// the same library, upload, consent and publishing as every website
  /// image. Built on first use.
  late final WebsiteContentAdminService media = _media ?? WebsiteContentAdminService(firestore: _calendar.firestore);

  /// [media], or null when it can't be built here (no Firebase Storage).
  WebsiteContentAdminService? get mediaIfAvailable {
    try {
      return media;
    } catch (_) {
      return null;
    }
  }

  static const _kind = WebsitePublicItemKind.event;

  /// The website copies of calendar events, by event id.
  Future<Map<String, WebsitePublicItem>> loadItems({required String requesterRole}) async {
    final items = await _website.listItems(requesterRole: requesterRole);
    return {
      for (final item in items)
        if (item.kind == _kind) item.sourceId: item,
    };
  }

  /// Why [event] can't be shown on the website, or null when it can.
  static String? ineligibility(CalendarEventModel event) => WebsitePublicItemsService.eventIneligibility(event);

  /// Where [event] stands, given its website copy [item] (if any).
  ///
  /// "On website" ([CalendarWebsiteState.current] or
  /// [CalendarWebsiteState.outOfDate]) means visitors see the copy at [now]
  /// (default: the current time), by the same rule as Upcoming events and
  /// the event's page ([isPublicEventAvailable]).
  static CalendarWebsiteState stateOf(CalendarEventModel event, WebsitePublicItem? item, {DateTime? now}) {
    if (item == null) return CalendarWebsiteState.notShown;
    if (ineligibility(event) != null) return CalendarWebsiteState.noLongerEligible;
    if (visibilityProblem(item, now: now) != null) return CalendarWebsiteState.notVisible;
    return item.sameSourceContentAs(WebsitePublicItemsService.itemForEvent(event))
        ? CalendarWebsiteState.current
        : CalendarWebsiteState.outOfDate;
  }

  /// Why visitors don't see the website copy [item] at [now] (default: the
  /// current time), or null when they do. Checked in the order an admin can
  /// act on: an invalid copy (Update website replaces it), then expiry, then
  /// an event that is over.
  static String? visibilityProblem(WebsitePublicItem item, {DateTime? now}) => WebsitePublicItemsService.visibilityProblem(item, now: now);


  /// Why [event], as saved, can't be shown on the website now because it is
  /// over (it would be refused by visitors' pages anyway), or null.
  static String? endedReason(CalendarEventModel event, {DateTime? now}) {
    if (ineligibility(event) != null) return null;
    final item = WebsitePublicItemsService.itemForEvent(event);
    return isPublicEventAvailable(item, now: now ?? DateTime.now()) ? null : 'This event has ended, so visitors wouldn’t see it on the website.';
  }

  /// What the website copy [item] shows differently from [event] (as
  /// saved), in words for the admin: "title", "date or time", "location",
  /// "description", "type". Empty when the copy is current or [event] can't
  /// be shown any more.
  static List<String> differences(CalendarEventModel event, WebsitePublicItem item) {
    if (ineligibility(event) != null) return const [];
    final now = WebsitePublicItemsService.itemForEvent(event);
    return [
      if (item.title.en != now.title.en) 'title',
      if (item.startAt != now.startAt || item.endAt != now.endAt || item.allDay != now.allDay) 'date or time',
      if (item.location.en != now.location.en) 'location',
      if (item.body.en != now.body.en) 'description',
      if (item.category.trim() != now.category.trim()) 'type',
    ];
  }

  /// Shows [event] on the website, or replaces its copy with the event as
  /// saved now. Refused unless [approvedForWebsite] and the event is
  /// Published for everyone. Translations and image already on the copy
  /// are kept.
  ///
  /// [image] changes the copy's image only (see
  /// [WebsitePublicItemsService.publish]): `() => id`, `() => null` to
  /// remove it, or null to keep the image it has.
  Future<WebsitePublicItem> show({
    required String requesterRole,
    required CalendarEventModel event,
    required bool approvedForWebsite,
    String? Function()? image,
  }) =>
      _website.publish(requesterRole: requesterRole, kind: _kind, sourceId: event.id, approvedForWebsite: approvedForWebsite, image: image);

  /// Takes [eventId]'s copy off the website (nothing happens when there is
  /// none). The event is untouched.
  Future<void> withdraw({required String requesterRole, required String eventId}) =>
      _website.withdraw(requesterRole: requesterRole, kind: _kind, sourceId: eventId);

  /// Applies the dialog's "Show on website" choice after [event] (as just
  /// saved) was edited: shows or updates the copy when chosen and the event
  /// can be shown, and removes it when it is on the website but isn't
  /// chosen or can't be shown any more.
  Future<CalendarWebsiteChange> applyChoice({
    required String requesterRole,
    required CalendarEventModel event,
    required bool showOnWebsite,
    required bool wasOnWebsite,
    String? Function()? image,
  }) async {
    final eligible = ineligibility(event) == null;
    if (showOnWebsite && eligible) {
      await show(requesterRole: requesterRole, event: event, approvedForWebsite: true, image: image);
      return wasOnWebsite ? CalendarWebsiteChange.updated : CalendarWebsiteChange.shown;
    }
    if (wasOnWebsite) {
      await withdraw(requesterRole: requesterRole, eventId: event.id);
      return CalendarWebsiteChange.withdrawn;
    }
    return CalendarWebsiteChange.none;
  }

  /// Archives [event], removing its website copy first. [onWebsite] is
  /// whether it has one (null when that couldn't be loaded).
  ///
  /// When the event is on the website and removing the copy fails, nothing
  /// is archived ([CalendarWebsiteRemovalException]). When that isn't known and removing
  /// fails, the event is archived anyway and false is returned: an archived
  /// event stays in the calendar, which shows a copy that is still on the
  /// website once it can be read, so it can be removed then.
  Future<bool> archive({required String requesterRole, required CalendarEventModel event, required bool? onWebsite}) async {
    var confirmed = true;
    if (onWebsite != false) {
      try {
        await withdraw(requesterRole: requesterRole, eventId: event.id);
      } catch (e) {
        if (onWebsite == true) throw CalendarWebsiteRemovalException('archived', e);
        confirmed = false;
      }
    }
    await _calendar.archiveEvent(event.id);
    return confirmed;
  }

  /// Deletes [event], removing its website copy first. Unless the event is
  /// known not to be on the website, nothing is deleted when removing the
  /// copy fails ([CalendarWebsiteRemovalException]): once the event is
  /// gone, nothing in the calendar could remove the copy any more.
  Future<void> delete({required String requesterRole, required CalendarEventModel event, required bool? onWebsite}) async {
    if (onWebsite != false) {
      try {
        await withdraw(requesterRole: requesterRole, eventId: event.id);
      } catch (e) {
        throw CalendarWebsiteRemovalException('deleted', e);
      }
    }
    await _calendar.deleteEvent(event.id);
  }
}
