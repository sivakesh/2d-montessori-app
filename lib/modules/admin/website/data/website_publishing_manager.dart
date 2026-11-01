import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../auth/models/app_user.dart';
import '../../../calendar/models/calendar_event_model.dart';
import '../../../calendar/services/calendar_service.dart';
import '../../../calendar/services/calendar_website_publisher.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_page_style.dart';
import '../../../public_website/content/website_public_item.dart';
import '../../notifications/data/admin_notification_service.dart';
import '../../notifications/data/announcement_website_publisher.dart';
import '../../notifications/models/admin_notification_model.dart';
import '../../settings/models/school_settings_model.dart';
import 'website_content_admin_service.dart';
import 'website_copy_status.dart';
import 'website_public_items_service.dart';

/// What a row of the Website Publishing Manager is.
enum PublishingType {
  page('Page'),
  event('Event'),
  announcement('Announcement');

  const PublishingType(this.label);

  final String label;
}

/// Where a row stands on the public website. "On website" only while
/// visitors actually see it: a copy that exists but is over, expired, not
/// yet due or invalid is [notVisible].
enum PublishingStatus {
  unpublished('Unpublished'),
  onWebsite('On website'),
  outOfDate('Website out of date'),
  notVisible('Not visible'),

  /// A copy whose source can't be shown any more (or no longer exists).
  shouldRemove('Remove from website');

  const PublishingStatus(this.label);

  final String label;
}

/// What can be done to rows, one at a time or in bulk.
enum PublishingAction {
  /// Puts an item that has no website copy on the website.
  publish('Publish', 'Published'),

  /// Replaces an out-of-date copy with the item as saved now.
  update('Update website', 'Updated'),

  /// Takes a copy off the website (the source is untouched).
  remove('Remove from website', 'Removed');

  const PublishingAction(this.label, this.done);

  final String label;
  final String done;
}

/// One page, event or announcement and where it stands on the website.
@immutable
class PublishingEntry {
  const PublishingEntry({
    required this.key,
    required this.type,
    required this.sourceId,
    required this.title,
    required this.sourceStatus,
    required this.schoolId,
    required this.status,
    this.date,
    this.problem,
    this.note,
    this.differences = const [],
    this.copy,
    this.visibilityProblem,
    this.image,
    this.route,
  });

  /// Unique across types: `page:custom:<id>`, `page:builtin:<id>`,
  /// `event:<id>`, `announcement:<id>`.
  final String key;
  final PublishingType type;
  final String sourceId;
  final String title;

  /// The source's own status (Draft, Published, Archived, …), or "Deleted"
  /// for a copy whose source is gone.
  final String sourceStatus;
  final String schoolId;
  final PublishingStatus status;

  /// An event's date, or when an announcement is shown from.
  final DateTime? date;

  /// Why it can't be published (or its copy updated) now, or null when it
  /// can. Checked by the existing publishing rules, never by its status
  /// field alone.
  final String? problem;

  /// Anything else the admin should know (what is published, when it
  /// would be shown).
  final String? note;

  /// What its website copy shows differently from the source.
  final List<String> differences;

  /// Its website copy, if it has one (events and announcements).
  final WebsitePublicItem? copy;

  /// Why visitors don't see [copy] now, or null.
  final String? visibilityProblem;

  /// Its website image's status, for events and announcements on the
  /// website.
  final ({String label, String detail, Color color, bool visible})? image;

  /// A page's web address.
  final String? route;

  bool get isPage => type == PublishingType.page;

  /// Whether it has a website copy (or, for a page, a published version).
  bool get hasCopy => status != PublishingStatus.unpublished;

  /// The copy shows something the source no longer does, or is invalid.
  bool get isStale => copy != null && (differences.isNotEmpty || copy!.validationErrors().isNotEmpty);

  bool can(PublishingAction action) => switch (action) {
        PublishingAction.publish => !hasCopy && problem == null,
        PublishingAction.update => !isPage && copy != null && problem == null && isStale,
        PublishingAction.remove => !isPage && copy != null,
      };

  /// Why [action] can't be done to it, or null when it can.
  String? whyNot(PublishingAction action) {
    if (can(action)) return null;
    return switch (action) {
      PublishingAction.publish => hasCopy ? 'It is already on the website.' : problem!,
      PublishingAction.update => isPage
          ? 'Pages are updated from their own editor.'
          : copy == null
              ? 'It isn’t on the website.'
              : problem ?? 'Its website copy is already up to date.',
      PublishingAction.remove => isPage ? 'Pages are unpublished from their own editor.' : 'It isn’t on the website.',
    };
  }
}

