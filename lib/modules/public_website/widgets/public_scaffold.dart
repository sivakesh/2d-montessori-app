import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_logo.dart';
import '../content/website_content_repository.dart';
import '../content/website_design.dart';
import '../content/website_site_layout.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../public_website_theme.dart';
import 'blocks/website_blocks_view.dart';
import 'public_account_controls.dart';

/// Page frame shared by every public page: header (inline navigation on
/// desktop, a menu drawer below that), scrollable [body] and footer. Never
/// touches Firebase, so it renders without signing in. The published
/// site design is in force for everything inside ([WebsiteDesignScope]).
class PublicScaffold extends ConsumerWidget {
  const PublicScaffold({super.key, required this.currentRoute, required this.body});

  /// The public route this page is (highlighted in the navigation).
  final String currentRoute;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final design = ref.watch(publicSiteChromeProvider).design;
    return WebsiteDesignScope(
      design: design,
      child: Scaffold(
        backgroundColor: PublicColors.background,
        // Used whenever the header falls back to its menu button.
        endDrawer: PublicMenuDrawer(currentRoute: currentRoute),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PublicHeader(currentRoute: currentRoute),
                body,
                const PublicFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Follows a navigation link: a public page in place, an external
/// `https://` link in a new tab (checked again before opening).
void openPublicNavEntry(BuildContext context, PublicNavEntry entry) {
  if (!entry.isExternal) {
    PublicRoutes.open(context, entry.route);
    return;
  }
  if (SiteNavTarget.validateExternalUrl(entry.route) != null) return;
  launchUrl(Uri.parse(entry.route), mode: LaunchMode.externalApplication);
}

/// The language switch for the published registry's visitor languages
/// (English and Tamil when none is published). Up to three languages: a
/// pill-shaped segmented control in the site palette (selected segment
/// filled forest green); more: the same pill showing the current language,
/// opening a menu of all of them. If the selected language stops being
/// offered, the switch returns the site to English.
///
/// The segmented pill: Built directly rather
/// than with SegmentedButton, which sizes segments from the label's
/// measured width and can wrap Tamil (drawn in a fallback font) onto two
/// lines. Here each label stays on one line, each segment is as wide as its
/// own label plus equal padding, and a fixed strut gives both labels the
/// same line box so they share one height and centre line. On a very narrow
/// screen with enlarged text the whole control scales down to fit.
class PublicLanguageSwitch extends ConsumerWidget {
  const PublicLanguageSwitch({super.key});

  static const _labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const _strut = StrutStyle(fontSize: 13, height: 1.4, forceStrutHeight: true);

  /// Up to this many languages show as segments.
  static const maxSegments = 3;

  Widget _pill(List<Widget> children) => DecoratedBox(
        key: const Key('public-language-switch'),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(side: BorderSide(color: PublicColors.line)),
          color: PublicColors.surface,
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: StadiumBorder()),
          child: IntrinsicHeight(
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );

  Widget _label(String text, {required bool selected}) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        strutStyle: _strut,
        style: _labelStyle.copyWith(color: selected ? Colors.white : PublicColors.forest),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = ref.watch(publicLanguagesProvider);
    final chosen = ref.watch(publicLanguageProvider);
    final offered = languages.contains(chosen);
    final selected = offered ? chosen : (languages.contains(PublicLanguage.english) ? PublicLanguage.english : languages.first);
    if (!offered) {
      // Not during build: after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(publicLanguageProvider) == chosen) ref.read(publicLanguageProvider.notifier).state = selected;
      });
    }
    if (languages.length > maxSegments) {
      return Semantics(
        label: PublicStrings.of(selected).language,
        container: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: _pill([
            Material(
              color: Colors.transparent,
              child: PopupMenuButton<PublicLanguage>(
                key: const Key('public-language-menu'),
                tooltip: PublicStrings.of(selected).language,
                initialValue: selected,
                onSelected: (language) => ref.read(publicLanguageProvider.notifier).state = language,
                itemBuilder: (context) => [
                  for (final language in languages)
                    PopupMenuItem(
                      key: Key('public-language-${language.name}'),
                      value: language,
                      child: Semantics(
                        selected: language == selected,
                        label: language.label,
                        excludeSemantics: true,
                        child: Text(language.nativeName, style: TextStyle(fontWeight: language == selected ? FontWeight.w700 : FontWeight.w500)),
                      ),
                    ),
                ],
                child: Container(
                  constraints: const BoxConstraints(minHeight: 34, minWidth: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _label(selected.shortLabel, selected: false),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded, size: 16, color: PublicColors.forest),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }
    final segments = <Widget>[];
    for (final language in languages) {
      final isSelected = language == selected;
      if (segments.isNotEmpty) segments.add(const VerticalDivider(width: 1, thickness: 1, color: PublicColors.line));
      segments.add(
        Semantics(
          button: true,
          selected: isSelected,
          label: language.label,
          excludeSemantics: true,
          child: Tooltip(
            message: language.label,
            child: Material(
              key: Key('public-language-${language.name}'),
              color: isSelected ? PublicColors.forest : Colors.transparent,
              child: InkWell(
                onTap: () => ref.read(publicLanguageProvider.notifier).state = language,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 34, minWidth: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: _label(language.shortLabel, selected: isSelected),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      label: PublicStrings.of(selected).language,
      container: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: _pill(segments),
      ),
    );
  }
}

/// Site header: a slim utility bar (language switch; Login from
/// tablet width up) above the main row (brand, then the section links
/// inline when they fit, otherwise a menu button opening the drawer).
/// Whether the links fit is measured for the current language and text
/// scale, so long labels (e.g. Tamil) fall back to the menu instead of
/// overflowing.
class PublicHeader extends ConsumerWidget {
  const PublicHeader({super.key, required this.currentRoute});

  final String currentRoute;

  /// Space the brand keeps next to inline links (logo plus a short name).
  static const _brandMinWidth = 200.0;

  /// Horizontal padding + spacing around each inline link (see [_NavLink]).
  static const _linkChrome = 28.0;

  static double _textWidth(BuildContext context, String text) => (TextPainter(
        text: TextSpan(text: text, style: PublicText.nav),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout())
          .width;

  static bool _linksFit(BuildContext context, List<String> labels, double available) {
    final scaler = MediaQuery.textScalerOf(context);
    var total = _brandMinWidth;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: PublicText.nav),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      total += painter.width + _linkChrome;
    }
    return total <= available;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final chrome = ref.watch(publicSiteChromeProvider);
    final style = chrome.header;
    final design = chrome.design;
    final entries = chrome.mainNav;
    final labels = [for (final entry in entries) entry.label(strings, language)];
    final button = chrome.headerButton;
    final buttonLabel = button?.label(strings, language) ?? '';
    final linkColor = design.resolve(style.linkColor) ?? design.colorOf('ink');
    final currentColor = design.resolve(style.linkColor) ?? design.colorOf('forest');
    final accent = design.resolve(style.accentColor) ?? design.colorOf('gold');
    final vertical = switch (style.height) { 'compact' => 8.0, 'spacious' => 22.0, _ => 14.0 };
    Widget? cta() => button == null
        ? null
        : Builder(
            builder: (context) => FilledButton(
              key: const Key('public-header-button'),
              onPressed: () => followBlockLink(context, button.route),
              style: FilledButton.styleFrom(
                backgroundColor: design.resolve(style.ctaBackground) ?? design.colorOf('forest'),
                foregroundColor: design.resolve(style.ctaTextColor) ?? Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(buttonLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          );
    return Container(
      key: const Key('public-header'),
      decoration: BoxDecoration(
        color: design.resolve(style.background) ?? design.colorOf('background'),
        border: Border(bottom: BorderSide(color: design.colorOf('line'))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('public-utility-bar'),
            color: design.resolve(style.utilityBackground) ?? design.colorOf('sageLight'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: PublicContentWidth(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  const PublicLanguageSwitch(),
                  if (!layout.isMobile) const PublicAccountControls(style: PublicAccountControlsStyle.utilityBar),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: vertical),
            child: PublicContentWidth(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final buttonWidth = button == null ? 0.0 : _textWidth(context, buttonLabel) + 60;
                  final inline = !layout.isMobile && _linksFit(context, labels, constraints.maxWidth - buttonWidth);
                  final links = [
                    for (var i = 0; i < entries.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _NavLink(
                          entry: entries[i],
                          label: labels[i],
                          selected: entries[i].route == currentRoute,
                          color: linkColor,
                          currentColor: currentColor,
                          accent: accent,
                        ),
                      ),
                  ];
                  final brand = _Brand(
                    onTap: () => PublicRoutes.open(context, PublicRoutes.home),
                    name: chrome.siteNameFor(strings, language),
                    showLogo: style.showLogo,
                    color: design.resolve(style.brandColor) ?? design.colorOf('forestDark'),
                  );
                  final centred = inline && style.navAlign == 'center';
                  final headerButton = inline ? cta() : null;
                  return Row(
                    children: [
                      if (centred) Align(alignment: Alignment.centerLeft, child: brand) else Expanded(child: Align(alignment: Alignment.centerLeft, child: brand)),
                      if (inline && centred) Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: links)) else if (inline) ...links,
                      if (headerButton != null) Padding(padding: const EdgeInsets.only(left: 12), child: headerButton),
                      if (!inline)
                        Builder(
                          builder: (context) => IconButton(
                            key: const Key('public-menu-button'),
                            tooltip: strings.menu,
                            icon: Icon(Icons.menu_rounded, color: design.resolve(style.linkColor) ?? design.colorOf('forest')),
                            onPressed: () => Scaffold.of(context).openEndDrawer(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.onTap, required this.name, this.showLogo = true, this.color = PublicColors.forestDark});

  final VoidCallback onTap;
  final String name;
  final bool showLogo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLogo) ...[const AppLogo(size: 40, padding: EdgeInsets.zero), const SizedBox(width: 10)],
            Flexible(
              child: Text(
                name,
                key: const Key('public-header-site-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.entry,
    required this.label,
    required this.selected,
    this.color = PublicColors.ink,
    this.currentColor = PublicColors.forest,
    this.accent = PublicColors.gold,
  });

  final PublicNavEntry entry;
  final String label;
  final bool selected;
  final Color color;
  final Color currentColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: Key('public-nav-${entry.route}'),
      onPressed: () => openPublicNavEntry(context, entry),
      style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: PublicText.nav.copyWith(color: selected ? currentColor : color)),
          const SizedBox(height: 4),
          Container(height: 2, width: 18, color: selected ? accent : Colors.transparent),
        ],
      ),
    );
  }
}

/// The mobile menu: the main navigation, language switch and account
/// controls.
class PublicMenuDrawer extends ConsumerWidget {
  const PublicMenuDrawer({super.key, required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final chrome = ref.watch(publicSiteChromeProvider);
    final entries = chrome.mainNav;
    final button = chrome.headerButton;
    return Drawer(
      key: const Key('public-menu'),
      backgroundColor: PublicColors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final entry in entries)
              ListTile(
                key: Key('public-menu-${entry.route}'),
                title: Text(
                  entry.label(strings, language),
                  style: PublicText.nav.copyWith(fontSize: 17, color: entry.route == currentRoute ? PublicColors.forest : PublicColors.ink),
                ),
                trailing: entry.route == currentRoute ? const Icon(Icons.circle, size: 8, color: PublicColors.gold) : null,
                onTap: () {
                  Navigator.of(context).pop(); // close the drawer
                  openPublicNavEntry(context, entry);
                },
              ),
            if (button != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(
                  key: const Key('public-menu-header-button'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    followBlockLink(context, button.route);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: chrome.design.resolve(chrome.header.ctaBackground) ?? chrome.design.colorOf('forest'),
                    foregroundColor: chrome.design.resolve(chrome.header.ctaTextColor) ?? Colors.white,
                  ),
                  child: Text(button.label(strings, language)),
                ),
              ),
            const Divider(height: 32, color: PublicColors.line),
            Text(strings.language, style: PublicText.body.copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerLeft, child: PublicLanguageSwitch()),
            const SizedBox(height: 24),
            const Align(alignment: Alignment.centerLeft, child: PublicAccountControls(style: PublicAccountControlsStyle.menu)),
          ],
        ),
      ),
    );
  }
}

/// Site footer: name and tagline, the footer navigation, optional footer
/// text, the staff login controls and optional copyright line.
class PublicFooter extends ConsumerWidget {
  const PublicFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final chrome = ref.watch(publicSiteChromeProvider);
    final style = chrome.footer;
    final design = chrome.design;
    final footerText = chrome.footerText.resolve(language);
    final copyright = chrome.copyright.resolve(language);
    final centred = style.align == 'center';
    final text = design.resolve(style.textColor) ?? Colors.white70;
    final faint = design.resolve(style.textColor)?.withValues(alpha: 0.85) ?? Colors.white60;
    final linkColor = design.resolve(style.linkColor) ?? Colors.white70;
    final textAlign = centred ? TextAlign.center : TextAlign.start;
    final address = style.address.resolve(language);
    final phone = style.phone.trim();
    final email = style.email.trim();
    Widget contactLine(Key key, IconData icon, String value, String? link) => Builder(
          builder: (context) => InkWell(
            key: key,
            onTap: link == null ? null : () => launchUrl(Uri.parse(link)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: linkColor),
                  const SizedBox(width: 8),
                  Flexible(child: Text(value, style: TextStyle(fontSize: 14, height: 1.5, color: link == null ? text : linkColor))),
                ],
              ),
            ),
          ),
        );
    final links = Wrap(
      alignment: centred ? WrapAlignment.center : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in chrome.footerNav)
          TextButton(
            key: Key('public-footer-${entry.route}'),
            onPressed: () => openPublicNavEntry(context, entry),
            style: TextButton.styleFrom(foregroundColor: linkColor),
            child: Text(entry.label(strings, language)),
          ),
      ],
    );
    return Container(
      key: const Key('public-footer'),
      color: design.resolve(style.background) ?? design.colorOf('forestDark'),
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: PublicContentWidth(
        child: Column(
          crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(chrome.siteNameFor(strings, language),
                key: const Key('public-footer-site-name'),
                textAlign: textAlign,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: design.resolve(style.headingColor) ?? Colors.white)),
            const SizedBox(height: 6),
            Text(chrome.taglineFor(strings, language), key: const Key('public-footer-tagline'), textAlign: textAlign, style: TextStyle(fontSize: 14, height: 1.5, color: text)),
            if (style.hasContact) ...[
              const SizedBox(height: 16),
              Wrap(
                key: const Key('public-footer-contact'),
                direction: Axis.vertical,
                crossAxisAlignment: centred ? WrapCrossAlignment.center : WrapCrossAlignment.start,
                children: [
                  if (address.isNotEmpty) contactLine(const Key('public-footer-address'), Icons.place_outlined, address, null),
                  if (phone.isNotEmpty) contactLine(const Key('public-footer-phone'), Icons.phone_outlined, phone, 'tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'),
                  if (email.isNotEmpty) contactLine(const Key('public-footer-email'), Icons.mail_outline, email, 'mailto:$email'),
                ],
              ),
            ],
            const SizedBox(height: 20),
            links,
            if (footerText.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(footerText, key: const Key('public-footer-text'), textAlign: textAlign, style: TextStyle(fontSize: 14, height: 1.5, color: text)),
            ],
            const Divider(height: 32, color: Colors.white24),
            Wrap(
              alignment: centred ? WrapAlignment.center : WrapAlignment.start,
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(strings.footerStaff, style: TextStyle(fontSize: 13, color: faint)),
                const PublicAccountControls(style: PublicAccountControlsStyle.footer),
              ],
            ),
            if (copyright.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(copyright, key: const Key('public-footer-copyright'), textAlign: textAlign, style: TextStyle(fontSize: 12, color: faint)),
            ],
          ],
        ),
      ),
    );
  }
}
