import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../content/blocks/asymmetric_gallery.dart';
import '../../content/blocks/block_spacing.dart';
import '../../content/blocks/field_spec.dart';
import '../../content/blocks/website_block.dart';
import '../../content/website_content_models.dart';
import '../../content/website_custom_page.dart';
import '../../content/website_design.dart';
import '../../public_strings.dart';
import '../../public_website_theme.dart';
import '../../ui/public_gallery_page.dart';
import '../public_website_image.dart';
import 'block_spacing_box.dart';
import 'website_blocks_view.dart' show followBlockLink;

/// An Asymmetric gallery block as visitors (and the editor's canvas) see
/// it: the layout for the screen size ([AsymmetricLayout]) within the
/// width available, then each image drawn in its rectangle. Only the images
/// shown on this screen size are built (and so loaded).
///
/// Keys: `public-asymmetric-<block id>` (the composition),
/// `public-asymmetric-tile-<item id>`, `-image`, `-caption`.
class PublicAsymmetricGallery extends StatelessWidget {
  const PublicAsymmetricGallery({
    super.key,
    required this.block,
    required this.media,
    required this.language,
    required this.interactive,
    required this.headingStyle,
    required this.bodyStyle,
    required this.captionColor,
    this.background,
    this.border,
    this.ownPadding = const SpacingSides(),
  });

  /// The block's own padding ([BlockSpacing]), inside its background when
  /// it has one (its sides replace the background padding), else around
  /// its content; Automatic: as before.
  final SpacingSides ownPadding;

  final StructuredBlock block;

  /// Published images by id.
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final bool interactive;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final Color captionColor;
  final Color? background;
  final Border? border;

  /// The screen size [width] is (`desktop`, `tablet`, `mobile`).
  static String screenOf(double width) => switch (PublicLayout.of(width)) {
        PublicLayout.mobile => 'mobile',
        PublicLayout.tablet => 'tablet',
        PublicLayout.desktop => 'desktop',
      };

  /// Whether visitors would see anything: text, or a published image.
  static bool hasContent(StructuredBlock block, Map<String, WebsiteMedia> media, PublicLanguage language) =>
      block.text('heading').resolve(language).trim().isNotEmpty ||
      block.text('description').resolve(language).trim().isNotEmpty ||
      block.items('images').any((i) => media[i.string('mediaId')] != null && i.value<bool>('visible') != false);

  /// The images shown on [screen] (published, not hidden there), in their
  /// order there.
  static List<({BlockItem item, WebsiteMedia media, int index})> shownOn(StructuredBlock block, Map<String, WebsiteMedia> media, String screen) {
    final list = [
      for (final (i, item) in block.items('images').indexed)
        if (AsymmetricGallery.shownOn(item, screen) && media[item.string('mediaId')] != null) (item: item, media: media[item.string('mediaId')]!, index: i),
    ];
    list.sort((a, b) {
      final byOrder = AsymmetricGallery.orderOf(a.item, screen, a.index).compareTo(AsymmetricGallery.orderOf(b.item, screen, b.index));
      return byOrder != 0 ? byOrder : a.index.compareTo(b.index);
    });
    return list;
  }

  /// [item]'s own [key], else the block's (an item's `auto` is the block's).
  String _pick(BlockItem item, String key) {
    final own = item.string(key);
    return own.isEmpty || own == 'auto' ? block.string(key) : own;
  }

  int? _number(BlockItem item, String key) => item.value<int>(key) ?? block.values[key] as int?;

  static Color? _color(SiteDesign design, String value) => switch (value) {
        '' || 'auto' => null,
        'transparent' => Colors.transparent,
        _ => design.resolve(value),
      };

