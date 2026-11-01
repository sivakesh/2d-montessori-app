import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../content/blocks/block_registry.dart';
import '../../content/blocks/block_spacing.dart';
import '../../content/blocks/embed_providers.dart';
import '../../content/blocks/field_spec.dart';
import '../../content/blocks/website_block.dart';
import '../../content/website_content_models.dart';
import '../../content/website_custom_page.dart';
import '../../content/website_design.dart';
import '../../public_routes.dart';
import '../../public_strings.dart';
import '../../public_website_theme.dart';
import '../../ui/public_gallery_page.dart';
import '../public_website_image.dart';
import '../../../forms/ui/public_website_form.dart';
import 'public_accreditations.dart';
import 'public_announcements_feed.dart';
import 'block_spacing_box.dart';
import 'public_asymmetric_gallery.dart';
import 'public_custom_html.dart';
import 'public_embed_block.dart';
import 'public_map_block.dart';
import 'public_testimonials.dart';
import 'public_events_feed.dart';
import 'public_item_cards.dart';
import 'public_feature_widgets.dart';

/// Follows a block's button link: a public page in place, an allowed
/// external link in a new tab. Checked again first; an unsafe link does
/// nothing.
Future<void> followBlockLink(BuildContext context, String target, {bool newTab = true}) async {
  if (SafeLinkTarget.validate(target) != null) return;
  if (SafeLinkTarget.isInternal(target)) {
    PublicRoutes.open(context, target);
    return;
  }
  // [newTab] false: another site in this tab (on the web).
  await launchUrl(Uri.parse(target), mode: newTab ? LaunchMode.externalApplication : LaunchMode.platformDefault, webOnlyWindowName: newTab ? null : '_self');
}

/// The icon a stored icon name stands for ([blockIconNames]).
IconData blockIconData(String name) => switch (name) {
      'family' => Icons.family_restroom_outlined,
      'school' => Icons.school_outlined,
      'spa' => Icons.spa_outlined,
      'grid' => Icons.grid_view_outlined,
      'care' => Icons.volunteer_activism_outlined,
      'book' => Icons.menu_book_outlined,
      'palette' => Icons.palette_outlined,
      'nature' => Icons.park_outlined,
      'heart' => Icons.favorite_border,
      'calendar' => Icons.event_outlined,
      'place' => Icons.place_outlined,
      'phone' => Icons.phone_outlined,
      'mail' => Icons.mail_outline,
      'question' => Icons.help_outline,
      'quote' => Icons.format_quote_outlined,
      'check' => Icons.check_circle_outline,
      _ => Icons.star_outline,
    };

/// How the page editor draws the blocks inside a section or columns block:
/// [frame] wraps each one (with [rendered] null when visitors wouldn't see
/// it, so the editor can show why), and [columnEnd] follows each column
/// (e.g. an "add a block here" button). Containers are then drawn even
/// when nothing inside them is shown yet.
@immutable
class WebsiteBlocksEditing {
  const WebsiteBlocksEditing({required this.frame, required this.columnEnd});

  final Widget Function(BuildContext context, StructuredBlock parent, int column, int index, WebsiteBlock child, Widget? rendered) frame;
  final Widget Function(BuildContext context, StructuredBlock parent, int column) columnEnd;
}

/// A page's blocks for visitors (or the admin preview, with [interactive]
/// false). Each block is checked again before it is drawn: hidden,
/// unsupported and invalid blocks are left out one by one, so a bad block
/// never breaks the page. Images not in [media] (the published images)
/// are left out; links are re-checked before being followed.
///
/// Colours and type sizes come from the [WebsiteDesignScope] above (the
/// site's own design without one), then from the section a block is in,
/// then from the block's own style.
///
/// [fullBleed]: the view spans the page's full width; sections are drawn
/// edge to edge and every other block at its content width
/// ([contentMaxWidth] unless it sets its own). Otherwise the view is
/// placed inside the page's content width and sections are drawn as
/// rounded panels.
class WebsiteBlocksView extends StatelessWidget {
  const WebsiteBlocksView({
    super.key,
    required this.blocks,
    required this.media,
    required this.language,
    this.interactive = true,
    this.spaced = true,
    this.fullBleed = false,
    this.contentMaxWidth = 960,
    this.editing,
  });

  final List<WebsiteBlock> blocks;
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final bool interactive;

  /// Each block's space above it (its `spacing`). The page editor's canvas
  /// draws blocks one at a time without it and spaces them itself.
  final bool spaced;
  final bool fullBleed;
  final double contentMaxWidth;
  final WebsiteBlocksEditing? editing;

  /// Whether [block] is shown at all (before checking its images).
  static bool isShown(WebsiteBlock block) => block is StructuredBlock && !block.hidden && BlockRegistry.blockProblems(block).isEmpty;

  /// Whether visitors would see anything of [block] with [media] (the
  /// published images): shown, and with something to show.
  static bool rendersVisibly(WebsiteBlock block, Map<String, WebsiteMedia> media, PublicLanguage language) =>
      _BlockWidget.maybe(block, WebsiteBlocksView(blocks: const [], media: media, language: language)) != null;

  /// The screen size [width] is, as block spacing names it.
  static String screenOf(double width) => switch (PublicLayout.of(width)) {
        PublicLayout.mobile => 'mobile',
        PublicLayout.tablet => 'tablet',
        PublicLayout.desktop => 'desktop',
      };

  /// Whether [block] sets its own top margin on [screen]: it then is the
  /// space above the block, in place of [spaceAbove] or [spaceInside]
  /// (never added to them).
  static bool ownsSpaceAbove(WebsiteBlock block, String? screen) =>
      screen != null && block is StructuredBlock && BlockSpacing.resolve(block.style[BlockSpacing.margin], screen, 'top') != null;

  /// The space above [block] on the page (none when its own top margin on
  /// [screen] takes its place).
  static double spaceAbove(WebsiteBlock block, {required bool mobile, String? screen}) {
    if (ownsSpaceAbove(block, screen)) return 0;
    final spacing = block is StructuredBlock ? block.spacing : 'normal';
    return switch (spacing) { 'none' => 0.0, 'compact' => 24.0, 'spacious' => 80.0, _ => 56.0 } * (mobile ? 0.7 : 1);
  }