/// Everything the manager lists, read at one time.
class PublishingSnapshot {
  PublishingSnapshot({required this.entries, required this.loadedAt, required this.schoolId}) : byKey = {for (final e in entries) e.key: e};

  final List<PublishingEntry> entries;
  final Map<String, PublishingEntry> byKey;
  final DateTime loadedAt;
  final String schoolId;
}

enum PublishingOutcomeKind { succeeded, failed, skipped }

/// What happened to one item in a run.
@immutable
class PublishingOutcome {
  const PublishingOutcome(this.key, this.title, this.kind, this.message);

  final String key;
  final String title;
  final PublishingOutcomeKind kind;
  final String message;
}

/// What a run did, judged from the website as re-read afterwards.
class PublishingRunResult {
  PublishingRunResult({required this.action, required this.outcomes, this.snapshot, this.reloadError});

  final PublishingAction action;
  final List<PublishingOutcome> outcomes;

  /// The state after the run, or null when it couldn't be re-read
  /// ([reloadError]): successes are then unconfirmed, so reported as
  /// failures.
  final PublishingSnapshot? snapshot;
  final Object? reloadError;

  List<PublishingOutcome> _of(PublishingOutcomeKind kind) => [for (final o in outcomes) if (o.kind == kind) o];
  List<PublishingOutcome> get succeeded => _of(PublishingOutcomeKind.succeeded);
  List<PublishingOutcome> get failed => _of(PublishingOutcomeKind.failed);
  List<PublishingOutcome> get skipped => _of(PublishingOutcomeKind.skipped);

  /// Every item was done (none failed or skipped).
  bool get complete => outcomes.isNotEmpty && failed.isEmpty && skipped.isEmpty;
}

/// Which tab rows are listed for.
enum PublishingTab { unpublished, published }

/// The status filter. [any] in the Published tab means "has a website
/// copy, or the last action on it failed".
enum PublishingStatusFilter {
  any('All'),
  eligible('Can be published'),
  ineligible('Can’t be published'),
  onWebsite('On website'),
  outOfDate('Website out of date'),
  notVisible('Not visible'),
  shouldRemove('Remove from website'),
  unpublished('Unpublished'),
  failed('Failed');

  const PublishingStatusFilter(this.label);

  final String label;

  static const forUnpublishedTab = [any, eligible, ineligible, failed];
  static const forPublishedTab = [any, onWebsite, outOfDate, notVisible, shouldRemove, unpublished, failed];
}

/// Search, type and status filters, applied independently of the UI.
@immutable
class PublishingQuery {
  const PublishingQuery({this.search = '', this.types = const {}, this.status = PublishingStatusFilter.any});

  final String search;

  /// Empty means every type.
  final Set<PublishingType> types;
  final PublishingStatusFilter status;

  PublishingQuery copyWith({String? search, Set<PublishingType>? types, PublishingStatusFilter? status}) =>
      PublishingQuery(search: search ?? this.search, types: types ?? this.types, status: status ?? this.status);

  /// The rows of [tab] matching this query, in [entries]' order. [failed]
  /// holds the keys whose last action failed.
  List<PublishingEntry> apply(Iterable<PublishingEntry> entries, PublishingTab tab, {Set<String> failed = const {}}) {
    final words = search.trim().toLowerCase();
    return [
      for (final e in entries)
        if (_inTab(e, tab, failed) &&
            (types.isEmpty || types.contains(e.type)) &&
            (words.isEmpty || e.title.toLowerCase().contains(words)) &&
            _status(e, tab, failed))
          e,
    ];
  }

  static bool _inTab(PublishingEntry e, PublishingTab tab, Set<String> failed) => switch (tab) {
        PublishingTab.unpublished => !e.hasCopy,
        // Events and announcements only: pages are published and
        // unpublished from their own editor.
        PublishingTab.published => !e.isPage,
      };

