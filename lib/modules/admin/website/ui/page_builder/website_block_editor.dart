import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/asymmetric_gallery.dart';
import '../../../../public_website/content/blocks/testimonials.dart';
import '../../../../public_website/content/blocks/block_ids.dart';
import '../../../../public_website/content/blocks/block_limits.dart';
import '../../../../public_website/content/blocks/block_spacing.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/custom_html.dart';
import '../../../../public_website/content/blocks/embed_providers.dart';
import '../../../../public_website/content/blocks/section_presets.dart';
import '../../../../public_website/content/blocks/field_spec.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_content_models.dart';
import '../../../../public_website/content/website_custom_page.dart';
import '../../../../public_website/content/website_design.dart';
import '../../../../public_website/public_website_theme.dart';
import '../../../../public_website/widgets/blocks/public_accreditations.dart';
import '../../../../public_website/widgets/blocks/public_custom_html.dart';
import '../../../../forms/models/website_form.dart';
import '../../../../forms/public/public_forms_repository.dart';
import '../website_content_editors.dart';
import '../website_content_screen.dart';
import 'block_list_ops.dart';
import 'website_color_field.dart';
import 'website_size_field.dart';
import 'website_spacing_field.dart';

/// What a page with no blocks shows: what to do first, and buttons for the
/// most used blocks (every type is also in the Add block menu). Keys start
/// with [addKey] (`<addKey>-empty`, `<addKey>-quick-<type>`).
class WebsiteBlocksEmptyState extends StatelessWidget {
  const WebsiteBlocksEmptyState({super.key, required this.addKey, required this.canAdd, required this.onAdd, this.sections = const [], this.onAddSection});

  final String addKey;
  final bool canAdd;
  final ValueChanged<BlockDefinition> onAdd;

  /// Ready-made sections offered first (`<addKey>-section-<id>`).
  final List<SectionPreset> sections;
  final ValueChanged<SectionPreset>? onAddSection;