  /// The space above [block] inside a section (smaller than on the page;
  /// none when its own top margin on [screen] takes its place).
  static double spaceInside(WebsiteBlock block, {required bool mobile, String? screen}) {
    if (ownsSpaceAbove(block, screen)) return 0;
    final spacing = block is StructuredBlock ? block.spacing : 'normal';
    return switch (spacing) { 'none' => 0.0, 'compact' => 16.0, 'spacious' => 56.0, _ => 32.0 } * (mobile ? 0.75 : 1);
  }

  /// The content width [block] is drawn at on a full-width page.
  double contentWidthOf(WebsiteBlock block) {
    final style = block is StructuredBlock ? block.style['width'] : null;
    return switch (style) {
      'narrow' => 760.0,
      'content' => 960.0,
      'wide' => 1160.0,
      _ => switch (block.type) {
          'hero' || 'cards' || 'features' || 'gallery_feed' || 'accreditations' || 'asymmetric_gallery' || 'testimonials' => 1160.0,
          'page_header' || 'notice' => 760.0,
          _ => contentMaxWidth,
        },
    };
  }

  /// [widget] (for [block]) placed on a full-width page.
  Widget place(WebsiteBlock block, Widget widget) =>
      block.type == 'section' ? widget : PublicContentWidth(maxWidth: contentWidthOf(block), child: widget);

  /// [block] drawn alone, or null when visitors wouldn't see it.
  Widget? render(WebsiteBlock block) => _BlockWidget.maybe(block, this);

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final children = <Widget>[];
    for (final block in blocks) {
      final widget = _BlockWidget.maybe(block, this);
      if (widget == null) continue;
      if (spaced) children.add(SizedBox(height: spaceAbove(block, mobile: layout.isMobile, screen: _BlockWidget.screenOf(layout))));
      children.add(KeyedSubtree(key: Key('public-block-${block.id}'), child: fullBleed ? place(block, widget) : widget));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// The colours a section (or columns block) passes to the blocks inside it.
class _InheritedLook extends InheritedWidget {
  const _InheritedLook({required this.text, required this.heading, required this.button, required this.buttonText, required this.align, required super.child});

  final Color? text;
  final Color? heading;
  final Color? button;
  final Color? buttonText;
  final String? align;

  static _InheritedLook? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_InheritedLook>();

  @override
  bool updateShouldNotify(_InheritedLook old) =>
      old.text != text || old.heading != heading || old.button != button || old.buttonText != buttonText || old.align != align;
}

/// A block's resolved look: its own style, else its section's, else the
/// site's design.
class _Look {
  _Look(BuildContext context, StructuredBlock block) : design = WebsiteDesignScope.of(context) {
    final inherited = _InheritedLook.of(context);
    Color? own(String key) => design.resolve(block.style[key]);
    heading = own('headingColor') ?? inherited?.heading ?? design.colorOf('forestDark');
    text = own('textColor') ?? inherited?.text ?? design.colorOf('muted');
    button = own('buttonColor') ?? inherited?.button ?? design.colorOf('forest');
    buttonText = own('buttonTextColor') ?? inherited?.buttonText;
    caption = own('textColor') ?? inherited?.text ?? design.colorOf('ink');
    align = block.style['align'] is String ? block.style['align'] as String : inherited?.align ?? 'start';
    scale = switch (block.style['fontSize']) { 'small' => 0.875, 'large' => 1.125, _ => 1.0 };
    double? px(String key) => BlockStyle.sizeKeys[key]!.allows(block.style[key]) ? (block.style[key] as num).toDouble() : null;
    ownHeadingSize = px('headingFontSize');
    ownBodySize = px('bodyFontSize');
  }

  /// The block's own sizes ([BlockStyle.sizeKeys]): they take the place of
  /// the site typography (and of the text size option).
  late final double? ownHeadingSize;
  late final double? ownBodySize;

  final SiteDesign design;
  late final Color heading;
  late final Color text;
  late final Color button;
  late final Color? buttonText;
  late final Color caption;
  late final String align;
  late final double scale;

  TextAlign get textAlign => switch (align) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };
  CrossAxisAlignment get cross => switch (align) { 'center' => CrossAxisAlignment.center, 'end' => CrossAxisAlignment.end, _ => CrossAxisAlignment.start };
  WrapAlignment get wrap => switch (align) { 'center' => WrapAlignment.center, 'end' => WrapAlignment.end, _ => WrapAlignment.start };

  TextStyle get headingStyle => PublicText.heading.copyWith(color: heading, fontSize: ownHeadingSize ?? design.headingSize * scale);
  TextStyle get titleStyle => PublicText.title.copyWith(color: heading);
  TextStyle get bodyStyle => PublicText.body.copyWith(color: text, fontSize: ownBodySize ?? design.bodySize * scale, height: design.lineHeight);

  /// A hero's or page header's title: the block's own heading size (on
  /// phones scaled as the site's titles are), else the site's title size.
  TextStyle displayStyle({required bool mobile}) {
    final base = design.titleStyle(mobile: mobile).copyWith(color: heading);
    final own = ownHeadingSize;
    if (own == null) return base;
    final ratio = mobile ? design.titleSizeFor(mobile: true) / design.titleSizeFor(mobile: false) : 1.0;
    return base.copyWith(fontSize: (own * ratio).roundToDouble());
  }

  /// Button labels: the site's button size, if it sets one.
  TextStyle? get buttonLabelStyle => design.buttonSize == null ? null : TextStyle(fontSize: design.buttonSize);
  TextStyle get eyebrowStyle => PublicText.eyebrow.copyWith(color: design.colorOf('gold'));
}

/// One shown block, or nothing ([maybe] returns null).
class _BlockWidget extends StatelessWidget {
  const _BlockWidget(this.block, this.view);

  final StructuredBlock block;
  final WebsiteBlocksView view;

