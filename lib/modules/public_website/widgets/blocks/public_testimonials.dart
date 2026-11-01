import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../content/blocks/field_spec.dart';
import '../../content/blocks/testimonials.dart';
import '../../content/blocks/website_block.dart';
import '../../content/website_content_models.dart';
import '../../content/website_design.dart';
import '../../public_strings.dart';
import '../../public_website_theme.dart';
import '../public_website_image.dart';

/// A Testimonials block as visitors (and the editor's canvas) see it: an
/// optional eyebrow, heading and description, then the testimonials as
/// cards in rows (per row by screen size, fewer when a card would be too
/// narrow), each card as tall as the others in its row.
///
/// Only what is entered is drawn: no avatar without a photo or a name, no
/// stars without a rating, nothing reserved for missing details.
///
/// Keys: `public-testimonials-<block id>`, `public-testimonial-<item id>`,
/// with `-avatar` (`-photo` or `-initials`), `-name`, `-role`, `-rating`,
/// `-quote`, `-details`, `-verification`.
class PublicTestimonials extends StatelessWidget {
  const PublicTestimonials({
    super.key,
    required this.block,
    required this.media,
    required this.language,
    required this.headingStyle,
    required this.bodyStyle,
    required this.headingColor,
  });

  final StructuredBlock block;

  /// Published images by id.
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final Color headingColor;

  /// A card is never narrower than this; fewer go in a row instead.
  static const minCardWidth = 220.0;

  /// The testimonials visitors see: those with text in [language] (or the
  /// English it falls back to).
  static List<BlockItem> shown(StructuredBlock block, PublicLanguage language) => [
        for (final item in block.items('testimonials'))
          if (item.text('quote').resolve(language).trim().isNotEmpty) item,
      ];

  /// Whether visitors would see anything: a testimonial, or the text above.
  static bool hasContent(StructuredBlock block, PublicLanguage language) =>
      shown(block, language).isNotEmpty || ['eyebrow', 'heading', 'description'].any((k) => block.text(k).resolve(language).trim().isNotEmpty);

  /// Cards per row on [layout] for [count] testimonials (before the width
  /// check): the setting, else 3 on desktop, 2 on tablets, 1 on phones,
  /// and never more than there are testimonials when Automatic.
  static int perRow(StructuredBlock block, PublicLayout layout, int count) {
    final own = int.tryParse(block.option(switch (layout) {
      PublicLayout.mobile => 'mobileColumns',
      PublicLayout.tablet => 'tabletColumns',
      PublicLayout.desktop => 'desktopColumns',
    }));
    if (own != null) return own;
    final auto = switch (layout) { PublicLayout.mobile => 1, PublicLayout.tablet => 2, PublicLayout.desktop => 3 };
    return math.max(1, math.min(auto, count));
  }

  /// Whether [item]'s rating is shown: ratings on, its own not hidden, and
  /// it has one.
  static bool ratingShown(StructuredBlock block, BlockItem item) =>
      block.toggle('showRatings') && item.value<bool>('hideRating') != true && Testimonials.ratingOf(item) != null;

  static Color? _color(SiteDesign design, String value) => switch (value) {
        '' || 'auto' => null,
        'transparent' => Colors.transparent,
        _ => design.resolve(value),
      };

  static Alignment _alignment(String align) => switch (align) { 'center' => Alignment.center, 'end' => Alignment.centerRight, _ => Alignment.centerLeft };
  static TextAlign _textAlign(String align) => switch (align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };

