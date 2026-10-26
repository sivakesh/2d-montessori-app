import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/field_spec.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_design.dart';
import '../../../public_website/content/website_site_layout.dart';
import '../../../public_website/content/website_site_style.dart';
import '../../../public_website/public_strings.dart';
import '../../../public_website/public_website_theme.dart';
import '../../../public_website/widgets/blocks/website_blocks_view.dart';
import '../../../public_website/widgets/public_scaffold.dart';
import '../data/website_content_admin_service.dart';
import 'website_content_editors.dart';
import 'website_content_screen.dart';
import 'website_design_editors.dart';

/// Where the layout in the editor came from when it opened.
enum WebsiteLayoutEditSource {
  /// Nothing saved: a first layout reproducing the current navigation.
  current,

  /// A saved draft that isn't published (visitors see the built-in layout).
  unpublishedDraft,

  /// A saved draft that differs from what is published.
  draftWithChanges,

  /// The published layout (no different draft).
  published;

  static WebsiteLayoutEditSource of(SiteLayout? draft, SiteLayout? live) {
    if (draft == null && live == null) return current;
    if (live == null) return unpublishedDraft;
    if (draft != null && !draft.sameContentAs(live)) return draftWithChanges;
    return published;
  }

  String get description => switch (this) {
    current => 'Nothing has been saved yet. This layout reproduces the website’s current header and footer; visitors see the built-in layout until you publish.',
    unpublishedDraft => 'You are editing a saved draft that is not published. Visitors see the built-in header and footer.',
    draftWithChanges => 'You are editing a saved draft with unpublished changes. Visitors still see the published layout.',
    published => 'You are editing the published layout that visitors see.',
  };
}

enum WebsiteLayoutPreviewDevice { desktop, mobile }

/// Settings -> Website -> Site layout: the public header and footer — site
/// name and tagline, main and footer navigation, footer text and
/// copyright — with a desktop/mobile, English/Tamil preview of the real
/// header and footer, a saved draft, and publish/unpublish. Login,
/// Dashboard and Logout are not part of the layout and never change here.
class WebsiteSiteLayoutEditorScreen extends ConsumerStatefulWidget {
  const WebsiteSiteLayoutEditorScreen({super.key, required this.service, required this.user});

  final WebsiteContentAdminService service;
  final AppUser user;

  @override
  ConsumerState<WebsiteSiteLayoutEditorScreen> createState() => _WebsiteSiteLayoutEditorScreenState();
}