  static Widget? maybe(WebsiteBlock block, WebsiteBlocksView view) {
    if (!WebsiteBlocksView.isShown(block)) return null;
    final b = block as StructuredBlock;
    // An image or grid with nothing to show (no published image) is left out.
    if (b.type == 'image' && view.media[b.string('mediaId')] == null) return null;
    if (b.type == 'gallery' && b.text('heading').resolve(view.language).isEmpty && !b.items('images').any((i) => view.media[i.string('mediaId')] != null)) return null;
    if (b.type == 'asymmetric_gallery' && !PublicAsymmetricGallery.hasContent(b, view.media, view.language)) return null;
    if (b.type == 'testimonials' && !PublicTestimonials.hasContent(b, view.language)) return null;
    // A section or columns block with nothing to show (no visible block,
    // and for a section no heading text either) is left out.
    if (containerTypes.contains(b.type) &&
        view.editing == null &&
        !(b.type == 'section' && _sectionHasHeader(b, view.language)) &&
        !b.columns('columns').any((c) => c.blocks.any((child) => maybe(child, view) != null))) {
      return null;
    }
    return _BlockWidget(b, view);
  }

  PublicLanguage get language => view.language;

  /// The optional text a section shows above its columns.
  static const _sectionHeaderKeys = ['eyebrow', 'heading', 'description'];

  static bool _sectionHasHeader(StructuredBlock section, PublicLanguage language) =>
      _sectionHeaderKeys.any((k) => section.text(k).resolve(language).trim().isNotEmpty);

  static Color? backgroundOf(StructuredBlock block, SiteDesign design) => switch (block.style['background']) {
        'sage' => design.colorOf('sageLight'),
        'gold' => design.colorOf('goldLight'),
        'white' || null => null,
        final value => design.resolve(value),
      };

  static double paddingOf(StructuredBlock block, String key, {required bool mobile, required double fallback}) {
    final value = block.style[key];
    final px = value is String ? double.tryParse(value) ?? fallback : fallback;
    return mobile && px > 48 ? 48 : px;
  }

  Border? _border(SiteDesign design, {double fallbackWidth = 1}) {
    final color = design.resolve(block.style['borderColor']);
    if (color == null) return null;
    final width = double.tryParse(block.style['borderWidth']?.toString() ?? '') ?? fallbackWidth;
    return width <= 0 ? null : Border.all(color: color, width: width);
  }

