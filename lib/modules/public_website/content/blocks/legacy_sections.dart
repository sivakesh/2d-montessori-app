import '../website_content_models.dart';
import '../website_custom_page.dart';
import 'block_registry.dart';
import 'field_spec.dart';
import 'website_block.dart';

/// Converts the first additional pages' sections (`text`, `image_text`,
/// `image_grid`, `cta`) to blocks, and back.
///
/// The conversion is deterministic: a section keeps its id as its block's
/// id, and anything the conversion creates inside it gets an id derived
/// from it (`<id>__img`, `<id>__txt`, `<id>__c1`, `<id>__btn`,
/// `<id>__m_<mediaId>`), so converting the same section always yields the
/// same ids — and the same translation paths. All language keys of every
/// text are carried over.
///
/// In this phase it is used only in memory: pages are still saved with
/// their sections (no page is converted or written by it).
class LegacySections {
  LegacySections._();

  static List<WebsiteBlock> toBlocks(List<CustomPageSection> sections) => [for (final s in sections) toBlock(s)];

  static StructuredBlock toBlock(CustomPageSection s) {
    switch (s.type) {
      case CustomSectionType.text:
        return StructuredBlock(definition: BlockRegistry.text, id: s.id, values: {'heading': s.heading, 'body': s.body});
      case CustomSectionType.imageText:
        final image = StructuredBlock(
          definition: BlockRegistry.image,
          id: '${s.id}__img',
          values: {'mediaId': s.mediaId ?? '', 'alt': const LocalizedText(), 'caption': const LocalizedText(), 'aspect': '4:3'},
        );
        final text = StructuredBlock(definition: BlockRegistry.text, id: '${s.id}__txt', values: {'heading': s.heading, 'body': s.body});
        final first = s.imageOnRight ? text : image;
        final second = s.imageOnRight ? image : text;
        return StructuredBlock(definition: BlockRegistry.columns, id: s.id, values: {
          'layout': '1:1',
          'columns': [
            BlockColumn(id: '${s.id}__c1', blocks: [first]),
            BlockColumn(id: '${s.id}__c2', blocks: [second]),
          ],
        });
      case CustomSectionType.imageGrid:
        final seen = <String, int>{};
        return StructuredBlock(definition: BlockRegistry.gallery, id: s.id, values: {
          'heading': s.heading,
          'columns': '3',
          'images': [
            for (final mediaId in s.mediaIds)
              BlockItem(id: _imageItemId(s.id, mediaId, seen), values: {'mediaId': mediaId}),
          ],
        });
      case CustomSectionType.callToAction:
        return StructuredBlock(definition: BlockRegistry.cta, id: s.id, values: {
          'heading': s.heading,
          'body': s.body,
          'buttons': [
            BlockItem(id: '${s.id}__btn', values: {'label': s.buttonLabel, 'target': s.target, 'variant': 'primary'}),
          ],
        });
    }
  }

  /// `<sectionId>__m_<mediaId>`, with `_2`, `_3` … for repeats of the same
  /// image. Characters an id can't hold are replaced.
  static String _imageItemId(String sectionId, String mediaId, Map<String, int> seen) {
    final safe = mediaId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    final n = (seen[safe] ?? 0) + 1;
    seen[safe] = n;
    return n == 1 ? '${sectionId}__m_$safe' : '${sectionId}__m_${safe}_$n';
  }

  /// The sections copy of a block page, for older versions of the app:
  /// every top-level block that has an exact section form (hidden blocks
  /// and blocks without one are left out), at most
  /// [CustomPage.maxSections]. Derived on every save, never edited.
  static List<CustomPageSection> mirror(List<WebsiteBlock> blocks) =>
      [for (final b in blocks) ?toSection(b)].take(CustomPage.maxSections).toList();

  /// [block] as a section, when it can be expressed as one exactly (the
  /// shapes [toBlock] produces); otherwise null. A style that only spells
  /// out the defaults (white background, normal spacing) looks the same as
  /// none, so it doesn't stop the copy. A columns block with a hidden block
  /// inside has no copy: a section can't hide half of itself.
  static CustomPageSection? toSection(WebsiteBlock block) {
    if (block is! StructuredBlock || block.hidden || !BlockStyle.isDefault(block.style) || block.preserved.isNotEmpty) return null;
    switch (block.type) {
      case 'text':
        return CustomPageSection(id: block.id, type: CustomSectionType.text, heading: block.text('heading'), body: block.text('body'));
      case 'columns':
        final cols = block.columns('columns');
        if (block.string('layout') != '1:1' || cols.length != 2 || cols.any((c) => c.blocks.length != 1)) return null;
        final a = cols[0].blocks.single;
        final b = cols[1].blocks.single;
        if (a is! StructuredBlock || b is! StructuredBlock || a.hidden || b.hidden) return null;
        final imageOnRight = a.type == 'text' && b.type == 'image';
        if (!imageOnRight && !(a.type == 'image' && b.type == 'text')) return null;
        final image = imageOnRight ? b : a;
        final text = imageOnRight ? a : b;
        if (image.string('aspect') != '4:3' || !image.text('alt').isEmpty || !image.text('caption').isEmpty) return null;
        final mediaId = image.string('mediaId');
        return CustomPageSection(
          id: block.id,
          type: CustomSectionType.imageText,
          heading: text.text('heading'),
          body: text.text('body'),
          mediaId: mediaId.isEmpty ? null : mediaId,
          imageOnRight: imageOnRight,
        );
      case 'gallery':
        if (block.string('columns') != '3') return null;
        return CustomPageSection(
          id: block.id,
          type: CustomSectionType.imageGrid,
          heading: block.text('heading'),
          mediaIds: [for (final item in block.items('images')) item.string('mediaId')],
        );
      case 'cta':
        final buttons = block.items('buttons');
        if (buttons.length != 1 || buttons.single.string('variant') != 'primary') return null;
        return CustomPageSection(
          id: block.id,
          type: CustomSectionType.callToAction,
          heading: block.text('heading'),
          body: block.text('body'),
          buttonLabel: buttons.single.text('label'),
          target: buttons.single.string('target'),
        );
    }
    return null;
  }
}