  bool _status(PublishingEntry e, PublishingTab tab, Set<String> failed) => switch (status) {
        PublishingStatusFilter.any => tab == PublishingTab.unpublished || e.hasCopy || failed.contains(e.key),
        PublishingStatusFilter.eligible => e.can(PublishingAction.publish),
        PublishingStatusFilter.ineligible => !e.hasCopy && e.problem != null,
        PublishingStatusFilter.onWebsite => e.status == PublishingStatus.onWebsite,
        PublishingStatusFilter.outOfDate => e.status == PublishingStatus.outOfDate,
        PublishingStatusFilter.notVisible => e.status == PublishingStatus.notVisible,
        PublishingStatusFilter.shouldRemove => e.status == PublishingStatus.shouldRemove,
        PublishingStatusFilter.unpublished => e.status == PublishingStatus.unpublished,
        PublishingStatusFilter.failed => failed.contains(e.key),
      };
}

/// Selection that spans every page of the results: keys, not rows.
class PublishingSelection {
  /// The keys of every row in [matching] (all of the current filter's
  /// results, not only the rows on screen) that [actions] can be applied
  /// to.
  static Set<String> allEligible(Iterable<PublishingEntry> matching, Iterable<PublishingAction> actions) => {
        for (final e in matching)
          if (actions.any(e.can)) e.key,
      };

  /// The selected rows that still exist, split by whether [action] can be
  /// done to them now.
  static ({List<PublishingEntry> eligible, List<({PublishingEntry entry, String reason})> ineligible, int missing}) plan(
    Set<String> selected,
    PublishingSnapshot snapshot,
    PublishingAction action,
  ) {
    final eligible = <PublishingEntry>[];
    final ineligible = <({PublishingEntry entry, String reason})>[];
    var missing = 0;
    for (final key in selected) {
      final entry = snapshot.byKey[key];
      if (entry == null) {
        missing++;
      } else if (entry.can(action)) {
        eligible.add(entry);
      } else {
        ineligible.add((entry: entry, reason: entry.whyNot(action)!));
      }
    }
    return (eligible: eligible, ineligible: ineligible, missing: missing);
  }

  /// The selection to keep after [result]: what didn't succeed, so it can
  /// be retried.
  static Set<String> afterRun(Set<String> selected, PublishingRunResult result) {
    final done = {for (final o in result.succeeded) o.key};
    return {for (final key in selected) if (!done.contains(key)) key};
  }
}

/// The Website Publishing Manager's data: every website page, calendar
/// event and school announcement with where it stands on the public
/// website, and bulk publish, update and remove — all through the existing
/// publishing services, never around them:
///
/// - Pages: [WebsiteContentAdminService.publishCustomPage] and
///   [WebsiteContentAdminService.publishBuiltInPage], with their own
///   validation, empty-page and image checks. A page whose publication
///   would replace a version visitors already see is never published here
///   (its editor asks first).
/// - Events and announcements: [WebsitePublicItemsService] (the same
///   sanitized copies in `website_public_items`, one per source at a fixed
///   id, so nothing can be duplicated), judged by
///   [CalendarWebsitePublisher] and [AnnouncementWebsitePublisher]'s rules.
///
/// Admin only (every call checks, as do the services). Scoped to
/// [schoolId]: website copies of another school are never listed or
/// changed. The app's sources have no school field (one school per
/// Firebase project), so they all belong to [schoolId].
class WebsitePublishingManager {
  WebsitePublishingManager({
    FirebaseFirestore? firestore,
    WebsiteContentAdminService? content,
    WebsitePublicItemsService? website,
    CalendarService? calendar,
    AdminNotificationService? notifications,
    this.schoolId = kDefaultSchoolId,
    DateTime Function()? clock,
  })  : _firestore = firestore,
        _content = content,
        _website = website,
        _calendar = calendar,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore? _firestore;
  final WebsiteContentAdminService? _content;
  final WebsitePublicItemsService? _website;
  final CalendarService? _calendar;
  final AdminNotificationService? _notifications;
  final DateTime Function() _clock;
  final String schoolId;

