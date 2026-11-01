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
import 'public_events_feed.dart';
import 'public_item_cards.dart';

/// The Announcements block: the announcements shown on the website
/// ([publicAnnouncementItemsProvider], which reads only the public copies),
/// current ones only ([currentPublicAnnouncements]: from their publication
/// date until their expiry), newest first (pinned first when
/// [highlightPinned]), at most [limit], in [layout] with the same
/// responsive columns as Upcoming events ([PublicItemCardGrid]).
///
/// Each announcement is a short preview — image, "Pinned" and category
/// labels, title and publication date — never its message, which only its
/// page shows (`PublicAnnouncementPage`). Text follows [language] (its own,
/// its fallback, then English); the category is the school's English
/// label. An image is shown only when it is a published website image.
///
/// When [interactive] (the website, not the editor's canvas), each one is a
/// button opening `/announcements/<id>`; Back returns here.
class PublicAnnouncementsFeed extends ConsumerWidget {
  const PublicAnnouncementsFeed({
    super.key,
    required this.language,
    required this.limit,
    this.layout = PublicItemsLayout.grid,
    this.desktopColumns = 3,
    this.tabletColumns = 2,
    this.mobileColumns = 1,
    required this.showImages,
    this.showCategory = true,
    this.highlightPinned = true,
    required this.heading,
    required this.headingStyle,
    required this.titleStyle,
    required this.bodyStyle,
    required this.accent,
    this.interactive = true,
  });

  final PublicLanguage language;
  final int limit;
  final PublicItemsLayout layout;
  final int desktopColumns;
  final int tabletColumns;
  final int mobileColumns;
  final bool showImages;
  final bool showCategory;

  /// Pinned announcements first, labelled "Pinned".
  final bool highlightPinned;
  final String heading;
  final TextStyle headingStyle;
  final TextStyle titleStyle;
  final TextStyle bodyStyle;
  final Color accent;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = PublicStrings.of(language);
    final announcements = ref.watch(publicAnnouncementItemsProvider);
    final now = ref.watch(publicClockProvider)();
    final media = {for (final m in ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[]) m.id: m};

    final body = announcements.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        key: const Key('public-announcements-loading'),
        label: strings.announcementsLoading,
        liveRegion: true,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage))),
        ),
      ),
      error: (_, _) => _Message(
        key: const Key('public-announcements-error'),
        title: strings.announcementsErrorTitle,
        body: strings.eventsErrorBody,
        action: OutlinedButton.icon(
          key: const Key('public-announcements-retry'),
          onPressed: () => ref.invalidate(publicAnnouncementItemsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.eventsRetry),
          style: OutlinedButton.styleFrom(foregroundColor: PublicColors.forest, side: const BorderSide(color: PublicColors.line)),
        ),
      ),
      data: (items) {
        final shown = currentPublicAnnouncements(items, now: now, limit: limit, pinnedFirst: highlightPinned);
        if (shown.isEmpty) return _Message(key: const Key('public-announcements-empty'), title: strings.announcementsEmpty);
        final entries = [for (final item in shown) (item: item, image: showImages ? media[item.imageMediaId] : null)];
        return switch (layout) {
          PublicItemsLayout.list => _list(entries, strings),
          PublicItemsLayout.grid || PublicItemsLayout.compactCards => PublicItemCardGrid(
              keyPrefix: 'public-announcements',
              compact: layout == PublicItemsLayout.compactCards,
              desktopColumns: desktopColumns,
              tabletColumns: tabletColumns,
              mobileColumns: mobileColumns,
              cards: [
                for (final e in entries)
                  (
                    key: Key('public-announcement-${e.item.id}'),
                    build: (context, width) => _clickable(
                          context,
                          e.item,
                          strings,
                          radius: 0,
                          layout == PublicItemsLayout.compactCards ? _compactCard(e, strings, width) : _gridCard(e, strings, width),
                        ),
                  ),
              ],
            ),
        };
      },
    );

    return Column(
      key: const Key('public-announcements-feed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: headingStyle), const SizedBox(height: 20)],
        body,
      ],
    );
  }

  /// "Published Tue 5 January 2027", at school time.
  String _date(WebsitePublicItem item) => PublicStrings.of(language).announcementPublishedOn(PublicEventDateText(item, language).date);

  Widget _list(List<({WebsitePublicItem item, WebsiteMedia? image})> entries, PublicStrings strings) => Column(
        key: const Key('public-announcements-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const Divider(height: 32, color: PublicColors.line),
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final image = e.image == null ? null : SizedBox(width: narrow ? double.infinity : 160, child: _image(e.image!, strings, narrow ? 16 / 9 : 4 / 3));
              final details = _details(e.item, strings);
              return _clickable(
                context,
                e.item,
                strings,
                Row(
                  key: Key('public-announcement-${e.item.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: narrow && image != null
                          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [image, const SizedBox(height: 12), details])
                          : details,
                    ),
                    if (!narrow && image != null) ...[const SizedBox(width: 20), image],
                  ],
                ),
              );
            }),
          ],
        ],
      );

  Widget _gridCard(({WebsitePublicItem item, WebsiteMedia? image}) e, PublicStrings strings, double width) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (e.image case final image?) _image(image, strings, 16 / 9, radius: 0),
          Padding(padding: EdgeInsets.all(width >= 260 ? 20 : 14), child: _details(e.item, strings)),
        ],
      );

  /// A thumbnail beside the text when there is room, otherwise a short
  /// banner above it.
  Widget _compactCard(({WebsitePublicItem item, WebsiteMedia? image}) e, PublicStrings strings, double width) {
    final details = _details(e.item, strings, compact: true);
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

  Widget _clickable(BuildContext context, WebsitePublicItem item, PublicStrings strings, Widget child, {double radius = 12}) => publicItemClickable(
        key: Key('public-announcement-open-${item.id}'),
        label: strings.announcementOpenLabel(item.title.resolve(language), PublicEventDateText(item, language).date),
        accent: accent,
        radius: radius,
        onTap: interactive ? () => Navigator.of(context).pushNamed(PublicRoutes.announcement(item.sourceId)) : null,
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

  /// Labels, title and date: never the message.
  Widget _details(WebsitePublicItem item, PublicStrings strings, {bool compact = false}) {
    final pinned = highlightPinned && item.pinned;
    final category = showCategory ? item.category.trim() : '';
    Widget label(String text, Key key, {bool strong = false}) => Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: accent.withValues(alpha: strong ? 0.16 : 0.08), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: bodyStyle.copyWith(fontSize: 12, height: 1.4, color: accent, fontWeight: strong ? FontWeight.w600 : null)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pinned || category.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (pinned) label(strings.announcementPinned, Key('public-announcement-pinned-${item.id}'), strong: true),
            if (category.isNotEmpty) label(category, Key('public-announcement-category-${item.id}')),
          ]),
          const SizedBox(height: 8),
        ],
        Text(item.title.resolve(language), key: Key('public-announcement-title-${item.id}'), style: compact ? titleStyle.copyWith(fontSize: 16) : titleStyle),
        const SizedBox(height: 4),
        Text(_date(item), key: Key('public-announcement-date-${item.id}'), style: bodyStyle.copyWith(fontSize: compact ? 13 : 14)),
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
            const Icon(Icons.campaign_outlined, size: 28, color: PublicColors.gold),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: PublicText.title),
            if (body.isNotEmpty) ...[const SizedBox(height: 6), Text(body, textAlign: TextAlign.center, style: PublicText.body)],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}
