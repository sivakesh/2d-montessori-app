import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/website_content_models.dart';
import '../../content/website_content_repository.dart';
import '../../content/website_public_events.dart';
import '../../content/website_public_item.dart';
import '../../public_routes.dart';
import '../../public_strings.dart';
import '../../public_website_theme.dart';
import '../public_website_image.dart';
import 'public_item_cards.dart';

/// How an event's day and time read in [language], at school time
/// ([SchoolTimeZone]): "Sun 14 February 2027" and "9:30 AM – 12:00 PM IST"
/// (24-hour in Tamil), or "All day". An end on another day is shown with
/// its date. Month and weekday names come from [PublicStrings] (English for
/// languages without their own).
class PublicEventDateText {
  PublicEventDateText(this.item, this.language, {this.zone = SchoolTimeZone.india}) : _strings = PublicStrings.of(language);

  final WebsitePublicItem item;
  final PublicLanguage language;
  final SchoolTimeZone zone;
  final PublicStrings _strings;

  DateTime get _start => zone.wallClock(item.startAt);

  String _day(DateTime wall) => '${_strings.weekdayShort(wall.weekday)} ${wall.day} ${_strings.monthName(wall.month)} ${wall.year}';

  String _time(DateTime wall) {
    final minutes = wall.minute.toString().padLeft(2, '0');
    if (language == PublicLanguage.tamil) return '${wall.hour.toString().padLeft(2, '0')}:$minutes';
    final hour = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
    return '$hour:$minutes ${wall.hour < 12 ? 'AM' : 'PM'}';
  }

  /// The event's (first) day.
  String get date => _day(_start);

  /// Day of the month and short month, for the date badge.
  int get dayOfMonth => _start.day;
  String get monthShort {
    final name = _strings.monthName(_start.month);
    return language == PublicLanguage.tamil || name.length <= 3 ? name : name.substring(0, 3);
  }

  /// "All day", or the start (and end) time with the school's zone.
  String get time {
    if (item.allDay) return _strings.eventsAllDay;
    final end = item.endAt;
    final start = _time(_start);
    if (end == null) return '$start ${zone.label}';
    final endWall = zone.wallClock(end);
    final endText = zone.sameDay(item.startAt, end) ? _time(endWall) : '${_day(endWall)}, ${_time(endWall)}';
    return '$start – $endText ${zone.label}';
  }
}

/// How the Upcoming events block lays out its events (the layouts shared
/// with Announcements).
typedef PublicEventsLayout = PublicItemsLayout;

/// The Upcoming events block: the events shown on the website
/// ([publicEventItemsProvider], which reads only the public copies),
/// upcoming ones only ([upcomingPublicEvents]), at most [limit], in
/// [layout] ([columnsFor] per screen size for the card layouts), with
/// loading, empty and error states. Text follows
/// [language] (its own text, its fallback, then English). An event's image
/// is shown only when it is a published website image ([media]); a missing
/// or unpublished one is simply left out.
///
/// Each event is a short preview — title, date, time, location and image —
/// never its description, which only its details page shows
/// (`PublicEventPage`).
///
/// When [interactive] (the website, not the editor's canvas), each event is
/// one button opening its details at `/events/<id>`
/// ([PublicRoutes.event]); Back returns here.
class PublicEventsFeed extends ConsumerWidget {
  const PublicEventsFeed({
    super.key,
    required this.language,
    required this.limit,
    this.layout = PublicEventsLayout.grid,
    this.desktopColumns = 3,
    this.tabletColumns = 2,
    this.mobileColumns = 1,
    required this.showImages,
    required this.heading,
    required this.headingStyle,
    required this.titleStyle,
    required this.bodyStyle,
    required this.accent,
    this.interactive = true,
    this.zone = SchoolTimeZone.india,
  });

  final PublicLanguage language;
  final int limit;
  final PublicEventsLayout layout;

  /// Columns of the card layouts on desktops, tablets and phones
  /// ([PublicLayout]); never so many that a card gets narrower than
  /// [minCardWidth].
  final int desktopColumns;
  final int tabletColumns;
  final int mobileColumns;
  final bool showImages;

