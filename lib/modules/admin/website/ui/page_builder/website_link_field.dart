import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/section_anchors.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_custom_page.dart';
import '../../../../public_website/content/website_link_targets.dart';
import '../website_content_editors.dart';

/// What the link fields of the page being edited know about the website:
/// its pages and their sections ([site]; null when they couldn't be read),
/// the address of the page being edited ([route]) and its blocks as they
/// are now ([blocks]). Provided by the visual editor.
class WebsiteLinkScope extends InheritedWidget {
  const WebsiteLinkScope({super.key, required this.site, required this.route, required this.blocks, required super.child});

  final WebsiteLinkSite? site;
  final String? route;
  final List<WebsiteBlock> blocks;

  static WebsiteLinkScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<WebsiteLinkScope>();

  /// The site with the page being edited as it is now.
  WebsiteLinkSite? get liveSite => site == null || route == null ? site : site!.withPage(route!, blocks);

  /// The sections of the page being edited, as visitors get their anchors.
  List<WebsiteLinkSection> get pageSections => WebsiteLinkPage(route: route ?? '', label: 'This page', blocks: blocks).sections;

  @override
  bool updateShouldNotify(WebsiteLinkScope old) => old.site != site || old.route != route || !identical(old.blocks, blocks);
}

/// The kinds of place a link can lead.
enum WebsiteLinkKind {
  page('A page of this website'),
  samePageSection('A section of this page'),
  otherPageSection('A section of another page'),
  external('Another website (https://)'),
  email('An email address (mailto:)'),
  phone('A phone number (tel:)'),
  custom('Type the address');

  const WebsiteLinkKind(this.label);
  final String label;

  /// The kind [target] is, on the page at [route].
  static WebsiteLinkKind of(String target, {required bool hasSite}) {
    final value = target.trim();
    if (value.isEmpty) return hasSite ? page : custom;
    if (value.startsWith('#')) return samePageSection;
    if (value.startsWith('/')) return SafeLinkTarget.split(value).anchor == null ? page : otherPageSection;
    final lower = value.toLowerCase();
    if (lower.startsWith('https://')) return external;
    if (lower.startsWith('mailto:')) return email;
    if (lower.startsWith('tel:')) return phone;
    return custom;
  }

  String get helper => switch (this) {
        page => 'Choose the page; its address is filled in.',
        samePageSection => 'Choose the section; visitors scroll to it on this page (#anchor).',
        otherPageSection => 'Choose the page, then its section; visitors open the page at that section (/page#anchor).',
        external => 'The full address, starting with https://.',
        email => 'mailto: followed by the address, for example mailto:office@example.org.',
        phone => 'tel: followed by the number, for example tel:+911234567890.',
        custom => 'A page of this website (/admissions, /pages/open-day), a section (#enquire, /admissions#enquire), an https:// link to another site, mailto: or tel:.',
      };
}

/// A link field: where it leads chosen by kind — a page, a section of this
/// page, a section of another page (from the website's pages), another
/// website, an email address or a phone number — and the address itself,
/// which can always be typed. The address is checked for its format
/// ([SafeLinkTarget]) and, for links within the website, that its page and
/// section exist ([WebsiteLinkSite.problemFor]).
///
/// Keys (from [keyPrefix]): `-kind`, `-page`, `-section`, and the address
/// `-<generation>` (a text field).
class WebsiteLinkField extends StatefulWidget {
  const WebsiteLinkField({super.key, required this.keyPrefix, required this.label, required this.value, required this.generation, required this.onChanged});

  final String keyPrefix;
  final String label;
  final String value;
  final int generation;
  final ValueChanged<String> onChanged;

  @override
  State<WebsiteLinkField> createState() => _WebsiteLinkFieldState();
}

class _WebsiteLinkFieldState extends State<WebsiteLinkField> {
  late final TextEditingController _address = TextEditingController(text: widget.value);
  WebsiteLinkKind? _kind;

  /// The page chosen for "A section of another page" before its section.
  String? _page;

