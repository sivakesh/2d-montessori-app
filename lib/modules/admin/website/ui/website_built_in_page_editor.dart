import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../auth/providers/auth_state_provider.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_site_layout.dart';
import '../../../public_website/public_strings.dart';
import '../../../public_website/ui/public_gallery_page.dart';
import '../../../public_website/ui/public_home_page.dart';
import '../../../public_website/ui/public_section_page.dart';
import '../../../public_website/widgets/public_scaffold.dart';
import '../data/website_content_admin_service.dart';
import 'page_builder/website_chrome_scope.dart';
import 'page_builder/website_visual_editor.dart';
import 'website_content_editors.dart';
import 'website_content_screen.dart';
import 'website_custom_page_editor.dart';

/// The public page widget for [page] (what visitors open at its address),
/// drawn with [content] — the same code path as the live site, so a
/// comparison or preview shows exactly what visitors would see. It runs in
/// its own provider container (a signed-out visitor's view of [content]
/// and the published [media]), separate from the admin app's.
class BuiltInPagePreview extends StatefulWidget {
  const BuiltInPagePreview({
    super.key,
    required this.page,
    required this.content,
    required this.media,
    required this.language,
    required this.mobile,
    this.height,
  });

  final BuiltInPage page;
  final LiveWebsiteContent content;

  /// The published images.
  final List<WebsiteMedia> media;
  final PublicLanguage language;
  final bool mobile;

  /// The frame's height (the page scrolls inside it); a tall default.
  final double? height;

  @override
  State<BuiltInPagePreview> createState() => _BuiltInPagePreviewState();
}

class _BuiltInPagePreviewState extends State<BuiltInPagePreview> {
  late ProviderContainer _container = _create();