  @override
  Widget build(BuildContext context) {
    final design = WebsiteDesignScope.of(context);
    final strings = PublicStrings.of(language);
    final screen = screenOf(MediaQuery.sizeOf(context).width);
    final settings = AsymmetricGallery.settings(block, screen);
    final shown = shownOn(block, media, screen);
    final marked = shown.where((s) => s.item.value<bool>('feature') == true).firstOrNull;
    final featureId = (marked ?? shown.firstOrNull)?.item.id;
    final align = block.string('align');
    final cross = switch (align) { 'start' => CrossAxisAlignment.start, 'end' => CrossAxisAlignment.end, _ => CrossAxisAlignment.center };
    final textAlign = switch (align) { 'start' => TextAlign.start, 'end' => TextAlign.end, _ => TextAlign.center };
    final heading = block.text('heading').resolve(language).trim();
    final description = block.text('description').resolve(language).trim();
    final captionsOn = block.toggle('showCaptions');
    final textScaler = MediaQuery.textScalerOf(context);

    TextStyle captionStyle(BlockItem item, {required bool overlay}) => PublicText.body.copyWith(
          fontSize: (block.values['captionSize'] as int? ?? 14).toDouble(),
          height: 1.35,
          fontWeight: switch (block.string('captionWeight')) { 'medium' => FontWeight.w500, 'bold' => FontWeight.w700, _ => FontWeight.w400 },
          fontStyle: block.string('captionStyle') == 'italic' ? FontStyle.italic : FontStyle.normal,
          color: _color(design, block.string('captionColor')) ?? (overlay ? Colors.white : captionColor),
        );
    String captionOf(BlockItem item, WebsiteMedia m) {
      final own = item.text('caption').resolve(language).trim();
      return own.isNotEmpty ? own : m.caption.resolve(language).trim();
    }

    String placementOf(BlockItem item) {
      final own = item.string('captionPlacement');
      return own == 'auto' || own.isEmpty ? block.string('captionPlacement') : own;
    }

    // The room a caption below an image needs (at most two lines).
    double below(BlockItem item, WebsiteMedia m, double width) {
      if (!captionsOn || placementOf(item) != 'below') return 0;
      final caption = captionOf(item, m);
      if (caption.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: caption, style: captionStyle(item, overlay: false)),
        maxLines: 2,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: math.max(1, width));
      final h = painter.height + 8;
      painter.dispose();
      return h;
    }

