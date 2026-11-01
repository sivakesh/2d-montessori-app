import 'package:flutter/material.dart';

import '../../content/blocks/accreditation_date.dart';
import '../../content/blocks/field_spec.dart';
import '../../content/blocks/website_block.dart';
import '../../content/website_content_models.dart';
import '../../content/website_custom_page.dart';
import '../../content/website_design.dart';
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
    this.issued = '',
    this.expires = '',
    this.background,
  });

  /// [item] in [language]; images from [media] (the published ones); a
  /// link only when it is safe; dates formatted as entered; its card
  /// background resolved with [design].
  factory AccreditationView.of(BlockItem item, Map<String, WebsiteMedia> media, PublicLanguage language, {SiteDesign design = SiteDesign.defaults}) {
    final strings = PublicStrings.of(language);
    String? date(String key, String Function(String) label) {
      final value = AccreditationDate.tryParse(item.text(key).en);
      return value == null ? null : label(value.format(strings.monthName));
    }

    final target = item.string('target').trim();
    final issued = date('issued', strings.accreditationIssued);
    final expires = date('expires', strings.accreditationExpires);
    return AccreditationView(
      id: item.id,
      name: item.text('name').resolve(language),
      title: item.text('title').resolve(language),
      description: item.text('description').resolve(language),
      logo: media[item.string('logoMediaId')],
      certificate: media[item.string('certificateMediaId')],
      target: verifiable(target) ? target : '',
      dates: [?issued, ?expires].join(' · '),
      issued: issued ?? '',
      expires: expires ?? '',
      background: switch (item.string('background')) {
        '' || ColorFieldSpec.automatic => null,
        ColorFieldSpec.transparent => Colors.transparent,
        // A removed palette colour or a malformed value: as automatic.
        final value => design.resolve(value),
      },
    );
  }

  final String id;

  /// The organisation or accrediting body; may be empty.
  final String name;
  final String title;

  /// What screen readers call it: the organisation, else the credential,
  /// else "Accreditation".
  String label(PublicStrings strings) => name.isNotEmpty ? name : (title.isNotEmpty ? title : strings.accreditationUnnamed);
  final String description;
  final WebsiteMedia? logo;
  final WebsiteMedia? certificate;

  /// The verification link exactly as entered, when [verifiable]; else ''.
  final String target;

  /// Whether [target] is offered as the Verify link: the site's usual safe
  /// links ([SafeLinkTarget]: https, mailto, tel or a page of this site),
  /// and for https only a real web address. A host a browser would read
  /// as a number or a local machine (`https://2` opens 0.0.0.2;
  /// `https://0x7f`, `https://127.0.0.1`, `https://localhost`) or with no
  /// domain at all is never offered.
  static bool verifiable(String target) {
    final value = target.trim();
    if (value.isEmpty || SafeLinkTarget.validate(value) != null) return false;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return true;
    return isWebHost(uri.host);
  }

  /// Whether [host] is a domain name: at least two labels of letters,
  /// digits and hyphens, the last (the top-level domain) with a letter;
  /// not `localhost`, not an IP address.
  static bool isWebHost(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost') || h.startsWith('[')) return false;
    final labels = h.split('.');
    if (labels.length < 2 || labels.any((l) => l.isEmpty || !RegExp(r'^[a-z0-9-]+$').hasMatch(l) || l.startsWith('-') || l.endsWith('-'))) return false;
    return RegExp('[a-z]').hasMatch(labels.last) && !RegExp(r'^(0x[0-9a-f]*|[0-9]+)$').hasMatch(labels.last);
  }

  /// "Issued March 2024 · Expires March 2027", or ''.
  final String dates;

  /// "Issued March 2024" and "Expires March 2027", each or ''.
  final String issued;
  final String expires;

  /// This card's own background: null is automatic (the white card);
  /// transparent shows the section behind.
  final Color? background;
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

  /// Whether [background] needs light text to stay readable.
  static bool isDark(Color background) => background.a > 0.5 && background.computeLuminance() < 0.35;

  /// These styles in light text, for a dark card background.
  AccreditationStyle onDark() => AccreditationStyle(
        title: title.copyWith(color: Colors.white),
        body: body.copyWith(color: const Color(0xF2FFFFFF)),
        muted: muted.copyWith(color: const Color(0xD9FFFFFF)),
        accent: Colors.white,
        line: line,
        badge: const Color(0x33FFFFFF),
      );
}