  Widget _paragraphs(String text, _Look look) => Column(
        crossAxisAlignment: look.cross,
        children: [
          for (final (i, paragraph) in text.split(RegExp(r'\n\s*\n')).indexed)
            if (paragraph.trim().isNotEmpty) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 14), child: Text(paragraph.trim(), style: look.bodyStyle, textAlign: look.textAlign)),
        ],
      );

  Widget _textBlock(String heading, String body, _Look look) => Column(
        crossAxisAlignment: look.cross,
        children: [
          if (heading.isNotEmpty) ...[Text(heading, style: look.headingStyle, textAlign: look.textAlign), const SizedBox(height: 12)],
          if (body.isNotEmpty) _paragraphs(body, look),
        ],
      );

  /// The block's safe buttons with a label, as visitors see them. A label
  /// is never shortened: one too long for the space wraps onto more lines
  /// (centred in a filled or outlined button) and the button grows.
  Widget? _buttons(List<BlockItem> items, _Look look, {WrapAlignment? align}) {
    final shown = [
      for (final item in items)
        if (item.text('label').resolve(language).isNotEmpty && SafeLinkTarget.validate(item.string('target').trim()) == null) item,
    ];
    if (shown.isEmpty) return null;
    return Wrap(
      alignment: align ?? look.wrap,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final item in shown)
          Builder(builder: (context) {
            final target = item.string('target').trim();
            final onPressed = view.interactive ? () => followBlockLink(context, target) : null;
            final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
            const padding = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
            final text = item.text('label').resolve(language);
            final key = Key('public-block-button-${item.id}');
            final link = item.string('variant') == 'link' || item.string('variant') == 'back';
            final label = Text(text, key: Key('public-block-button-${item.id}-label'), style: look.buttonLabelStyle, textAlign: link ? TextAlign.start : TextAlign.center);
            return switch (item.string('variant')) {
              'secondary' => OutlinedButton(
                  key: key,
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(foregroundColor: look.button, side: BorderSide(color: look.button), padding: padding, shape: shape),
                  child: label,
                ),
              'link' || 'back' => TextButton.icon(
                  key: key,
                  onPressed: onPressed,
                  icon: Icon(item.string('variant') == 'back' ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, size: 18),
                  label: label,
                  style: TextButton.styleFrom(foregroundColor: look.button),
                ),
              _ => FilledButton(
                  key: key,
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(backgroundColor: look.button, foregroundColor: look.buttonText, padding: padding, shape: shape),
                  child: label,
                ),
            };
          }),
      ],
    );
  }

  /// [child] placed by [look]'s alignment (as it is when aligned to the
  /// start).
  static Widget _aligned(_Look look, Widget child) => look.align == 'start'
      ? child
      : Align(alignment: look.align == 'center' ? Alignment.topCenter : Alignment.topRight, child: child);

  static double? _aspect(String value) => switch (value) { '16:9' => 16 / 9, '4:3' => 4 / 3, '1:1' => 1.0, '3:4' => 3 / 4, _ => null };

  /// The screen size [layout] is, as spacing names it.
  static String screenOf(PublicLayout layout) => switch (layout) { PublicLayout.mobile => 'mobile', PublicLayout.tablet => 'tablet', PublicLayout.desktop => 'desktop' };

  /// The block's own padding and margin on [layout] ([BlockSpacing]; sides
  /// not set are Automatic).
  SpacingSides _spacing(String kind, PublicLayout layout) => BlockSpacing.sidesOn(block.style[kind], screenOf(layout));

  /// A block surface (its background and border) with [automatic] padding
  /// inside: exactly as before unless the block sets its own padding,
  /// whose sides then replace those of [automatic].
  Widget _surface(PublicLayout layout, {Key? key, double? width, required Decoration? decoration, required EdgeInsets automatic, required Widget child}) {
    final own = _spacing(BlockSpacing.padding, layout);
    if (own.isAutomatic) return Container(key: key, width: width, padding: automatic, decoration: decoration, child: child);
    final p = own.over(top: automatic.top, right: automatic.right, bottom: automatic.bottom, left: automatic.left);
    return Container(key: key, width: width, decoration: decoration, child: FitPadding(padding: EdgeInsets.fromLTRB(p.left, p.top, p.right, p.bottom), child: child));
  }

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final drawn = _build(context, layout);
    // The margin, outside the block's surface; Automatic: none (the space
    // between blocks is the page's or the section's, as before).
    final margin = _spacing(BlockSpacing.margin, layout);
    final padding = _spacing(BlockSpacing.padding, layout);
    // With its own side spacing a block spans the width it is given (on a
    // full-width page, the content width), so its sides are measured from
    // those edges; otherwise a narrow block is centred there and a side
    // would move it by only half (as before when nothing is set).
    final sides = margin.left != null || margin.right != null || padding.left != null || padding.right != null;
    Widget out = drawn;
    if (!margin.isAutomatic) {
      final m = margin.over();
      out = FitPadding(key: Key('public-block-${block.id}-margin'), padding: EdgeInsets.fromLTRB(m.left, m.top, m.right, m.bottom), child: out);
    }
    return sides ? SizedBox(width: double.infinity, child: out) : out;
  }

  Widget _build(BuildContext context, PublicLayout layout) {
    final strings = PublicStrings.of(language);
    final look = _Look(context, block);
    if (block.type == 'section') return _section(context, layout, look);
    final content = switch (block.type) {
      'text' => _aligned(
          look,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _textBlock(block.text('heading').resolve(language), block.text('body').resolve(language), look),
          ),
        ),
      'image' => _image(strings, look),
      'gallery' => _gallery(context, strings, layout, look),
      'asymmetric_gallery' => PublicAsymmetricGallery(
          block: block,
          media: view.media,
          language: language,
          interactive: view.interactive,
          headingStyle: look.headingStyle,
          bodyStyle: look.bodyStyle,
          captionColor: look.caption,
          background: backgroundOf(block, look.design),
          border: _border(look.design),
          ownPadding: _spacing(BlockSpacing.padding, layout),
        ),
      'cta' => _surface(
          layout,
          automatic: EdgeInsets.all(layout.isMobile ? 24 : 36),
          decoration: BoxDecoration(
            color: (block.style['background'] is String && SiteDesign.isColorValue(block.style['background']) ? look.design.resolve(block.style['background']) : null) ??
                look.design.colorOf('sageLight'),
            borderRadius: BorderRadius.circular(20),
            border: _border(look.design),
          ),
          child: Column(
            crossAxisAlignment: look.cross,
            children: [
              _textBlock(block.text('heading').resolve(language), block.text('body').resolve(language), look),
              if (_buttons(block.items('buttons'), look) case final buttons?) ...[const SizedBox(height: 20), buttons],
            ],
          ),
        ),
      'buttons' => _buttons(block.items('buttons'), look, align: block.string('align') == 'center' ? WrapAlignment.center : WrapAlignment.start) ?? const SizedBox.shrink(),
      'columns' => _columns(context, layout, look),
      'divider' => Padding(
          padding: EdgeInsets.symmetric(vertical: switch (block.string('size')) { 'small' => 4.0, 'large' => 32.0, _ => 16.0 }),
          child: Divider(height: 1, thickness: 1, color: look.design.resolve(block.style['lineColor']) ?? look.design.colorOf('line')),
        ),
      'hero' => _hero(strings, layout, look),
      'cards' => _cards(layout, look),
      'testimonials' => PublicTestimonials(
          block: block,
          media: view.media,
          language: language,
          headingStyle: look.headingStyle,
          bodyStyle: look.bodyStyle,
          headingColor: look.heading,
        ),
      'features' => _features(layout, look),
      'page_header' => _pageHeader(strings, layout, look),
      'notice' => _surface(
          layout,
          width: double.infinity,
          automatic: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: backgroundOf(block, look.design) ?? look.design.colorOf('goldLight'), borderRadius: BorderRadius.circular(16), border: _border(look.design)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.text('title').resolve(language) case final title when title.isNotEmpty) Text(title, style: look.titleStyle),
              if (block.text('body').resolve(language) case final body when body.isNotEmpty) ...[const SizedBox(height: 6), Text(body, style: look.bodyStyle)],
            ],
          ),
        ),
      'gallery_feed' => view.interactive ? const PublicGalleryFeed() : _galleryFeedPreview(strings, layout),
      // The editor and preview show the events visitors see now (the
      // public copies only).
      'events_feed' => PublicEventsFeed(
          language: language,
          limit: int.tryParse(block.string('maxItems')) ?? 6,
          layout: PublicEventsLayout.parse(block.string('layout')),
          desktopColumns: int.tryParse(block.string('desktopColumns')) ?? 3,
          tabletColumns: int.tryParse(block.string('tabletColumns')) ?? 2,
          mobileColumns: int.tryParse(block.string('mobileColumns')) ?? 1,
          showImages: block.flag('showImages'),
          heading: block.text('heading').resolve(language),
          headingStyle: look.headingStyle,
          titleStyle: look.titleStyle,
          bodyStyle: look.bodyStyle,
          accent: look.button,
          interactive: view.interactive,
        ),
      'announcements_feed' => PublicAnnouncementsFeed(
          language: language,
          limit: int.tryParse(block.string('maxItems')) ?? 6,
          layout: PublicItemsLayout.parse(block.string('layout')),
          desktopColumns: int.tryParse(block.string('desktopColumns')) ?? 3,
          tabletColumns: int.tryParse(block.string('tabletColumns')) ?? 2,
          mobileColumns: int.tryParse(block.string('mobileColumns')) ?? 1,
          showImages: block.flag('showImages'),
          showCategory: block.flag('showCategory'),
          highlightPinned: block.flag('highlightPinned'),
          heading: block.text('heading').resolve(language),
          headingStyle: look.headingStyle,
          titleStyle: look.titleStyle,
          bodyStyle: look.bodyStyle,
          accent: look.button,
          interactive: view.interactive,
        ),
      // Only the form's id is stored; its active version is read when
      // shown (nothing for visitors when it isn't active).
      'form' => WebsiteFormBlockView(
          formId: block.string('formId'),
          language: language,
          heading: block.text('heading').resolve(language),
          intro: block.text('intro').resolve(language),
          headingStyle: look.headingStyle,
          bodyStyle: look.bodyStyle,
          accent: look.button,
          interactive: view.interactive,
        ),
      'map' => PublicMapBlock(
          key: Key('public-map-${block.id}'),
          config: MapBlockConfig.of(block),
          heading: block.text('heading').resolve(language),
          details: block.text('details').resolve(language),
          language: language,
          wide: !layout.isMobile,
          headingStyle: look.headingStyle,
          bodyStyle: look.bodyStyle,
          accent: look.button,
          interactive: view.interactive,
        ),
      'accreditations' => _accreditations(context, layout, look),
      // A provider's frame from the address rebuilt from the block's
      // source; the block is valid only when it parses.
      'embed' => PublicEmbedBlock(
          key: Key('public-embed-block-${block.id}'),
          id: block.id,
          source: EmbedSource.parse(block.text('source').en),
          title: block.text('title').resolve(language),
          caption: block.text('caption').resolve(language),
          shape: block.option('shape'),
          height: block.option('height'),
          loadOnClick: block.toggle('loadOnClick'),
          allowFullscreen: block.toggle('allowFullscreen'),
          language: language,
          interactive: view.interactive,
          onOpen: (target) => followBlockLink(context, target),
          style: EmbedStyle(
            body: look.bodyStyle,
            muted: look.bodyStyle.copyWith(fontSize: 13, color: look.text),
            accent: look.button,
            line: look.design.colorOf('line'),
            panel: look.design.colorOf('sageLight'),
          ),
        ),
      // Drawn as text from sanitized markup ([CustomHtml]); never as HTML.
      'html' => _aligned(
          look,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PublicCustomHtml(
              key: Key('public-html-${block.id}'),
              source: block.text('html').en,
              bodyStyle: look.bodyStyle,
              headingStyle: look.headingStyle,
              linkColor: look.button,
              ruleColor: look.design.colorOf('line'),
              textAlign: look.textAlign,
              interactive: view.interactive,
            ),
          ),
        ),
      _ => const SizedBox.shrink(),
    };
    // A notice draws its own box; a call to action and an asymmetric
    // gallery their own background.
    final own = block.type == 'cta' || block.type == 'notice' || block.type == 'asymmetric_gallery';
    final background = own ? null : backgroundOf(block, look.design);
    final border = own ? null : _border(look.design);
    if (background == null && border == null) {
      // No surface: the block's own padding (if any) around its content.
      final padding = own ? const SpacingSides() : _spacing(BlockSpacing.padding, layout);
      if (padding.isAutomatic) return content;
      final p = padding.over();
      return FitPadding(key: Key('public-block-${block.id}-padding'), padding: EdgeInsets.fromLTRB(p.left, p.top, p.right, p.bottom), child: content);
    }
    return _surface(
      layout,
      automatic: EdgeInsets.all(layout.isMobile ? 20 : 32),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20), border: border),
      child: content,
    );
  }

  Widget _image(PublicStrings strings, _Look look) {
    final image = view.media[block.string('mediaId')]!;
    final alt = block.text('alt').resolve(language);
    final caption = block.text('caption').resolve(language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PublicWebsiteImage(
          media: image,
          aspectRatio: _aspect(block.string('aspect')) ?? image.aspectRatio,
          semanticLabel: alt.isNotEmpty ? alt : image.alt.resolve(language),
          errorLabel: strings.imageUnavailable,
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(caption, style: PublicText.body.copyWith(fontSize: 14, color: look.caption)),
        ],
      ],
    );
  }

  Widget _gallery(BuildContext context, PublicStrings strings, PublicLayout layout, _Look look) {
    final heading = block.text('heading').resolve(language);
    // The chosen images that exist, in their order, up to the limit.
    final limit = int.tryParse(block.option('limit'));
    final shown = [
      for (final item in block.items('images'))
        if (view.media[item.string('mediaId')] case final media?) (item: item, media: media),
    ].take(limit ?? CustomPage.maxGridImages).toList();
    final images = [for (final s in shown) s.media];
    final desktop = int.parse(block.option('columns'));
    final perRow = switch (layout) {
      PublicLayout.mobile => int.parse(block.option('mobileColumns')),
      PublicLayout.tablet => int.tryParse(block.option('tabletColumns')) ?? desktop,
      PublicLayout.desktop => desktop,
    };
    final aspect = _aspect(block.option('aspect')) ?? 4 / 3;
    final showCaptions = block.toggle('showCaptions');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: look.headingStyle), const SizedBox(height: 20)],
        LayoutBuilder(builder: (context, constraints) {
          final gap = layout.isMobile ? 12.0 : 20.0;
          final width = PublicLayout.tileWidth(constraints.maxWidth, perRow, gap);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < shown.length; i++)
                Builder(builder: (context) {
                  final item = shown[i].item;
                  final media = shown[i].media;
                  // The image's own caption, else the library's.
                  final own = item.text('caption').resolve(language);
                  final caption = own.isNotEmpty ? own : media.caption.resolve(language);
                  final target = item.string('target').trim();
                  final link = target.isNotEmpty && SafeLinkTarget.validate(target) == null;
                  return SizedBox(
                    key: Key('public-gallery-item-${item.id}'),
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          button: view.interactive,
                          link: link,
                          label: media.alt.resolve(language),
                          excludeSemantics: true,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              // A linked image follows its link; others open larger.
                              onTap: !view.interactive ? null : () => link ? followBlockLink(context, target) : showPublicGalleryLightbox(context, images, i),
                              child: PublicWebsiteImage(
                                media: media,
                                aspectRatio: aspect,
                                borderRadius: 16,
                                semanticLabel: media.alt.resolve(language),
                                errorLabel: strings.imageUnavailable,
                                placeholder: const PublicImagePlaceholder(compact: true),
                              ),
                            ),
                          ),
                        ),
                        if (showCaptions && caption.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: PublicText.body.copyWith(fontSize: 14, color: look.caption)),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          );
        }),
      ],
    );
  }

  /// The blocks of column [c] of this container, as visitors (or the
  /// editor) see them, [gap] apart.
  List<Widget> _columnChildren(BuildContext context, BlockColumn c, int column, double Function(WebsiteBlock child) gap) {
    final editing = view.editing;
    final items = <Widget>[];
    for (final (j, child) in c.blocks.indexed) {
      final rendered = _BlockWidget.maybe(child, view);
      final widget = editing != null ? editing.frame(context, block, column, j, child, rendered) : rendered;
      if (widget == null) continue;
      if (items.isNotEmpty) items.add(SizedBox(height: gap(child)));
      items.add(widget);
    }
    if (editing != null) items.add(editing.columnEnd(context, block, column));
    return items;
  }

  /// Style gap [key] (`columnGap`, `rowGap`) in px, or [fallback].
  double _gap(String key, double fallback) => BlockStyle.gaps.contains(block.style[key]) ? double.parse(block.style[key] as String) : fallback;

  /// [children] (one widget per column) side by side from tablet width
  /// (relative widths from the layout); stacked on mobile. Four columns
  /// make two rows of two on tablets. Column and row gaps come from the
  /// block's style (else 40 between columns and [stackGap] between rows).
  Widget _columnsLayout(PublicLayout layout, List<Widget> children, {required CrossAxisAlignment cross, double stackGap = 24}) {
    final widths = columnLayouts[block.string('layout')] ?? const [1, 1];
    final columnGap = _gap('columnGap', 40);
    final rowGap = _gap('rowGap', stackGap);
    if (layout.isMobile || children.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final (i, c) in children.indexed) ...[if (i > 0) SizedBox(height: rowGap), c]],
      );
    }
    Widget row(List<Widget> cells, List<int> flexes) => Row(
          crossAxisAlignment: cross,
          children: [
            for (final (i, c) in cells.indexed) ...[
              if (i > 0) SizedBox(width: columnGap),
              Expanded(flex: i < flexes.length ? flexes[i] : 1, child: c),
            ],
          ],
        );
    if (layout == PublicLayout.tablet && children.length > 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i += 2) ...[
            if (i > 0) SizedBox(height: rowGap),
            row([children[i], if (i + 1 < children.length) children[i + 1] else const SizedBox.shrink()], const [1, 1]),
          ],
        ],
      );
    }
    return row(children, widths);
  }

  /// Items per row on this screen size from the block's per-row settings
  /// (`desktopColumns`, `tabletColumns`, `mobileColumns`), or null for
  /// the block's automatic layout (as before these settings existed).
  int? _perRow(PublicLayout layout) {
    int? n(String key) => int.tryParse(block.option(key));
    return switch (layout) {
      PublicLayout.mobile => n('mobileColumns'),
      PublicLayout.tablet => n('tabletColumns') ?? n('desktopColumns'),
      PublicLayout.desktop => n('desktopColumns'),
    };
  }

  /// [items] in rows of [perRow], [gap] apart; the last row keeps the
  /// same widths. [stretch]: the items of a row share its height.
  static Widget perRowGrid(List<Widget> items, int perRow, {double gap = 24, double rowGap = 24, bool stretch = false}) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += perRow) {
      final cells = [for (var j = i; j < i + perRow; j++) j < items.length ? items[j] : const SizedBox.shrink()];
      final row = Row(
        crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: [for (final (k, c) in cells.indexed) ...[if (k > 0) SizedBox(width: gap), Expanded(child: c)]],
      );
      if (rows.isNotEmpty) rows.add(SizedBox(height: rowGap));
      rows.add(stretch ? IntrinsicHeight(child: row) : row);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// [child] with this container's own colours and alignment passed down
  /// (or, where it sets none, those it inherited).
  Widget _withLook(BuildContext context, Widget child, _Look look) {
    final inherited = _InheritedLook.of(context);
    Color? own(String key) => look.design.resolve(block.style[key]);
    return _InheritedLook(
      text: own('textColor') ?? inherited?.text,
      heading: own('headingColor') ?? inherited?.heading,
      button: own('buttonColor') ?? inherited?.button,
      buttonText: own('buttonTextColor') ?? inherited?.buttonText,
      align: block.style['align'] is String ? block.style['align'] as String : inherited?.align,
      child: child,
    );
  }

  /// Side by side from tablet width (relative widths from the layout);
  /// stacked on mobile. Each column's blocks are checked like any other.
  Widget _columns(BuildContext context, PublicLayout layout, _Look look) {
    final cols = block.columns('columns');
    final children = [
      for (final (i, c) in cols.indexed)
        Column(
          key: Key('public-block-column-${c.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _columnChildren(context, c, i, (_) => 24),
        ),
    ];
    return _withLook(context, _columnsLayout(layout, children, cross: CrossAxisAlignment.center), look);
  }

  /// A band of the page: its background (edge to edge on a full-width
  /// page), padding and border, then its columns at its content width.
  Widget _section(BuildContext context, PublicLayout layout, _Look look) {
    final design = look.design;
    final mobile = layout.isMobile;
    final cols = block.columns('columns');
    final children = [
      for (final (i, c) in cols.indexed)
        Column(
          key: Key('public-block-column-${c.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _columnChildren(context, c, i, (child) => WebsiteBlocksView.spaceInside(child, mobile: mobile, screen: screenOf(layout))),
        ),
    ];
    final padding = paddingOf(block, 'padding', mobile: mobile, fallback: 48);
    final top = block.style.containsKey('paddingTop') ? paddingOf(block, 'paddingTop', mobile: mobile, fallback: padding) : padding;
    final bottom = block.style.containsKey('paddingBottom') ? paddingOf(block, 'paddingBottom', mobile: mobile, fallback: padding) : padding;
    final background = backgroundOf(block, design);
    final borderColor = design.resolve(block.style['borderColor']);
    final borderWidth = double.tryParse(block.style['borderWidth']?.toString() ?? '') ?? (borderColor == null ? 0 : 1);
    final columns = _columnsLayout(layout, children, cross: CrossAxisAlignment.start, stackGap: mobile ? 24 : 32);
    final header = _sectionHeader(look, mobile: mobile);
    final hasColumns = children.any((c) => c.children.isNotEmpty);
    final inner = _withLook(
      context,
      header == null
          ? columns
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, if (hasColumns) ...[SizedBox(height: mobile ? 24 : 32), columns]],
            ),
      look,
    );
    if (view.fullBleed) {
      final side = borderColor == null || borderWidth <= 0 ? BorderSide.none : BorderSide(color: borderColor, width: borderWidth);
      return _surface(
        layout,
        key: Key('public-section-${block.id}'),
        width: double.infinity,
        decoration: BoxDecoration(color: background, border: Border(top: side, bottom: side)),
        automatic: EdgeInsets.only(top: top, bottom: bottom),
        child: PublicContentWidth(maxWidth: view.contentWidthOf(block), child: inner),
      );
    }
    final across = background == null && borderColor == null ? 0.0 : (mobile ? 20.0 : 32.0);
    return _surface(
      layout,
      key: Key('public-section-${block.id}'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: borderColor == null || borderWidth <= 0 ? null : Border.all(color: borderColor, width: borderWidth),
      ),
      automatic: EdgeInsets.fromLTRB(across, top, across, bottom),
      child: inner,
    );
  }

  /// A section's small heading, heading and description (each optional,
  /// placed by the section's alignment), or null when it has none.
  Widget? _sectionHeader(_Look look, {required bool mobile}) {
    final eyebrow = block.text('eyebrow').resolve(language).trim();
    final heading = block.text('heading').resolve(language).trim();
    final description = block.text('description').resolve(language).trim();
    if (eyebrow.isEmpty && heading.isEmpty && description.isEmpty) return null;
    final parts = <Widget>[
      if (eyebrow.isNotEmpty) Text(eyebrow, key: Key('public-section-${block.id}-eyebrow'), style: look.eyebrowStyle, textAlign: look.textAlign),
      if (heading.isNotEmpty)
        Semantics(header: true, child: Text(heading, key: Key('public-section-${block.id}-heading'), style: look.headingStyle, textAlign: look.textAlign)),
      if (description.isNotEmpty) KeyedSubtree(key: Key('public-section-${block.id}-description'), child: _paragraphs(description, look)),
    ];
    return Column(
      key: Key('public-section-${block.id}-header'),
      crossAxisAlignment: look.cross,
      children: [for (final (i, p) in parts.indexed) ...[if (i > 0) const SizedBox(height: 12), p]],
    );
  }

  /// A large heading and introduction beside a photograph (or decorative
  /// shapes); on mobile the photograph, if any, goes below.
  Widget _hero(PublicStrings strings, PublicLayout layout, _Look look) {
    final image = view.media[block.string('mediaId')];
    final eyebrow = block.text('eyebrow').resolve(language);
    final body = block.text('body').resolve(language);
    final buttons = _buttons(block.items('buttons'), look);
    final text = Column(
      crossAxisAlignment: look.cross,
      children: [
        if (eyebrow.isNotEmpty) ...[Text(eyebrow, style: look.eyebrowStyle, textAlign: look.textAlign), const SizedBox(height: 16)],
        Text(
          block.text('heading').resolve(language),
          key: const Key('public-hero-title'),
          textAlign: look.textAlign,
          style: look.displayStyle(mobile: layout.isMobile),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(body, key: const Key('public-hero-body'), textAlign: look.textAlign, style: PublicText.body.copyWith(fontSize: 17, color: look.text)),
          ),
        ],
        if (buttons != null) ...[const SizedBox(height: 28), buttons],
      ],
    );
    final decor = block.flag('decor');
    Widget? visual(double aspectRatio) => image != null
        ? PublicWebsiteImage(
            key: const Key('public-hero-image'),
            media: image,
            aspectRatio: aspectRatio,
            borderRadius: 32,
            semanticLabel: image.alt.resolve(language),
            errorLabel: strings.imageUnavailable,
            placeholder: const PublicImagePlaceholder(),
          )
        : decor
            ? const PublicHeroOrnament(key: Key('public-hero-ornament'))
            : null;
    if (layout.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [text, if (image != null) ...[const SizedBox(height: 32), visual(4 / 3)!]],
      );
    }
    final side = visual(1);
    if (side == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [Expanded(flex: 3, child: text), const SizedBox(width: 48), Expanded(flex: 2, child: side)],
    );
  }

  /// A heading and linked cards side by side (stacked on mobile).
  Widget _cards(PublicLayout layout, _Look look) {
    final heading = block.text('heading').resolve(language);
    final cards = [
      for (final item in block.items('cards'))
        Builder(builder: (context) {
          final target = item.string('target').trim();
          final safe = target.isNotEmpty && SafeLinkTarget.validate(target) == null;
          final title = item.text('title').resolve(language);
          // Only a published image: a banner across the top of the card,
          // half as tall as it is wide, covered (centred on its focal
          // point; never stretched). Its alt text is read; without one it is
          // decorative (the title is read once, from the card).
          final image = view.media[item.string('imageMediaId')];
          final alt = image?.alt.resolve(language) ?? '';
          return PublicPathwayCard(
            key: Key('public-card-${item.id}'),
            image: image == null
                ? null
                : ExcludeSemantics(
                    excluding: alt.isEmpty,
                    child: PublicWebsiteImage(
                      key: Key('public-card-${item.id}-image'),
                      media: image,
                      aspectRatio: 2,
                      fit: BoxFit.cover,
                      borderRadius: 0,
                      semanticLabel: alt,
                      errorLabel: PublicStrings.of(language).imageUnavailable,
                    ),
                  ),
            icon: item.string('icon') == 'none' ? null : blockIconData(item.string('icon')),
            title: title,
            body: item.text('body').resolve(language),
            cta: safe ? item.text('linkLabel').resolve(language) : '',
            route: '',
            accent: item.string('accent') == 'secondary' ? look.design.colorOf('gold') : look.design.colorOf('forest'),
            enabled: view.interactive && safe,
            onTap: () => followBlockLink(context, target),
            titleColor: look.heading,
            bodyColor: look.text,
          );
        }),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: look.headingStyle), const SizedBox(height: 24)],
        if (_perRow(layout) case final perRow?)
          perRowGrid(cards, perRow, gap: 24, rowGap: layout.isMobile ? 16 : 24, stretch: true)
        else if (layout.isMobile)
          Column(children: [for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(height: 16), c]])
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 24), Expanded(child: c)]],
            ),
          ),
      ],
    );
  }

  /// A heading, an introduction, then the accreditations: certificate
  /// cards (3, 2 and 1 per row unless set) or a wrapping strip of logos.
  Widget _accreditations(BuildContext context, PublicLayout layout, _Look look) {
    final heading = block.text('heading').resolve(language);
    final intro = block.text('intro').resolve(language);
    final style = AccreditationStyle(
      title: look.bodyStyle.copyWith(color: look.heading, fontSize: (look.bodyStyle.fontSize ?? 16) + 2, fontWeight: FontWeight.w700),
      body: look.bodyStyle,
      muted: look.bodyStyle.copyWith(fontSize: 13, color: look.text),
      accent: look.button,
      line: look.design.colorOf('line'),
      badge: look.design.colorOf('sageLight'),
    );
    final items = [for (final item in block.items('items')) AccreditationView.of(item, view.media, language, design: look.design)];
    // The details are on a neutral surface, whatever the section's colours.
    final details = AccreditationStyle(
      title: PublicText.body.copyWith(color: look.design.colorOf('forestDark'), fontSize: 18, fontWeight: FontWeight.w700),
      body: PublicText.body.copyWith(color: look.design.colorOf('ink')),
      muted: PublicText.body.copyWith(color: look.design.colorOf('muted'), fontSize: 13),
      accent: look.design.colorOf('forest'),
      line: look.design.colorOf('line'),
      badge: look.design.colorOf('sageLight'),
    );
    final accreditationLayout = AccreditationLayout.of(block);
    void open(String target) => followBlockLink(context, target);
    final Widget body;
    if (block.option('display') == 'logos') {
      body = Wrap(
        key: Key('public-accreditations-${block.id}-logos'),
        alignment: look.wrap,
        spacing: layout.isMobile ? 16 : 32,
        runSpacing: 24,
        crossAxisAlignment: accreditationLayout.centred ? WrapCrossAlignment.center : WrapCrossAlignment.start,
        children: [for (final i in items) PublicAccreditationLogo(item: i, style: style, language: language, interactive: view.interactive, onOpen: open, layout: accreditationLayout, detailsStyle: details)],
      );
    } else {
      final perRow = _perRow(layout) ?? switch (layout) { PublicLayout.mobile => 1, PublicLayout.tablet => 2, PublicLayout.desktop => 3 };
      body = KeyedSubtree(
        key: Key('public-accreditations-${block.id}-cards'),
        child: perRowGrid(
          [for (final i in items) PublicAccreditationCard(item: i, style: style, language: language, interactive: view.interactive, onOpen: open, layout: accreditationLayout, detailsStyle: details)],
          perRow,
          gap: 24,
          rowGap: layout.isMobile ? 16 : 24,
          // Centred content: the cards in a row share its height.
          stretch: accreditationLayout.centred,
        ),
      );
    }
    return Column(
      crossAxisAlignment: look.cross,
      children: [
        if (heading.isNotEmpty) ...[Text(heading, style: look.headingStyle, textAlign: look.textAlign), const SizedBox(height: 12)],
        if (intro.isNotEmpty) ...[ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(intro, style: look.bodyStyle, textAlign: look.textAlign)), const SizedBox(height: 12)],
        if (heading.isNotEmpty || intro.isNotEmpty) const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: body),
      ],
    );
  }

  /// A heading and points with icons in a row (stacked on mobile).
  Widget _features(PublicLayout layout, _Look look) {
    final eyebrow = block.text('eyebrow').resolve(language);
    final heading = block.text('heading').resolve(language);
    final items = [
      for (final item in block.items('items'))
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(blockIconData(item.string('icon')), color: look.design.colorOf('sage'), size: 28),
            const SizedBox(height: 12),
            Text(item.text('title').resolve(language), style: look.titleStyle),
            if (item.text('body').resolve(language) case final body when body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: PublicText.body.copyWith(color: look.text)),
            ],
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty) ...[Text(eyebrow, style: look.eyebrowStyle), const SizedBox(height: 12)],
        if (heading.isNotEmpty) ...[Text(heading, style: look.headingStyle), const SizedBox(height: 32)],
        if (_perRow(layout) case final perRow?)
          perRowGrid(items, perRow, gap: 32, rowGap: 28)
        else if (layout.isMobile)
          Column(children: [for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 28), child: item)])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final (i, item) in items.indexed) ...[if (i > 0) const SizedBox(width: 32), Expanded(child: item)]],
          ),
      ],
    );
  }

  /// A page's title, introduction and banner (or decorative placeholder).
  Widget _pageHeader(PublicStrings strings, PublicLayout layout, _Look look) {
    final image = view.media[block.string('mediaId')];
    final intro = block.text('intro').resolve(language);
    final banner = image != null || block.flag('placeholder');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(block.text('heading').resolve(language),
            key: const Key('public-section-title'), style: look.displayStyle(mobile: layout.isMobile)),
        if (intro.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(intro, key: const Key('public-section-intro'), style: PublicText.body.copyWith(fontSize: 17, color: look.text)),
        ],
        if (banner) ...[
          const SizedBox(height: 32),
          PublicWebsiteImage(
            key: Key(image == null ? 'public-section-placeholder' : 'public-section-image'),
            media: image,
            aspectRatio: 16 / 9,
            semanticLabel: image?.alt.resolve(language) ?? '',
            errorLabel: strings.imageUnavailable,
          ),
        ],
      ],
    );
  }

  /// The editor's preview of the School gallery block: the published
  /// gallery photographs it has (the live block loads them itself).
  Widget _galleryFeedPreview(PublicStrings strings, PublicLayout layout) {
    final images = [for (final m in view.media.values) if (m.inGallery) m]..sort((a, b) => a.galleryOrder.compareTo(b.galleryOrder));
    final perRow = switch (layout) { PublicLayout.mobile => 2, PublicLayout.tablet => 3, PublicLayout.desktop => 4 };
    if (images.isEmpty) {
      return Text(strings.galleryEmptyTitle, key: const Key('public-gallery-feed-preview'), style: PublicText.title);
    }
    return LayoutBuilder(
      key: const Key('public-gallery-feed-preview'),
      builder: (context, constraints) {
        final gap = layout.isMobile ? 12.0 : 20.0;
        final width = PublicLayout.tileWidth(constraints.maxWidth, perRow, gap);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in images.take(perRow * 2))
              SizedBox(
                width: width,
                child: PublicWebsiteImage(media: m, aspectRatio: 4 / 3, borderRadius: 16, semanticLabel: m.alt.resolve(language), placeholder: const PublicImagePlaceholder(compact: true)),
              ),
          ],
        );
      },
    );
  }
}