  @override
  Widget build(BuildContext context) {
    final design = WebsiteDesignScope.of(context);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final mobile = layout.isMobile;
    final items = shown(block, language);
    final align = block.option('align');
    final eyebrow = block.text('eyebrow').resolve(language).trim();
    final heading = block.text('heading').resolve(language).trim();
    final description = block.text('description').resolve(language).trim();
    final gap = (block.values['gap'] as int? ?? (mobile ? 16 : 24)).toDouble();
    final maxWidth = (block.values['maxWidth'] as int?)?.toDouble() ?? double.infinity;

    final header = [
      if (eyebrow.isNotEmpty) Text(eyebrow, key: Key('public-testimonials-${block.id}-eyebrow'), style: PublicText.eyebrow.copyWith(color: design.colorOf('gold')), textAlign: _textAlign(align)),
      if (heading.isNotEmpty) Text(heading, key: Key('public-testimonials-${block.id}-heading'), style: headingStyle, textAlign: _textAlign(align)),
      if (description.isNotEmpty) Text(description, key: Key('public-testimonials-${block.id}-description'), style: bodyStyle, textAlign: _textAlign(align)),
    ];

    return Padding(
      key: Key('public-testimonials-${block.id}'),
      padding: EdgeInsets.only(top: (block.values['paddingTop'] as int? ?? 0).toDouble(), bottom: (block.values['paddingBottom'] as int? ?? 0).toDouble()),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, h) in header.indexed) ...[if (i > 0) SizedBox(height: i == 1 && eyebrow.isNotEmpty ? 8 : 12), Align(alignment: _alignment(align), child: h)],
              if (header.isNotEmpty && items.isNotEmpty) SizedBox(height: mobile ? 24 : 36),
              if (items.isNotEmpty)
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final fit = math.max(1, ((width + gap) / (minCardWidth + gap)).floor());
                  final n = math.min(perRow(block, layout, items.length), fit);
                  final cards = [
                    for (final item in items)
                      _TestimonialCard(block: block, item: item, media: media, language: language, design: design, mobile: mobile, bodyStyle: bodyStyle, headingColor: headingColor),
                  ];
                  final rows = <Widget>[];
                  for (var i = 0; i < cards.length; i += n) {
                    if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
                    final cells = [for (var j = i; j < i + n; j++) j < cards.length ? cards[j] : const SizedBox.shrink()];
                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final (k, c) in cells.indexed) ...[if (k > 0) SizedBox(width: gap), Expanded(child: c)]],
                    );
                    rows.add(n == 1 ? cells.first : IntrinsicHeight(child: row));
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
                }),
            ],
          ),
        ),
      ),
    );
  }
}