/// How the content inside each card or logo is laid out (the block's
/// `imageAlign`, `textAlign`, `verticalAlign`, `imageSize`, `imageSpacing`
/// and `cardPadding`). Every setting left at "auto" (or absent, as in
/// blocks saved before they existed) is how it looked before: on cards the
/// image and text on the left, a 64 px logo, 16 px between image and text,
/// 20 px padding; in the logo strip a centred 72 px logo with centred text
/// 8 px below. Content is placed at the top unless centred.
@immutable
class AccreditationLayout {
  const AccreditationLayout({
    this.imageAlign = 'auto',
    this.textAlign = 'auto',
    this.verticalAlign = 'top',
    this.imageSize = 'auto',
    this.imageSpacing = 'auto',
    this.cardPadding = 'auto',
  });

  /// The layout [block] sets.
  factory AccreditationLayout.of(StructuredBlock block) => AccreditationLayout(
        imageAlign: block.option('imageAlign'),
        textAlign: block.option('textAlign'),
        verticalAlign: block.option('verticalAlign'),
        imageSize: block.option('imageSize'),
        imageSpacing: block.option('imageSpacing'),
        cardPadding: block.option('cardPadding'),
      );

  final String imageAlign;
  final String textAlign;
  final String verticalAlign;
  final String imageSize;
  final String imageSpacing;
  final String cardPadding;

  /// Whether content is centred vertically (cards in a row then share
  /// their height).
  bool get centred => verticalAlign == 'center';

  static String _side(String value, {required bool strip}) => value == 'auto' ? (strip ? 'center' : 'left') : value;

  /// Where the image sits across a card ([strip] false) or a logo slot.
  Alignment image({required bool strip}) => switch (_side(imageAlign, strip: strip)) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };

  TextAlign text({required bool strip}) => switch (_side(textAlign, strip: strip)) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      };

  /// Where a non-text element of the text (a card's link) sits.
  Alignment textBox({required bool strip}) => switch (_side(textAlign, strip: strip)) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };

  /// A logo's height: on a card (shown alone) or in the strip.
  double logoHeight({required bool strip}) => switch (imageSize) {
        'small' => 48,
        'medium' => 72,
        'large' => 104,
        _ => strip ? 72 : 64,
      };

  /// The share of a card's width a certificate image takes.
  double get certificateWidth => switch (imageSize) { 'small' => 0.5, 'medium' => 0.75, _ => 1.0 };

  double spacing({required bool strip}) => double.tryParse(imageSpacing) ?? (strip ? 8 : 16);

  double get padding => double.tryParse(cardPadding) ?? 20;

  @override
  bool operator ==(Object other) =>
      other is AccreditationLayout &&
      other.imageAlign == imageAlign &&
      other.textAlign == textAlign &&
      other.verticalAlign == verticalAlign &&
      other.imageSize == imageSize &&
      other.imageSpacing == imageSpacing &&
      other.cardPadding == cardPadding;

  @override
  int get hashCode => Object.hash(imageAlign, textAlign, verticalAlign, imageSize, imageSpacing, cardPadding);
}

String _alt(WebsiteMedia media, PublicLanguage language, String fallback) {
  final own = media.alt.resolve(language);
  return own.isNotEmpty ? own : fallback;
}

/// A certificate card: only the image (the certificate, else the logo,
/// else a plain badge), placed by [layout], on the item's own background
/// (automatic: white). When the layout centres content, the card fills
/// the height it is given (its row's) with the image in the middle.
///
/// On the website ([interactive]) the whole card is one button that opens
/// the details ([showAccreditationDetails], in [detailsStyle]): the
/// credential, organisation, description, dates and Verify link are
/// there. In the editor it is inert. Keys: `public-accreditation-<id>`,
/// `-open`, `-visual`.
class PublicAccreditationCard extends StatelessWidget {
  const PublicAccreditationCard({
    super.key,
    required this.item,
    required AccreditationStyle style,
    required this.language,
    required this.interactive,
    required this.onOpen,
    this.layout = const AccreditationLayout(),
    this.detailsStyle,
  }) : _style = style;

