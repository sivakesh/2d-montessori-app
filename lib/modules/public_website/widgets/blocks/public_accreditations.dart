import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../content/blocks/accreditation_date.dart';
import '../../content/blocks/field_spec.dart';
import '../../content/website_content_models.dart';
import '../../content/website_custom_page.dart';
import '../../public_strings.dart';
import '../public_website_image.dart';

/// One accreditation as visitors see it: only what the school entered,
/// with its images when they are published.
@immutable
class AccreditationView {
  const AccreditationView({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.logo,
    required this.certificate,
    required this.target,
    required this.dates,
  });

  /// [item] in [language]; images from [media] (the published ones); a
  /// link only when it is safe; dates formatted as entered.
  factory AccreditationView.of(BlockItem item, Map<String, WebsiteMedia> media, PublicLanguage language) {
    final strings = PublicStrings.of(language);
    String? date(String key, String Function(String) label) {
      final value = AccreditationDate.tryParse(item.text(key).en);
      return value == null ? null : label(value.format(strings.monthName));
    }

    final target = item.string('target').trim();
    return AccreditationView(
      id: item.id,
      name: item.text('name').resolve(language),
      title: item.text('title').resolve(language),
      description: item.text('description').resolve(language),
      logo: media[item.string('logoMediaId')],
      certificate: media[item.string('certificateMediaId')],
      target: target.isNotEmpty && SafeLinkTarget.validate(target) == null ? target : '',
      dates: [?date('issued', strings.accreditationIssued), ?date('expires', strings.accreditationExpires)].join(' · '),
    );
  }

  final String id;
  final String name;
  final String title;
  final String description;
  final WebsiteMedia? logo;
  final WebsiteMedia? certificate;

  /// A safe link, or ''.
  final String target;

  /// "Issued March 2024 · Expires March 2027", or ''.
  final String dates;
}

/// The styles an accreditation is drawn in (the block's look).
@immutable
class AccreditationStyle {
  const AccreditationStyle({required this.title, required this.body, required this.muted, required this.accent, required this.line, required this.badge});

  final TextStyle title;
  final TextStyle body;
  final TextStyle muted;
  final Color accent;
  final Color line;

  /// The placeholder behind an item without images.
  final Color badge;
}

String _alt(WebsiteMedia media, PublicLanguage language, String fallback) {
  final own = media.alt.resolve(language);
  return own.isNotEmpty ? own : fallback;
}

/// A certificate card: the certificate image (else the logo, else a plain
/// badge), the credential, the body, the description, the dates and a
/// link. Keys: `public-accreditation-<id>` and `-link`.
class PublicAccreditationCard extends StatelessWidget {
  const PublicAccreditationCard({super.key, required this.item, required this.style, required this.language, required this.interactive, required this.onOpen});

  final AccreditationView item;
  final AccreditationStyle style;
  final PublicLanguage language;
  final bool interactive;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final label = item.title.isNotEmpty ? item.title : item.name;
    final certificate = item.certificate;
    final logo = item.logo;
    final Widget visual;
    if (certificate != null) {
      visual = PublicWebsiteImage(
        media: certificate,
        aspectRatio: 4 / 3,
        fit: BoxFit.contain,
        borderRadius: 12,
        semanticLabel: _alt(certificate, language, strings.accreditationCertificate(label)),
        errorLabel: strings.imageUnavailable,
      );
    } else if (logo != null) {
      visual = Align(alignment: Alignment.centerLeft, child: _Logo(media: logo, height: 64, label: _alt(logo, language, strings.accreditationLogo(item.name)), strings: strings));
    } else {
      visual = ExcludeSemantics(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: style.badge, shape: BoxShape.circle),
          child: Icon(Icons.workspace_premium_outlined, color: style.accent, size: 26),
        ),
      );
    }
    return Container(
      key: Key('public-accreditation-${item.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: style.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          visual,
          const SizedBox(height: 16),
          if (certificate != null && logo != null) ...[
            _Logo(media: logo, height: 32, label: _alt(logo, language, strings.accreditationLogo(item.name)), strings: strings),
            const SizedBox(height: 10),
          ],
          if (item.title.isNotEmpty) ...[Text(item.title, style: style.title), const SizedBox(height: 4)],
          Text(item.name, style: item.title.isEmpty ? style.title : style.body.copyWith(fontWeight: FontWeight.w600)),
          if (item.description.isNotEmpty) ...[const SizedBox(height: 8), Text(item.description, style: style.body)],
          if (item.dates.isNotEmpty) ...[const SizedBox(height: 8), Text(item.dates, key: Key('public-accreditation-${item.id}-dates'), style: style.muted)],
          if (item.target.isNotEmpty) ...[
            const SizedBox(height: 8),
            Semantics(
              link: true,
              label: strings.accreditationLinkFor(item.name),
              excludeSemantics: true,
              child: TextButton.icon(
                key: Key('public-accreditation-${item.id}-link'),
                onPressed: interactive ? () => onOpen(item.target) : null,
                icon: Icon(Icons.open_in_new, size: 16, color: style.accent),
                label: Text(strings.accreditationLink),
                style: TextButton.styleFrom(foregroundColor: style.accent, disabledForegroundColor: style.accent, padding: EdgeInsets.zero),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One logo in a logo strip: the logo (else the name in a plain box),
/// then the name; the whole of it follows the link, if any. Key:
/// `public-accreditation-<id>`.
class PublicAccreditationLogo extends StatelessWidget {
  const PublicAccreditationLogo({super.key, required this.item, required this.style, required this.language, required this.interactive, required this.onOpen});

  static const width = 160.0;

  final AccreditationView item;
  final AccreditationStyle style;
  final PublicLanguage language;
  final bool interactive;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final logo = item.logo;
    final content = SizedBox(
      key: Key('public-accreditation-${item.id}'),
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: 72,
            child: Center(
              child: logo != null
                  ? _Logo(media: logo, height: 72, label: _alt(logo, language, strings.accreditationLogo(item.name)), strings: strings)
                  : ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: style.badge, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.workspace_premium_outlined, color: style.accent, size: 32),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: style.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
          if (item.title.isNotEmpty) Text(item.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: style.muted),
        ],
      ),
    );
    if (item.target.isEmpty) return content;
    return Semantics(
      link: true,
      label: strings.accreditationLinkFor(item.name),
      child: InkWell(
        key: Key('public-accreditation-${item.id}-link'),
        onTap: interactive ? () => onOpen(item.target) : null,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

/// A logo at [height], as wide as its shape needs (at most a logo slot).
class _Logo extends StatelessWidget {
  const _Logo({required this.media, required this.height, required this.label, required this.strings});

  final WebsiteMedia media;
  final double height;
  final String label;
  final PublicStrings strings;

  @override
  Widget build(BuildContext context) {
    final aspect = media.aspectRatio;
    final width = math.min(PublicAccreditationLogo.width, height * aspect);
    return SizedBox(
      width: width,
      height: width / aspect,
      child: PublicWebsiteImage(media: media, aspectRatio: aspect, fit: BoxFit.contain, borderRadius: 4, semanticLabel: label, errorLabel: strings.imageUnavailable),
    );
  }
}
