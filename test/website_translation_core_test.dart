// Translation core (L2a), pure Dart — nothing is stored yet:
// - Paths use stable ids and field names: page, block, item, table header
//   and cell, layout, navigation label and image text; never positions.
// - Reordering keeps every path; duplicating gives new ones; a deleted
//   block's translations become orphans and never attach to new content.
// - Source hashes ignore line-ending and surrounding-whitespace changes.
// - Changing the English makes a translation outdated without touching its
//   text; the workflow's allowed moves; records parse tolerantly.
// - Coverage: required and optional counts by derived status.
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/translation/field_path.dart';
import 'package:montessori_app/modules/public_website/content/translation/source_hash.dart';
import 'package:montessori_app/modules/public_website/content/translation/translation_coverage.dart';
import 'package:montessori_app/modules/public_website/content/translation/translation_record.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';

List<WebsiteBlock> _blocks() => BlockRegistry.parseList([
      {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About us', 'ta': 'எங்களைப் பற்றி'}, 'body': {'en': 'We teach.', 'ta': ''}},
      {
        'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:1',
        'columns': [
          {'id': 'c_a', 'blocks': [{'id': 'b_inner00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left'}}]},
          {'id': 'c_b', 'blocks': [{'id': 'b_inner00002', 'type': 'image', 'v': 1, 'mediaId': 'm1', 'caption': {'en': 'A garden'}}]},
        ],
      },
      {
        'id': 'b_btns000001', 'type': 'buttons', 'v': 1,
        'buttons': [
          {'id': 'i_one', 'label': {'en': 'Visit'}, 'target': '/contact'},
          {'id': 'i_two', 'label': {'en': 'Apply'}, 'target': '/admissions'},
        ],
      },
      {'id': 'b_future0001', 'type': 'timeline', 'v': 1, 'title': {'en': 'Not known'}},
    ]);

Set<String> _paths(List<TranslatableSource> sources) => {for (final s in sources) s.path.value};

TranslationEntry _approved(String text, String source) => TranslationEntry(text: text, status: TranslationStatus.approved, sourceHash: SourceHash.of(source));