class _WebsiteSiteLayoutEditorScreenState extends ConsumerState<WebsiteSiteLayoutEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  final _siteNameEn = TextEditingController();
  final _siteNameTa = TextEditingController();
  final _taglineEn = TextEditingController();
  final _taglineTa = TextEditingController();
  final _footerTextEn = TextEditingController();
  final _footerTextTa = TextEditingController();
  final _copyrightEn = TextEditingController();
  final _copyrightTa = TextEditingController();
  List<TextEditingController> get _controllers => [_siteNameEn, _siteNameTa, _taglineEn, _taglineTa, _footerTextEn, _footerTextTa, _copyrightEn, _copyrightTa];

  List<SiteNavEntry> _mainNav = const [];
  List<SiteNavEntry> _footerNav = const [];

  /// The site design and the header's and footer's look (shared by every
  /// page).
  SiteDesign _design = SiteDesign.defaults;
  SiteHeaderStyle _header = const SiteHeaderStyle();
  SiteFooterStyle _footer = const SiteFooterStyle();

  /// Bumped when the form is refilled, so fields holding their own text
  /// (colour codes, button and contact text) start again.
  int _generation = 0;
  SiteLayout? _savedDraft;
  SiteLayout? _live;
  bool _liveUnreadable = false;

  /// Every additional page (to choose link targets) and the published ones
  /// (what visitors' links resolve against).
  List<({CustomPage draft, CustomPage? live})> _pages = const [];
  List<CustomPage> _published = const [];
  bool _loading = true;

  /// Loading failed: the form isn't shown, so an empty layout can never be
  /// published over the real one.
  bool _loadFailed = false;
  bool _busy = false;
  PublicLanguage _previewLanguage = PublicLanguage.english;

  /// The website's enabled languages (for the preview).
  List<PublicLanguage> _languages = PublicLanguage.builtIn;
  WebsiteLayoutPreviewDevice _previewDevice = WebsiteLayoutPreviewDevice.desktop;

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// The loaded identity and footer text: the form edits their English and
  /// Tamil; any other language is saved back unchanged.
  SiteLayout _base = const SiteLayout();

  void _fill(SiteLayout layout) {
    _base = layout;
    _siteNameEn.text = layout.siteName.en;
    _siteNameTa.text = layout.siteName.ta;
    _taglineEn.text = layout.tagline.en;
    _taglineTa.text = layout.tagline.ta;
    _footerTextEn.text = layout.footerText.en;
    _footerTextTa.text = layout.footerText.ta;
    _copyrightEn.text = layout.copyright.en;
    _copyrightTa.text = layout.copyright.ta;
    _mainNav = layout.mainNav;
    _footerNav = layout.footerNav;
    _design = layout.design;
    _header = layout.header;
    _footer = layout.footer;
    _generation++;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final ok = await attempt(() async {
      final saved = await service.getSiteLayout(requesterRole: role);
      final pages = await service.listCustomPages(requesterRole: role);
      final published = await service.publishedCustomPages(requesterRole: role);
      final languages = (await service.editorLanguageRegistry(requesterRole: role)).editorLanguages;
      if (!mounted) return;
      setState(() {
        _languages = languages;
        _savedDraft = saved.draft;
        _live = saved.live;
        _liveUnreadable = saved.liveUnreadable;
        _pages = pages;
        _published = published;
        _fill(saved.draft ?? saved.live ?? SiteLayout.fromCurrentNavigation(published));
      });
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = !ok;
      });
    }
  }

  /// The layout being edited. Built on the loaded one, so its keys this
  /// version doesn't know are kept.
  SiteLayout get _layout => _base.copyWith(
    siteName: _base.siteName.copyWith(en: _siteNameEn.text, ta: _siteNameTa.text),
    tagline: _base.tagline.copyWith(en: _taglineEn.text, ta: _taglineTa.text),
    mainNav: _mainNav,
    footerNav: _footerNav,
    footerText: _base.footerText.copyWith(en: _footerTextEn.text, ta: _footerTextTa.text),
    copyright: _base.copyright.copyWith(en: _copyrightEn.text, ta: _copyrightTa.text),
    design: _design,
    header: _header,
    footer: _footer,
  );

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok) {
      refreshPublicSite();
      final saved = await service.getSiteLayout(requesterRole: role);
      if (mounted) {
        setState(() {
          _savedDraft = saved.draft;
          _live = saved.live;
          _liveUnreadable = saved.liveUnreadable;
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirm({required String title, required String body, required String action, required Key key}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: key, onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _publish() async {
    if (!await _confirm(
      title: 'Publish this layout?',
      body: 'Every public page will show this header, menu and footer straight away. Links to pages that are not published are refused.',
      action: 'Publish',
      key: const Key('website-layout-publish-confirm'),
    )) {
      return;
    }
    await _run(() => service.publishSiteLayout(requesterRole: role, actor: user, layout: _layout), 'Published. Visitors now see this layout.');
  }

  Future<void> _unpublish() async {
    if (!await _confirm(
      title: 'Unpublish the layout?',
      body: 'The website returns to its built-in header and footer. Your draft is kept, and no page is unpublished.',
      action: 'Unpublish',
      key: const Key('website-layout-unpublish-confirm'),
    )) {
      return;
    }
    await _run(() => service.unpublishSiteLayout(requesterRole: role, actor: user), 'Unpublished. The website uses its built-in header and footer again.');
  }

  Future<void> _startFromCurrent() async {
    if (!await _confirm(
      title: 'Start again from the current navigation?',
      body:
          'The editor is reset to the website’s built-in header and footer and its current navigation, in every language: '
          'the site name, tagline, footer text, copyright and link labels return to the built-in wording, including any text in languages '
          'other than English and Tamil. Nothing changes on the website until you save a draft or publish.',
      action: 'Start again',
      key: const Key('website-layout-reset-confirm'),
    )) {
      return;
    }
    // The design and the header's and footer's look are kept.
    setState(() => _fill(SiteLayout.fromCurrentNavigation(_published).copyWith(design: _design, header: _header, footer: _footer)));
    showMessage('Reset in the editor. Save a draft or publish to apply it.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Site layout')),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('The site layout could not be loaded.'),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('website-layout-retry'), onPressed: _load, child: const Text('Try again')),
                  ],
                ),
        ),
      );
    }

    final layout = _layout;
    final live = _live;
    final source = WebsiteLayoutEditSource.of(_savedDraft, live);
    final saved = _savedDraft ?? live;
    final unsaved = saved == null || !layout.sameContentAs(saved);
    final errors = layout.validationErrors();
    final warnings = layout.unpublishedLinkErrors({for (final p in _published) p.id});
    final en = PublicStrings.of(PublicLanguage.english);

    return WebsiteEditorFrame(
      title: 'Site layout',
      busy: _busy,
      children: [
        WebsiteEditSourceBanner(
          key: const Key('website-layout-source'),
          text: source.description,
          chips: [
            live == null ? const WebsiteStatusChip(label: 'Not published', color: Color(0xFF6E6E73)) : const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
            if (source == WebsiteLayoutEditSource.draftWithChanges || source == WebsiteLayoutEditSource.unpublishedDraft) const WebsiteStatusChip(label: 'Draft saved', color: Color(0xFF8A6A33)),
            if (unsaved) const WebsiteStatusChip(key: Key('website-layout-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
          ],
        ),
        if (_liveUnreadable)
          Container(
            key: const Key('website-layout-live-unreadable'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'The published layout could not be read, so visitors see the built-in header and footer. Publish this layout to replace it, or unpublish it.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const WebsiteEditorSectionTitle('Site identity'),
        const Text(
          'Leave a field blank to use the website’s built-in wording. If you leave the Tamil text blank, Tamil visitors see the English text.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        _pair(_siteNameEn, _siteNameTa, 'Site name', SiteLayout.maxSiteNameLength, en.schoolName, 'website-layout-site-name'),
        _pair(_taglineEn, _taglineTa, 'Tagline (shown in the footer)', SiteLayout.maxTaglineLength, en.footerTagline, 'website-layout-tagline', lines: 2),
        const WebsiteEditorSectionTitle('Main navigation'),
        const Text('Shown in the header and the mobile menu. Hiding a link keeps its page published and reachable by its address.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 10),
        _NavListEditor(keyPrefix: 'website-layout-main', entries: _mainNav, max: SiteLayout.maxMainEntries, pages: _pages, published: _published, onChanged: (list) => setState(() => _mainNav = list)),
        const WebsiteEditorSectionTitle('Footer navigation'),
        const Text('Shown only in the footer.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 10),
        _NavListEditor(
          keyPrefix: 'website-layout-footer',
          entries: _footerNav,
          max: SiteLayout.maxFooterEntries,
          pages: _pages,
          published: _published,
          onChanged: (list) => setState(() => _footerNav = list),
        ),
        const WebsiteEditorSectionTitle('Footer content'),
        _pair(_footerTextEn, _footerTextTa, 'Footer text (optional)', SiteLayout.maxFooterTextLength, '', 'website-layout-footer-text', lines: 3),
        _pair(_copyrightEn, _copyrightTa, 'Copyright (optional)', SiteLayout.maxCopyrightLength, '', 'website-layout-copyright'),
        Container(
          key: const Key('website-layout-every-page'),
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
          child: const Row(
            children: [
              Icon(Icons.public, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The design, header and footer below are shared by every page of the website. '
                  'Preview them here; visitors see them when you publish the layout.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const WebsiteEditorSectionTitle('Design: colours and type'),
        WebsiteDesignEditor(key: ValueKey('website-design-$_generation'), design: _design, onChanged: (d) => setState(() => _design = d)),
        const WebsiteEditorSectionTitle('Header'),
        WebsiteHeaderStyleEditor(key: ValueKey('website-header-$_generation'), style: _header, design: _design, onChanged: (h) => setState(() => _header = h)),
        const WebsiteEditorSectionTitle('Footer and contact details'),
        WebsiteFooterStyleEditor(key: ValueKey('website-footer-$_generation'), style: _footer, design: _design, onChanged: (f) => setState(() => _footer = f)),
        _PreviewControls(
          languages: _languages,
          language: _previewLanguage,
          device: _previewDevice,
          onLanguage: (l) => setState(() => _previewLanguage = l),
          onDevice: (d) => setState(() => _previewDevice = d),
        ),
        WebsiteSiteLayoutPreview(key: const Key('website-layout-preview'), layout: layout, publishedPages: _published, language: _previewLanguage, device: _previewDevice),
        if (errors.isNotEmpty || warnings.isNotEmpty)
          Container(
            key: const Key('website-layout-errors'),
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errors.isNotEmpty) ...[const Text('Fix before saving:', style: TextStyle(fontWeight: FontWeight.w600)), for (final e in errors) Text('• $e', style: const TextStyle(fontSize: 13))],
                if (warnings.isNotEmpty) ...[
                  if (errors.isNotEmpty) const SizedBox(height: 8),
                  const Text('Fix before publishing (these links are hidden from visitors):', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final w in warnings) Text('• $w', style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              key: const Key('website-layout-save-draft'),
              onPressed: () => _run(
                () => service.saveSiteLayoutDraft(requesterRole: role, actor: user, layout: layout),
                live == null ? 'Draft saved. Visitors still see the built-in layout.' : 'Draft saved. Visitors still see the published layout.',
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save draft'),
            ),
            FilledButton.icon(
              key: const Key('website-layout-publish'),
              onPressed: _publish,
              icon: const Icon(Icons.public),
              label: const Text('Publish'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            ),
            if (live != null || _liveUnreadable)
              TextButton.icon(key: const Key('website-layout-unpublish'), onPressed: _unpublish, icon: const Icon(Icons.visibility_off_outlined), label: const Text('Unpublish')),
            TextButton.icon(key: const Key('website-layout-reset'), onPressed: _startFromCurrent, icon: const Icon(Icons.restart_alt), label: const Text('Start again from current navigation')),
          ],
        ),
      ],
    );
  }

  Widget _pair(TextEditingController en, TextEditingController ta, String label, int max, String builtIn, String key, {int lines = 1}) {
    final hint = builtIn.isEmpty ? null : 'Blank: $builtIn';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          TextField(
            key: Key('$key-en'),
            controller: en,
            maxLength: max,
            maxLines: lines,
            decoration: websiteField('$label (English)', hint: hint),
          ),
          const SizedBox(height: 8),
          TextField(key: Key('$key-ta'), controller: ta, maxLength: max, maxLines: lines, decoration: websiteField('$label (Tamil)')),
        ],
      ),
    );
  }
}

/// The default (page) name of a link's destination, for the admin.
String _destinationName(SiteNavTarget target, List<({CustomPage draft, CustomPage? live})> pages) {
  switch (target.kind) {
    case SiteNavTargetKind.builtIn:
      final route = SiteBuiltInPages.routeFor(target.value);
      return route == null ? 'Unknown page' : PublicStrings.of(PublicLanguage.english).labelFor(route);
    case SiteNavTargetKind.page:
      for (final p in pages) {
        if (p.draft.id == target.value) return p.draft.title.en.isNotEmpty ? p.draft.title.en : p.draft.slug;
      }
      return 'Deleted page';
    case SiteNavTargetKind.external:
      return target.value;
  }
}

class _NavListEditor extends StatelessWidget {
  const _NavListEditor({required this.keyPrefix, required this.entries, required this.max, required this.pages, required this.published, required this.onChanged});

  final String keyPrefix;
  final List<SiteNavEntry> entries;
  final int max;
  final List<({CustomPage draft, CustomPage? live})> pages;
  final List<CustomPage> published;
  final ValueChanged<List<SiteNavEntry>> onChanged;

  void _replace(int i, SiteNavEntry entry) => onChanged([...entries]..[i] = entry);

  void _move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= entries.length) return;
    final list = [...entries];
    final item = list.removeAt(i);
    list.insert(to, item);
    onChanged(list);
  }

  Future<void> _remove(BuildContext context, int i) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this link?'),
        content: const Text('Only the link is removed from the layout; its page stays published. Nothing changes on the website until you save a draft or publish.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: Key('$keyPrefix-remove-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) onChanged([...entries]..removeAt(i));
  }

  /// Why visitors won't see this link, or null when they will.
  String? _hiddenReason(SiteNavEntry e) {
    if (!e.visible) return 'Hidden';
    if (e.target.validate() != null) return 'Invalid';
    if (e.target.kind != SiteNavTargetKind.page) return null;
    if (published.any((p) => p.id == e.target.value)) return null;
    for (final p in pages) {
      if (p.draft.id == e.target.value) return p.draft.archived ? 'Page archived' : 'Page not published';
    }
    return 'Page deleted';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No links. Visitors see none here.', style: TextStyle(color: AppColors.textSecondary)),
          ),
        for (var i = 0; i < entries.length; i++)
          Builder(
            builder: (context) {
              final e = entries[i];
              final name = _destinationName(e.target, pages);
              final label = e.label.en.trim().isNotEmpty ? e.label.en.trim() : name;
              final reason = _hiddenReason(e);
              final kind = switch (e.target.kind) {
                SiteNavTargetKind.builtIn => 'Built-in page',
                SiteNavTargetKind.page => 'Additional page',
                SiteNavTargetKind.external => 'External link',
              };
              return Card(
                key: Key('$keyPrefix-entry-${e.id}'),
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(e.target.kind == SiteNavTargetKind.external ? kind : '$kind · $name', style: const TextStyle(fontSize: 12)),
                          if (e.label.ta.trim().isNotEmpty) Text('தமிழ்: ${e.label.ta.trim()}', style: const TextStyle(fontSize: 12)),
                          if (reason != null) WebsiteStatusChip(key: Key('$keyPrefix-status-${e.id}'), label: reason, color: reason == 'Hidden' ? const Color(0xFF6E6E73) : const Color(0xFFB3261E)),
                        ],
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Visible', style: TextStyle(fontSize: 13)),
                              Switch(
                                key: Key('$keyPrefix-visible-${e.id}'),
                                value: e.visible,
                                onChanged: (v) => _replace(i, e.copyWith(visible: v)),
                              ),
                            ],
                          ),
                          IconButton(key: Key('$keyPrefix-up-${e.id}'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward)),
                          IconButton(key: Key('$keyPrefix-down-${e.id}'), tooltip: 'Move down', onPressed: i == entries.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward)),
                          IconButton(
                            key: Key('$keyPrefix-edit-${e.id}'),
                            tooltip: 'Edit link',
                            onPressed: () async {
                              final edited = await showSiteNavEntryDialog(context, pages: pages, entry: e);
                              if (edited != null) _replace(i, edited);
                            },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(key: Key('$keyPrefix-remove-${e.id}'), tooltip: 'Remove link', onPressed: () => _remove(context, i), icon: const Icon(Icons.delete_outline)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-add'),
            onPressed: entries.length >= max
                ? null
                : () async {
                    final created = await showSiteNavEntryDialog(context, pages: pages);
                    if (created != null) onChanged([...entries, created]);
                  },
            icon: const Icon(Icons.add_link),
            label: Text(entries.length >= max ? 'At most $max links' : 'Add link'),
          ),
        ),
      ],
    );
  }
}