    final byId = {for (final s in shown) s.item.id: s};
    final composition = LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
      final width = math.min(available, (block.values['maxWidth'] as int? ?? 100000).toDouble()).floorToDouble();
      final tiles = [
        for (final s in shown)
          AsymmetricTile(
            id: s.item.id,
            naturalRatio: s.media.aspectRatio,
            ratio: AsymmetricGallery.ratioOf(s.item.string('aspect'), s.item.text('aspectCustom').en),
            feature: s.item.id == featureId,
            weight: int.tryParse(s.item.string('weight')) ?? 1,
            colSpan: AsymmetricGallery.spanOf(s.item, screen, 'colSpan'),
            rowSpan: AsymmetricGallery.spanOf(s.item, screen, 'rowSpan'),
          ),
      ];
      final layout = AsymmetricLayout.compute(tiles, settings, width, extraBelow: (t, w) => below(byId[t.id]!.item, byId[t.id]!.media, w));
      // The larger view moves through the images that open it, in order.
      final viewable = [
        for (final p in layout.placements)
          if (_action(byId[p.id]!.item) == 'lightbox') p.id,
      ];
      final viewMedia = [for (final id in viewable) byId[id]!.media];
      return Align(
        alignment: switch (align) { 'start' => Alignment.topLeft, 'end' => Alignment.topRight, _ => Alignment.topCenter },
        child: SizedBox(
          key: Key('public-asymmetric-${block.id}'),
          width: width,
          height: layout.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final (n, p) in layout.placements.indexed)
                Positioned.fromRect(
                  rect: p.rect,
                  child: () {
                    final s = byId[p.id]!;
                    final item = s.item;
                    final action = _action(item);
                    final alt = item.text('alt').resolve(language).trim();
                    final decorative = item.value<bool>('decorative') == true;
                    final caption = captionsOn && placementOf(item) != 'none' ? captionOf(item, s.media) : '';
                    final label = decorative ? '' : (alt.isNotEmpty ? alt : s.media.alt.resolve(language).trim());
                    final fx = _number(item, 'focalX');
                    final fy = _number(item, 'focalY');
                    final overlayColor = _color(design, _pick(item, 'overlayColor'));
                    final opacity = (_number(item, 'overlayOpacity') ?? (overlayColor == null ? 0 : 30)) / 100;
                    final target = item.string('target').trim();
                    return _AsymmetricTileView(
                      key: Key('public-asymmetric-tile-${item.id}'),
                      id: item.id,
                      media: s.media,
                      size: p.rect.size,
                      fit: _pick(item, 'fit') == 'contain' ? BoxFit.contain : BoxFit.cover,
                      alignment: fx == null && fy == null ? null : Alignment(((fx ?? (s.media.focalX * 100)) / 50) - 1, ((fy ?? (s.media.focalY * 100)) / 50) - 1),
                      radius: (_number(item, 'radius') ?? 16).toDouble(),
                      borderWidth: double.tryParse(_pick(item, 'borderWidth')) ?? 0,
                      borderColor: _color(design, _pick(item, 'borderColor')) ?? design.colorOf('line'),
                      overlay: overlayColor?.withValues(alpha: (overlayColor.a * opacity).clamp(0, 1)),
                      hover: _pick(item, 'hover'),
                      shadow: _pick(item, 'shadow'),
                      caption: caption,
                      captionOver: placementOf(item) == 'overlay',
                      captionBand: below(item, s.media, p.rect.width),
                      captionStyle: captionStyle(item, overlay: placementOf(item) == 'overlay'),
                      captionAlign: switch (block.string('captionAlign')) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start },
                      captionBackground: _color(design, block.string('captionBackground')) ?? const Color(0xA6101A15),
                      // A decorative image that does something still needs a name.
                      label: label.isNotEmpty || action == 'none' ? label : (caption.isNotEmpty ? caption : strings.galleryImageNumber(n + 1)),
                      decorative: decorative || label.isEmpty,
                      link: action == 'link',
                      onTap: !interactive || action == 'none'
                          ? null
                          : action == 'link'
                              ? () => followBlockLink(context, target, newTab: item.value<bool>('newTab') != false)
                              : () => showPublicGalleryLightbox(context, viewMedia, viewable.indexOf(item.id)),
                      errorLabel: strings.imageUnavailable,
                    );
                  }(),
                ),
            ],
          ),
        ),
      );
    });

    Widget content = Column(
      crossAxisAlignment: cross,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: headingStyle, textAlign: textAlign), SizedBox(height: description.isEmpty ? 24 : 10)],
        if (description.isNotEmpty) ...[
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(description, style: bodyStyle, textAlign: textAlign)),
          const SizedBox(height: 24),
        ],
        if (shown.isNotEmpty) SizedBox(width: double.infinity, child: composition),
      ],
    );
    if (background != null || border != null) {
      final pad = (block.values['backgroundPadding'] as int? ?? (screen == 'mobile' ? 20 : 32)).toDouble();
      final own = ownPadding.over(top: pad, right: pad, bottom: pad, left: pad);
      content = Container(
        key: Key('public-asymmetric-${block.id}-background'),
        padding: ownPadding.isAutomatic ? EdgeInsets.all(pad) : null,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20), border: border),
        child: ownPadding.isAutomatic ? content : FitPadding(padding: EdgeInsets.fromLTRB(own.left, own.top, own.right, own.bottom), child: content),
      );
    } else if (!ownPadding.isAutomatic) {
      final own = ownPadding.over();
      content = FitPadding(padding: EdgeInsets.fromLTRB(own.left, own.top, own.right, own.bottom), child: content);
    }
    final top = (block.values['paddingTop'] as int? ?? 0).toDouble();
    final bottom = (block.values['paddingBottom'] as int? ?? 0).toDouble();
    return Padding(padding: EdgeInsets.only(top: top, bottom: bottom), child: content);
  }

  /// What clicking [item] does: `link`, `lightbox` or `none`. Automatic is
  /// its link if it has one, else the larger view (if the block allows it).
  String _action(BlockItem item) {
    final target = item.string('target').trim();
    final hasLink = target.isNotEmpty && SafeLinkTarget.validate(target) == null;
    final lightbox = block.toggle('lightbox');
    return switch (item.string('action')) {
      'link' => hasLink ? 'link' : 'none',
      'lightbox' => lightbox ? 'lightbox' : 'none',
      'none' => 'none',
      _ => hasLink ? 'link' : (lightbox ? 'lightbox' : 'none'),
    };
  }
}

/// One image in its rectangle: the photograph (cropped or contained, from
/// its focal point), its border, overlay, shadow and hover effect, and its
/// caption below or over it. One tap does one thing ([onTap]). Hover and
/// keyboard focus show the hover effect; with reduced motion nothing moves.
class _AsymmetricTileView extends StatefulWidget {
  const _AsymmetricTileView({
    super.key,
    required this.id,
    required this.media,
    required this.size,
    required this.fit,
    required this.alignment,
    required this.radius,
    required this.borderWidth,
    required this.borderColor,
    required this.overlay,
    required this.hover,
    required this.shadow,
    required this.caption,
    required this.captionOver,
    required this.captionBand,
    required this.captionStyle,
    required this.captionAlign,
    required this.captionBackground,
    required this.label,
    required this.decorative,
    required this.link,
    required this.onTap,
    required this.errorLabel,
  });