  final AccreditationView item;
  final AccreditationLayout layout;
  final AccreditationStyle _style;

  /// The details' styles (a neutral surface); else the card's.
  final AccreditationStyle? detailsStyle;
  final PublicLanguage language;
  final bool interactive;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final background = item.background ?? Colors.white;
    final style = AccreditationStyle.isDark(background) ? _style.onDark() : _style;
    final label = item.title.isNotEmpty ? item.title : item.label(strings);
    final named = item.label(strings);
    final certificate = item.certificate;
    final logo = item.logo;
    final imageAt = layout.image(strip: false);
    final Widget visual;
    if (certificate != null) {
      visual = Align(
        alignment: imageAt,
        child: FractionallySizedBox(
          widthFactor: layout.certificateWidth,
          child: PublicWebsiteImage(
            media: certificate,
            aspectRatio: 4 / 3,
            fit: BoxFit.contain,
            borderRadius: 12,
            semanticLabel: _alt(certificate, language, strings.accreditationCertificate(label)),
            errorLabel: strings.imageUnavailable,
          ),
        ),
      );
    } else if (logo != null) {
      visual = Align(
        alignment: imageAt,
        child: _Logo(
          media: logo,
          height: layout.logoHeight(strip: false),
          // As before unless a size is chosen; then up to the card's width.
          maxWidth: layout.imageSize == 'auto' ? PublicAccreditationLogo.width : double.infinity,
          label: _alt(logo, language, strings.accreditationLogo(named)),
          strings: strings,
        ),
      );
    } else {
      visual = Align(
        alignment: imageAt,
        child: ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: style.badge, shape: BoxShape.circle),
            child: Icon(Icons.workspace_premium_outlined, color: style.accent, size: 26),
          ),
        ),
      );
    }
    final open = interactive ? () => showAccreditationDetails(context, item: item, style: detailsStyle ?? _style, language: language, onOpen: onOpen) : null;
    final card = Material(
      key: Key('public-accreditation-${item.id}'),
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _style.line)),
      clipBehavior: Clip.antiAlias,
      child: _Tappable(
        tapKey: Key('public-accreditation-${item.id}-open'),
        onTap: open,
        accent: style.accent,
        // The border is drawn over the edge: content keeps its place.
        child: Padding(
          padding: EdgeInsets.all(layout.padding + 1),
          child: Column(
            mainAxisAlignment: layout.centred ? MainAxisAlignment.center : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Only the image: the details are in the popup.
            children: [KeyedSubtree(key: Key('public-accreditation-${item.id}-visual'), child: visual)],
          ),
        ),
      ),
    );
    if (open == null) return card;
    // One stop for the card, then its link, before the next card.
    return FocusTraversalGroup(child: Semantics(container: true, button: true, label: strings.accreditationDetailsFor(named), child: card));
  }
}

/// The whole of a card or logo slot as one button: a pointer, a light
/// tint on hover, a focus tint, Enter and Space ([InkWell]). Inert (no
/// tint, no pointer, not focusable) when [onTap] is null: the editor.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.tapKey, required this.onTap, required this.accent, required this.child, this.radius});

  final Key tapKey;
  final VoidCallback? onTap;
  final Color accent;
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return InkWell(
      key: tapKey,
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: radius == null ? null : BorderRadius.circular(radius!),
      hoverColor: accent.withValues(alpha: 0.05),
      focusColor: accent.withValues(alpha: 0.12),
      highlightColor: accent.withValues(alpha: 0.08),
      splashColor: accent.withValues(alpha: 0.10),
      child: child,
    );
  }
}

/// One logo in a logo strip: the logo (else the name in a plain box),
/// then the name, laid out by [layout] within its slot, on the item's own
/// background when it has one (automatic and transparent: none, as
/// before). On the website the whole slot opens the details
/// ([showAccreditationDetails]), where its link is; in the editor it is
/// inert. Keys: `public-accreditation-<id>`, `-open`, `-visual`, `-text`.
class PublicAccreditationLogo extends StatelessWidget {
  const PublicAccreditationLogo({
    super.key,
    required this.item,
    required AccreditationStyle style,
    required this.language,
    required this.interactive,
    required this.onOpen,
    this.layout = const AccreditationLayout(),
    this.detailsStyle,
  }) : _style = style;

