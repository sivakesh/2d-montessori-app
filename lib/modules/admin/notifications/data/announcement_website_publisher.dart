import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../public_website/content/website_public_item.dart';
import '../../website/data/website_content_admin_service.dart';
import '../../website/data/website_copy_status.dart';
import '../../website/data/website_public_items_service.dart';
import '../models/admin_notification_model.dart';
import 'admin_notification_service.dart';

/// Puts chosen school announcements (`school_notifications`) on the public
/// website, and takes them off again, through [WebsitePublicItemsService]:
/// the same sanitized copies (`website_public_items`) as calendar events.
///
/// - Nothing is shown automatically: saving an announcement never touches
///   the website. An admin shows, updates or removes the copy explicitly
///   (Notifications → Public website).
/// - Only an announcement that is Published, for everyone (audience
///   Public) and not sent to particular classes, students or staff can be
///   shown ([ineligibility]).
/// - The copy holds the title, full message, publication date, expiry,
///   category, pin and an admin-chosen website image (by media id), never
///   the creator, recipients, attachment or any other field.
/// - One copy per announcement, at a fixed id: showing again replaces it.
/// - No flag is written to the announcement: whether it is on the website
///   is whether its copy exists.
/// - Archiving removes the copy first ([archive]).
class AnnouncementWebsitePublisher {
  AnnouncementWebsitePublisher({
    FirebaseFirestore? firestore,
    WebsitePublicItemsService? website,
    WebsiteContentAdminService? media,
    AdminNotificationService? notifications,
  })  : _firestore = firestore,
        _website = website,
        _media = media,
        _notifications = notifications;

  final FirebaseFirestore? _firestore;
  final WebsitePublicItemsService? _website;
  final WebsiteContentAdminService? _media;
  final AdminNotificationService? _notifications;

  static const _kind = WebsitePublicItemKind.announcement;

  // Built on first use, so constructing this never needs Firebase.
  late final WebsitePublicItemsService website = _website ?? WebsitePublicItemsService(firestore: _firestore);
  late final AdminNotificationService notifications = _notifications ?? AdminNotificationService(firestore: _firestore);
  late final WebsiteContentAdminService media = _media ?? WebsiteContentAdminService(firestore: _firestore);

  /// [media], or null when it can't be built here (no Firebase Storage).
  WebsiteContentAdminService? get mediaIfAvailable {
    try {
      return media;
    } catch (_) {
      return null;
    }
  }

  /// The website copies of announcements, by announcement id.
  Future<Map<String, WebsitePublicItem>> loadItems({required String requesterRole}) async {
    final items = await website.listItems(requesterRole: requesterRole);
    return {
      for (final item in items)
        if (item.kind == _kind) item.sourceId: item,
    };
  }

  /// Why [notice] can't be shown on the website, or null when it can
  /// ([WebsitePublicItemsService.announcementIneligibility]).
  static String? ineligibility(AdminNotificationModel notice) => WebsitePublicItemsService.announcementIneligibility(notice);

  /// Why [notice] (eligible) wouldn't be seen if shown now: it has expired,
  /// or it has no publication date. Null when visitors would see it (now,
  /// or from its publication date).
  static String? endedReason(AdminNotificationModel notice, {DateTime? now}) {
    if (ineligibility(notice) != null) return null;
    final WebsitePublicItem item;
    try {
      item = WebsitePublicItemsService.itemForAnnouncement(notice);
    } on WebsiteContentException catch (e) {
      return e.message;
    }
    if (item.expireAt case final expiry? when !expiry.isAfter(now ?? DateTime.now())) {
      return 'This announcement has expired, so visitors wouldn’t see it on the website.';
    }
    return null;
  }

  /// Where [notice] stands, given its copy [item] (if any), at [now]
  /// (default: the current time). "On website" ([WebsiteCopyState.current]
  /// or [WebsiteCopyState.outOfDate]) only while visitors see the copy.
  static WebsiteCopyState stateOf(AdminNotificationModel notice, WebsitePublicItem? item, {DateTime? now}) {
    if (item == null) return WebsiteCopyState.notShown;
    if (ineligibility(notice) != null) return WebsiteCopyState.noLongerEligible;
    if (visibilityProblem(item, now: now) != null) return WebsiteCopyState.notVisible;
    final WebsitePublicItem current;
    try {
      current = WebsitePublicItemsService.itemForAnnouncement(notice);
    } on WebsiteContentException {
      return WebsiteCopyState.outOfDate;
    }
    return item.sameSourceContentAs(current) ? WebsiteCopyState.current : WebsiteCopyState.outOfDate;
  }

  /// Why visitors don't see copy [item] at [now], or null.
  static String? visibilityProblem(WebsitePublicItem item, {DateTime? now}) => WebsitePublicItemsService.visibilityProblem(item, now: now);

  /// What copy [item] shows differently from [notice] as saved, in words
  /// for the admin. Empty when it is current or [notice] can't be shown.
  static List<String> differences(AdminNotificationModel notice, WebsitePublicItem item) {
    if (ineligibility(notice) != null) return const [];
    final WebsitePublicItem now;
    try {
      now = WebsitePublicItemsService.itemForAnnouncement(notice);
    } on WebsiteContentException {
      return const ['publication date'];
    }
    return [
      if (item.title.en != now.title.en) 'title',
      if (item.body.en != now.body.en) 'message',
      if (item.startAt != now.startAt) 'publication date',
      if (item.expireAt != now.expireAt) 'expiry date',
      if (item.category.trim() != now.category.trim()) 'category',
      if (item.pinned != now.pinned) 'pin',
    ];
  }

  /// Shows [notice] on the website, or replaces its copy with the
  /// announcement as saved now. Refused unless [approvedForWebsite] and it
  /// can be shown. [image]: `() => id`, `() => null` to remove the image, or
  /// null to keep it. Translations already on the copy are kept.
  Future<WebsitePublicItem> show({
    required String requesterRole,
    required AdminNotificationModel notice,
    required bool approvedForWebsite,
    String? Function()? image,
  }) =>
      website.publish(requesterRole: requesterRole, kind: _kind, sourceId: notice.id, approvedForWebsite: approvedForWebsite, image: image);

  /// Takes [noticeId]'s copy off the website (nothing happens when there is
  /// none). The announcement is untouched.
  Future<void> withdraw({required String requesterRole, required String noticeId}) =>
      website.withdraw(requesterRole: requesterRole, kind: _kind, sourceId: noticeId);

  /// Archives [notice], removing its copy first. [onWebsite] is whether it
  /// has one (null when that couldn't be loaded). When it is on the
  /// website and removing the copy fails, nothing is archived (the error is
  /// thrown). When that isn't known and removing fails, it is archived
  /// anyway and false is returned: the list then shows a copy still on the
  /// website once it can be read, so it can be removed.
  Future<bool> archive({required String requesterRole, required AdminNotificationModel notice, required bool? onWebsite}) async {
    var confirmed = true;
    if (onWebsite != false) {
      try {
        await withdraw(requesterRole: requesterRole, noticeId: notice.id);
      } catch (e) {
        if (onWebsite == true) throw WebsiteContentException('Its copy on the public website couldn’t be removed, so it wasn’t archived. $e');
        confirmed = false;
      }
    }
    await notifications.archiveNotification(notice.id);
    return confirmed;
  }
}