  ProviderContainer _create() => ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        liveWebsiteContentProvider.overrideWith((ref) async => widget.content),
        publishedWebsiteMediaProvider.overrideWith((ref) async => widget.media),
        publicLanguageProvider.overrideWith((ref) => widget.language),
      ]);

  @override
  void didUpdateWidget(BuiltInPagePreview old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content || old.media != widget.media || old.language != widget.language) {
      final previous = _container;
      _container = _create();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  Widget get _page => switch (widget.page) {
        BuiltInPage.home => const PublicHomePage(),
        BuiltInPage.gallery => const PublicGalleryPage(),
        _ => PublicSectionPage(route: widget.page.route),
      };

  @override
  Widget build(BuildContext context) {
    final width = widget.mobile ? 390.0 : 1280.0;
    final h = widget.height ?? (widget.mobile ? 2600.0 : 2000.0);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: h,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, h)),
              child: UncontrolledProviderScope(
                key: ObjectKey(_container),
                container: _container,
                // A picture of the page: nothing inside reacts.
                child: IgnorePointer(child: ExcludeFocus(child: _page)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits a built-in page (Home, Admissions, Teacher Training, Programs,
/// Gallery, Contact) with the visual editor.
///
/// A page not yet built with blocks is shown twice, side by side, through
/// the real public page: as it is today, and as converted to blocks
/// ([BuiltInPageAdapter]: every text in English and Tamil, the page's
/// managed headline, introduction and image). Nothing changes until the
/// admin chooses "Use the visual editor"; even then nothing is saved until
/// Save draft, and nothing is public until Publish. "Return to the
/// built-in page" removes the blocks again (the page's managed headline,
/// introduction and image are always kept, for older versions of the app).
class WebsiteBuiltInPageEditorScreen extends ConsumerStatefulWidget {
  const WebsiteBuiltInPageEditorScreen({super.key, required this.service, required this.user, required this.page});

  final WebsiteContentAdminService service;
  final AppUser user;
  final BuiltInPage page;

  @override
  ConsumerState<WebsiteBuiltInPageEditorScreen> createState() => _WebsiteBuiltInPageEditorScreenState();
}

class _WebsiteBuiltInPageEditorScreenState extends ConsumerState<WebsiteBuiltInPageEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  BuiltInPage get _pageId => widget.page;

  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  /// Saved draft blocks and published blocks (null: not built with blocks
  /// there).
  List<WebsiteBlock>? _draftBlocks;
  List<WebsiteBlock>? _liveBlocks;

  /// The blocks being edited; null while the page is still its built-in
  /// self in the editor.
  List<WebsiteBlock>? _blocks;
  WebsitePageContent? _content;

  /// The managed content published for the built-in page (heading,
  /// introduction, image), as visitors see it while no blocks are
  /// published; null when nothing is published (or for Contact).
  WebsitePageContent? _liveContent;
  List<WebsiteMedia> _library = const [];
  List<PublicLanguage> _languages = PublicLanguage.builtIn;
  SiteLayout? _siteLayout;
  List<CustomPage> _publishedPages = const [];
  int _generation = 0;
  PublicLanguage _language = PublicLanguage.english;
  bool _mobile = false;
  bool _previewOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final ok = await attempt(() async {
      final page = await service.getBuiltInPage(requesterRole: role, page: _pageId);
      final library = await service.listMedia(requesterRole: role);
      final layout = await service.getSiteLayout(requesterRole: role);
      final languages = (await service.editorLanguageRegistry(requesterRole: role)).editorLanguages;
      final publishedPages = await service.publishedCustomPages(requesterRole: role);
      if (!mounted) return;
      setState(() {
        _draftBlocks = page.draft;
        _liveBlocks = page.live;
        _blocks = page.draft == null ? null : [...page.draft!];
        _content = page.content;
        _liveContent = page.liveContent;
        _library = library;
        _languages = languages;
        _siteLayout = layout.draft ?? layout.live;
        _publishedPages = publishedPages;
        _generation++;
      });
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = !ok;
      });
    }
  }

  Future<void> _reloadSiteLayout() async {
    await attempt(() async {
      final layout = await service.getSiteLayout(requesterRole: role);
      final publishedPages = await service.publishedCustomPages(requesterRole: role);
      if (mounted) {
        setState(() {
          _siteLayout = layout.draft ?? layout.live;
          _publishedPages = publishedPages;
        });
      }
    });
  }

  List<WebsiteMedia> get _published => [for (final m in _library) if (m.isPublished) m];

  /// What visitors would get with [blocks] (null: the built-in page), and
  /// this page's managed content.
  LiveWebsiteContent _contentWith(List<WebsiteBlock>? blocks) {
    final slot = _pageId.slot;
    return LiveWebsiteContent(
      pages: {if (slot != null && _content != null) slot: _content!},
      customPages: _publishedPages,
      layout: _siteLayout,
      builtInBlocks: {_pageId.id: ?blocks},
    );
  }

  static String _encode(List<WebsiteBlock>? blocks) => blocks == null ? 'null' : jsonEncode(BlockRegistry.toMapList(blocks), toEncodable: (o) => o.toString());

  bool get _unsaved => _encode(_blocks) != _encode(_draftBlocks);

  /// The published blocks aren't what publishing the saved draft would
  /// store (hidden blocks are never published).
  bool get _draftUnpublished => _liveBlocks != null && _draftBlocks != null && _encode(_liveBlocks) != _encode(BlockRegistry.withoutHidden(_draftBlocks!));

  /// Runs [action]; whether it succeeded. Afterwards — even when it
  /// failed part-way — the saved draft and published blocks are read
  /// again, so the status shows what is actually stored. The blocks being
  /// edited are never touched here.
  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok) refreshPublicSite();
    await _refreshSaved();
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<void> _refreshSaved() async {
    try {
      final page = await service.getBuiltInPage(requesterRole: role, page: _pageId);
      if (mounted) {
        setState(() {
          _draftBlocks = page.draft;
          _liveBlocks = page.live;
          _liveContent = page.liveContent;
        });
      }
    } catch (_) {
      // Offline: the status stays as last read; the action's own error
      // has already been shown.
    }
  }

  Future<bool> _confirm(String title, String body, String action, Key key) async {
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

  void _convert() {
    setState(() {
      _blocks = BuiltInPageAdapter.blocksFor(_pageId, _content);
      _generation++;
    });
    showMessage('The page is in the visual editor. Save a draft to keep it; visitors see no change until you publish.');
  }

  Future<void> _discard() async {
    if (!await _confirm('Discard unsaved changes?', 'The page goes back to its last saved draft.', 'Discard', const Key('website-builtin-discard-confirm'))) return;
    setState(() {
      _blocks = _draftBlocks == null ? null : [..._draftBlocks!];
      _generation++;
    });
  }

  /// Whether visitors see something published for this page that
  /// publishing blocks replaces: published blocks, or a heading,
  /// introduction or (published) image published with the form editor.
  /// Text stored blank means the site's own wording, which is not a
  /// published version.
  bool get _hasPublishedVersion {
    if (_liveBlocks != null) return true;
    final live = _liveContent;
    if (live == null) return false;
    final image = live.imageMediaId;
    return !live.headline.isEmpty || !live.intro.isEmpty || (image != null && _library.any((m) => m.id == image && m.isPublished));
  }

  /// Publishes [blocks]; over a published version, only once confirmed.
  Future<void> _publish(List<WebsiteBlock> blocks) async {
    if (_hasPublishedVersion && !await confirmReplacePublished(const Key('website-builtin-publish-confirm'))) return;
    await _run(() => service.publishBuiltInPage(requesterRole: role, actor: user, page: _pageId, blocks: blocks), 'Published at ${_pageId.route}.');
  }

  Future<void> _unpublish() async {
    if (!await _confirm(
      'Take the blocks off the website?',
      'Visitors see the built-in ${_pageId.label} page again (with its published heading, introduction and image, if any). The draft keeps its blocks.',
      'Unpublish',
      const Key('website-builtin-unpublish-confirm'),
    )) {
      return;
    }
    await _run(() => service.unpublishBuiltInPage(requesterRole: role, actor: user, page: _pageId), 'Unpublished. Visitors see the built-in page.');
  }

  Future<void> _revert() async {
    if (!await _confirm(
      'Return to the built-in page?',
      'The blocks are removed from the draft and from the website, and the page shows its built-in content again. '
          'Its heading, introduction and image are kept. You can convert it again at any time.',
      'Return to the built-in page',
      const Key('website-builtin-revert-confirm'),
    )) {
      return;
    }
    final ok = await _run(() async {
      try {
        await service.revertBuiltInPage(requesterRole: role, actor: user, page: _pageId);
      } on UnauthorizedWebsiteContentException {
        rethrow;
      } catch (_) {
        throw WebsiteContentException('The page could not be returned to its built-in content. The status shows what is saved now, and your edits are kept. Please try again.');
      }
    }, 'The page is its built-in self again.');
    // Only once the blocks are gone everywhere; otherwise the editor keeps
    // the blocks being edited, with the status read back from what is saved.
    if (!ok || !mounted) return;
    setState(() {
      _draftBlocks = null;
      _liveBlocks = null;
      _blocks = null;
      _generation++;
    });
  }

  List<String> _warnings(List<WebsiteBlock> blocks) {
    final unpublished = [
      for (final id in BlockRegistry.referencedMedia(blocks))
        if (!_library.any((m) => m.id == id && m.isPublished)) id,
    ];
    final hidden = BlockRegistry.flatten(blocks).whereType<StructuredBlock>().where((b) => b.hidden).length;
    final unsupported = BlockRegistry.flatten(blocks).whereType<UnsupportedBlock>().length;
    return [
      if (unpublished.isNotEmpty) '${unpublished.length} image(s) used here aren’t published: visitors don’t see them, and publishing the page is refused until they are.',
      if (hidden > 0) '$hidden block(s) hidden: kept, but not shown to visitors.',
      if (unsupported > 0) '$unsupported unsupported block(s): kept unchanged and not shown to visitors.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_pageId.label} · visual editor';
    if (_loading || _loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : OutlinedButton(key: const Key('website-builtin-retry'), onPressed: _load, child: const Text('Try again')),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: AbsorbPointer(absorbing: _busy, child: _blocks == null ? _comparison(context) : _editor(context)),
    );
  }

  Widget _languageAndWidth() => Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          WebsiteLanguagePicker(languages: _languages, selected: _language, onChanged: (l) => setState(() => _language = l), keyPrefix: 'website-preview'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.desktop_windows_outlined), label: Text('Desktop', key: Key('website-builtin-desktop'))),
              ButtonSegment(value: true, icon: Icon(Icons.phone_iphone), label: Text('Mobile', key: Key('website-builtin-mobile'))),
            ],
            selected: {_mobile},
            onSelectionChanged: (s) => setState(() => _mobile = s.first),
          ),
        ],
      );

  /// Not built with blocks yet: today's page and the converted page, side
  /// by side, through the real public page.
  Widget _comparison(BuildContext context) {
    final converted = BuiltInPageAdapter.blocksFor(_pageId, _content);
    final published = _published;
    Widget frame(String caption, Key key, List<WebsiteBlock>? blocks) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(caption, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                key: key,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.white),
                child: BuiltInPagePreview(page: _pageId, content: _contentWith(blocks), media: published, language: _language, mobile: _mobile),
              ),
            ],
          ),
        );
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 840;
      final today = frame('Today', const Key('website-builtin-compare-current'), null);
      final blocks = frame('Built with blocks (not saved)', const Key('website-builtin-compare-blocks'), converted);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            key: const Key('website-builtin-intro'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_pageId.label} is the website’s built-in page', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'To edit it visually, it is rebuilt from sections and blocks with the same wording (English and Tamil), images and links${_pageId.slot == null ? '' : ', including your published heading, introduction and image'}. '
                  'Compare the two below. Nothing changes until you choose to use the visual editor, nothing is saved until you save a draft, '
                  'and visitors see the built-in page until you publish. You can return to the built-in page at any time.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('website-builtin-convert'),
                      onPressed: _convert,
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Use the visual editor for this page'),
                    ),
                    _languageAndWidth(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (narrow) ...[
            Row(children: [today]),
            const SizedBox(height: 16),
            Row(children: [blocks]),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [today, const SizedBox(width: 16), blocks]),
        ],
      );
    });
  }

  Widget _editor(BuildContext context) {
    final blocks = _blocks!;
    final chrome = PublicSiteChrome.resolve(_siteLayout, _publishedPages);
    final errors = BlockRegistry.validate(blocks);
    final warnings = _warnings(blocks);
    final published = {for (final m in _published) m.id: m};
    final unsaved = _unsaved;
    final narrow = MediaQuery.sizeOf(context).width < narrowEditorWidth;
    final status = [
      if (_liveBlocks != null)
        const WebsiteStatusChip(label: 'Published with blocks', color: Color(0xFF2E7D5B))
      else
        const WebsiteStatusChip(label: 'Visitors see the built-in page', color: Color(0xFF6E6E73)),
      if (_draftBlocks == null) const WebsiteStatusChip(key: Key('website-builtin-not-saved'), label: 'Converted, not saved', color: Color(0xFF8A6A33)),
      if (_draftUnpublished) const WebsiteStatusChip(key: Key('website-builtin-draft-unpublished'), label: 'Draft not published', color: Color(0xFF8A6A33)),
      if (unsaved) const WebsiteStatusChip(key: Key('website-builtin-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
      if (errors.isNotEmpty) WebsiteStatusChip(key: const Key('website-builtin-fix-count'), label: '${errors.length} to fix', color: const Color(0xFFB3261E)),
    ];
    final actions = [
      OutlinedButton.icon(
        key: const Key('website-builtin-save-draft'),
        onPressed: () => _run(() => service.saveBuiltInPageDraft(requesterRole: role, actor: user, page: _pageId, blocks: blocks), 'Draft saved. Visitors see no change until you publish.'),
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save draft'),
      ),
      FilledButton.icon(
        key: const Key('website-builtin-publish'),
        onPressed: () => _publish(blocks),
        icon: const Icon(Icons.public),
        label: const Text('Publish'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
      ),
    ];
    final more = <(String, String, IconData, VoidCallback)>[
      ('preview', _previewOnly ? 'Back to editing' : 'Preview as visitors see it', _previewOnly ? Icons.edit_outlined : Icons.visibility_outlined, () => setState(() => _previewOnly = !_previewOnly)),
      if (unsaved) ('discard', 'Discard changes', Icons.undo, _discard),
      if (_liveBlocks != null) ('unpublish', 'Unpublish the blocks', Icons.visibility_off_outlined, _unpublish),
      if (_draftBlocks != null || _liveBlocks != null) ('revert', 'Return to the built-in page', Icons.history, _revert),
    ];
    final preview = _previewOnly
        ? Container(
            key: const Key('website-builtin-preview'),
            color: Colors.white,
            child: BuiltInPagePreview(page: _pageId, content: _contentWith(blocks), media: _published, language: _language, mobile: _mobile),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: const Key('website-builtin-toolbar'),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...status,
                if (!narrow) _languageAndWidth() else WebsiteLanguagePicker(languages: _languages, selected: _language, onChanged: (l) => setState(() => _language = l), keyPrefix: 'website-preview'),
                ...actions,
                if (narrow)
                  PopupMenuButton<VoidCallback>(
                    key: const Key('website-builtin-more'),
                    tooltip: 'More',
                    onSelected: (action) => action(),
                    itemBuilder: (context) => [
                      PopupMenuItem(key: const Key('website-builtin-more-width'), value: () => setState(() => _mobile = !_mobile), child: Text(_mobile ? 'Show at desktop width' : 'Show at phone width')),
                      for (final (id, label, _, action) in more) PopupMenuItem(key: Key('website-builtin-more-$id'), value: action, child: Text(label)),
                    ],
                  )
                else
                  for (final (id, label, icon, action) in more) TextButton.icon(key: Key('website-builtin-$id'), onPressed: action, icon: Icon(icon), label: Text(label)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: WebsiteVisualEditor(
            key: const Key('website-builtin-blocks'),
            blocks: blocks,
            onChanged: (list) => setState(() => _blocks = list),
            library: _library,
            media: published,
            language: _language,
            generation: _generation,
            mobilePreview: _mobile,
            previewView: preview,
            design: chrome.design,
            siteHeader: WebsiteChromeScope(chrome: chrome, language: _language, child: PublicHeader(currentRoute: _pageId.route)),
            siteFooter: WebsiteChromeScope(chrome: chrome, language: _language, child: const PublicFooter()),
            siteChromeInfo: (part) => openSiteDesignButton(context, service: service, user: user, onReturn: _reloadSiteLayout),
            banner: WebsiteEditSourceBanner(
              key: const Key('website-builtin-source'),
              text: _liveBlocks == null
                  ? 'You are editing ${_pageId.label} with blocks. Visitors still see the built-in page until you publish.'
                  : 'You are editing ${_pageId.label}, published with blocks at ${_pageId.route}. Changes reach visitors when you publish.',
              chips: const [],
            ),
            pageSettings: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_pageId.label} — ${_pageId.route}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  'A built-in page: its address and place in the navigation are fixed (the navigation is set in Site layout & design). '
                  'Select a section or block to edit it, or add sections with the + points.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  _pageId.slot == null
                      ? 'Older versions of the app show the built-in Contact page.'
                      : 'Older versions of the app show the page’s built-in content with its managed heading, introduction and image, which are kept.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            checks: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (errors.isNotEmpty)
                  Container(
                    key: const Key('website-builtin-errors'),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [const Text('Fix before saving:', style: TextStyle(fontWeight: FontWeight.w600)), for (final e in errors) Text('• $e', style: const TextStyle(fontSize: 13))],
                    ),
                  ),
                if (warnings.isNotEmpty)
                  Container(
                    key: const Key('website-builtin-warnings'),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [const Text('Good to know:', style: TextStyle(fontWeight: FontWeight.w600)), for (final w in warnings) Text('• $w', style: const TextStyle(fontSize: 13))],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