  static const width = 160.0;

  final AccreditationView item;
  final AccreditationLayout layout;
  final AccreditationStyle _style;
  final AccreditationStyle? detailsStyle;
  final PublicLanguage language;
  final bool interactive;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final logo = item.logo;
    final named = item.label(strings);
    final height = layout.logoHeight(strip: true);
    final textAlign = layout.text(strip: true);
    final background = item.background;
    final filled = background != null && background.a > 0;
    final style = filled && AccreditationStyle.isDark(background) ? _style.onDark() : _style;
    final column = Padding(
      // A coloured slot keeps its 160 px; its content sits inside.
      padding: EdgeInsets.all(filled ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: Key('public-accreditation-${item.id}-visual'),
            height: height,
            child: Align(
              alignment: layout.image(strip: true),
              child: logo != null
                  ? _Logo(media: logo, height: height, label: _alt(logo, language, strings.accreditationLogo(named)), strings: strings)
                  : ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: style.badge, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.workspace_premium_outlined, color: style.accent, size: 32),
                      ),
                    ),
            ),
          ),
          if (item.name.isNotEmpty || item.title.isNotEmpty) ...[
            SizedBox(height: layout.spacing(strip: true)),
            Column(
              key: Key('public-accreditation-${item.id}-text'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.name.isNotEmpty) Text(item.name, textAlign: textAlign, maxLines: 2, overflow: TextOverflow.ellipsis, style: style.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                if (item.title.isNotEmpty) Text(item.title, textAlign: textAlign, maxLines: 2, overflow: TextOverflow.ellipsis, style: style.muted),
              ],
            ),
          ],
        ],
      ),
    );
    final open = interactive ? () => showAccreditationDetails(context, item: item, style: detailsStyle ?? _style, language: language, onOpen: onOpen) : null;
    final slot = SizedBox(
      key: Key('public-accreditation-${item.id}'),
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(color: filled ? background : null, borderRadius: BorderRadius.circular(12)),
          child: _Tappable(tapKey: Key('public-accreditation-${item.id}-open'), onTap: open, accent: style.accent, radius: 12, child: column),
        ),
      ),
    );
    if (open == null) return slot;
    return Semantics(container: true, button: true, label: strings.accreditationDetailsFor(named), child: slot);
  }
}

/// Opens [item]'s details over the page (a modal: the page behind can't
/// be used; Escape, the Close button or a click outside close it, and
/// focus returns to the card).
Future<void> showAccreditationDetails(
  BuildContext context, {
  required AccreditationView item,
  required AccreditationStyle style,
  required PublicLanguage language,
  required ValueChanged<String> onOpen,
}) {
  final strings = PublicStrings.of(language);
  return showDialog<void>(
    context: context,
    barrierLabel: strings.galleryClose,
    builder: (_) => PublicAccreditationDetails(item: item, style: style, language: language, onOpen: onOpen),
  );
}

/// An accreditation's details: its images (the logo, and the certificate
/// whole, uncropped), the credential (else the organisation, else
/// "Accreditation") as the title with the organisation under it, the
/// description, the issue and expiry dates and a Verify link to the
/// address entered (when it is [AccreditationView.verifiable]). Only what was
/// entered is shown. A centred dialog, full screen on phones; always on
/// a white surface. Keys: `public-accreditation-details`, `-title`,
/// `-organisation`, `-logo`, `-certificate`, `-description`, `-issued`,
/// `-expires`, `-link`, `-close`.
class PublicAccreditationDetails extends StatelessWidget {
  const PublicAccreditationDetails({super.key, required this.item, required this.style, required this.language, required this.onOpen});

  static const maxWidth = 640.0;

  /// Below this width the details fill the screen.
  static const fullScreenBelow = 600.0;

