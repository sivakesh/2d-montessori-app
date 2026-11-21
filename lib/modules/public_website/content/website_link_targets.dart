import 'package:flutter/foundation.dart';

import '../public_routes.dart';
import 'blocks/field_spec.dart';
import 'blocks/section_anchors.dart';
import 'blocks/website_block.dart';
import 'website_custom_page.dart';

/// One section a link can lead to: its anchor id and a label for lists
/// (its editor name, else its heading).
@immutable
class WebsiteLinkSection {
  const WebsiteLinkSection({required this.anchor, required this.label, this.hidden = false});

  final String anchor;
  final String label;

  /// Hidden: kept in the page but not shown to visitors, so a link to it
  /// leads to the top of the page.
  final bool hidden;
}

/// A page of this website as the link editor knows it: its address, name,
/// and the sections it has (from its draft, which is what the editor
/// shows; null blocks: not built with sections).
@immutable
class WebsiteLinkPage {
  const WebsiteLinkPage({
    required this.route,
    required this.label,
    this.blocks,
    this.reachable = true,
    this.sectionsPublished = true,
    this.archived = false,
  });

  final String route;
  final String label;
  final List<WebsiteBlock>? blocks;

  /// Visitors can open it (an additional page that is published; built-in
  /// pages always).
  final bool reachable;

  /// Its sections are on the website (it is published with blocks).
  final bool sectionsPublished;

  /// An archived additional page (never shown to visitors).
  final bool archived;

  WebsiteLinkPage withBlocks(List<WebsiteBlock> blocks) =>
      WebsiteLinkPage(route: route, label: label, blocks: blocks, reachable: reachable, sectionsPublished: sectionsPublished, archived: archived);

  /// Its sections, in page order, each with its anchor (as visitors get
  /// it, [SectionAnchors.effective]).
  List<WebsiteLinkSection> get sections {
    final list = blocks;
    if (list == null) return const [];
    final anchors = SectionAnchors.effective(list);
    final sections = SectionAnchors.sectionsOf(list);
    return [
      for (final (i, s) in sections.indexed)
        if (anchors[s.id] case final anchor?) WebsiteLinkSection(anchor: anchor, label: SectionAnchors.labelOf(s, i + 1), hidden: s.hidden),
    ];
  }

  WebsiteLinkSection? section(String anchor) {
    for (final s in sections) {
      if (s.anchor == anchor) return s;
    }
    return null;
  }
}

/// One link found on a page: where it is ("Block 2 (Hero), Button 1"),
/// and where it leads.
typedef WebsiteLinkUse = ({String where, String target});

/// The website's pages, for choosing where a link leads and checking that
/// internal links (`/admissions`, `#enquire`, `/teacher-training#enquire`)
/// lead to a page and a section that exist. Only links whose format is
/// allowed ([SafeLinkTarget]) are checked here; those that aren't are
/// already problems of their block.
@immutable
class WebsiteLinkSite {
  const WebsiteLinkSite({required this.pages});

  final List<WebsiteLinkPage> pages;

  /// [route] as pages are identified: normalised (`/Pages/Open-Day/` is
  /// `/pages/open-day`).
  static String _key(String route) => PublicRoutes.normalizeRoute(route);

  WebsiteLinkPage? pageFor(String route) {
    final key = _key(route);
    for (final p in pages) {
      if (_key(p.route) == key) return p;
    }
    return null;
  }

  /// This site with [route]'s page showing [blocks] (the page being
  /// edited, as it is now).
  WebsiteLinkSite withPage(String route, List<WebsiteBlock> blocks) => WebsiteLinkSite(pages: [
        for (final p in pages)
          if (_key(p.route) == _key(route)) p.withBlocks(blocks) else p,
      ]);

  /// Why internal link [target] on the page at [currentRoute] doesn't lead
  /// where it says, or null when it does (or isn't an internal link, or
  /// its format is already refused). The page and section must exist; a
  /// hidden section, an unpublished page or one whose sections aren't
  /// published yet is reported too, since visitors wouldn't get there.
  String? problemFor(String target, {required String currentRoute}) {
    final value = target.trim();
    if (value.isEmpty || !SafeLinkTarget.isInternal(value) || SafeLinkTarget.validate(value) != null) return null;
    final (:path, :anchor) = SafeLinkTarget.split(value);
    final samePage = path.isEmpty;
    final route = samePage ? currentRoute : path;
    final page = pageFor(route);
    if (page == null) return 'There is no page at ${PublicRoutes.pathOf(route)}.';
    // A section of the page itself is reached wherever the page is.
    if (!samePage && page.archived) return '${page.label} (${page.route}) is archived: visitors can’t open it.';
    if (!samePage && !page.reachable) return '${page.label} (${page.route}) isn’t published yet: visitors get “page not found”.';
    if (anchor == null) return null;
    final where = samePage ? 'this page' : '${page.label} (${page.route})';
    if (page.blocks == null) return '$where isn’t built with sections, so it has no section “#$anchor”.';
    final section = page.section(anchor);
    if (section == null) return 'There is no section “#$anchor” on $where. Choose one of its sections.';
    if (section.hidden) return 'The section “#$anchor” (${section.label}) on $where is hidden: visitors would land at the top of the page.';
    if (!samePage && !page.sectionsPublished) return '${page.label} (${page.route}) isn’t published with its sections yet: visitors would land at the top of the page.';
    return null;
  }