/// Adds or edits one navigation link: its destination (a built-in page,
/// an additional page, or an external https:// link) and its English and
/// Tamil label. Returns the link, or null when cancelled.
Future<SiteNavEntry?> showSiteNavEntryDialog(BuildContext context, {required List<({CustomPage draft, CustomPage? live})> pages, SiteNavEntry? entry}) {
  return showDialog<SiteNavEntry>(
    context: context,
    builder: (_) => _NavEntryDialog(pages: pages, entry: entry),
  );
}

class _NavEntryDialog extends StatefulWidget {
  const _NavEntryDialog({required this.pages, this.entry});

  final List<({CustomPage draft, CustomPage? live})> pages;
  final SiteNavEntry? entry;

  @override
  State<_NavEntryDialog> createState() => _NavEntryDialogState();
}

class _NavEntryDialogState extends State<_NavEntryDialog> {
  late SiteNavTargetKind _kind;
  String? _builtInId;
  String? _pageId;
  final _url = TextEditingController();
  final _labelEn = TextEditingController();
  final _labelTa = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final target = widget.entry?.target;
    _kind = target?.kind ?? SiteNavTargetKind.builtIn;
    switch (_kind) {
      case SiteNavTargetKind.builtIn:
        _builtInId = target?.value;
      case SiteNavTargetKind.page:
        _pageId = target?.value;
      case SiteNavTargetKind.external:
        _url.text = target?.value ?? '';
    }
    _labelEn.text = widget.entry?.label.en ?? '';
    _labelTa.text = widget.entry?.label.ta ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _labelEn.dispose();
    _labelTa.dispose();
    super.dispose();
  }

  void _submit() {
    final target = switch (_kind) {
      SiteNavTargetKind.builtIn => SiteNavTarget.builtIn(_builtInId ?? ''),
      SiteNavTargetKind.page => SiteNavTarget.page(_pageId ?? ''),
      SiteNavTargetKind.external => SiteNavTarget.external(_url.text.trim()),
    };
    // Other languages of an existing label are kept.
    final label = (widget.entry?.label ?? const LocalizedText()).copyWith(en: _labelEn.text.trim(), ta: _labelTa.text.trim());
    final entry = widget.entry?.copyWith(target: target, label: label) ?? SiteNavEntry.create(target, label: label);
    // The same checks as saving, for this one link.
    final errors = SiteLayout(mainNav: [entry]).validationErrors();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.first.replaceFirst('Main navigation, link 1', 'This link').replaceFirst('This link: ', ''));
      return;
    }
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final en = PublicStrings.of(PublicLanguage.english);
    final choosable = [
      for (final p in widget.pages)
        if (!p.draft.archived || p.draft.id == _pageId) p.draft,
    ];
    return AlertDialog(
      title: Text(widget.entry == null ? 'Add link' : 'Edit link'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<SiteNavTargetKind>(
                key: const Key('website-link-kind'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SiteNavTargetKind.builtIn,
                    label: Text('Built-in page', key: Key('website-link-kind-builtin')),
                  ),
                  ButtonSegment(
                    value: SiteNavTargetKind.page,
                    label: Text('Additional page', key: Key('website-link-kind-page')),
                  ),
                  ButtonSegment(
                    value: SiteNavTargetKind.external,
                    label: Text('External', key: Key('website-link-kind-external')),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              switch (_kind) {
                SiteNavTargetKind.builtIn => DropdownButtonFormField<String>(
                  key: const Key('website-link-builtin'),
                  initialValue: _builtInId,
                  decoration: websiteField('Page'),
                  items: [
                    for (final id in SiteBuiltInPages.ids)
                      DropdownMenuItem(
                        value: id,
                        child: Text(en.labelFor(SiteBuiltInPages.routeFor(id)!), key: Key('website-link-builtin-$id')),
                      ),
                  ],
                  onChanged: (v) => setState(() => _builtInId = v),
                ),
                SiteNavTargetKind.page =>
                  choosable.isEmpty
                      ? const Text('There are no additional pages yet. Create one in the Pages tab.')
                      : DropdownButtonFormField<String>(
                          key: const Key('website-link-page'),
                          initialValue: choosable.any((p) => p.id == _pageId) ? _pageId : null,
                          isExpanded: true,
                          decoration: websiteField('Page', helper: 'Visitors see the link only while the page is published.'),
                          items: [
                            for (final p in choosable)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  '${p.title.en.isNotEmpty ? p.title.en : p.slug}${widget.pages.firstWhere((e) => e.draft.id == p.id).live == null ? ' (not published)' : ''}',
                                  key: Key('website-link-page-${p.id}'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _pageId = v),
                        ),
                SiteNavTargetKind.external => TextField(
                  key: const Key('website-link-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: websiteField('Web address', hint: 'https://example.org/page', helper: 'Only complete https:// addresses. It opens in a new tab.'),
                ),
              },
              const SizedBox(height: 16),
              TextField(
                key: const Key('website-link-label-en'),
                controller: _labelEn,
                maxLength: SiteLayout.maxLabelLength,
                decoration: websiteField('Label (English)', helper: _kind == SiteNavTargetKind.external ? 'Required.' : 'Leave blank to use the page’s own name.'),
              ),
              const SizedBox(height: 8),
              TextField(key: const Key('website-link-label-ta'), controller: _labelTa, maxLength: SiteLayout.maxLabelLength, decoration: websiteField('Label (Tamil)')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('website-link-error'),
                    style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('website-link-save'), onPressed: _submit, child: Text(widget.entry == null ? 'Add' : 'Done')),
      ],
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({required this.languages, required this.language, required this.device, required this.onLanguage, required this.onDevice});

  final List<PublicLanguage> languages;
  final PublicLanguage language;
  final WebsiteLayoutPreviewDevice device;
  final ValueChanged<PublicLanguage> onLanguage;
  final ValueChanged<WebsiteLayoutPreviewDevice> onDevice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Preview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          SegmentedButton<WebsiteLayoutPreviewDevice>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: WebsiteLayoutPreviewDevice.desktop,
                label: Text('Desktop', key: Key('website-layout-preview-desktop')),
              ),
              ButtonSegment(
                value: WebsiteLayoutPreviewDevice.mobile,
                label: Text('Mobile', key: Key('website-layout-preview-mobile')),
              ),
            ],
            selected: {device},
            onSelectionChanged: (s) => onDevice(s.first),
          ),
          WebsiteLanguagePicker(languages: languages, selected: language, onChanged: onLanguage, keyPrefix: 'website-layout-preview'),
        ],
      ),
    );
  }
}