  final String id;
  final WebsiteMedia media;
  final Size size;
  final BoxFit fit;
  final Alignment? alignment;
  final double radius;
  final double borderWidth;
  final Color borderColor;
  final Color? overlay;
  final String hover;
  final String shadow;
  final String caption;
  final bool captionOver;

  /// The room under the image for a caption below it (0: none).
  final double captionBand;
  final TextStyle captionStyle;
  final TextAlign captionAlign;
  final Color captionBackground;

  /// What screen readers read ('' with [decorative]: nothing).
  final String label;
  final bool decorative;
  final bool link;
  final VoidCallback? onTap;
  final String errorLabel;

  @override
  State<_AsymmetricTileView> createState() => _AsymmetricTileViewState();
}

class _AsymmetricTileViewState extends State<_AsymmetricTileView> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = _hovered || _focused;
    final duration = still ? Duration.zero : const Duration(milliseconds: 220);
    // A caption below, unless the image would be left too small: then over it.
    final band = w.captionBand > 0 && w.size.height - w.captionBand >= w.size.height * 0.45 ? w.captionBand : 0.0;
    final over = w.caption.isNotEmpty && (w.captionOver || (w.captionBand > 0 && band == 0));
    final imageHeight = math.max(1.0, w.size.height - band);
    final radius = BorderRadius.circular(w.radius);

    Widget image = PublicWebsiteImage(
      key: Key('public-asymmetric-tile-${w.id}-image'),
      media: w.media,
      aspectRatio: w.size.width / imageHeight,
      fit: w.fit,
      alignment: w.alignment,
      borderRadius: 0,
      semanticLabel: '',
      errorLabel: w.errorLabel,
      placeholder: const PublicImagePlaceholder(compact: true),
    );
    if (w.hover == 'zoom' && !still) image = AnimatedScale(scale: active ? 1.04 : 1, duration: duration, curve: Curves.easeOut, child: image);
    final visual = Container(
      width: w.size.width,
      height: imageHeight,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: switch (w.shadow) {
          'soft' => const [BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 6))],
          'strong' => const [BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 12))],
          _ => null,
        },
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: _focused
            ? Border.all(color: const Color(0xFF1F4D3A), width: 3)
            : w.borderWidth > 0
                ? Border.all(color: w.borderColor, width: w.borderWidth)
                : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (w.overlay != null) IgnorePointer(child: ColoredBox(color: w.overlay!)),
            if (w.hover == 'dim') IgnorePointer(child: AnimatedOpacity(opacity: active ? 1 : 0, duration: duration, child: const ColoredBox(color: Color(0x26000000)))),
            if (over)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  key: Key('public-asymmetric-tile-${w.id}-caption'),
                  color: w.captionBackground,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Text(w.caption, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: w.captionAlign, style: w.captionStyle),
                ),
              ),
          ],
        ),
      ),
    );
    Widget lifted = visual;
    if (w.hover == 'lift' && !still) {
      lifted = AnimatedSlide(offset: active ? Offset(0, -4 / imageHeight) : Offset.zero, duration: duration, curve: Curves.easeOut, child: visual);
    }
    final interactive = w.onTap != null;
    Widget tile = ExcludeSemantics(child: lifted);
    tile = MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: interactive
          ? InkWell(
              onTap: w.onTap,
              borderRadius: radius,
              onFocusChange: (f) => setState(() => _focused = f),
              child: tile,
            )
          : tile,
    );
    // One node: the image's name and its action (a decorative image that
    // does nothing is skipped; its caption is still read).
    tile = w.decorative && !interactive
        ? ExcludeSemantics(child: tile)
        : MergeSemantics(child: Semantics(image: !w.decorative, link: w.link, button: interactive && !w.link, label: w.label, child: tile));
    final captionRead = w.caption != w.label;
    final overText = over ? Semantics(label: captionRead ? w.caption : null, child: const SizedBox.shrink()) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(children: [tile, ?overText]),
        if (band > 0 && w.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExcludeSemantics(
            excluding: !captionRead,
            child: Text(w.caption, key: Key('public-asymmetric-tile-${w.id}-caption'), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: w.captionAlign, style: w.captionStyle),
          ),
        ],
      ],
    );
  }
}