  /// Every link on [blocks] that leads nowhere (see [problemFor]), located
  /// as BlockRegistry.validate locates problems.
  List<String> linkProblems(List<WebsiteBlock> blocks, {required String currentRoute}) => [
        for (final use in linksIn(blocks))
          if (problemFor(use.target, currentRoute: currentRoute) case final problem?) '${use.where}: $problem',
      ];

  /// The links on other pages that lead to a section of [route] that
  /// [blocks] (the page as it is now) no longer has, or has hidden: what
  /// deleting a section, or changing its anchor, breaks elsewhere.
  List<String> brokenElsewhere(String route, List<WebsiteBlock> blocks) {
    final here = (pageFor(route) ?? WebsiteLinkPage(route: route, label: route)).withBlocks(blocks);
    final problems = <String>[];
    for (final page in pages) {
      if (_key(page.route) == _key(route) || page.archived) continue;
      for (final use in linksIn(page.blocks ?? const [])) {
        final value = use.target.trim();
        if (!SafeLinkTarget.isInternal(value) || SafeLinkTarget.validate(value) != null) continue;
        final (:path, :anchor) = SafeLinkTarget.split(value);
        if (anchor == null || path.isEmpty || _key(path) != _key(route)) continue;
        final section = here.section(anchor);
        if (section == null || section.hidden) {
          problems.add('${page.label} (${page.route}), ${use.where}: leads to “#$anchor”, which ${section == null ? 'isn’t on this page' : 'is hidden on this page'}.');
        }
      }
    }
    return problems;
  }

  /// How many links lead to the section [anchor] of [route]: on its own
  /// page ([blocks], as it is now; `#anchor` or the page's address) and on
  /// the other pages.
  int linksTo(String route, String anchor, List<WebsiteBlock> blocks) {
    var count = 0;
    bool leads(String target, String from) {
      final value = target.trim();
      if (!SafeLinkTarget.isInternal(value) || SafeLinkTarget.validate(value) != null) return false;
      final split = SafeLinkTarget.split(value);
      return split.anchor == anchor && _key(split.path.isEmpty ? from : split.path) == _key(route);
    }

    for (final use in linksIn(blocks)) {
      if (leads(use.target, route)) count++;
    }
    for (final page in pages) {
      if (_key(page.route) == _key(route)) continue;
      for (final use in linksIn(page.blocks ?? const [])) {
        if (leads(use.target, page.route)) count++;
      }
    }
    return count;
  }

  /// Every link field of [blocks] that has a value, at every depth.
  static List<WebsiteLinkUse> linksIn(List<WebsiteBlock> blocks) {
    final uses = <WebsiteLinkUse>[];
    void walk(List<WebsiteBlock> list, String prefix) {
      for (final (i, block) in list.indexed) {
        if (block is! StructuredBlock) continue;
        final where = '$prefix${prefix.isEmpty ? 'Block' : 'block'} ${i + 1} (${block.definition.label})';
        for (final f in block.definition.fields) {
          if (f is LinkFieldSpec && block.string(f.key).trim().isNotEmpty) uses.add((where: where, target: block.string(f.key)));
          if (f is ItemsFieldSpec) {
            for (final (j, item) in block.items(f.key).indexed) {
              for (final g in f.itemFields.whereType<LinkFieldSpec>()) {
                if (item.string(g.key).trim().isNotEmpty) uses.add((where: '$where, ${f.itemLabel} ${j + 1}', target: item.string(g.key)));
              }
            }
          }
          if (f is ColumnsFieldSpec) {
            for (final (ci, c) in block.columns(f.key).indexed) {
              walk(c.blocks, '$where, column ${ci + 1}, ');
            }
          }
        }
      }
    }

    walk(blocks, '');
    return uses;
  }
}