  final AccreditationView item;
  final AccreditationStyle style;
  final PublicLanguage language;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final size = MediaQuery.sizeOf(context);
    final fullScreen = size.width < fullScreenBelow;
    final title = item.title.isNotEmpty ? item.title : item.label(strings);
    final organisation = item.title.isNotEmpty ? item.name : '';
    final named = item.label(strings);
    final logo = item.logo;
    final certificate = item.certificate;
    const k = 'public-accreditation-details';

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Beside the title when a certificate is shown below; otherwise
        // the logo is shown larger below.
        if (logo != null && certificate != null) ...[
          KeyedSubtree(key: const Key('$k-logo'), child: _Logo(media: logo, height: 56, label: _alt(logo, language, strings.accreditationLogo(named)), strings: strings)),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, key: const Key('$k-title'), style: style.title.copyWith(fontSize: (style.title.fontSize ?? 18) + 4))),
              if (organisation.isNotEmpty) ...[const SizedBox(height: 4), Text(organisation, key: const Key('$k-organisation'), style: style.body.copyWith(fontWeight: FontWeight.w600))],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('$k-close'),
          autofocus: true,
          tooltip: strings.galleryClose,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
    final parts = <Widget>[
      if (certificate != null)
        Center(
          key: const Key('$k-certificate'),
          child: ConstrainedBox(
            // Whole and uncropped, at most most of the screen's height.
            constraints: BoxConstraints(maxHeight: size.height * (fullScreen ? 0.55 : 0.6)),
            child: AspectRatio(
              aspectRatio: certificate.aspectRatio,
              child: PublicWebsiteImage(
                media: certificate,
                aspectRatio: certificate.aspectRatio,
                fit: BoxFit.contain,
                borderRadius: 12,
                semanticLabel: _alt(certificate, language, strings.accreditationCertificate(title)),
                errorLabel: strings.imageUnavailable,
              ),
            ),
          ),
        )
      else if (logo != null)
        Center(
          key: const Key('$k-logo'),
          child: _Logo(media: logo, height: 120, maxWidth: 320, label: _alt(logo, language, strings.accreditationLogo(named)), strings: strings),
        ),
      if (item.description.isNotEmpty) Text(item.description, key: const Key('$k-description'), style: style.body.copyWith(height: 1.5)),
      if (item.issued.isNotEmpty || item.expires.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.issued.isNotEmpty) Text(item.issued, key: const Key('$k-issued'), style: style.body),
            if (item.expires.isNotEmpty) Text(item.expires, key: const Key('$k-expires'), style: style.body),
          ],
        ),
      if (item.target.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            container: true,
            link: true,
            label: strings.accreditationVerifyFor(named),
            excludeSemantics: true,
            // Opens exactly the address entered (followBlockLink: a new tab
            // for https; a page of this site in place).
            child: OutlinedButton.icon(
              key: const Key('$k-link'),
              onPressed: () => onOpen(item.target),
              icon: Icon(Icons.verified_outlined, size: 18, color: style.accent),
              label: Text(strings.accreditationVerify),
              style: OutlinedButton.styleFrom(foregroundColor: style.accent, side: BorderSide(color: style.accent)),
            ),
          ),
        ),
    ];
    // The dialog is named by its title for screen readers.
    final content = Semantics(
      key: const Key('$k-content'),
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, fullScreen ? 12 : 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            for (final part in parts) ...[const SizedBox(height: 16), Padding(padding: const EdgeInsets.only(right: 8), child: part)],
          ],
        ),
      ),
    );
    return fullScreen
        ? Dialog.fullscreen(key: const Key(k), backgroundColor: Colors.white, child: SafeArea(child: content))
        : Dialog(
            key: const Key(k),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: content),
          );
  }
}

/// A logo at [height], as wide as its shape needs, but no wider than
/// [maxWidth] (a logo slot) or the space it is in: a wide logo is then
/// less tall.
class _Logo extends StatelessWidget {
  const _Logo({required this.media, required this.height, required this.label, required this.strings, this.maxWidth = PublicAccreditationLogo.width});

  final WebsiteMedia media;
  final double height;
  final double maxWidth;
  final String label;
  final PublicStrings strings;

  @override
  Widget build(BuildContext context) {
    final aspect = media.aspectRatio;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: height),
      child: AspectRatio(
        aspectRatio: aspect,
        child: PublicWebsiteImage(media: media, aspectRatio: aspect, fit: BoxFit.contain, borderRadius: 4, semanticLabel: label, errorLabel: strings.imageUnavailable),
      ),
    );
  }
}