  // Built on first use, so constructing this never needs Firebase.
  late final WebsiteContentAdminService content = _content ?? WebsiteContentAdminService(firestore: _firestore);
  late final WebsitePublicItemsService website = _website ?? WebsitePublicItemsService(firestore: _firestore);
  late final CalendarService calendar = _calendar ?? CalendarService(firestore: _firestore);
  late final AdminNotificationService notifications = _notifications ?? AdminNotificationService(firestore: _firestore);

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') throw UnauthorizedWebsiteContentException(requesterRole);
  }

  /// Reads everything the manager lists.
  Future<PublishingSnapshot> load({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final now = _clock();
    final media = await content.listMedia(requesterRole: requesterRole);
    final mediaById = {for (final m in media) m.id: m};
    final copies = await website.listItems(requesterRole: requesterRole);
    final events = await calendar.getAllEvents();
    final notices = await notifications.getNotifications();
    final customPages = await content.listCustomPages(requesterRole: requesterRole);
    final builtIn = [for (final page in BuiltInPage.values) (page: page, state: await content.getBuiltInPage(requesterRole: requesterRole, page: page))];

    final copyFor = <String, WebsitePublicItem>{};
    final foreign = <String>{};
    for (final copy in copies) {
      final key = '${copy.kind.id}:${copy.sourceId}';
      // Another school's copy is neither listed nor touched.
      copy.schoolId == schoolId ? copyFor[key] = copy : foreign.add(key);
    }

    final entries = <PublishingEntry>[
      for (final p in customPages) ?_customPageEntry(p.draft, p.live, mediaById),
      for (final b in builtIn) ?_builtInEntry(b.page, b.state, media),
      for (final event in events) _eventEntry(event, copyFor.remove('event:${event.id}'), foreign.contains('event:${event.id}'), mediaById, now),
      for (final notice in notices)
        _announcementEntry(notice, copyFor.remove('announcement:${notice.id}'), foreign.contains('announcement:${notice.id}'), mediaById, now),
      // Copies whose source is gone: still on the website, to be removed.
      for (final copy in copyFor.values) _orphanEntry(copy, mediaById, now),
    ];
    return PublishingSnapshot(entries: entries, loadedAt: now, schoolId: schoolId);
  }

  // ------------------------------------------------------------- pages

  /// The images in [ids] visitors wouldn't see, as the publishing check
  /// words it, or null.
  static String? _unpublishedImages(Iterable<String> ids, Map<String, WebsiteMedia> media) {
    final missing = [for (final id in ids) if (!(media[id]?.isPublished ?? false)) id];
    if (missing.isEmpty) return null;
    return '${missing.length} image${missing.length == 1 ? '' : 's'} on it ${missing.length == 1 ? 'isn’t' : 'aren’t'} published. '
        'Publish ${missing.length == 1 ? 'it' : 'them'} first (Media library), or choose published ones.';
  }

  PublishingEntry? _customPageEntry(CustomPage draft, CustomPage? live, Map<String, WebsiteMedia> media) {
    final title = draft.title.en.trim().isNotEmpty ? draft.title.en.trim() : draft.slug;
    final key = 'page:custom:${draft.id}';
    if (live != null) {
      return PublishingEntry(
        key: key,
        type: PublishingType.page,
        sourceId: draft.id,
        title: title,
        sourceStatus: draft.archived ? 'Archived' : 'Published',
        schoolId: schoolId,
        status: PublishingStatus.onWebsite,
        route: live.route,
        note: draft.samePublishedContentAs(live) ? null : 'It has unpublished changes: publish them from the page’s editor.',
      );
    }
    final blocks = draft.blocks;
    final errors = draft.validationErrors();
    final problem = draft.archived
        ? 'This page is archived. Restore it before publishing it.'
        : errors.isNotEmpty
            ? errors.first
            : blocks != null && !WebsiteContentAdminService.showsVisitorsSomething(blocks)
                ? WebsiteContentAdminService.nothingVisibleMessage
                : _unpublishedImages(draft.referencedMedia, media);
    return PublishingEntry(
      key: key,
      type: PublishingType.page,
      sourceId: draft.id,
      title: title,
      sourceStatus: draft.archived ? 'Archived' : 'Draft',
      schoolId: schoolId,
      status: PublishingStatus.unpublished,
      problem: problem,
      route: draft.route,
      note: problem == null ? 'Publishing puts it at ${draft.route}${draft.showInNavigation ? ' and in the navigation' : ''}.' : null,
    );
  }

  /// A built-in page built with the visual editor. Null when it has no
  /// blocks anywhere (nothing to publish: visitors see the built-in page).
  PublishingEntry? _builtInEntry(BuiltInPage page, BuiltInPageState state, List<WebsiteMedia> media) {
    final key = 'page:builtin:${page.id}';
    final title = '${page.label} (built-in page)';
    if (state.live != null) {
      return PublishingEntry(
        key: key,
        type: PublishingType.page,
        sourceId: page.id,
        title: title,
        sourceStatus: 'Published',
        schoolId: schoolId,
        status: PublishingStatus.onWebsite,
        route: page.route,
      );
    }
    final draft = state.draft;
    if (draft == null) return null;
    final errors = BlockRegistry.validate(draft);
    final mediaById = {for (final m in media) m.id: m};
    final problem = WebsiteContentAdminService.builtInHasPublishedVersion(liveBlocks: state.live, liveContent: state.liveContent, media: media)
        ? 'Visitors see a published version of this page. Publish it from its visual editor, which asks before replacing it.'
        : errors.isNotEmpty
            ? errors.first
            : !WebsiteContentAdminService.showsVisitorsSomething(draft)
                ? WebsiteContentAdminService.nothingVisibleMessage
                : _unpublishedImages(BlockRegistry.referencedMedia(draft), mediaById);
    return PublishingEntry(
      key: key,
      type: PublishingType.page,
      sourceId: page.id,
      title: title,
      sourceStatus: 'Draft',
      schoolId: schoolId,
      status: PublishingStatus.unpublished,
      problem: problem,
      route: page.route,
      note: problem == null ? 'Publishing replaces the site’s built-in wording at ${page.route} with this draft.' : null,
    );
  }

  // ------------------------------------------- events and announcements

  static PublishingStatus _statusOf(WebsiteCopyState state) => switch (state) {
        WebsiteCopyState.notShown => PublishingStatus.unpublished,
        WebsiteCopyState.current => PublishingStatus.onWebsite,
        WebsiteCopyState.outOfDate => PublishingStatus.outOfDate,
        WebsiteCopyState.notVisible => PublishingStatus.notVisible,
        WebsiteCopyState.noLongerEligible => PublishingStatus.shouldRemove,
      };

  static String? _copyProblem(WebsitePublicItem Function() build) {
    try {
      final errors = build().validationErrors();
      return errors.isEmpty ? null : errors.first;
    } on WebsiteContentException catch (e) {
      return e.message;
    }
  }

  static const _foreignCopy = 'Its website copy belongs to another school, so it can’t be changed here.';

  PublishingEntry _eventEntry(CalendarEventModel event, WebsitePublicItem? copy, bool foreign, Map<String, WebsiteMedia> media, DateTime now) {
    final state = CalendarWebsitePublisher.stateOf(event, copy, now: now);
    final ineligible = CalendarWebsitePublisher.ineligibility(event);
    final problem = foreign
        ? _foreignCopy
        : ineligible ??
            _copyProblem(() => WebsitePublicItemsService.itemForEvent(event)) ??
            (copy == null ? CalendarWebsitePublisher.endedReason(event, now: now) : null);
    return PublishingEntry(
      key: 'event:${event.id}',
      type: PublishingType.event,
      sourceId: event.id,
      title: event.title.trim().isEmpty ? 'Untitled event' : event.title.trim(),
      sourceStatus: event.status,
      schoolId: schoolId,
      status: _statusOf(state),
      date: event.date,
      problem: problem,
      copy: copy,
      differences: copy == null ? const [] : CalendarWebsitePublisher.differences(event, copy),
      visibilityProblem: copy == null ? null : CalendarWebsitePublisher.visibilityProblem(copy, now: now),
      image: copy == null ? null : websiteImageStatus(copy.imageMediaId, media[copy.imageMediaId], what: 'event'),
    );
  }

  PublishingEntry _announcementEntry(AdminNotificationModel notice, WebsitePublicItem? copy, bool foreign, Map<String, WebsiteMedia> media, DateTime now) {
    final state = AnnouncementWebsitePublisher.stateOf(notice, copy, now: now);
    final ineligible = AnnouncementWebsitePublisher.ineligibility(notice);
    String? problem = foreign ? _foreignCopy : ineligible ?? _copyProblem(() => WebsitePublicItemsService.itemForAnnouncement(notice));
    DateTime? shownFrom;
    if (ineligible == null) {
      try {
        shownFrom = WebsitePublicItemsService.itemForAnnouncement(notice).startAt;
      } on WebsiteContentException {
        shownFrom = null;
      }
    }
    if (problem == null && copy == null) {
      // Not put on the website from here when visitors wouldn't see it:
      // expired, or scheduled for later.
      problem = AnnouncementWebsitePublisher.endedReason(notice, now: now) ??
          (shownFrom != null && shownFrom.isAfter(now)
              ? 'It is scheduled for ${_day(shownFrom)}, so it can’t be published from here yet. Publish it once it is due, or from Notifications.'
              : null);
    }
    return PublishingEntry(
      key: 'announcement:${notice.id}',
      type: PublishingType.announcement,
      sourceId: notice.id,
      title: notice.title.trim().isEmpty ? 'Untitled announcement' : notice.title.trim(),
      sourceStatus: notice.status,
      schoolId: schoolId,
      status: _statusOf(state),
      date: shownFrom ?? notice.publishDate ?? notice.createdAt,
      problem: problem,
      copy: copy,
      differences: copy == null ? const [] : AnnouncementWebsitePublisher.differences(notice, copy),
      visibilityProblem: copy == null ? null : AnnouncementWebsitePublisher.visibilityProblem(copy, now: now),
      image: copy == null ? null : websiteImageStatus(copy.imageMediaId, media[copy.imageMediaId], what: 'announcement'),
    );
  }

  PublishingEntry _orphanEntry(WebsitePublicItem copy, Map<String, WebsiteMedia> media, DateTime now) {
    final isEvent = copy.kind == WebsitePublicItemKind.event;
    final what = isEvent ? 'event' : 'announcement';
    return PublishingEntry(
      key: '${copy.kind.id}:${copy.sourceId}',
      type: isEvent ? PublishingType.event : PublishingType.announcement,
      sourceId: copy.sourceId,
      title: copy.title.en.trim().isEmpty ? 'Untitled $what' : copy.title.en.trim(),
      sourceStatus: 'Deleted',
      schoolId: copy.schoolId,
      status: PublishingStatus.shouldRemove,
      date: copy.startAt,
      problem: 'This $what no longer exists in the app. Remove its copy from the website.',
      copy: copy,
      visibilityProblem: WebsitePublicItemsService.visibilityProblem(copy, now: now),
      image: websiteImageStatus(copy.imageMediaId, media[copy.imageMediaId], what: what),
    );
  }

  static String _day(DateTime at) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final local = at.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  // ------------------------------------------------------------ actions

  /// Does [action] to each of [keys], one at a time, through the existing
  /// publishing services, then re-reads everything and reports per item:
  ///
  /// - skipped: it no longer exists, or [action] can't be done to it as
  ///   saved now (re-read first, so nothing ineligible is published and
  ///   nothing already on the website is published again);
  /// - failed: the service refused or the write failed, or the change
  ///   couldn't be confirmed when the website was re-read;
  /// - succeeded: done and confirmed.
  ///
  /// One item failing never stops the others. [onProgress] is told after
  /// each item.
  Future<PublishingRunResult> run({
    required String requesterRole,
    required AppUser actor,
    required PublishingAction action,
    required Iterable<String> keys,
    void Function(int done, int total)? onProgress,
  }) async {
    _requireAdmin(requesterRole);
    final todo = keys.toSet().toList();
    final before = await load(requesterRole: requesterRole);
    final attempted = <String, PublishingOutcome>{};
    final outcomes = <PublishingOutcome>[];
    for (final (i, key) in todo.indexed) {
      final entry = before.byKey[key];
      if (entry == null) {
        outcomes.add(PublishingOutcome(key, key, PublishingOutcomeKind.skipped, 'It no longer exists.'));
      } else if (entry.whyNot(action) case final reason?) {
        outcomes.add(PublishingOutcome(key, entry.title, PublishingOutcomeKind.skipped, reason));
      } else {
        try {
          final skipped = await _apply(action, entry, requesterRole, actor);
          final outcome = skipped == null
              ? PublishingOutcome(key, entry.title, PublishingOutcomeKind.succeeded, action.done)
              : PublishingOutcome(key, entry.title, PublishingOutcomeKind.skipped, skipped);
          if (skipped == null) attempted[key] = outcome;
          outcomes.add(outcome);
        } catch (e) {
          outcomes.add(PublishingOutcome(key, entry.title, PublishingOutcomeKind.failed, describeError(e)));
        }
      }
      onProgress?.call(i + 1, todo.length);
    }

    // Final statuses come from the website as it now is.
    PublishingSnapshot? after;
    Object? reloadError;
    try {
      after = await load(requesterRole: requesterRole);
    } catch (e) {
      reloadError = e;
    }
    final confirmed = [
      for (final o in outcomes)
        if (o.kind != PublishingOutcomeKind.succeeded)
          o
        else if (after == null)
          PublishingOutcome(o.key, o.title, PublishingOutcomeKind.failed, 'It may not have been ${action.done.toLowerCase()}: the website couldn’t be re-read to check.')
        else if (_confirmed(action, after.byKey[o.key]))
          o
        else
          PublishingOutcome(o.key, o.title, PublishingOutcomeKind.failed, 'It wasn’t ${action.done.toLowerCase()}: the website, re-read afterwards, doesn’t show the change.'),
    ];
    return PublishingRunResult(action: action, outcomes: confirmed, snapshot: after, reloadError: reloadError);
  }

  static bool _confirmed(PublishingAction action, PublishingEntry? now) => switch (action) {
        PublishingAction.publish => now != null && now.hasCopy,
        PublishingAction.update => now != null && now.copy != null && !now.isStale,
        PublishingAction.remove => now == null || now.copy == null,
      };

  /// Does [action] to [entry], re-reading what it would change first.
  /// Returns why it was skipped, or null when it was done.
  Future<String?> _apply(PublishingAction action, PublishingEntry entry, String role, AppUser actor) async {
    switch (entry.type) {
      case PublishingType.page:
        return _publishPage(entry, role, actor);
      case PublishingType.event:
      case PublishingType.announcement:
        final kind = entry.type == PublishingType.event ? WebsitePublicItemKind.event : WebsitePublicItemKind.announcement;
        final existing = action == PublishingAction.remove ? null : await website.getItem(requesterRole: role, kind: kind, sourceId: entry.sourceId);
        switch (action) {
          case PublishingAction.publish:
            // Published meanwhile: never published twice.
            if (existing != null) return 'It is already on the website.';
            await website.publish(requesterRole: role, kind: kind, sourceId: entry.sourceId, approvedForWebsite: true);
          case PublishingAction.update:
            if (existing == null) return 'It was removed from the website meanwhile.';
            await website.update(requesterRole: role, kind: kind, sourceId: entry.sourceId);
          case PublishingAction.remove:
            // Removing is safe to repeat: a copy already gone stays gone.
            await website.withdraw(requesterRole: role, kind: kind, sourceId: entry.sourceId);
        }
        return null;
    }
  }

  /// Publishes a page that isn't on the website, from its saved draft as
  /// it is now. Never one with a published version (that is its editor's
  /// to replace, after asking).
  Future<String?> _publishPage(PublishingEntry entry, String role, AppUser actor) async {
    if (entry.key.startsWith('page:custom:')) {
      final current = await content.getCustomPage(requesterRole: role, pageId: entry.sourceId);
      if (current == null) return 'It no longer exists.';
      if (current.live != null) return 'It was published meanwhile.';
      await content.publishCustomPage(requesterRole: role, actor: actor, page: current.draft);
      return null;
    }
    final page = BuiltInPage.parse(entry.sourceId);
    if (page == null) return 'It no longer exists.';
    final state = await content.getBuiltInPage(requesterRole: role, page: page);
    final draft = state.draft;
    if (draft == null) return 'Its draft no longer exists.';
    final media = await content.listMedia(requesterRole: role);
    if (WebsiteContentAdminService.builtInHasPublishedVersion(liveBlocks: state.live, liveContent: state.liveContent, media: media)) {
      return 'Visitors now see a published version of this page. Publish it from its visual editor, which asks before replacing it.';
    }
    await content.publishBuiltInPage(requesterRole: role, actor: actor, page: page, blocks: draft, style: state.draftStyle);
    return null;
  }

  /// [e] in words for the admin.
  static String describeError(Object e) => switch (e) {
        WebsiteContentException(:final message) => message,
        UnauthorizedWebsiteContentException() => e.toString(),
        FirebaseException(:final message, :final code) => 'The website couldn’t be changed (${message ?? code}).',
        _ => 'Something went wrong: $e',
      };
}

/// What [WebsiteContentAdminService.getBuiltInPage] returns.
typedef BuiltInPageState = ({List<WebsiteBlock>? draft, List<WebsiteBlock>? live, WebsitePageContent? content, WebsitePageContent? liveContent, PageStyle draftStyle, PageStyle liveStyle});