/// One testimonial's card.
class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({
    required this.block,
    required this.item,
    required this.media,
    required this.language,
    required this.design,
    required this.mobile,
    required this.bodyStyle,
    required this.headingColor,
  });

  final StructuredBlock block;
  final BlockItem item;
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final SiteDesign design;
  final bool mobile;
  final TextStyle bodyStyle;
  final Color headingColor;

  String _align(String key, String fallback) {
    final own = block.option(key);
    return own == 'auto' ? fallback : own;
  }

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final id = item.id;
    final kind = block.option('layout');
    final compact = kind == 'compact';
    final content = _align('contentAlign', kind == 'vertical' ? 'center' : 'start');
    final textAlign = PublicTestimonials._textAlign(content);
    final gap = (block.values['elementGap'] as int? ?? 12).toDouble();
    final muted = bodyStyle.color ?? design.colorOf('muted');

    final name = item.text('name').resolve(language).trim();
    final role = item.text('role').resolve(language).trim();
    final quote = item.text('quote').resolve(language).trim();
    final details = [item.text('date').resolve(language).trim(), item.text('location').resolve(language).trim()].where((t) => t.isNotEmpty).join(' · ');
    final verification = item.text('verification').resolve(language).trim();

    final avatar = block.toggle('showAvatars') ? _avatar(strings, name, size: (block.values['avatarSize'] as int? ?? (compact ? 40 : 56)).toDouble()) : null;
    final rating = PublicTestimonials.ratingShown(block, item) ? _rating(strings, Testimonials.ratingOf(item)!, muted) : null;

    Widget aligned(Widget child, String align) => Align(alignment: PublicTestimonials._alignment(align), child: child);
    final nameText = name.isEmpty ? null : Text(name, key: Key('public-testimonial-$id-name'), style: PublicText.title.copyWith(color: headingColor, fontSize: 16, height: 1.3), textAlign: textAlign);
    final roleText = role.isEmpty ? null : Text(role, key: Key('public-testimonial-$id-role'), style: PublicText.body.copyWith(color: muted, fontSize: 13.5, height: 1.35), textAlign: textAlign);
    final quoteText = Text(
      quote,
      key: Key('public-testimonial-$id-quote'),
      style: compact ? bodyStyle.copyWith(fontSize: (bodyStyle.fontSize ?? 16) * 0.94) : bodyStyle,
      textAlign: textAlign,
    );
    final extra = [
      if (details.isNotEmpty) Text(details, key: Key('public-testimonial-$id-details'), style: PublicText.body.copyWith(color: muted, fontSize: 13, height: 1.35), textAlign: textAlign),
      if (verification.isNotEmpty)
        aligned(
          Row(
            key: Key('public-testimonial-$id-verification'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(Icons.verified_outlined, size: 16, color: design.colorOf('forest'))),
              const SizedBox(width: 6),
              Flexible(child: Text(verification, style: PublicText.body.copyWith(color: design.colorOf('forest'), fontSize: 13, fontWeight: FontWeight.w600, height: 1.3))),
            ],
          ),
          content,
        ),
    ];

    // Runs of parts, [gap] apart (a role sits close under its name).
    List<Widget> spaced(List<Widget?> parts) {
      final out = <Widget>[];
      for (final p in parts.nonNulls) {
        if (out.isNotEmpty) out.add(SizedBox(height: gap));
        out.add(p);
      }
      return out;
    }

    final person = nameText == null && roleText == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [?nameText, if (nameText != null && roleText != null) const SizedBox(height: 2), ?roleText],
          );

    final ratingRow = rating == null ? null : aligned(rating, _align('ratingAlign', content));

    final Widget body = switch (kind) {
      // The avatar's alignment is down the card: top, centre or bottom of
      // the text beside it.
      'horizontal' => Row(
          crossAxisAlignment: switch (_align('avatarAlign', 'start')) { 'center' => CrossAxisAlignment.center, 'end' => CrossAxisAlignment.end, _ => CrossAxisAlignment.start },
          children: [
            if (avatar != null) ...[avatar, SizedBox(width: math.max(gap, 12))],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: spaced([person, ratingRow, quoteText, ...extra]),
              ),
            ),
          ],
        ),
      'compact' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: spaced([
            ratingRow,
            quoteText,
            if (avatar != null || person != null)
              Row(
                mainAxisAlignment: switch (_align('avatarAlign', content)) { 'center' => MainAxisAlignment.center, 'end' => MainAxisAlignment.end, _ => MainAxisAlignment.start },
                children: [
                  ?avatar,
                  if (avatar != null && person != null) const SizedBox(width: 10),
                  if (person case final p?) Flexible(child: p),
                ],
              ),
            ...extra,
          ]),
        ),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: spaced([
            if (avatar != null) aligned(avatar, _align('avatarAlign', content)),
            person,
            ratingRow,
            quoteText,
            ...extra,
          ]),
        ),
    };

    final borderWidth = double.parse(block.option('cardBorderWidth'));
    final radius = (block.values['cardRadius'] as int? ?? 16).toDouble();
    final padding = (block.values['cardPadding'] as int? ?? (compact || mobile ? 20 : 28)).toDouble();
    return Semantics(
      container: true,
      child: Container(
        key: Key('public-testimonial-$id'),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: PublicTestimonials._color(design, block.string('cardBackground')) ?? design.colorOf('surface'),
          borderRadius: BorderRadius.circular(radius),
          border: borderWidth <= 0 ? null : Border.all(color: PublicTestimonials._color(design, block.string('cardBorderColor')) ?? design.colorOf('line'), width: borderWidth),
          boxShadow: switch (block.option('cardShadow')) {
            'soft' => const [BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8))],
            'strong' => const [BoxShadow(color: Color(0x26000000), blurRadius: 32, offset: Offset(0, 12))],
            _ => null,
          },
        ),
        child: body,
      ),
    );
  }

  /// The profile photo (published) as a circle, else the initials of
  /// [name]; null with neither.
  Widget? _avatar(PublicStrings strings, String name, {required double size}) {
    final photo = media[item.string('photoMediaId').trim()];
    final initials = Testimonials.initialsOf(name);
    if (photo == null && initials.isEmpty) return null;
    final borderWidth = double.parse(block.option('avatarBorderWidth'));
    final border = borderWidth <= 0 ? null : Border.all(color: PublicTestimonials._color(design, block.string('avatarBorderColor')) ?? Colors.white, width: borderWidth);
    final inner = size - 2 * borderWidth;
    final Widget face;
    if (photo != null) {
      final own = item.text('photoAlt').resolve(language).trim();
      final library = photo.alt.resolve(language).trim();
      final alt = own.isNotEmpty ? own : (library.isNotEmpty ? library : (name.isNotEmpty ? strings.photoOf(name) : strings.profilePhoto));
      face = SizedBox.square(
        key: Key('public-testimonial-${item.id}-photo'),
        dimension: inner,
        child: PublicWebsiteImage(media: photo, aspectRatio: 1, borderRadius: inner / 2, semanticLabel: alt, errorLabel: alt, placeholder: const PublicImagePlaceholder(compact: true)),
      );
    } else {
      face = Semantics(
        key: Key('public-testimonial-${item.id}-initials'),
        container: true,
        label: strings.initialsOf(name),
        image: true,
        child: ExcludeSemantics(
          child: Container(
            width: inner,
            height: inner,
            alignment: Alignment.center,
            padding: EdgeInsets.all(inner * 0.14),
            decoration: BoxDecoration(shape: BoxShape.circle, color: PublicTestimonials._color(design, block.string('avatarBackground')) ?? design.colorOf('goldLight')),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                initials,
                style: TextStyle(fontSize: inner * 0.38, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: PublicTestimonials._color(design, block.string('avatarTextColor')) ?? design.colorOf('forestDark')),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      key: Key('public-testimonial-${item.id}-avatar'),
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: border),
      child: face,
    );
  }

  /// Five stars (full, half and empty ones differ in shape, not only in
  /// colour), and the number if chosen; read as "4.5 out of 5 stars".
  Widget _rating(PublicStrings strings, double rating, Color muted) {
    final size = (block.values['starSize'] as int? ?? 18).toDouble();
    final full = PublicTestimonials._color(design, block.string('starColor')) ?? const Color(0xFFB7791F);
    final empty = PublicTestimonials._color(design, block.string('emptyStarColor')) ?? const Color(0xFF8C939D);
    final text = Testimonials.ratingText(rating);
    final number = switch (block.option('ratingNumber')) {
      'number' => rating.toStringAsFixed(1),
      'outOf' => '${rating.toStringAsFixed(1)} / 5',
      _ => null,
    };
    return Semantics(
      key: Key('public-testimonial-${item.id}-rating'),
      container: true,
      label: strings.ratingOutOfFive(text),
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            for (var i = 0; i < 5; i++)
              if (rating >= i + 1)
                Icon(Icons.star_rounded, key: Key('public-testimonial-${item.id}-star-$i-full'), size: size, color: full)
              else if (rating >= i + 0.5)
                Icon(Icons.star_half_rounded, key: Key('public-testimonial-${item.id}-star-$i-half'), size: size, color: full)
              else
                Icon(Icons.star_outline_rounded, key: Key('public-testimonial-${item.id}-star-$i-empty'), size: size, color: empty),
            if (number != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(number, key: Key('public-testimonial-${item.id}-rating-number'), style: PublicText.body.copyWith(color: muted, fontSize: math.max(12, size * 0.75), fontWeight: FontWeight.w600, height: 1.2)),
              ),
          ],
        ),
      ),
    );
  }
}
