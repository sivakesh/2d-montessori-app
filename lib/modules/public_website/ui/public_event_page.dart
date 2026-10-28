import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../content/website_custom_page.dart';
import '../content/website_public_events.dart';
import '../content/website_public_item.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../content/website_design.dart';
import '../public_website_theme.dart';
import '../widgets/blocks/public_events_feed.dart';
import '../widgets/blocks/website_blocks_view.dart';
import '../widgets/public_scaffold.dart';
import '../widgets/public_website_image.dart';

/// One event's details at `/events/<id>` (Upcoming events → an event, or a
/// shared link), open without signing in. Reads only that event's public
/// copy ([publicEventProvider]); the school's calendar is never read.
///
/// An event that is no longer on the website (withdrawn), is over or has
/// expired ([isPublicEventAvailable]), or whose copy is malformed shows "not
/// available" instead, with a way back. Back returns to the page the
/// visitor came from, or Home when the link was opened directly.
class PublicEventPage extends ConsumerWidget {
  const PublicEventPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final event = ref.watch(publicEventProvider(sourceId));
    final now = ref.watch(publicClockProvider)();
    final media = ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[];

    final back = TextButton.icon(
      key: const Key('public-event-back'),
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

    final body = event.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        key: const Key('public-event-loading'),
        label: strings.eventLoading,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage))),
        ),
      ),
      error: (_, _) => message(
        key: const Key('public-event-error'),
        icon: Icons.cloud_off_outlined,
        title: strings.eventsErrorTitle,
        body: strings.eventsErrorBody,
        action: OutlinedButton.icon(
          key: const Key('public-event-retry'),
          onPressed: () => ref.invalidate(publicEventProvider(sourceId)),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.eventsRetry),
          style: OutlinedButton.styleFrom(foregroundColor: PublicColors.forest, side: const BorderSide(color: PublicColors.line)),
        ),
      ),
      data: (item) => item == null || !isPublicEventAvailable(item, now: now)
          ? message(key: const Key('public-event-unavailable'), icon: Icons.event_busy_outlined, title: strings.eventUnavailableTitle, body: strings.eventUnavailableBody)
          : _details(context, item, {for (final m in media) m.id: m}, language, strings, layout, back),
    );

    return PublicScaffold(
      currentRoute: PublicRoutes.event(sourceId),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 40 : 72),
        child: PublicContentWidth(maxWidth: 760, child: body),
      ),
    );
  }

  Widget _details(
    BuildContext context,
    WebsitePublicItem item,
    Map<String, WebsiteMedia> media,
    PublicLanguage language,
    PublicStrings strings,
    PublicLayout layout,
    Widget back,
  ) {
    final dates = PublicEventDateText(item, language);
    final image = media[item.imageMediaId];
    final location = item.location.resolve(language);
    final description = item.body.resolve(language);
    // Checked again before it is offered, and again when followed.
    final registration = item.registrationUrl;
    final canRegister = registration != null && SafeLinkTarget.validate(registration) == null;

    Widget line(IconData icon, String text, Key key) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: PublicColors.sage),
              const SizedBox(width: 10),
              Expanded(child: Text(text, key: key, style: PublicText.body.copyWith(color: PublicColors.ink))),
            ],
          ),
        );

    return Column(
      key: const Key('public-event-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        back,
        const SizedBox(height: 16),
        Builder(builder: (context) => Text(item.title.resolve(language), key: const Key('public-event-title'), style: WebsiteDesignScope.of(context).titleStyle(mobile: layout.isMobile))),
        const SizedBox(height: 8),
        line(Icons.calendar_today_outlined, dates.date, const Key('public-event-date')),
        line(Icons.access_time, dates.time, const Key('public-event-time')),
        if (location.isNotEmpty) line(Icons.place_outlined, location, const Key('public-event-location')),
        if (image != null) ...[
          const SizedBox(height: 28),
          PublicWebsiteImage(
            key: const Key('public-event-image'),
            media: image,
            aspectRatio: 16 / 9,
            semanticLabel: image.alt.resolve(language),
            errorLabel: strings.imageUnavailable,
          ),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 28),
          for (final (i, paragraph) in description.split(RegExp(r'\n\s*\n')).indexed)
            if (paragraph.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                child: Text(paragraph.trim(), key: i == 0 ? const Key('public-event-description') : null, style: PublicText.body.copyWith(fontSize: 17)),
              ),
        ],
        if (canRegister) ...[
          const SizedBox(height: 32),
          FilledButton(
            key: const Key('public-event-register'),
            onPressed: () => followBlockLink(context, registration),
            style: FilledButton.styleFrom(
              backgroundColor: PublicColors.forest,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(strings.eventRegister),
          ),
        ],
      ],
    );
  }
}
