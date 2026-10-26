import 'package:flutter/foundation.dart';

import '../blocks/block_registry.dart';
import '../blocks/field_spec.dart';
import '../blocks/website_block.dart';
import '../website_content_models.dart';
import '../website_custom_page.dart';
import '../website_site_layout.dart';
import 'field_path.dart';
import 'translation_record.dart';

/// One English text that can be translated, at a stable [path].
/// [required]: a page can't be published in a language until this text is
/// translated there (titles, headings, labels); other texts fall back to
/// English.
@immutable
class TranslatableSource {
  const TranslatableSource(this.path, this.text, {this.required = false, this.localized});

  final TranslationPath path;

  /// The English source text.
  final String text;
  final bool required;

  /// The field's text in every language as stored inline (when the source
  /// came from content), for readiness before translation records exist.
  final LocalizedText? localized;
}

/// The translatable English texts of content. Texts with no English are
/// left out (there is nothing to translate; blank often means "use the
/// built-in wording").
class TranslatableSources {
  TranslatableSources._();

  static void _add(List<TranslatableSource> out, TranslationPath path, LocalizedText text, {bool required = false}) {
    if (text.en.trim().isNotEmpty) out.add(TranslatableSource(path, text.en, required: required, localized: text));
  }

  /// Every translatable text field of [blocks], their items, and blocks
  /// inside columns (declared by each block type's [TextFieldSpec]s).
  /// Unsupported blocks contribute nothing.
  static List<TranslatableSource> forBlocks(List<WebsiteBlock> blocks) {
    final out = <TranslatableSource>[];
    for (final b in BlockRegistry.flatten(blocks)) {
      if (b is! StructuredBlock) continue;
      for (final f in b.definition.fields) {
        if (f is TextFieldSpec && f.translatable) _add(out, TranslationPath.block(b.id, f.key), b.text(f.key), required: f.translationRequired);
        if (f is ItemsFieldSpec) {
          for (final item in b.items(f.key)) {
            for (final g in f.itemFields.whereType<TextFieldSpec>()) {
              if (g.translatable) _add(out, TranslationPath.item(b.id, item.id, g.key), item.text(g.key), required: g.translationRequired);
            }
          }
        }
      }
    }
    return out;
  }

  /// An additional page: its title (required), introduction and content
  /// (its blocks, or its sections as blocks).
  static List<TranslatableSource> forCustomPage(CustomPage page) => [
        if (page.title.en.trim().isNotEmpty) TranslatableSource(TranslationPath.page('title'), page.title.en, required: true, localized: page.title),
        if (page.intro.en.trim().isNotEmpty) TranslatableSource(TranslationPath.page('intro'), page.intro.en, localized: page.intro),
        ...forBlocks(page.effectiveBlocks),
      ];

  /// The site layout: its texts and the labels written for links (a blank
  /// label uses the page's own name, translated with that page).
  static List<TranslatableSource> forLayout(SiteLayout layout) {
    final out = <TranslatableSource>[];
    _add(out, TranslationPath.layout('siteName'), layout.siteName, required: true);
    _add(out, TranslationPath.layout('tagline'), layout.tagline);
    _add(out, TranslationPath.layout('footerText'), layout.footerText);
    _add(out, TranslationPath.layout('copyright'), layout.copyright);
    final seen = <String>{};
    for (final e in [...layout.mainNav, ...layout.footerNav]) {
      if (seen.add(e.id)) _add(out, TranslationPath.navLabel(e.id), e.label, required: true);
    }
    return out;
  }

  /// An image's alt text (required: it describes the image) and caption.
  static List<TranslatableSource> forMedia(WebsiteMedia media) {
    final out = <TranslatableSource>[];
    _add(out, TranslationPath.media(media.id, 'alt'), media.alt, required: true);
    _add(out, TranslationPath.media(media.id, 'caption'), media.caption);
    return out;
  }
}

/// How far one language's translation of some content has got.
@immutable
class TranslationCoverage {
  const TranslationCoverage({required this.counts, required this.requiredCounts, required this.orphans});

  /// Every source in [sources] against [record] (null = nothing
  /// translated yet). Statuses are derived: an entry whose English has
  /// changed counts as outdated, and its text is not touched.
  factory TranslationCoverage.of(List<TranslatableSource> sources, TranslationRecord? record) {
    final counts = {for (final s in TranslationStatus.values) s: 0};
    final requiredCounts = {for (final s in TranslationStatus.values) s: 0};
    for (final source in sources) {
      final status = TranslationEntry.statusOf(record?.entryFor(source.path), source.text);
      counts[status] = counts[status]! + 1;
      if (source.required) requiredCounts[status] = requiredCounts[status]! + 1;
    }
    return TranslationCoverage(
      counts: Map.unmodifiable(counts),
      requiredCounts: Map.unmodifiable(requiredCounts),
      orphans: record == null ? 0 : record.orphanPaths([for (final s in sources) s.path]).length,
    );
  }

  /// Sources by derived status.
  final Map<TranslationStatus, int> counts;

  /// Required sources by derived status.
  final Map<TranslationStatus, int> requiredCounts;

  /// Translations whose source was deleted (ignored; cleaned up later).
  final int orphans;

  int get total => counts.values.fold(0, (a, b) => a + b);
  int get requiredTotal => requiredCounts.values.fold(0, (a, b) => a + b);
  int get optionalTotal => total - requiredTotal;

  /// Approved or published, and not outdated.
  int get ready => counts[TranslationStatus.approved]! + counts[TranslationStatus.published]!;
  int get requiredReady => requiredCounts[TranslationStatus.approved]! + requiredCounts[TranslationStatus.published]!;
  int get optionalReady => ready - requiredReady;

  int get missing => counts[TranslationStatus.missing]!;
  int get outdated => counts[TranslationStatus.outdated]!;

  /// Every required text is approved or published and up to date — the
  /// condition for publishing this content in this language (optional
  /// texts may fall back to English).
  bool get requiredComplete => requiredReady == requiredTotal;

  /// Share of all sources that are ready (1.0 when there are none).
  double get readyShare => total == 0 ? 1 : ready / total;
}

/// How much of some content already has text in a language inline (in its
/// [LocalizedText] fields, e.g. existing Tamil) — a readiness indication
/// before translation records exist. It can't tell whether inline text is
/// up to date with the English; nothing is created or stored.
@immutable
class InlineTranslationReadiness {
  const InlineTranslationReadiness({required this.total, required this.translated, required this.requiredTotal, required this.requiredTranslated});

  factory InlineTranslationReadiness.of(List<TranslatableSource> sources, String lang) {
    var translated = 0;
    var requiredTotal = 0;
    var requiredTranslated = 0;
    for (final s in sources) {
      final has = (s.localized?.textFor(lang) ?? '').trim().isNotEmpty;
      if (has) translated++;
      if (s.required) {
        requiredTotal++;
        if (has) requiredTranslated++;
      }
    }
    return InlineTranslationReadiness(total: sources.length, translated: translated, requiredTotal: requiredTotal, requiredTranslated: requiredTranslated);
  }

  final int total;
  final int translated;
  final int requiredTotal;
  final int requiredTranslated;

  bool get requiredComplete => requiredTranslated == requiredTotal;
}