  static final _quick = [
    (BlockRegistry.text, Icons.notes),
    (BlockRegistry.image, Icons.image_outlined),
    (BlockRegistry.columns, Icons.view_column_outlined),
    (BlockRegistry.cta, Icons.campaign_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('$addKey-empty'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This page has no content yet', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Start with a ready-made section, or add your first block. You can add text, images, columns, buttons and more, then reorder them at any time. Nothing is on the website until you publish.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (sections.isNotEmpty && onAddSection != null) ...[
            const Text('Sections', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in sections)
                  ActionChip(
                    key: Key('$addKey-section-${p.id}'),
                    avatar: const Icon(Icons.view_agenda_outlined, size: 16),
                    label: Text(p.label),
                    tooltip: p.description,
                    onPressed: canAdd ? () => onAddSection!(p) : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Blocks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (d, icon) in _quick)
                OutlinedButton.icon(
                  key: Key('$addKey-quick-${d.type}'),
                  onPressed: canAdd ? () => onAdd(d) : null,
                  icon: Icon(icon, size: 18),
                  label: Text(d.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short description of [block] for the page structure.
String blockSummary(WebsiteBlock block) {
  if (block is! StructuredBlock) return 'Kept unchanged; this version of the editor can’t show or edit it.';
  for (final key in ['heading', 'caption', 'body']) {
    final f = block.definition.field(key);
    if (f is TextFieldSpec && block.text(key).en.trim().isNotEmpty) {
      final t = block.text(key).en.trim();
      return t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }
  }
  return switch (block.type) {
    'image' => block.string('mediaId').isEmpty ? 'No image chosen' : 'Image',
    'columns' => '${block.columns('columns').length} columns (${block.string('layout')})',
    'buttons' => '${block.items('buttons').length} button(s)',
    'gallery' => '${block.items('images').length} image(s)',
    'asymmetric_gallery' =>
      '${block.items('images').length} image(s), ${AsymmetricGallery.arrangementLabels[AsymmetricGallery.settings(block, 'desktop').arrangement]!.toLowerCase()}',
    'map' => block.text('address').en.trim().isEmpty ? 'No address yet' : block.text('address').en.trim(),
    'accreditations' => '${block.items('items').length} accreditation(s)',
    'testimonials' => '${block.items('testimonials').length} testimonial(s)',
    'embed' => switch (EmbedSource.parse(block.text('source').en)) {
        final e when e.isValid => '${e.provider!.label}: ${block.text('title').en.trim().isEmpty ? 'no title yet' : block.text('title').en.trim()}',
        _ => 'Not a supported link yet',
      },
    'html' => switch (CustomHtml.plainText(block.text('html').en)) {
        '' => 'No HTML yet',
        final t => t.length > 60 ? '${t.substring(0, 60)}…' : t,
      },
    'divider' => 'Space: ${block.string('size')}',
    _ => '',
  };
}

/// An icon for a block type (unsupported blocks get a lock).
IconData blockIcon(WebsiteBlock block) => switch (block is StructuredBlock ? block.type : '') {
      'text' => Icons.notes,
      'image' => Icons.image_outlined,
      'columns' => Icons.view_column_outlined,
      'cta' => Icons.campaign_outlined,
      'buttons' => Icons.smart_button_outlined,
      'gallery' => Icons.photo_library_outlined,
      'asymmetric_gallery' => Icons.auto_awesome_mosaic_outlined,
      'gallery_feed' => Icons.collections_outlined,
      'map' => Icons.map_outlined,
      'divider' => Icons.horizontal_rule,
      'section' => Icons.view_agenda_outlined,
      'hero' => Icons.title,
      'cards' => Icons.dashboard_outlined,
      'features' => Icons.checklist,
      'page_header' => Icons.short_text,
      'notice' => Icons.info_outline,
      'events_feed' => Icons.event_outlined,
      'announcements_feed' => Icons.campaign_outlined,
      'form' => Icons.assignment_outlined,
      'accreditations' => Icons.workspace_premium_outlined,
      'testimonials' => Icons.format_quote_outlined,
      'html' => Icons.code,
      'embed' => Icons.smart_display_outlined,
      // Unsupported blocks (and any type without its own icon).
      _ => Icons.lock_outline,
    };

/// The properties form for one block, generated from its type's field
/// declarations ([BlockDefinition.fields]); there is no per-type editor.
/// English and Tamil are edited; text in other languages, and unknown
/// fields, are kept unchanged. Then its display options (background,
/// space above).
///
/// A columns block lists the blocks in each column; [onSelectNested]
/// selects one of them (column, position) to edit it. Text fields hold
/// their own text: their keys end with [generation], bumped when the
/// editor is refilled (load, discard, convert).
class WebsiteBlockForm extends StatelessWidget {
  const WebsiteBlockForm({
    super.key,
    required this.block,
    required this.library,
    required this.generation,
    required this.onChanged,
    this.onSelectNested,
    this.design = SiteDesign.defaults,
  });

  final StructuredBlock block;

  /// The whole media library (images can be chosen whatever their status;
  /// visitors only ever see published ones).
  final List<WebsiteMedia> library;
  final int generation;
  final ValueChanged<WebsiteBlock> onChanged;
  final void Function(int column, int position)? onSelectNested;

  /// The site design whose palette the colour settings offer.
  final SiteDesign design;

  @override
  Widget build(BuildContext context) {
    final prefix = 'website-block-${block.id}';
    final entries = <(FieldSpec, Widget)>[
      for (final field in block.definition.fields)
        // A setting of a feature that is off isn't offered (its value is kept).
        if (field.shownWhen?.call(block.values, block.values) ?? true)
        (
          field,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The accreditation layout settings, as one marked group (block
              // settings: they apply to every accreditation in the block).
              if (block.type == BlockRegistry.accreditations.type && field.key == 'imageAlign')
                Column(
                  key: Key('$prefix-layout-heading'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Divider(height: 20),
                    Text('Layout of each accreditation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Applies to every accreditation in this block, as cards or in the logo strip.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    SizedBox(height: 10),
                  ],
                ),
              if (block.type == BlockRegistry.accreditations.type && field.key == 'items') const Divider(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FieldEditor(
                  keyPrefix: '$prefix-${field.key}',
                  field: field,
                  value: block.values[field.key],
                  library: library,
                  generation: generation,
                  onChanged: (v) => onChanged(block.withValue(field.key, v)),
                  owner: block,
                  onBlockChanged: onChanged,
                  onSelectNested: onSelectNested,
                  design: design,
                ),
              ),
            ],
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...groupedFields(prefix, entries),
        if (block.type == BlockRegistry.html.type) _CustomHtmlNotes(block: block, design: design),
        if (block.type == BlockRegistry.embed.type) _EmbedNotes(block: block),
        if (block.type == BlockRegistry.accreditations.type) _AccreditationLinkNotes(block: block),
        if (block.type == AsymmetricGallery.type) _AsymmetricGalleryNotes(block: block, library: library),
        WebsiteStyleEditor(block: block, design: design, onChanged: onChanged),
      ],
    );
  }
}

/// Under an Embed block's source: what was recognised and the address
/// the frame will use (rebuilt, never the pasted one), what of pasted
/// code isn't used, and the supported providers.
class _EmbedNotes extends StatelessWidget {
  const _EmbedNotes({required this.block});

  final StructuredBlock block;

  @override
  Widget build(BuildContext context) {
    final source = block.text('source').en;
    final parsed = EmbedSource.parse(source);
    final prefix = 'website-block-${block.id}-embed';
    const small = TextStyle(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: Key('$prefix-info'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Supported: ${EmbedSource.supported}. Paste the link, or the provider’s <iframe> code: only its address is read, and the frame’s address is rebuilt from it. '
            'Scripts and other code in what you paste are never run, so embeds that need a script (for example social media posts) can’t be shown. '
            'On the website visitors click to load it unless you turn that off; the editor shows a placeholder.',
            style: small,
          ),
        ),
        if (source.trim().isNotEmpty)
          Container(
            key: Key(parsed.isValid ? '$prefix-recognised' : '$prefix-problem'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: parsed.isValid ? const Color(0xFFE6EDE2) : const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parsed.isValid) ...[
                  Text('Recognised: ${parsed.provider!.label}', style: small.copyWith(fontWeight: FontWeight.w600)),
                  SelectableText('Frame address: ${parsed.embedUrl}', style: small),
                ] else
                  Text(parsed.error!, style: small),
                if (parsed.ignored.isNotEmpty) Text('Not used from the pasted code: ${parsed.ignored.join(', ')}', style: small),
              ],
            ),
          ),
      ],
    );
  }
}

/// Under a Custom HTML block's source: what is supported, what of it
/// visitors won't see, and a preview drawn exactly as on the website.
class _CustomHtmlNotes extends StatelessWidget {
  const _CustomHtmlNotes({required this.block, required this.design});

  final StructuredBlock block;
  final SiteDesign design;

  @override
  Widget build(BuildContext context) {
    final source = block.text('html').en;
    final report = CustomHtml.report(source);
    final prefix = 'website-block-${block.id}-html';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: Key('$prefix-warning'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
          child: const Text(
            'JavaScript is not supported. Scripts, styles, forms, iframes, embeds and event handlers (onclick and similar) are removed before anything is shown. '
            'Supported: headings, paragraphs, bold, italic, lists, quotes, code, dividers, links to https://, mailto: or pages of this website, '
            'and images from https:// addresses (with their alt description, width and height; scaled to fit). Visitors’ browsers load those images from that address. '
            'For maps, forms, videos and phone links use their own blocks (Map, Form, Video embed, Buttons).',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (report.changesSomething)
          Container(
            key: Key('$prefix-removed'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visitors won’t see:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                if (report.removedElements.isNotEmpty)
                  Text('• Removed with their content: ${[for (final e in report.removedElements.entries) e.key == 'nested too deeply' ? 'markup nested too deeply' : '<${e.key}>${e.value > 1 ? ' ×${e.value}' : ''}'].join(', ')}', style: const TextStyle(fontSize: 12)),
                if (report.ignoredAttributes.isNotEmpty) Text('• Attributes not used: ${report.ignoredAttributes.join(', ')}', style: const TextStyle(fontSize: 12)),
                if (report.blockedLinks.isNotEmpty) Text('• Links not followed (their text still shows): ${report.blockedLinks.join(', ')}', style: const TextStyle(fontSize: 12)),
                if (report.blockedImages.isNotEmpty)
                  Text('• Image addresses never loaded (an image needs an https:// address): ${report.blockedImages.join(', ')}', style: const TextStyle(fontSize: 12)),
                if (report.imagesAsLinkText > 0)
                  Text('• Images: ${report.imagesAsLinkText} inside a link shown as its description (the link’s text), not as a picture', style: const TextStyle(fontSize: 12)),
                if (report.imagesNotShown > 0) Text('• Images not shown: ${report.imagesNotShown}', style: const TextStyle(fontSize: 12)),
                if (report.emptyLinks.isNotEmpty)
                  Text('• Links left out because nothing in them has text (give the image an alt description or the link a title): ${report.emptyLinks.join(', ')}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (report.imagesWithoutAlt > 0)
          Container(
            key: Key('$prefix-alt'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
            child: Text(
              '${report.imagesWithoutAlt == 1 ? 'An image has' : '${report.imagesWithoutAlt} images have'} no description: add alt="…" so screen readers can describe ${report.imagesWithoutAlt == 1 ? 'it' : 'them'}.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        Container(
          key: Key('$prefix-preview'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
          child: report.hasContent
              ? PublicCustomHtml(
                  source: source,
                  bodyStyle: PublicText.body.copyWith(color: design.colorOf('muted'), fontSize: 15),
                  headingStyle: PublicText.heading.copyWith(color: design.colorOf('forestDark'), fontSize: 22),
                  linkColor: design.colorOf('forest'),
                  ruleColor: design.colorOf('line'),
                  interactive: false,
                )
              : const Text('Nothing to show yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

/// Under an Accreditations block: the accreditations whose link visitors
/// won't get as Verify ([AccreditationView.verifiable]), such as an https
/// address without a domain name (`https://2`, which a browser opens as
/// 0.0.0.2). A note only: the block still saves and shows, without that
/// link. Key: `website-block-<id>-links`.
class _AccreditationLinkNotes extends StatelessWidget {
  const _AccreditationLinkNotes({required this.block});

  final StructuredBlock block;

  @override
  Widget build(BuildContext context) {
    final unused = [
      for (final (i, item) in block.items('items').indexed)
        if (item.string('target').trim() case final target when target.isNotEmpty && SafeLinkTarget.validate(target) == null && !AccreditationView.verifiable(target)) (i + 1, target),
    ];
    if (unused.isEmpty) return const SizedBox.shrink();
    return Container(
      key: Key('website-block-${block.id}-links'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify links visitors won’t see', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          for (final (n, target) in unused)
            Text('• Accreditation $n: $target is not a website address. Enter the full address, for example https://www.example.org/certificate/123.', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// A block's display options ([BlockDefinition.styleKeys]): colours from
/// the palette or custom, and choices. An option left unset is inherited
/// (from the section around the block, then the site design) and shown as
/// such; "Reset to default" / "Default" clears an option set here. Keys:
/// `website-block-<id>-style-<key>`.
class WebsiteStyleEditor extends StatelessWidget {
  const WebsiteStyleEditor({super.key, required this.block, required this.design, required this.onChanged});

  final StructuredBlock block;
  final SiteDesign design;
  final ValueChanged<WebsiteBlock> onChanged;

  static const labels = {
    'background': 'Background',
    'textColor': 'Text colour',
    'headingColor': 'Heading colour',
    'buttonColor': 'Button colour',
    'buttonTextColor': 'Button text colour',
    'borderColor': 'Border colour',
    'lineColor': 'Line colour',
    'spacing': 'Space above',
    'padding': 'Padding (top and bottom)',
    'paddingTop': 'Padding at the top',
    'paddingBottom': 'Padding at the bottom',
    'align': 'Alignment',
    'fontSize': 'Text size',
    'headingFontSize': 'Heading font size',
    'bodyFontSize': 'Body font size',
    'width': 'Content width',
    'borderWidth': 'Border width',
    'columnGap': 'Space between columns',
    'rowGap': 'Space between rows (when columns wrap or stack)',
  };

  static String optionLabel(String key, String option) => switch ((key, option)) {
        ('align', 'start') => 'Left',
        ('align', 'center') => 'Centre',
        ('align', 'end') => 'Right',
        ('width', 'narrow') => 'Narrow (760 px)',
        ('width', 'content') => 'Standard (960 px)',
        ('width', 'wide') => 'Wide (1160 px)',
        ('padding' || 'paddingTop' || 'paddingBottom' || 'borderWidth' || 'columnGap' || 'rowGap', _) => '$option px',
        _ => '${option[0].toUpperCase()}${option.substring(1)}',
      };

  /// What [key] shows without an override: the site typography (with
  /// this block's text size option); a hero's or page header's heading is
  /// a page title.
  double _inheritedSize(String key) {
    final scale = switch (block.style['fontSize']) { 'small' => 0.875, 'large' => 1.125, _ => 1.0 };
    if (key == 'bodyFontSize') return (design.bodySize * scale).roundToDouble();
    if (block.type == 'hero' || block.type == 'page_header') return design.titleSizeFor(mobile: false);
    return (design.headingSize * scale).roundToDouble();
  }

  /// The section keys its padding control replaces in this list (still
  /// drawn: they are what its Automatic is).
  static const _sectionPaddingKeys = {'padding', 'paddingTop', 'paddingBottom'};

  /// A section's top or bottom padding with no override on [screen], as
  /// it is drawn: its earlier padding setting, else 48 px; at most 48 on
  /// phones.
  int _sectionAutomatic(String screen, String side) {
    int px(Object? v, int fallback) => v is String ? int.tryParse(v) ?? fallback : fallback;
    final both = px(block.style['padding'], 48);
    final key = side == 'top' ? 'paddingTop' : 'paddingBottom';
    final value = block.style.containsKey(key) ? px(block.style[key], both) : both;
    return screen == 'mobile' && value > 48 ? 48 : value;
  }

  StructuredBlock _set(String key, Object? value) {
    final style = Map<String, dynamic>.of(block.style);
    value == null ? style.remove(key) : style[key] = value;
    return block.copyWith(style: style);
  }

  @override
  Widget build(BuildContext context) {
    final prefix = 'website-block-${block.id}-style';
    final legacy = <String, (String, Color?)>{
      'white': ('None (white)', null),
      'sage': ('Classic sage', design.colorOf('sageLight')),
      'gold': ('Classic gold', design.colorOf('goldLight')),
    };
    return Column(
      key: Key(prefix),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 2),
          child: Text('Design', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            block.type == 'section'
                ? 'Options left unset follow the site design. Colours set here apply to the blocks inside this section unless they set their own.'
                : 'Options left unset follow the section around this block, then the site design.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // A section's top and bottom padding first, for each screen size:
        // the same values as its Padding below (one setting, two views).
        if (block.type == 'section')
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: Key('$prefix-section-padding-group'),
                initiallyExpanded: true,
                title: const Text('Section padding (top and bottom)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(WebsiteSpacingField.summary(block.style[BlockSpacing.padding], sides: const ['top', 'bottom']),
                    key: Key('$prefix-section-padding-summary'), style: const TextStyle(fontSize: 12)),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                dense: true,
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                collapsedShape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WebsiteSpacingField(
                    fieldKey: '$prefix-section-padding',
                    kind: BlockSpacing.padding,
                    sides: const ['top', 'bottom'],
                    value: block.style[BlockSpacing.padding],
                    automaticOf: _sectionAutomatic,
                    description: 'The space inside the section’s background, above and below its content: 0 to 200 px for each screen size '
                        '(blank is Automatic: tablets follow desktop, phones the tablet). Automatic is the section’s earlier padding, or 48 px.',
                    onChanged: (v) => onChanged(_set(BlockSpacing.padding, v)),
                  ),
                ],
              ),
            ),
          ),
        for (final key in block.definition.styleKeys)
          if (block.type == 'section' && _sectionPaddingKeys.contains(key))
            const SizedBox.shrink()
          else if (BlockStyle.sizeKeys[key] case final range?)
            WebsiteSizeField(
              fieldKey: '$prefix-$key',
              label: labels[key] ?? key,
              range: range,
              value: range.allows(block.style[key]) ? (block.style[key] as num).toDouble() : null,
              inheritedValue: _inheritedSize(key),
              inheritedFrom: 'the site typography',
              onChanged: (v) => onChanged(_set(key, v?.round())),
            )
          else if (key == 'background' || BlockStyle.colorKeys.contains(key))
            WebsiteColorField(
              fieldKey: '$prefix-$key',
              label: labels[key] ?? key,
              value: block.style[key] is String ? block.style[key] as String : null,
              design: design,
              legacy: key == 'background' ? legacy : const {},
              inheritedLabel: key == 'background' || block.type == 'section' ? 'the page' : 'the section or site design',
              onChanged: (v) => onChanged(_set(key, v)),
            )
          else if (BlockStyle.optionsFor(key) case final options?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                key: Key('$prefix-$key'),
                initialValue: options.contains(block.style[key]) ? block.style[key] as String : '',
                isExpanded: true,
                decoration: websiteField(labels[key] ?? key),
                items: [
                  DropdownMenuItem(value: '', child: Text('Default (inherited)', key: Key('$prefix-$key-default'))),
                  for (final o in options) DropdownMenuItem(value: o, child: Text(optionLabel(key, o), key: Key('$prefix-$key-$o'))),
                ],
                onChanged: (v) => onChanged(_set(key, v == null || v.isEmpty ? null : v)),
              ),
            ),
        // Every block type, last in Design: its own padding and margin.
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 6),
          child: Text('Spacing', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        for (final kind in BlockSpacing.kinds)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: Key('$prefix-$kind-group'),
                title: Text(kind == BlockSpacing.padding ? 'Padding (inside the block)' : 'Margin (outside the block)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(WebsiteSpacingField.summary(block.style[kind]), key: Key('$prefix-$kind-group-summary'), style: const TextStyle(fontSize: 12)),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                dense: true,
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                collapsedShape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WebsiteSpacingField(fieldKey: '$prefix-$kind', kind: kind, value: block.style[kind], onChanged: (v) => onChanged(_set(kind, v))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Widget _choice(BuildContext context, String key, String label, List<String> options, String value, ValueChanged<String> onChanged, {Map<String, String> labels = const {}}) {
  return SizedBox(
    width: 220,
    child: DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      decoration: websiteField(label),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(labels[o] ?? o, key: Key('$key-$o')))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// One field's editor, chosen by its kind.
class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.keyPrefix,
    required this.field,
    required this.value,
    required this.library,
    required this.generation,
    required this.onChanged,
    this.owner,
    this.onBlockChanged,
    this.onSelectNested,
    this.design = SiteDesign.defaults,
  });

  final String keyPrefix;
  final FieldSpec field;

  /// The site design whose palette colour fields offer.
  final SiteDesign design;
  final Object? value;
  final List<WebsiteMedia> library;
  final int generation;
  final ValueChanged<Object?> onChanged;

  /// The block this field belongs to (for columns, which also change the
  /// layout); null inside items.
  final StructuredBlock? owner;
  final ValueChanged<WebsiteBlock>? onBlockChanged;

  /// Selects a block inside a column (column, position).
  final void Function(int column, int position)? onSelectNested;

  @override
  Widget build(BuildContext context) {
    final f = field;
    switch (f) {
      case TextFieldSpec():
        final text = value as LocalizedText? ?? const LocalizedText();
        Widget input(String lang, String label) => TextFormField(
              key: Key('$keyPrefix-$lang-$generation'),
              initialValue: text.textFor(lang),
              maxLength: f.maxLength,
              minLines: f.code && f.maxLength > 5000 ? 10 : (f.multiline ? 3 : 1),
              maxLines: f.code ? 24 : (f.multiline ? 8 : 1),
              style: f.code ? const TextStyle(fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'], fontSize: 13) : null,
              keyboardType: f.code ? TextInputType.multiline : null,
              decoration: websiteField(label, helper: lang == 'ta' ? 'If left blank, Tamil visitors see the English.' : null),
              // Only this language changes; every other is kept.
              onChanged: (v) => onChanged((value as LocalizedText? ?? const LocalizedText()).withText(lang, v)),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Source code is the same in every language.
            input('en', f.code ? f.label : '${f.label} (English)${f.required ? '' : ', optional'}'),
            if (multilingualEditing) ...[const SizedBox(height: 6), input('ta', '${f.label} (Tamil)')],
          ],
        );
      case MediaFieldSpec():
        final id = value as String? ?? '';
        WebsiteMedia? media;
        for (final m in library) {
          if (m.id == id) media = m;
        }
        final row = Row(
          children: [
            WebsiteMediaThumb(media: media, size: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                id.isEmpty
                    ? 'No image chosen.'
                    : media == null
                        ? 'This image no longer exists.'
                        : media.isPublished
                            ? (media.alt.en.isNotEmpty ? media.alt.en : 'No alt text yet')
                            : 'Not published — visitors won’t see it until it is published in the Media library.',
                key: Key('$keyPrefix-status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: media != null && !media.isPublished ? const Color(0xFF8A6A33) : null),
              ),
            ),
            TextButton(
              key: Key('$keyPrefix-choose'),
              onPressed: () async {
                final chosen = await showWebsiteImagePicker(context, library, selected: id.isEmpty ? null : id);
                if (chosen != null) onChanged(chosen);
              },
              child: Text(id.isEmpty ? 'Choose' : 'Change'),
            ),
            if (f.removable && id.isNotEmpty) TextButton(key: Key('$keyPrefix-remove'), onPressed: () => onChanged(''), child: const Text('Remove')),
          ],
        );
        if (!f.removable) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(f.label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)), const SizedBox(height: 4), row],
        );
      case LinkFieldSpec():
        final target = value as String? ?? '';
        return TextFormField(
          key: Key('$keyPrefix-$generation'),
          initialValue: target,
          decoration: websiteField(f.label, helper: 'A page of this website (/admissions, /pages/open-day), an https:// link to another site, mailto: or tel:.')
              .copyWith(errorText: target.trim().isEmpty ? null : SafeLinkTarget.validate(target.trim())),
          onChanged: onChanged,
        );
      case ChoiceFieldSpec():
        // A container's layout sets its columns too.
        if (owner != null && containerTypes.contains(owner!.type) && f.key == 'layout') {
          return _LayoutChoice(keyPrefix: keyPrefix, field: f, block: owner!, onChanged: onBlockChanged!);
        }
        return _choice(context, keyPrefix, f.label, f.options, value as String? ?? f.initial, onChanged, labels: f.optionLabels);
      case FormRefFieldSpec():
        return _FormChoice(keyPrefix: keyPrefix, label: f.label, value: value as String? ?? '', onChanged: onChanged);
      case NumberFieldSpec():
        return _NumberField(key: ValueKey('$keyPrefix-$generation'), fieldKey: keyPrefix, field: f, value: value as int?, onChanged: onChanged);
      case ToggleFieldSpec():
        return SwitchListTile(key: Key(keyPrefix), contentPadding: EdgeInsets.zero, title: Text(f.label), value: value as bool? ?? f.initial, onChanged: onChanged);
      case ItemsFieldSpec():
        return _ItemsEditor(
          keyPrefix: keyPrefix,
          field: f,
          items: value as List<BlockItem>? ?? const [],
          library: library,
          generation: generation,
          onChanged: onChanged,
          design: design,
          blockValues: owner?.values ?? const {},
          itemPreview: owner?.type == Testimonials.type ? (item) => _TestimonialPreview(keyPrefix: '$keyPrefix-item-${item.id}', item: item, block: owner!, library: library) : null,
        );
      case ColorFieldSpec():
        // Automatic is "unset" in the picker (its Reset to default).
        final v = value as String? ?? ColorFieldSpec.automatic;
        return WebsiteColorField(
          fieldKey: keyPrefix,
          label: f.label,
          value: v == ColorFieldSpec.automatic ? null : v,
          design: design,
          inheritedLabel: f.automaticLabel,
          legacy: {
            ColorFieldSpec.transparent: ('Transparent (shows the section behind)', null),
            for (final p in f.presets.entries) p.key: (p.value, design.resolve(p.key)),
          },
          onChanged: (c) => onChanged(c ?? ColorFieldSpec.automatic),
        );
      case ColumnsFieldSpec():
        // The blocks in each column are added, arranged and removed in the
        // page structure; here they are listed to be selected and edited,
        // and the columns themselves added, moved and removed.
        return _ColumnsEditor(
          keyPrefix: keyPrefix,
          block: owner!,
          onChanged: onBlockChanged!,
          onSelectNested: onSelectNested,
        );
    }
  }
}

/// The items of an items field (buttons, gallery images): add, edit, move
/// and remove, each with a fresh id when added.
class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.keyPrefix,
    required this.field,
    required this.items,
    required this.library,
    required this.generation,
    required this.onChanged,
    this.design = SiteDesign.defaults,
    this.blockValues = const {},
    this.itemPreview,
  });

  final String keyPrefix;
  final SiteDesign design;

  /// The values of the block the items are in (for [FieldSpec.shownWhen]).
  final Map<String, Object?> blockValues;

  /// Shown under an item's title (a testimonial's avatar and rating).
  final Widget Function(BlockItem item)? itemPreview;
  final ItemsFieldSpec field;
  final List<BlockItem> items;
  final List<WebsiteMedia> library;
  final int generation;
  final ValueChanged<Object?> onChanged;

  /// The image of an image list's items (a gallery's), if it is one.
  MediaFieldSpec? get _imageField => field.itemFields.isNotEmpty && field.itemFields.first is MediaFieldSpec ? field.itemFields.first as MediaFieldSpec : null;

  /// [items] without untouched empty ones (every field still its default).
  List<BlockItem> get _filled => [
        for (final item in items)
          if (field.itemFields.any((f) => jsonEncode(f.serialize(item.values[f.key] ?? f.defaultValue)) != jsonEncode(f.serialize(f.defaultValue)))) item,
      ];

  void _move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= items.length) return;
    final list = [...items];
    final item = list.removeAt(i);
    list.insert(to, item);
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(field.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        for (final (i, item) in items.indexed)
          Container(
            key: Key('$keyPrefix-item-${item.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${field.itemLabel} ${i + 1}', style: const TextStyle(fontSize: 13)),
                          if (field.badge?.call(items, i) case final badge?)
                            Container(
                              key: Key('$keyPrefix-item-${item.id}-badge'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
                              child: Text(badge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(key: Key('$keyPrefix-item-${item.id}-up'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward, size: 18)),
                    IconButton(key: Key('$keyPrefix-item-${item.id}-down'), tooltip: 'Move down', onPressed: i == items.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward, size: 18)),
                    IconButton(
                      key: Key('$keyPrefix-item-${item.id}-remove'),
                      tooltip: 'Remove',
                      onPressed: items.length <= field.minItems ? null : () => onChanged([...items]..removeAt(i)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                if (itemPreview?.call(item) case final preview?) Padding(padding: const EdgeInsets.only(bottom: 8, right: 6), child: preview),
                ...groupedFields('$keyPrefix-item-${item.id}', [
                  for (final f in field.itemFields)
                    if (f.shownWhen?.call(item.values, blockValues) ?? true)
                    (
                      f,
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, right: 6),
                        child: _FieldEditor(
                          keyPrefix: '$keyPrefix-item-${item.id}-${f.key}',
                          field: f,
                          value: item.values[f.key],
                          library: library,
                          generation: generation,
                          onChanged: (v) => onChanged([
                            for (final (j, other) in items.indexed)
                              if (j == i)
                                item.withValue(f.key, v)
                              // One item only (the feature image): on here, off in the others.
                              else if (f is ToggleFieldSpec && f.exclusive && v == true && other.values[f.key] == true)
                                other.withValue(f.key, false)
                              else
                                other,
                          ]),
                          design: design,
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            children: [
              // Images: choose several from the media library at once.
              if (_imageField case final media?)
                TextButton.icon(
                  key: Key('$keyPrefix-add-images'),
                  onPressed: _filled.length >= field.maxItems
                      ? null
                      : () async {
                          // Untouched empty slots (a new gallery starts with
                          // one) are filled first rather than left behind.
                          final kept = _filled;
                          final room = field.maxItems - kept.length;
                          final chosen = await showWebsiteImagesPicker(context, library, already: {for (final i in kept) i.string(media.key)}, max: room);
                          if (chosen == null || chosen.isEmpty) return;
                          onChanged([
                            ...kept,
                            for (final id in chosen.take(room))
                              BlockItem(id: BlockIds.item(), values: {for (final f in field.itemFields) f.key: f.key == media.key ? id : f.newValue}),
                          ]);
                        },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(_filled.length >= field.maxItems ? 'At most ${field.maxItems}' : 'Add images'),
                )
              else
                TextButton.icon(
                  key: Key('$keyPrefix-add'),
                  onPressed: items.length >= field.maxItems
                      ? null
                      : () => onChanged([...items, BlockItem(id: BlockIds.item(), values: {for (final f in field.itemFields) f.key: f.newValue})]),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(items.length >= field.maxItems ? 'At most ${field.maxItems}' : 'Add ${field.itemLabel.toLowerCase()}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Chooses the Form block's form among the active ones. A form chosen
/// earlier that is no longer active stays chosen, marked as such: visitors
/// don't see the block until it is active again.
class _FormChoice extends ConsumerWidget {
  const _FormChoice({required this.keyPrefix, required this.label, required this.value, required this.onChanged});

  final String keyPrefix;
  final String label;
  final String value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forms = ref.watch(activeWebsiteFormsProvider);
    return forms.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Row(
        children: [
          const Expanded(child: Text('The active forms couldn’t be loaded.', style: TextStyle(fontSize: 13))),
          TextButton(key: Key('$keyPrefix-retry'), onPressed: () => ref.invalidate(activeWebsiteFormsProvider), child: const Text('Try again')),
        ],
      ),
      data: (forms) {
        final active = value.isEmpty || forms.any((f) => f.id == value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: Key(keyPrefix),
              isExpanded: true,
              initialValue: value.isEmpty ? null : value,
              decoration: websiteField(label, helper: forms.isEmpty ? 'No form is active yet. Create and activate one in Settings → Website forms.' : null),
              items: [
                for (final PublicWebsiteForm f in forms) DropdownMenuItem(value: f.id, child: Text(f.title.en, overflow: TextOverflow.ellipsis)),
                if (!active) DropdownMenuItem(value: value, child: const Text('A form that isn’t active', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => onChanged(v ?? ''),
            ),
            if (!active)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This form isn’t active, so visitors don’t see this block. Activate it, or choose another.',
                  key: Key('$keyPrefix-inactive'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A33)),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _blocksCount(int n) => '$n block${n == 1 ? '' : 's'}';

/// A section's or columns block's layout. A layout with fewer columns
/// that would remove columns holding blocks first asks to move those
/// blocks into the last column kept; cancelled, the choice goes back.
class _LayoutChoice extends StatefulWidget {
  const _LayoutChoice({required this.keyPrefix, required this.field, required this.block, required this.onChanged});

  final String keyPrefix;
  final ChoiceFieldSpec field;
  final StructuredBlock block;
  final ValueChanged<WebsiteBlock> onChanged;

  @override
  State<_LayoutChoice> createState() => _LayoutChoiceState();
}

class _LayoutChoiceState extends State<_LayoutChoice> {
  /// Bumped to put the dropdown back after a cancelled change.
  int _reset = 0;

  Future<void> _choose(String layout) async {
    final block = widget.block;
    final moved = ColumnOps.blocksRemovedBy(block, layout);
    if (moved == 0) return widget.onChanged(ColumnOps.withLayout(block, layout));
    final count = columnLayouts[layout]!.length;
    final last = block.columns('columns')[count - 1];
    final fits = last.blocks.length + moved <= BlockLimits.defaults.maxColumnBlocks;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fewer columns'),
        content: Text(fits
            ? 'The columns this layout removes hold ${_blocksCount(moved)}. They will be moved to the end of column $count. Nothing is deleted.'
            : 'The columns this layout removes hold ${_blocksCount(moved)}, more than column $count has room for. Move or delete some blocks first.'),
        actions: [
          TextButton(key: const Key('website-columns-layout-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          if (fits)
            FilledButton(key: const Key('website-columns-layout-move'), onPressed: () => Navigator.pop(context, true), child: Text('Move blocks to column $count')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      widget.onChanged(ColumnOps.withLayout(block, layout, moveBlocks: true));
    } else {
      setState(() => _reset++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    return KeyedSubtree(
      key: ValueKey(_reset),
      child: _choice(context, widget.keyPrefix, f.label, f.options, widget.block.string(f.key), (v) {
        if (v != widget.block.string(f.key)) _choose(v);
      }, labels: f.optionLabels),
    );
  }
}

/// The columns of a section or columns block: each one's blocks (to
/// select and edit), moved left or right, removed; and a column added.
/// Removing a column that holds blocks asks whether to move them into a
/// neighbouring column or delete them with it.
class _ColumnsEditor extends StatelessWidget {
  const _ColumnsEditor({required this.keyPrefix, required this.block, required this.onChanged, this.onSelectNested});

  final String keyPrefix;
  final StructuredBlock block;
  final ValueChanged<WebsiteBlock> onChanged;
  final void Function(int column, int position)? onSelectNested;

  Future<void> _remove(BuildContext context, int index) async {
    final cols = block.columns('columns');
    final column = cols[index];
    if (column.blocks.isEmpty) return onChanged(ColumnOps.withColumnRemoved(block, index)!);
    final into = index > 0 ? index - 1 : 1;
    final fits = ColumnOps.canMerge(block, index, into);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove column ${index + 1}?'),
        content: Text(
          'Column ${index + 1} holds ${_blocksCount(column.blocks.length)}. Move them to the end of column ${into + 1}, or remove them with the column. '
          '${fits ? '' : 'Column ${into + 1} doesn’t have room for them. '}Nothing changes on the website until you save and publish.',
        ),
        actions: [
          TextButton(key: const Key('website-column-remove-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            key: const Key('website-column-remove-delete'),
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove with its blocks'),
          ),
          if (fits)
            FilledButton(key: const Key('website-column-remove-move'), onPressed: () => Navigator.pop(context, 'move'), child: Text('Move blocks to column ${into + 1}')),
        ],
      ),
    );
    if (choice == 'move') onChanged(ColumnOps.withColumnRemoved(block, index, moveInto: into)!);
    if (choice == 'delete') onChanged(ColumnOps.withColumnRemoved(block, index, deleteBlocks: true)!);
  }

  @override
  Widget build(BuildContext context) {
    final cols = block.columns('columns');
    final (fewest, most) = ColumnOps.range(block);
    final added = ColumnOps.withColumnAdded(block);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in cols.indexed)
          Container(
            key: Key('website-column-${c.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 6),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Column ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    IconButton(
                      key: Key('website-column-${c.id}-left'),
                      tooltip: 'Move column ${i + 1} left',
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: i == 0 ? null : () => onChanged(ColumnOps.withColumnMoved(block, i, -1)),
                    ),
                    IconButton(
                      key: Key('website-column-${c.id}-right'),
                      tooltip: 'Move column ${i + 1} right',
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      onPressed: i == cols.length - 1 ? null : () => onChanged(ColumnOps.withColumnMoved(block, i, 1)),
                    ),
                    IconButton(
                      key: Key('website-column-${c.id}-remove'),
                      tooltip: cols.length <= fewest ? 'A ${block.definition.label.toLowerCase()} needs at least $fewest column${fewest == 1 ? '' : 's'}' : 'Remove column ${i + 1}',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: cols.length <= fewest ? null : () => _remove(context, i),
                    ),
                  ],
                ),
                if (c.blocks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('Empty column. Add blocks to it in the page structure.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                for (final (j, child) in c.blocks.indexed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: Key('website-column-${c.id}-select-$j'),
                      onPressed: onSelectNested == null ? null : () => onSelectNested!(i, j),
                      icon: Icon(blockIcon(child), size: 18),
                      label: Text(
                        '${child is StructuredBlock ? child.definition.label : 'Unsupported block'}: ${blockSummary(child)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-add-column'),
            onPressed: added == null ? null : () => onChanged(added),
            icon: const Icon(Icons.add, size: 18),
            label: Text(added == null ? 'At most $most columns' : 'Add column'),
          ),
        ),
      ],
    );
  }
}

/// [entries] (each field and its editor) with each run of fields in one
/// [FieldSpec.group] folded into a collapsible section, closed at first
/// (keys `<prefix>-group-<group, lower case, dashed>`).
List<Widget> groupedFields(String prefix, List<(FieldSpec, Widget)> entries) {
  final out = <Widget>[];
  for (var i = 0; i < entries.length;) {
    final group = entries[i].$1.group;
    if (group == null) {
      out.add(entries[i].$2);
      i++;
      continue;
    }
    final members = <Widget>[];
    while (i < entries.length && entries[i].$1.group == group) {
      members.add(entries[i].$2);
      i++;
    }
    out.add(Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: Key('$prefix-group-${groupSlug(group)}'),
          title: Text(group, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          dense: true,
          shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          collapsedShape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: members,
        ),
      ),
    ));
  }
  return out;
}

/// [group] as a key part ("Layout on desktop" → "layout-on-desktop").
String groupSlug(String group) => group.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

/// A whole number, or blank for Automatic ([NumberFieldSpec.automaticLabel]),
/// with a reset to Automatic. A number out of range is explained (and
/// stopped by validation when saving).
class _NumberField extends StatefulWidget {
  const _NumberField({super.key, required this.fieldKey, required this.field, required this.value, required this.onChanged});

  final String fieldKey;
  final NumberFieldSpec field;
  final int? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _text = TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Reset (or changed elsewhere): show what is set.
    if (widget.value != int.tryParse(_text.text)) _text.text = widget.value?.toString() ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final unit = f.unit.isEmpty ? '' : ' ${f.unit}';
    final range = '${f.min}–${f.max}$unit';
    final n = int.tryParse(_text.text);
    final error = _text.text.isEmpty ? null : (n == null || !f.allows(n) ? 'Must be from $range.' : null);
    return TextField(
      key: Key(widget.fieldKey),
      controller: _text,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
      decoration: websiteField('${f.label}${f.unit.isEmpty ? '' : ' (${f.unit})'}', helper: _text.text.isEmpty ? '${f.automaticLabel}. Or enter $range.' : 'From $range.').copyWith(
        hintText: 'Automatic',
        errorText: error,
        suffixIcon: widget.value == null && _text.text.isEmpty
            ? null
            : IconButton(
                key: Key('${widget.fieldKey}-reset'),
                tooltip: 'Reset to Automatic',
                icon: const Icon(Icons.restart_alt, size: 18),
                onPressed: () {
                  setState(_text.clear);
                  widget.onChanged(null);
                },
              ),
      ),
      onChanged: (t) {
        setState(() {});
        widget.onChanged(t.isEmpty ? null : int.tryParse(t));
      },
    );
  }
}

/// Under an Asymmetric gallery's settings: images visitors won't see as
/// intended (missing, unpublished, or without alt text and not marked
/// decorative), and how the screen sizes work.
class _AsymmetricGalleryNotes extends StatelessWidget {
  const _AsymmetricGalleryNotes({required this.block, required this.library});

  final StructuredBlock block;
  final List<WebsiteMedia> library;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in library) m.id: m};
    final notes = <String>[];
    for (final (i, item) in block.items('images').indexed) {
      final id = item.string('mediaId');
      final media = byId[id];
      final where = 'Image ${i + 1}';
      if (id.isEmpty) continue;
      if (media == null) {
        notes.add('$where no longer exists in the Media library: choose another or remove it.');
        continue;
      }
      if (!media.isPublished) notes.add('$where isn’t published: visitors won’t see it until it is.');
      if (item.value<bool>('decorative') != true && item.text('alt').en.trim().isEmpty && media.alt.en.trim().isEmpty) {
        notes.add('$where has no alt text: describe it here or in the Media library, or mark it decorative only.');
      }
    }
    return Container(
      key: Key('website-block-${block.id}-asymmetric-notes'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: notes.isEmpty ? const Color(0xFFE6EDE2) : const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(n, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          const Text(
            'Desktop, tablets and phones each have their own layout (Automatic until you set it): switch the preview size above the canvas to see each. '
            'The first image is the feature image unless you choose another.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A testimonial as its card will show the person: the avatar (the
/// profile photo, else the generated initials, else none), the name and
/// the rating, updated as they are edited.
class _TestimonialPreview extends StatelessWidget {
  const _TestimonialPreview({required this.keyPrefix, required this.item, required this.block, required this.library});

  final String keyPrefix;
  final BlockItem item;
  final StructuredBlock block;
  final List<WebsiteMedia> library;

  @override
  Widget build(BuildContext context) {
    final name = item.text('name').en.trim();
    final initials = Testimonials.initialsOf(name);
    final photoId = item.string('photoMediaId').trim();
    WebsiteMedia? photo;
    for (final m in library) {
      if (m.id == photoId) photo = m;
    }
    final rating = Testimonials.ratingOf(item);
    final String ratingNote;
    if (rating == null) {
      ratingNote = 'No rating';
    } else if (item.value<bool>('hideRating') == true) {
      ratingNote = 'Rating hidden (${Testimonials.ratingText(rating)} / 5)';
    } else if (block.toggle('showRatings')) {
      ratingNote = '${[for (var i = 0; i < 5; i++) rating >= i + 1 ? '★' : (rating >= i + 0.5 ? '½' : '☆')].join()}  ${Testimonials.ratingText(rating)} / 5';
    } else {
      ratingNote = 'Ratings are turned off for this block (${Testimonials.ratingText(rating)} / 5)';
    }
    const size = 40.0;
    final Widget? avatar = !block.toggle('showAvatars')
        ? null
        : photo != null
            ? ClipOval(key: Key('$keyPrefix-preview-photo'), child: WebsiteMediaThumb(media: photo, size: size))
            : initials.isEmpty
                ? null
                : Container(
                    key: Key('$keyPrefix-preview-initials'),
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF3EADB)),
                    child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF163829))),
                  );
    return Row(
      key: Key('$keyPrefix-preview'),
      children: [
        if (avatar != null) ...[avatar, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? (photo == null ? 'No name or photo: no avatar is shown' : 'No name yet') : name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(ratingNote, key: Key('$keyPrefix-preview-rating'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