void main() {
  group('paths', () {
    test('every kind of text has an id-based path', () {
      expect(TranslationPath.page('title').value, 'page/title');
      expect(TranslationPath.page('seo/description').value, 'page/seo/description');
      expect(TranslationPath.block('b_text000001', 'heading').value, 'b/b_text000001/heading');
      expect(TranslationPath.item('b_btns000001', 'i_one', 'label').value, 'b/b_btns000001/i/i_one/label');
      expect(TranslationPath.tableHeader('b_tbl', 'c_age').value, 'b/b_tbl/col/c_age/header');
      expect(TranslationPath.tableCell('b_tbl', 'r_1', 'c_age').value, 'b/b_tbl/row/r_1/c_age');
      expect(TranslationPath.layout('siteName').value, 'layout/siteName');
      expect(TranslationPath.navLabel('n1xk').value, 'nav/n1xk/label');
      expect(TranslationPath.media('m_8812', 'alt').value, 'media/m_8812/alt');
      for (final p in ['page/title', 'b/b_x/heading', 'b/b_x/i/i_y/label', 'b/b_x/col/c_1/header', 'b/b_x/row/r_1/c_1', 'layout/tagline', 'nav/n1/label', 'media/m1/caption']) {
        expect(TranslationPath.tryParse(p)?.value, p, reason: p);
      }
      for (final bad in ['', 'title', 'page', 'b/b_x', 'b/b.x/heading', 'b/b_x/Heading', 'b/b_x/i/i_y', 'b/b_x/x/i_y/label', 'nav/n1/text', 'media/m1', 'page.title', 'other/x/y']) {
        expect(TranslationPath.tryParse(bad), isNull, reason: bad);
      }
      expect(() => TranslationPath.block('a/b', 'heading'), throwsArgumentError);
    });

    test('block texts: headings, items and blocks inside columns; unsupported blocks contribute nothing', () {
      final sources = TranslatableSources.forBlocks(_blocks());
      expect(_paths(sources), {
        'b/b_text000001/heading',
        'b/b_text000001/body',
        'b/b_inner00001/heading',
        'b/b_inner00002/caption',
        'b/b_btns000001/i/i_one/label',
        'b/b_btns000001/i/i_two/label',
      });
      expect({for (final s in sources) if (s.required) s.path.value}, {'b/b_text000001/heading', 'b/b_inner00001/heading', 'b/b_btns000001/i/i_one/label', 'b/b_btns000001/i/i_two/label'});
      expect(sources.firstWhere((s) => s.path.value == 'b/b_text000001/heading').text, 'About us', reason: 'English is the source');
    });

    test('reordering blocks and items keeps every path', () {
      final blocks = _blocks();
      final buttons = blocks[2] as StructuredBlock;
      final reversedItems = buttons.withValue('buttons', buttons.items('buttons').reversed.toList());
      final reordered = [reversedItems, blocks[3], blocks[1], blocks[0]];
      expect(_paths(TranslatableSources.forBlocks(reordered)), _paths(TranslatableSources.forBlocks(blocks)));
    });

    test('a duplicate has its own paths', () {
      final blocks = _blocks();
      final copy = BlockRegistry.duplicate(blocks[2]);
      final original = _paths(TranslatableSources.forBlocks([blocks[2]]));
      final copied = _paths(TranslatableSources.forBlocks([copy]));
      expect(copied, hasLength(original.length));
      expect(copied.intersection(original), isEmpty);
    });

    test('deleting a block orphans its translations; a new block never inherits them', () {
      final blocks = _blocks();
      var record = const TranslationRecord(lang: 'hi', scope: 'page', docId: 'p1');
      for (final s in TranslatableSources.forBlocks(blocks)) {
        record = record.withEntry(s.path, _approved('hi: ${s.text}', s.text));
      }
      final replacement = BlockRegistry.create(BlockRegistry.text).withValue('heading', const LocalizedText(en: 'About us'));
      final after = [replacement, ...blocks.skip(1)];
      final sources = TranslatableSources.forBlocks(after);
      expect(record.orphanPaths([for (final s in sources) s.path]), {'b/b_text000001/heading', 'b/b_text000001/body'});
      final newHeading = sources.firstWhere((s) => s.path.blockId == replacement.id);
      expect(TranslationEntry.statusOf(record.entryFor(newHeading.path), newHeading.text), TranslationStatus.missing, reason: 'same English, new block: not translated');
      expect(TranslationCoverage.of(sources, record).orphans, 2);
    });
  });

  group('source hashes', () {
    test('SHA-256 of the normalised UTF-8 text', () {
      expect(SourceHash.of('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(SourceHash.of('Line one\r\nLine two'), SourceHash.of('Line one\nLine two'));
      expect(SourceHash.of('Line one\rLine two'), SourceHash.of('Line one\nLine two'));
      expect(SourceHash.of('  Hello\n'), SourceHash.of('Hello'));
      expect(SourceHash.of('Hello'), isNot(SourceHash.of('Hello!')));
      expect(SourceHash.of('Hello world'), isNot(SourceHash.of('Hello  world')), reason: 'inner spacing is content');
      expect(SourceHash.of('வணக்கம்'), hasLength(64));
    });
  });

  group('lifecycle', () {
    test('changing the English makes a translation outdated; its text is kept', () {
      final entry = TranslationEntry.manual(text: 'हमारे बारे में', source: 'About us');
      expect(TranslationEntry.statusOf(entry, 'About us'), TranslationStatus.draft);
      expect(TranslationEntry.statusOf(entry, 'About us\r\n'), TranslationStatus.draft, reason: 'normalised');
      final approved = entry.approve(currentSource: 'About us');
      expect(TranslationEntry.statusOf(approved, 'About our school'), TranslationStatus.outdated);
      expect(approved.text, 'हमारे बारे में');
      expect(() => entry.approve(currentSource: 'About our school'), throwsStateError, reason: 'review against the new English first');
      expect(TranslationEntry.statusOf(null, 'x'), TranslationStatus.missing);
      expect(TranslationEntry.statusOf(entry.edit('  ', source: 'About us'), 'About us'), TranslationStatus.missing);
    });

    test('editing approved or published text keeps the previous text until published again', () {
      final published = _approved('पुराना', 'Old').markPublished();
      expect(published.status, TranslationStatus.published);
      final edited = published.edit('नया', source: 'New');
      expect(edited.status, TranslationStatus.draft);
      expect(edited.previousText, 'पुराना');
      expect(TranslationEntry.statusOf(edited, 'New'), TranslationStatus.draft);
      final again = edited.edit('नया २', source: 'New');
      expect(again.previousText, 'पुराना', reason: 'still the last published text');
      final republished = again.submitForReview().approve(currentSource: 'New').markPublished();
      expect(republished.previousText, isNull);
    });

    test('allowed moves only; derived statuses are never stored', () {
      final draft = TranslationEntry.manual(text: 'x', source: 'y');
      expect(() => draft.markPublished(), throwsStateError, reason: 'only approved text is published');
      expect(draft.submitForReview().status, TranslationStatus.needsReview);
      expect(() => draft.submitForReview().submitForReview(), returnsNormally, reason: 'staying put is allowed');
      expect(TranslationEntry.canTransition(TranslationStatus.needsReview, TranslationStatus.published), isFalse);
      expect(TranslationEntry.canTransition(TranslationStatus.published, TranslationStatus.approved), isFalse);
      expect(TranslationStatus.parseStored('published'), TranslationStatus.published);
      expect(TranslationStatus.parseStored('outdated'), TranslationStatus.draft, reason: 'never stored; read as draft');
      expect(TranslationStatus.parseStored('approved!'), TranslationStatus.draft);
    });

    test('records round-trip; unusable entries are left out', () {
      final record = const TranslationRecord(lang: 'hi', scope: 'page', docId: 'Xy12')
          .withEntry(TranslationPath.page('title'), _approved('प्रवेश', 'Admissions'))
          .withEntry(TranslationPath.item('b_x', 'i_y', 'label'), TranslationEntry.manual(text: 'बुक', source: 'Book'));
      expect(record.id, 'hi__page__Xy12');
      final map = record.toMap();
      expect(map['schemaVersion'], 1);
      final back = TranslationRecord.fromMap(map)!;
      expect(back.toMap(), map);
      final tolerant = TranslationRecord.fromMap({
        ...map,
        'fields': {
          ...map['fields'] as Map,
          'b/0/heading': {'text': 'positional ids are still ids', 'sourceHash': 'h'},
          'not a path': {'text': 'x', 'sourceHash': 'h'},
          'page/intro': {'text': 'no hash'},
          'page/seo/description': 'not a map',
        },
      })!;
      expect(tolerant.fields.keys.toSet(), {'page/title', 'b/b_x/i/i_y/label', 'b/0/heading'});
      expect(TranslationRecord.fromMap({'lang': 'hi'}), isNull);
    });
  });

  group('coverage', () {
    test('required and optional counts by derived status; complete only when every required text is ready', () {
      final sources = [
        TranslatableSource(TranslationPath.page('title'), 'Admissions', required: true),
        TranslatableSource(TranslationPath.block('b_1', 'heading'), 'Visit us', required: true),
        TranslatableSource(TranslationPath.block('b_1', 'body'), 'Weekday mornings.'),
        TranslatableSource(TranslationPath.item('b_2', 'i_1', 'label'), 'Book', required: true),
        TranslatableSource(TranslationPath.block('b_3', 'caption'), 'Garden'),
      ];
      var record = const TranslationRecord(lang: 'hi', scope: 'page', docId: 'p')
          .withEntry(sources[0].path, _approved('प्रवेश', 'Admissions').markPublished())
          .withEntry(sources[1].path, _approved('पधारें', 'Visit'))
          .withEntry(sources[2].path, TranslationEntry.manual(text: 'सुबह', source: 'Weekday mornings.').submitForReview());
      var c = TranslationCoverage.of(sources, record);
      expect(c.total, 5);
      expect(c.requiredTotal, 3);
      expect(c.optionalTotal, 2);
      expect(c.counts[TranslationStatus.published], 1);
      expect(c.counts[TranslationStatus.outdated], 1, reason: 'translated from “Visit”, English is now “Visit us”');
      expect(c.counts[TranslationStatus.needsReview], 1);
      expect(c.missing, 2);
      expect(c.requiredReady, 1);
      expect(c.requiredComplete, isFalse);

      record = record
          .withEntry(sources[1].path, record.entryFor(sources[1].path)!.edit('हमसे मिलें', source: 'Visit us').approve(currentSource: 'Visit us'))
          .withEntry(sources[3].path, _approved('बुक करें', 'Book'));
      c = TranslationCoverage.of(sources, record);
      expect(c.requiredReady, 3);
      expect(c.requiredComplete, isTrue, reason: 'optional texts may fall back to English');
      expect(c.optionalReady, 0);
      expect(c.readyShare, closeTo(0.6, 0.001));
      expect(TranslationCoverage.of(const [], null).requiredComplete, isTrue);
    });

    test('content sources: custom pages (blocks or legacy sections), the site layout and image text', () {
      final legacy = CustomPage(
        id: 'p',
        slug: 'open-day',
        title: const LocalizedText(en: 'Open day', ta: 'திறந்த நாள்'),
        intro: const LocalizedText(en: 'Come and see.'),
        sections: const [
          CustomPageSection(id: 'lq3x9ddd', type: CustomSectionType.callToAction, heading: LocalizedText(en: 'Visit'), buttonLabel: LocalizedText(en: 'Book'), target: '/contact'),
          CustomPageSection(id: 'lq3x9bbb', type: CustomSectionType.imageText, heading: LocalizedText(en: 'Garden'), mediaId: 'm1'),
        ],
      );
      expect(_paths(TranslatableSources.forCustomPage(legacy)), {
        'page/title',
        'page/intro',
        'b/lq3x9ddd/heading',
        'b/lq3x9ddd/i/lq3x9ddd__btn/label',
        'b/lq3x9bbb__txt/heading',
      }, reason: 'legacy sections map to the same paths every time');
      final withBlocks = legacy.copyWith(blocks: () => _blocks());
      expect(_paths(TranslatableSources.forCustomPage(withBlocks)), containsAll(['page/title', 'b/b_text000001/heading']));

      const layout = SiteLayout(
        siteName: LocalizedText(en: 'Our School'),
        footerText: LocalizedText(en: 'Open weekdays.'),
        mainNav: [SiteNavEntry(id: 'n1', target: SiteNavTarget.builtIn('home'), label: LocalizedText(en: 'Start')), SiteNavEntry(id: 'n2', target: SiteNavTarget.builtIn('gallery'))],
        footerNav: [SiteNavEntry(id: 'n1', target: SiteNavTarget.builtIn('home'), label: LocalizedText(en: 'Start'))],
      );
      expect(_paths(TranslatableSources.forLayout(layout)), {'layout/siteName', 'layout/footerText', 'nav/n1/label'}, reason: 'blank labels use the page’s own name');

      const media = WebsiteMedia(id: 'm1', url: 'u', storagePath: 's', alt: LocalizedText(en: 'Children reading'), caption: LocalizedText(en: 'Library'));
      final mediaSources = TranslatableSources.forMedia(media);
      expect(_paths(mediaSources), {'media/m1/alt', 'media/m1/caption'});
      expect(mediaSources.firstWhere((s) => s.path.value == 'media/m1/alt').required, isTrue);
    });

    test('English/Tamil behaviour is unchanged and other language keys stay in blocks', () {
      final block = _blocks().first as StructuredBlock;
      expect(block.text('heading').resolve(PublicLanguage.tamil), 'எங்களைப் பற்றி');
      expect(block.text('body').resolve(PublicLanguage.tamil), 'We teach.', reason: 'no Tamil: English');
      final withHindi = BlockRegistry.parse({...block.toMap(), 'heading': {'en': 'About us', 'ta': 'எங்களைப் பற்றி', 'hi': 'हमारे बारे में'}}) as StructuredBlock;
      expect(withHindi.toMap()['heading'], {'en': 'About us', 'ta': 'எங்களைப் பற்றி', 'hi': 'हमारे बारे में'});
      expect(BlockRegistry.definition('text')!.fields.whereType<TextFieldSpec>().map((f) => f.key), ['heading', 'body']);
    });
  });
}