/// The real public header and footer (and, on mobile, the menu) drawn
/// with [layout] — the draft being edited — resolved against the published
/// pages, at desktop (1280 px, scaled to fit) or mobile (390 px) width.
/// Nothing is published or saved, and the preview can't be clicked.
class WebsiteSiteLayoutPreview extends StatelessWidget {
  const WebsiteSiteLayoutPreview({super.key, required this.layout, required this.publishedPages, required this.language, required this.device});

  /// A heading, a paragraph and buttons, drawn with the design.
  static final List<WebsiteBlock> _sample = [
    StructuredBlock(
      definition: BlockRegistry.cta,
      id: 'sample_cta',
      values: {
        'heading': const LocalizedText(en: 'A sample section', ta: 'மாதிரிப் பகுதி'),
        'body': const LocalizedText(en: 'Headings, text and buttons on every page use the site design.'),
        'buttons': [
          BlockItem(
            id: 'sample_button',
            values: {
              'label': const LocalizedText(en: 'A button'),
              'target': '/contact',
              'variant': 'primary',
            },
          ),
        ],
      },
    ),
  ];

  static const desktopWidth = 1280.0;
  static const mobileWidth = 390.0;

  final SiteLayout layout;
  final List<CustomPage> publishedPages;
  final PublicLanguage language;
  final WebsiteLayoutPreviewDevice device;