  @override
  void didUpdateWidget(WebsiteLinkField old) {
    super.didUpdateWidget(old);
    if (widget.value != _address.text) _address.text = widget.value;
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _set(String target) {
    _address.text = target;
    widget.onChanged(target);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebsiteLinkScope.maybeOf(context);
    final site = scope?.liveSite;
    final target = _address.text.trim();
    final kind = _kind ?? WebsiteLinkKind.of(target, hasSite: site != null);
    final formatError = target.isEmpty ? null : SafeLinkTarget.validate(target);
    final siteProblem = formatError != null || site == null ? null : site.problemFor(target, currentRoute: scope?.route ?? '');
    final pages = [
      for (final p in site?.pages ?? const <WebsiteLinkPage>[])
        if (!p.archived) p,
    ];
    final (:path, :anchor) = SafeLinkTarget.split(target);
    final pagePath = target.startsWith('/') ? path : null;

    Widget pagePicker({required bool withSections}) {
      final choices = [
        for (final p in pages)
          if (!withSections || (p.sections.isNotEmpty && p.route != scope?.route)) p,
      ];
      final selected = withSections ? (_page ?? pagePath) : pagePath;
      final value = choices.any((p) => p.route == selected) ? selected : null;
      return DropdownButtonFormField<String>(
        key: Key('${widget.keyPrefix}-page'),
        initialValue: value,
        isExpanded: true,
        decoration: websiteField(withSections ? 'Page' : 'Page of this website'),
        hint: Text(choices.isEmpty ? 'No other page has sections yet' : 'Choose a page'),
        items: [
          for (final p in choices)
            DropdownMenuItem(value: p.route, child: Text('${p.label} — ${p.route}${p.reachable ? '' : ' (not published)'}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (route) {
          if (route == null) return;
          if (withSections) {
            setState(() => _page = route);
          } else {
            _set(route);
          }
        },
      );
    }

    Widget sectionPicker(List<WebsiteLinkSection> sections, String Function(String anchor) linkFor, String? selected, String empty) {
      if (sections.isEmpty) {
        return Text(empty, key: Key('${widget.keyPrefix}-no-sections'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary));
      }
      final value = sections.any((s) => s.anchor == selected) ? selected : null;
      return DropdownButtonFormField<String>(
        key: Key('${widget.keyPrefix}-section'),
        initialValue: value,
        isExpanded: true,
        decoration: websiteField('Section'),
        hint: const Text('Choose a section'),
        items: [
          for (final s in sections)
            DropdownMenuItem(value: s.anchor, child: Text('${s.label} (#${s.anchor})${s.hidden ? ' — hidden' : ''}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (a) {
          if (a != null) _set(linkFor(a));
        },
      );
    }

    final pickers = <Widget>[];
    switch (kind) {
      case WebsiteLinkKind.page:
        if (site != null) pickers.add(pagePicker(withSections: false));
      case WebsiteLinkKind.samePageSection:
        final samePage = target.startsWith('#') || (pagePath != null && scope?.route != null && site?.pageFor(pagePath) == site?.pageFor(scope!.route!));
        pickers.add(sectionPicker(scope?.pageSections ?? const [], (a) => '#$a', samePage ? anchor : null, 'This page has no sections yet. Add a section first.'));
      case WebsiteLinkKind.otherPageSection:
        if (site != null) {
          pickers.add(pagePicker(withSections: true));
          final route = _page ?? pagePath;
          final page = route == null ? null : site.pageFor(route);
          if (page != null) {
            pickers.add(const SizedBox(height: 8));
            pickers.add(sectionPicker(page.sections, (a) => '${page.route}#$a', route == pagePath ? anchor : null, '${page.label} has no sections.'));
          }
        }
      case WebsiteLinkKind.external || WebsiteLinkKind.email || WebsiteLinkKind.phone || WebsiteLinkKind.custom:
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scope != null) ...[
          DropdownButtonFormField<WebsiteLinkKind>(
            key: Key('${widget.keyPrefix}-kind'),
            initialValue: kind,
            isExpanded: true,
            decoration: websiteField('${widget.label}: leads to'),
            items: [for (final k in WebsiteLinkKind.values) DropdownMenuItem(value: k, child: Text(k.label, key: Key('${widget.keyPrefix}-kind-${k.name}')))],
            onChanged: (k) => setState(() {
              _kind = k;
              _page = null;
            }),
          ),
          const SizedBox(height: 8),
          ...pickers,
          if (pickers.isNotEmpty) const SizedBox(height: 8),
        ],
        TextFormField(
          key: Key('${widget.keyPrefix}-${widget.generation}'),
          controller: _address,
          decoration: websiteField(scope == null ? widget.label : '${widget.label} (address)', helper: kind.helper).copyWith(errorText: formatError ?? siteProblem, errorMaxLines: 3),
          onChanged: (v) {
            widget.onChanged(v);
            setState(() {});
          },
        ),
      ],
    );
  }
}

/// A section's anchor id (Section anchor ID): given automatically, shown
/// here and editable. Checked for its format and that no other section of
/// the page uses it; Regenerate makes a new one from the section's name.
/// Changing it warns how many links lead to the anchor it had when the
/// section was opened (they stop working until they are updated). An
/// empty field is never saved: the anchor it had is kept.
///
/// Keys (from [keyPrefix]): the field `-<generation>`, `-regenerate`,
/// `-links`.
class WebsiteAnchorField extends StatefulWidget {
  const WebsiteAnchorField({super.key, required this.keyPrefix, required this.section, required this.generation, required this.onChanged});

  final String keyPrefix;
  final StructuredBlock section;
  final int generation;
  final ValueChanged<String> onChanged;

  @override
  State<WebsiteAnchorField> createState() => _WebsiteAnchorFieldState();
}

class _WebsiteAnchorFieldState extends State<WebsiteAnchorField> {
  late final TextEditingController _text;

  /// The anchor the section had when opened (links lead to it).
  late String _original;

  @override
  void initState() {
    super.initState();
    _original = SectionAnchors.stored(widget.section);
    _text = TextEditingController(text: _original);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A section saved before anchors existed shows the anchor it has.
    if (_original.isEmpty) {
      final scope = WebsiteLinkScope.maybeOf(context);
      final effective = scope == null ? null : SectionAnchors.effective(scope.blocks)[widget.section.id];
      if (effective != null) {
        _original = effective;
        _text.text = effective;
      }
    }
  }

  @override
  void didUpdateWidget(WebsiteAnchorField old) {
    super.didUpdateWidget(old);
    if (old.section.id != widget.section.id) {
      _original = SectionAnchors.stored(widget.section);
      _text.text = _original;
    } else {
      final stored = SectionAnchors.stored(widget.section);
      if (stored.isNotEmpty && stored != _text.text.trim()) _text.text = stored;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _commit(String value) {
    setState(() {});
    // Never cleared: an empty field keeps the anchor the section has.
    if (value.trim().isNotEmpty) widget.onChanged(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebsiteLinkScope.maybeOf(context);
    final blocks = scope?.blocks ?? const <WebsiteBlock>[];
    final value = _text.text.trim();
    final usedElsewhere = [
      for (final s in SectionAnchors.sectionsOf(blocks))
        if (s.id != widget.section.id && SectionAnchors.stored(s) == value) s,
    ];
    final error = SectionAnchors.formatProblem(value) ??
        (usedElsewhere.isEmpty ? null : 'Another section of this page (${SectionAnchors.labelOf(usedElsewhere.first, SectionAnchors.sectionsOf(blocks).indexOf(usedElsewhere.first) + 1)}) uses “$value”. Each section needs its own.');
    final changed = _original.isNotEmpty && value != _original;
    final route = scope?.route;
    // Links on this page, and on the other pages when they could be read.
    final links = changed ? (scope?.site ?? const WebsiteLinkSite(pages: [])).linksTo(route ?? '', _original, blocks) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: Key('${widget.keyPrefix}-${widget.generation}'),
                controller: _text,
                maxLength: SectionAnchors.maxLength,
                decoration: websiteField(
                  'Section anchor ID',
                  helper: 'Used for website navigation: link to this section with #${value.isEmpty ? 'anchor' : value}${route == null || route.isEmpty ? '' : ' or $route#${value.isEmpty ? 'anchor' : value}'}. '
                      'Changing the section name doesn’t change it.',
                ).copyWith(prefixText: '#', errorText: error, errorMaxLines: 3),
                onChanged: _commit,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                key: Key('${widget.keyPrefix}-regenerate'),
                onPressed: () {
                  final next = SectionAnchors.regenerate(widget.section, blocks);
                  _text.text = next;
                  _commit(next);
                },
                child: const Text('Regenerate'),
              ),
            ),
          ],
        ),
        if (changed)
          Container(
            key: Key('${widget.keyPrefix}-links'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(8)),
            child: Text(
              links == 0
                  ? 'The anchor was “$_original”. No link on this website leads to it, so nothing breaks; links typed elsewhere (emails, posters) would land at the top of the page.'
                  : '$links link${links == 1 ? '' : 's'} on this website lead${links == 1 ? 's' : ''} to “#$_original”. ${links == 1 ? 'It stops' : 'They stop'} working until updated to “#$value”; see Links to check.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// "Links to check": internal links that lead to a page or section that
/// doesn't exist or that visitors can't reach, and links on other pages to
/// sections of this page that are gone or hidden. A warning only — the
/// page can still be saved and published — so a deleted section or a
/// changed anchor is seen before visitors meet it. Nothing is redirected.
class WebsiteLinkChecks extends StatelessWidget {
  const WebsiteLinkChecks({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Links to check:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            const Text('Visitors following these links won’t reach the page or section they name. Choose another destination, or restore the section.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            for (final p in problems) Text('• $p', style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}
