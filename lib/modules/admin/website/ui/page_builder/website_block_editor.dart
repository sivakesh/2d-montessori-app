import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/block_ids.dart';
import '../../../../public_website/content/blocks/block_limits.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/section_presets.dart';
import '../../../../public_website/content/blocks/field_spec.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_content_models.dart';
import '../../../../public_website/content/website_custom_page.dart';
import '../../../../public_website/content/website_design.dart';
import '../../../../forms/models/website_form.dart';
import '../../../../forms/public/public_forms_repository.dart';
import '../website_content_editors.dart';
import '../website_content_screen.dart';
import 'block_list_ops.dart';
import 'website_color_field.dart';
import 'website_size_field.dart';

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
    'map' => block.text('address').en.trim().isEmpty ? 'No address yet' : block.text('address').en.trim(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in block.definition.fields)
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
            ),
          ),
        WebsiteStyleEditor(block: block, design: design, onChanged: onChanged),
      ],
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
        for (final key in block.definition.styleKeys)
          if (BlockStyle.sizeKeys[key] case final range?)
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
  });

  final String keyPrefix;
  final FieldSpec field;
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
              minLines: f.multiline ? 3 : 1,
              maxLines: f.multiline ? 8 : 1,
              decoration: websiteField(label, helper: lang == 'ta' ? 'If left blank, Tamil visitors see the English.' : null),
              // Only this language changes; every other is kept.
              onChanged: (v) => onChanged((value as LocalizedText? ?? const LocalizedText()).withText(lang, v)),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            input('en', '${f.label} (English)${f.required ? '' : ', optional'}'),
            if (multilingualEditing) ...[const SizedBox(height: 6), input('ta', '${f.label} (Tamil)')],
          ],
        );
      case MediaFieldSpec():
        final id = value as String? ?? '';
        WebsiteMedia? media;
        for (final m in library) {
          if (m.id == id) media = m;
        }
        return Row(
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
          ],
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
      case ToggleFieldSpec():
        return SwitchListTile(key: Key(keyPrefix), contentPadding: EdgeInsets.zero, title: Text(f.label), value: value as bool? ?? f.initial, onChanged: onChanged);
      case ItemsFieldSpec():
        return _ItemsEditor(keyPrefix: keyPrefix, field: f, items: value as List<BlockItem>? ?? const [], library: library, generation: generation, onChanged: onChanged);
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
  const _ItemsEditor({required this.keyPrefix, required this.field, required this.items, required this.library, required this.generation, required this.onChanged});

  final String keyPrefix;
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
                    Expanded(child: Text('${field.itemLabel} ${i + 1}', style: const TextStyle(fontSize: 13))),
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
                for (final f in field.itemFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, right: 6),
                    child: _FieldEditor(
                      keyPrefix: '$keyPrefix-item-${item.id}-${f.key}',
                      field: f,
                      value: item.values[f.key],
                      library: library,
                      generation: generation,
                      onChanged: (v) => onChanged([...items]..[i] = item.withValue(f.key, v)),
                    ),
                  ),
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
                              BlockItem(id: BlockIds.item(), values: {for (final f in field.itemFields) f.key: f.key == media.key ? id : f.defaultValue}),
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
                      : () => onChanged([...items, BlockItem(id: BlockIds.item(), values: {for (final f in field.itemFields) f.key: f.defaultValue})]),
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