  @override
  Widget build(BuildContext context) {
    final mobile = device == WebsiteLayoutPreviewDevice.mobile;
    final width = mobile ? mobileWidth : desktopWidth;
    final chrome = PublicSiteChrome.resolve(layout, publishedPages);
    Widget sized(double w, double? h, Widget child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(size: Size(w, h ?? 900)),
      child: SizedBox(width: w, height: h, child: child),
    );

    final page = sized(
      width,
      null,
      Material(
        color: PublicColors.background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PublicHeader(currentRoute: '/'),
            // Sample content in the site design: palette and type changes
            // show here as they will on every page.
            Padding(
              key: const Key('website-layout-preview-sample'),
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: WebsiteBlocksView(blocks: _sample, media: const {}, language: language, interactive: false, spaced: false, fullBleed: true),
            ),
            const PublicFooter(),
          ],
        ),
      ),
    );
    final frames = <Widget>[
      _frame(mobile ? 'Mobile · 390 px' : 'Desktop · 1280 px', page, key: Key(mobile ? 'website-layout-preview-frame-mobile' : 'website-layout-preview-frame-desktop')),
      if (mobile) _frame('Mobile menu', sized(304, 560, const PublicMenuDrawer(currentRoute: '/')), key: const Key('website-layout-preview-frame-menu')),
    ];

    return WebsiteDesignScope(
      design: layout.design,
      child: ProviderScope(
        // A new scope per language: a changed overrideWith isn't applied to
        // an existing scope.
        key: ValueKey(language),
        overrides: [publicSiteChromeProvider.overrideWithValue(chrome), publicLanguageProvider.overrideWith((ref) => language)],
        // A picture of the site: links, language switch and account controls
        // do nothing here.
        child: IgnorePointer(
          child: ExcludeFocus(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: Wrap(spacing: 16, runSpacing: 16, children: frames),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(String caption, Widget child, {required Key key}) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: child),
          ),
        ],
      ),
    );
  }
}
