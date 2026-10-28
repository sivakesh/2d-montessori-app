import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../content/website_public_events.dart';
import '../content/website_public_item.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../content/website_design.dart';
import '../public_website_theme.dart';
import '../widgets/blocks/public_events_feed.dart';
import '../widgets/public_scaffold.dart';
import '../widgets/public_website_image.dart';

/// One announcement at `/announcements/<id>` (Announcements → an
/// announcement, or a shared link), open without signing in, built like an
/// event's page (`PublicEventPage`). Reads only that announcement's public
/// copy ([publicAnnouncementProvider]); the school's notifications are never
/// read.
///
/// Shows its title, publication date, category, approved image and full
/// message. One that is withdrawn, expired, not yet due
/// ([isPublicAnnouncementAvailable]), malformed or unknown shows "not
/// available" instead, with a way back. Back returns to the page the
/// visitor came from, or Home when the link was opened directly.
class PublicAnnouncementPage extends ConsumerWidget {
  const PublicAnnouncementPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final announcement = ref.watch(publicAnnouncementProvider(sourceId));
    final now = ref.watch(publicClockProvider)();
    final media = ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[];

    final back = TextButton.icon(
      key: const Key('public-announcement-back'),
      onPressed: () {
        final navigator = Navigator.of(context);
        navigator.canPop() ? navigator.pop() : PublicRoutes.open(context, PublicRoutes.home);
      },
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: Text(strings.eventBack),
      style: TextButton.styleFrom(foregroundColor: PublicColors.forest),
    );

    Widget message({required Key key, required IconData icon, required String title, required String body, Widget? action}) => Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: PublicColors.gold),
            const SizedBox(height: 16),
            Text(title, style: WebsiteDesignScope.of(context).titleStyle(mobile: layout.isMobile)),
            const SizedBox(height: 12),
            Text(body, style: PublicText.body.copyWith(fontSize: 17)),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ?action,
                back,
                TextButton.icon(
                  key: const Key('public-back-home'),
                  onPressed: () => PublicRoutes.open(context, PublicRoutes.home),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: Text(strings.backHome),
                  style: TextButton.styleFrom(foregroundColor: PublicColors.forest),
                ),
              ],
            ),
          ],
        );

    final body = announcement.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        key: const Key('public-announcement-loading'),
        label: strings.announcementLoading,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage))),
        ),
      ),
      error: (_, _) => message(
        key: const Key('public-announcement-error'),
        icon: Icons.cloud_off_outlined,
        title: strings.announcementsErrorTitle,
        body: strings.eventsErrorBody,
        action: OutlinedButton.icon(
          key: const Key('public-announcement-retry'),
          onPressed: () => ref.invalidate(publicAnnouncementProvider(sourceId)),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.eventsRetry),
          style: OutlinedButton.styleFrom(foregroundColor: PublicColors.forest, side: const BorderSide(color: PublicColors.line)),
        ),
      ),
      data: (item) => item == null || !isPublicAnnouncementAvailable(item, now: now)
          ? message(
              key: const Key('public-announcement-unavailable'),
              icon: Icons.campaign_outlined,
              title: strings.announcementUnavailableTitle,
              body: strings.announcementUnavailableBody,
            )
          : _details(item, {for (final m in media) m.id: m}, language, strings, layout, back),
    );

    return PublicScaffold(
      currentRoute: PublicRoutes.announcement(sourceId),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 40 : 72),
        child: PublicContentWidth(maxWidth: 760, child: body),
      ),
    );
  }

  Widget _details(WebsitePublicItem item, Map<String, WebsiteMedia> media, PublicLanguage language, PublicStrings strings, PublicLayout layout, Widget back) {
    final image = media[item.imageMediaId];
    final text = item.body.resolve(language);
    final category = item.category.trim();
    return Column(
      key: const Key('public-announcement-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        back,
        const SizedBox(height: 16),
        if (category.isNotEmpty) ...[
          Text(category.toUpperCase(), key: const Key('public-announcement-category'), style: PublicText.eyebrow),
          const SizedBox(height: 8),
        ],
        Builder(builder: (context) => Text(item.title.resolve(language), key: const Key('public-announcement-title'), style: WebsiteDesignScope.of(context).titleStyle(mobile: layout.isMobile))),
        const SizedBox(height: 10),
        Text(
          strings.announcementPublishedOn(PublicEventDateText(item, language).date),
          key: const Key('public-announcement-date'),
          style: PublicText.body.copyWith(color: PublicColors.ink),
        ),
        if (image != null) ...[
          const SizedBox(height: 28),
          PublicWebsiteImage(
            key: const Key('public-announcement-image'),
            media: image,
            aspectRatio: 16 / 9,
            semanticLabel: image.alt.resolve(language),
            errorLabel: strings.imageUnavailable,
          ),
        ],
        if (text.isNotEmpty) ...[
          const SizedBox(height: 28),
          for (final (i, paragraph) in text.split(RegExp(r'\n\s*\n')).indexed)
            if (paragraph.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                child: Text(paragraph.trim(), key: i == 0 ? const Key('public-announcement-body') : null, style: PublicText.body.copyWith(fontSize: 17)),
              ),
        ],
      ],
    );
  }
}