  /// The narrowest a card may be ([publicItemMinCardWidth]).
  static const minCardWidth = publicItemMinCardWidth;

  /// How many card columns fit ([publicItemColumns]).
  static int columnsFor({
    required double screenWidth,
    required double available,
    required int desktop,
    required int tablet,
    required int mobile,
    required double gap,
  }) =>
      publicItemColumns(screenWidth: screenWidth, available: available, desktop: desktop, tablet: tablet, mobile: mobile, gap: gap);

  /// Shown above the events when not empty.
  final String heading;
  final TextStyle headingStyle;
  final TextStyle titleStyle;
  final TextStyle bodyStyle;

  /// The date badge's colour.
  final Color accent;

  /// Events open their details when selected.
  final bool interactive;
  final SchoolTimeZone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = PublicStrings.of(language);
    final events = ref.watch(publicEventItemsProvider);
    final now = ref.watch(publicClockProvider)();
    final media = {for (final m in ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[]) m.id: m};

    final body = events.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        key: const Key('public-events-loading'),
        label: strings.eventsLoading,
        liveRegion: true,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage))),
        ),
      ),
      error: (_, _) => _Message(
        key: const Key('public-events-error'),
        title: strings.eventsErrorTitle,
        body: strings.eventsErrorBody,
        action: OutlinedButton.icon(
          key: const Key('public-events-retry'),
          onPressed: () => ref.invalidate(publicEventItemsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.eventsRetry),
          style: OutlinedButton.styleFrom(foregroundColor: PublicColors.forest, side: const BorderSide(color: PublicColors.line)),
        ),
      ),
      data: (items) {
        final shown = upcomingPublicEvents(items, now: now, limit: limit, zone: zone);
        if (shown.isEmpty) return _Message(key: const Key('public-events-empty'), title: strings.eventsEmpty);
        final entries = [
          for (final item in shown) (item: item, image: showImages ? media[item.imageMediaId] : null),
        ];
        return switch (layout) {
          PublicEventsLayout.list => _list(entries, strings),
          PublicEventsLayout.grid || PublicEventsLayout.compactCards => _cards(entries, strings, compact: layout == PublicEventsLayout.compactCards),
        };
      },
    );

    return Column(
      key: const Key('public-events-feed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: headingStyle), const SizedBox(height: 20)],
        body,
      ],
    );
  }

  Widget _list(List<({WebsitePublicItem item, WebsiteMedia? image})> entries, PublicStrings strings) => Column(
        key: const Key('public-events-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const Divider(height: 32, color: PublicColors.line),
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final dates = PublicEventDateText(e.item, language, zone: zone);
              final image = e.image == null
                  ? null
                  : SizedBox(width: narrow ? double.infinity : 160, child: _image(e.image!, strings, narrow ? 16 / 9 : 4 / 3));
              final details = _details(e.item, dates);
              return _clickable(context, e.item, dates, strings, Row(
                key: Key('public-event-${e.item.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _badge(dates),
                  const SizedBox(width: 20),
                  Expanded(
                    child: narrow && image != null
                        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [image, const SizedBox(height: 12), details])
                        : details,
                  ),
                  if (!narrow && image != null) ...[const SizedBox(width: 20), image],
                ],
              ));
            }),
          ],
        ],
      );

  /// The grid or compact cards ([PublicItemCardGrid]).
  Widget _cards(List<({WebsitePublicItem item, WebsiteMedia? image})> entries, PublicStrings strings, {required bool compact}) => PublicItemCardGrid(
        keyPrefix: 'public-events',
        compact: compact,
        desktopColumns: desktopColumns,
        tabletColumns: tabletColumns,
        mobileColumns: mobileColumns,
        cards: [
          for (final e in entries)
            (
              key: Key('public-event-${e.item.id}'),
              build: (context, width) => _clickable(
                    context,
                    e.item,
                    PublicEventDateText(e.item, language, zone: zone),
                    strings,
                    radius: 0,
                    compact ? _compactCard(e, strings, width) : _gridCard(e, strings, width),
                  ),
            ),
        ],
      );

  /// Image on top, then the date badge (when the card is wide enough for
  /// it beside the text) and the text.
  Widget _gridCard(({WebsitePublicItem item, WebsiteMedia? image}) e, PublicStrings strings, double width) {
    final dates = PublicEventDateText(e.item, language, zone: zone);
    final roomy = width >= 260;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.image case final image?) _image(image, strings, 16 / 9, radius: 0),
        Padding(
          padding: EdgeInsets.all(roomy ? 20 : 14),
          child: roomy
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_badge(dates), const SizedBox(width: 16), Expanded(child: _details(e.item, dates))],
                )
              : _details(e.item, dates),
        ),
      ],
    );
  }

  /// A small card: a square thumbnail beside the text when there is room,
  /// otherwise a short banner above it; no date badge (the date is in the
  /// text).
  Widget _compactCard(({WebsitePublicItem item, WebsiteMedia? image}) e, PublicStrings strings, double width) {
    final dates = PublicEventDateText(e.item, language, zone: zone);
    final details = _details(e.item, dates, compact: true);
    final image = e.image;
    if (image == null) return Padding(padding: const EdgeInsets.all(12), child: details);
    if (width >= 240) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SizedBox(width: 72, child: _image(image, strings, 1, radius: 8)), const SizedBox(width: 12), Expanded(child: details)],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_image(image, strings, 2, radius: 0), Padding(padding: const EdgeInsets.all(12), child: details)],
    );
  }

  /// [child] as one button opening [item]'s details
  /// ([publicItemClickable]); just [child] in the editor's canvas.
  Widget _clickable(BuildContext context, WebsitePublicItem item, PublicEventDateText dates, PublicStrings strings, Widget child, {double radius = 12}) =>
      publicItemClickable(
        key: Key('public-event-open-${item.id}'),
        label: strings.eventOpenLabel(item.title.resolve(language), dates.date, dates.time),
        accent: accent,
        radius: radius,
        onTap: interactive ? () => Navigator.of(context).pushNamed(PublicRoutes.event(item.sourceId)) : null,
        child: child,
      );

  Widget _image(WebsiteMedia media, PublicStrings strings, double aspect, {double radius = 12}) => PublicWebsiteImage(
        media: media,
        aspectRatio: aspect,
        borderRadius: radius,
        semanticLabel: media.alt.resolve(language),
        errorLabel: strings.imageUnavailable,
        placeholder: const PublicImagePlaceholder(compact: true),
      );

  Widget _badge(PublicEventDateText dates) => ExcludeSemantics(
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text('${dates.dayOfMonth}', style: titleStyle.copyWith(color: accent, fontSize: 22, height: 1.1)),
              Text(dates.monthShort, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle.copyWith(color: accent, fontSize: 12, height: 1.2)),
            ],
          ),
        ),
      );

  /// The preview's text: no description (see [PublicEventsFeed]).
  Widget _details(WebsitePublicItem item, PublicEventDateText dates, {bool compact = false}) {
    final location = item.location.resolve(language);
    final small = bodyStyle.copyWith(fontSize: compact ? 13 : 14);
    Widget line(IconData icon, String text, Key key) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: small.color),
              const SizedBox(width: 6),
              Expanded(child: Text(text, key: key, style: small)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title.resolve(language), key: Key('public-event-title-${item.id}'), style: compact ? titleStyle.copyWith(fontSize: 16) : titleStyle),
        line(Icons.calendar_today_outlined, dates.date, Key('public-event-date-${item.id}')),
        line(Icons.access_time, dates.time, Key('public-event-time-${item.id}')),
        if (location.isNotEmpty) line(Icons.place_outlined, location, Key('public-event-location-${item.id}')),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.title, this.body = '', this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(color: PublicColors.goldLight.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            const Icon(Icons.event_outlined, size: 28, color: PublicColors.gold),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: PublicText.title),
            if (body.isNotEmpty) ...[const SizedBox(height: 6), Text(body, textAlign: TextAlign.center, style: PublicText.body)],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}
