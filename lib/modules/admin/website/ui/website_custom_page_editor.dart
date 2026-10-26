import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/legacy_sections.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/translation/translation_coverage.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/public_routes.dart';
import '../../../public_website/public_strings.dart';
import '../../../public_website/public_website_theme.dart';
import '../../../public_website/ui/public_custom_page.dart';
import '../../../public_website/widgets/blocks/website_blocks_view.dart';
import '../data/website_content_admin_service.dart';
import '../../../public_website/content/website_site_layout.dart';
import '../../../public_website/widgets/public_scaffold.dart';
import 'page_builder/website_chrome_scope.dart';
import 'page_builder/website_visual_editor.dart';
import 'website_content_editors.dart';
import 'website_content_screen.dart';
import 'website_site_layout_editor.dart';

/// Asks for a new page's English/Tamil title and web address (suggested
/// from the English title until edited) and creates it as a draft.
/// Returns the new page, or null when cancelled.
Future<CustomPage?> showCreateCustomPageDialog(BuildContext context, {required WebsiteContentAdminService service, required AppUser user}) {
  return showDialog<CustomPage>(context: context, builder: (_) => _CreateCustomPageDialog(service: service, user: user));
}

class _CreateCustomPageDialog extends StatefulWidget {
  const _CreateCustomPageDialog({required this.service, required this.user});

  final WebsiteContentAdminService service;
  final AppUser user;

  @override
  State<_CreateCustomPageDialog> createState() => _CreateCustomPageDialogState();
}

class _CreateCustomPageDialogState extends State<_CreateCustomPageDialog> {
  final _titleEn = TextEditingController();
  final _titleTa = TextEditingController();
  final _slug = TextEditingController();
  bool _slugEdited = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_titleEn, _titleTa, _slug]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.service.createCustomPage(
        requesterRole: widget.user.role.toLowerCase(),
        actor: widget.user,
        title: LocalizedText(en: _titleEn.text, ta: _titleTa.text),
        slug: _slug.text,
      );
      if (mounted) Navigator.of(context).pop(page);
    } on WebsiteContentException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'The page could not be created. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = _slug.text.trim();
    final slugError = slug.isEmpty ? null : CustomPage.validateSlugFormat(slug);
    return AlertDialog(
      title: const Text('New page'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('website-new-page-title-en'),
                controller: _titleEn,
                maxLength: CustomPage.maxTitleLength,
                decoration: websiteField('Title (English)'),
                onChanged: (value) => setState(() {
                  if (!_slugEdited) _slug.text = CustomPage.slugify(value);
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('website-new-page-title-ta'),
                controller: _titleTa,
                maxLength: CustomPage.maxTitleLength,
                decoration: websiteField('Title (Tamil)', helper: 'If left blank, Tamil visitors see the English title.'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('website-new-page-slug'),
                controller: _slug,
                maxLength: 60,
                decoration: websiteField('Web address', helper: 'The page will be at ${PublicRoutes.customPage(slug.isEmpty ? '…' : slug)}').copyWith(
                  prefixText: PublicRoutes.customPagePrefix,
                  errorText: slugError,
                ),
                onChanged: (_) => setState(() => _slugEdited = true),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, key: const Key('website-new-page-error'), style: TextStyle(color: Colors.red.shade700)),
                ),
              const SizedBox(height: 8),
              const Text('New pages start as unpublished drafts and are not added to the navigation.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('website-new-page-create'),
          onPressed: _busy || _titleEn.text.trim().isEmpty || slug.isEmpty || slugError != null ? null : _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Edits an additional page: title, web address, introduction, optional
/// banner image and its sections (text, image with text, image grid, call
/// to action) in English and Tamil, whether it is listed in the navigation,
/// with a preview of the version being edited or the live one. Saves a
/// draft, publishes, unpublishes, archives or restores it.
class WebsiteCustomPageEditorScreen extends ConsumerStatefulWidget {
  const WebsiteCustomPageEditorScreen({super.key, required this.service, required this.user, required this.pageId});

  final WebsiteContentAdminService service;
  final AppUser user;
  final String pageId;

  @override
  ConsumerState<WebsiteCustomPageEditorScreen> createState() => _WebsiteCustomPageEditorScreenState();
}

class _WebsiteCustomPageEditorScreenState extends ConsumerState<WebsiteCustomPageEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  final _titleEn = TextEditingController();
  final _titleTa = TextEditingController();
  final _slug = TextEditingController();
  final _introEn = TextEditingController();
  final _introTa = TextEditingController();
  String? _heroId;
  List<CustomPageSection> _sections = const [];

  /// The page's blocks while editing a page built with blocks (the only
  /// editable copy of its content); null for a page made of sections.
  List<WebsiteBlock>? _blocks;
  bool _showInNavigation = false;

  /// The preview at mobile width (390 px) instead of the editor's width.
  bool _previewMobile = false;

  /// A site layout is published, so it — not [_showInNavigation] — decides
  /// whether this page is in the header and footer.
  bool _layoutPublished = false;

  /// The site layout being prepared (the draft, else what is live; null
  /// for the built-in one) and the published pages its links resolve
  /// against: the canvas shows the real header, footer and design with
  /// them.
  SiteLayout? _siteLayout;
  List<CustomPage> _publishedPages = const [];

  CustomPage? _draft;
  CustomPage? _live;
  List<WebsiteMedia> _library = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;

  /// Bumped whenever the fields are refilled, so per-section text fields
  /// (which hold their own text) start again from the loaded values.
  int _generation = 0;
  PublicLanguage _previewLanguage = PublicLanguage.english;

  /// The website's enabled languages (for the preview).
  List<PublicLanguage> _languages = PublicLanguage.builtIn;
  WebsitePreviewSource _previewSource = WebsitePreviewSource.editing;

  @override
  void initState() {
    super.initState();
    for (final c in [_titleEn, _titleTa, _slug, _introEn, _introTa]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_titleEn, _titleTa, _slug, _introEn, _introTa]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The loaded title and introduction: the form edits their English and
  /// Tamil; any other language is saved back unchanged.
  LocalizedText _baseTitle = const LocalizedText();
  LocalizedText _baseIntro = const LocalizedText();

  void _fill(CustomPage page) {
    _baseTitle = page.title;
    _baseIntro = page.intro;
    _titleEn.text = page.title.en;
    _titleTa.text = page.title.ta;
    _slug.text = page.slug;
    _introEn.text = page.intro.en;
    _introTa.text = page.intro.ta;
    _heroId = page.heroMediaId;
    _sections = [...page.sections];
    _blocks = page.blocks == null ? null : [...page.blocks!];
    _showInNavigation = page.showInNavigation;
    _generation++;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    var found = true;
    final ok = await attempt(() async {
      final page = await service.getCustomPage(requesterRole: role, pageId: widget.pageId);
      final library = await service.listMedia(requesterRole: role);
      final layout = await service.getSiteLayout(requesterRole: role);
      final languages = (await service.editorLanguageRegistry(requesterRole: role)).editorLanguages;
      final publishedPages = await service.publishedCustomPages(requesterRole: role);
      if (!mounted) return;
      _layoutPublished = layout.live != null;
      _siteLayout = layout.draft ?? layout.live;
      _publishedPages = publishedPages;
      _languages = languages;
      if (page == null) {
        found = false;
        return;
      }
      setState(() {
        _draft = page.draft;
        _live = page.live;
        _library = library;
        _fill(page.draft);
      });
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = !ok || !found;
      });
    }
  }

  /// The latest layout draft and published pages (after Site layout &
  /// design): only the canvas's header, footer and design change; the
  /// page's unsaved edits are kept.
  Future<void> _reloadSiteLayout() async {
    await attempt(() async {
      final layout = await service.getSiteLayout(requesterRole: role);
      final publishedPages = await service.publishedCustomPages(requesterRole: role);
      if (!mounted) return;
      setState(() {
        _layoutPublished = layout.live != null;
        _siteLayout = layout.draft ?? layout.live;
        _publishedPages = publishedPages;
      });
    });
  }

  Future<void> _refreshState() async {
    final page = await service.getCustomPage(requesterRole: role, pageId: widget.pageId);
    if (page != null && mounted) {
      setState(() {
        _draft = page.draft;
        _live = page.live;
      });
    }
  }

  CustomPage get _page => CustomPage(
        id: widget.pageId,
        slug: _slug.text.trim(),
        title: _baseTitle.copyWith(en: _titleEn.text, ta: _titleTa.text),
        intro: _baseIntro.copyWith(en: _introEn.text, ta: _introTa.text),
        heroMediaId: _heroId,
        sections: _sections,
        // For a page built with blocks, its blocks (its sections copy is
        // derived from them when saving).
        blocks: _blocks,
        showInNavigation: _showInNavigation,
        navOrder: _draft?.navOrder ?? 0,
        archived: _draft?.archived ?? false,
      );

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok) {
      refreshPublicSite();
      await _refreshState();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this page?'),
        content: const Text('It is taken off the website (its address shows “page not found”) and moved to Archived pages. You can restore it later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-custom-archive-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => service.archiveCustomPage(requesterRole: role, actor: user, pageId: widget.pageId), 'Archived.');
  }

  void _updateSection(int index, CustomPageSection section) => setState(() => _sections = [..._sections]..[index] = section);

  void _moveSection(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _sections.length) return;
    setState(() {
      final list = [..._sections];
      final item = list.removeAt(index);
      list.insert(target, item);
      _sections = list;
    });
  }

  /// Shows the page converted to blocks — as visitors would see it — and,
  /// when confirmed, uses the blocks in the editor. Nothing is saved until
  /// Save draft (Discard changes undoes it).
  Future<void> _convert(Map<String, WebsiteMedia> published) async {
    final converted = _page.convertedToBlocks();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert this page to blocks?'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Each of the ${_sections.length} sections becomes a block with the same content and languages. '
                  'The page looks the same to visitors (below), and keeps a sections copy for older versions of the app. '
                  'Nothing is saved until you save a draft; “Discard changes” undoes it.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text('Blocks: ${[for (final b in converted.blocks!) (b as StructuredBlock).definition.label].join(', ')}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Container(
                  key: const Key('website-custom-convert-preview'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: PublicColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: PublicColors.line)),
                  child: WebsiteBlocksView(blocks: converted.blocks!, media: published, language: _previewLanguage, interactive: false),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(key: const Key('website-custom-convert-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-custom-convert-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Convert')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _blocks = converted.blocks;
      _generation++;
    });
    showMessage('Converted in the editor. Save a draft to keep it, or discard the changes.');
  }

  /// Back to the last saved draft (all unsaved edits, including a
  /// conversion, are dropped).
  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('The page goes back to its last saved draft.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(key: const Key('website-custom-discard-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (confirmed != true || !mounted || _draft == null) return;
    setState(() => _fill(_draft!));
    showMessage('Changes discarded.');
  }

  /// Things to know about a page built with blocks that don't stop saving.
  List<String> _blockWarnings(List<WebsiteBlock> blocks) {
    final flat = BlockRegistry.flatten(blocks).toList();
    final unpublished = [
      for (final id in BlockRegistry.referencedMedia(blocks))
        if (_mediaById(id) case final m when m == null || !m.isPublished) id,
    ];
    final hidden = flat.whereType<StructuredBlock>().where((b) => b.hidden).length;
    final unsupported = flat.whereType<UnsupportedBlock>().length;
    final noCopy = blocks.where((b) => LegacySections.toSection(b) == null && !(b is StructuredBlock && b.hidden)).length;
    return [
      if (unpublished.isNotEmpty) '${unpublished.length} image(s) used here aren’t published: visitors don’t see them, and publishing the page is refused until they are.',
      if (hidden > 0) '$hidden block(s) hidden: kept, but not shown to visitors.',
      if (unsupported > 0) '$unsupported unsupported block(s): kept unchanged and not shown to visitors.',
      if (noCopy > 0) '$noCopy block(s) have no copy for older versions of the app, which show the page without them.',
    ];
  }

  WebsiteMedia? _mediaById(String? id) {
    for (final m in _library) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _sourceText(CustomPage draft, CustomPage? live) {
    if (draft.archived) return 'This page is archived. It is not on the website; restore it to edit and publish it again.';
    if (live == null) return 'You are editing a draft that is not published. Visitors to ${draft.route} see “page not found”.';
    if (!draft.samePublishedContentAs(live)) return 'You are editing a saved draft with unpublished changes. Visitors still see the published version.';
    return 'You are editing the published page that visitors see.';
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (_loading || _loadFailed || draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Page')),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('This page could not be loaded.'),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('website-custom-retry'), onPressed: _load, child: const Text('Try again')),
                  ],
                ),
        ),
      );
    }
    return _blocks == null ? _sectionsEditor(context, draft) : _visualEditor(context, draft);
  }

  /// The page's status chips: archived, draft or published; in the
  /// navigation; unsaved edits.
  List<Widget> _statusChips(CustomPage draft, CustomPage? live, bool unsaved) => [
        if (draft.archived)
          const WebsiteStatusChip(label: 'Archived', color: Color(0xFF6E6E73))
        else if (live == null)
          const WebsiteStatusChip(label: 'Draft', color: Color(0xFF6E6E73))
        else
          const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
        if (live != null && live.showInNavigation) const WebsiteStatusChip(label: 'In navigation', color: Color(0xFF2E7D5B)),
        if (unsaved) const WebsiteStatusChip(key: Key('website-custom-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
      ];

  /// Title, web address, introduction and banner image.
  List<Widget> _pageFields(CustomPage? live) {
    final slugError = CustomPage.validateSlugFormat(_slug.text.trim());
    final slugChangedWhileLive = live != null && live.slug != _slug.text.trim();
    return [
      TextField(key: const Key('website-custom-title-en'), controller: _titleEn, maxLength: CustomPage.maxTitleLength, decoration: websiteField('Title (English)')),
      const SizedBox(height: 8),
      TextField(
        key: const Key('website-custom-title-ta'),
        controller: _titleTa,
        maxLength: CustomPage.maxTitleLength,
        decoration: websiteField('Title (Tamil)', helper: 'If left blank, Tamil visitors see the English title.'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('website-custom-slug'),
        controller: _slug,
        maxLength: 60,
        decoration: websiteField(
          'Web address',
          helper: slugChangedWhileLive
              ? 'Publishing a new address breaks existing links to ${live.route}.'
              : 'Visitors open this page at ${PublicRoutes.customPage(_slug.text.trim())}',
        ).copyWith(prefixText: PublicRoutes.customPagePrefix, errorText: slugError),
      ),
      const SizedBox(height: 8),
      TextField(key: const Key('website-custom-intro-en'), controller: _introEn, maxLength: CustomPage.maxIntroLength, maxLines: 3, decoration: websiteField('Introduction (English, optional)')),
      const SizedBox(height: 8),
      TextField(key: const Key('website-custom-intro-ta'), controller: _introTa, maxLength: CustomPage.maxIntroLength, maxLines: 3, decoration: websiteField('Introduction (Tamil, optional)')),
      const WebsiteEditorSectionTitle('Banner image (optional)'),
      _ImageChooser(
        keyPrefix: 'website-custom-hero',
        media: _mediaById(_heroId),
        hasSelection: _heroId != null,
        onChoose: () async {
          final chosen = await showWebsiteImagePicker(context, _library, selected: _heroId);
          if (chosen != null) setState(() => _heroId = chosen);
        },
        onRemove: () => setState(() => _heroId = null),
      ),
    ];
  }

  List<Widget> _navigation() => [
        const WebsiteEditorSectionTitle('Navigation'),
        SwitchListTile(
          key: const Key('website-custom-show-in-nav'),
          contentPadding: EdgeInsets.zero,
          value: _showInNavigation,
          onChanged: (v) => setState(() => _showInNavigation = v),
          title: const Text('Show in the website navigation'),
          subtitle: Text(
            _layoutPublished
                ? 'Not used while a site layout is published: the header and footer links are set in Website → Site layout. '
                    'This setting applies again only if the site layout is unpublished.'
                : 'Takes effect when the page is published. Set the order in the Pages list. '
                    'Once a site layout is published, Site layout controls the navigation instead.',
            key: const Key('website-custom-nav-help'),
          ),
        ),
      ];

  Widget? _warningsBox(List<String> warnings, CustomPage draft) => warnings.isEmpty || draft.archived
      ? null
      : Container(
          key: const Key('website-custom-warnings'),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Good to know:', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final w in warnings) Text('• $w', style: const TextStyle(fontSize: 13)),
            ],
          ),
        );

  Widget? _readinessBox(List<TranslatableSource> sources) => _languages.length <= 1 || sources.isEmpty
      ? null
      : Container(
          key: const Key('website-custom-readiness'),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Translation readiness', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final l in _languages)
                if (l.code != PublicLanguage.sourceCode)
                  Builder(builder: (context) {
                    final r = InlineTranslationReadiness.of(sources, l.code);
                    return Text(
                      '${l.englishName}: ${r.translated} of ${r.total} texts have ${l.englishName} text (required: ${r.requiredTranslated} of ${r.requiredTotal}). Others show in the fallback language.',
                      key: Key('website-custom-readiness-${l.code}'),
                      style: const TextStyle(fontSize: 13),
                    );
                  }),
              const Text('Translation records and review come in a later step; nothing is created now.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        );

  Widget? _errorsBox(List<String> errors, CustomPage draft) => errors.isEmpty || draft.archived
      ? null
      : Container(
          key: const Key('website-custom-errors'),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFCEEEE), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fix before saving:', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final e in errors) Text('• $e', style: const TextStyle(fontSize: 13)),
            ],
          ),
        );

  /// Restore (archived), or save draft, publish, unpublish, discard and
  /// archive — the existing service calls and their checks.
  void _restore() => _run(() => service.restoreCustomPage(requesterRole: role, actor: user, pageId: widget.pageId), 'Restored as an unpublished draft.');

  void _saveDraft(CustomPage page, CustomPage? live) => _run(
        () => service.saveCustomPageDraft(requesterRole: role, actor: user, page: page),
        live == null ? 'Draft saved. It is not on the website yet.' : 'Draft saved. Visitors still see the published version.',
      );

  void _publish(CustomPage page) => _run(() => service.publishCustomPage(requesterRole: role, actor: user, page: page), 'Published at ${page.route}.');

  void _unpublish() => _run(() => service.unpublishCustomPage(requesterRole: role, actor: user, pageId: widget.pageId), 'Unpublished. Its address now shows “page not found”.');

  /// Restore, or save draft and publish: the main actions.
  List<Widget> _mainActions(CustomPage draft, CustomPage? live, CustomPage page) => [
        if (draft.archived)
          FilledButton.icon(key: const Key('website-custom-restore'), onPressed: _restore, icon: const Icon(Icons.unarchive_outlined), label: const Text('Restore'))
        else ...[
          OutlinedButton.icon(key: const Key('website-custom-save-draft'), onPressed: () => _saveDraft(page, live), icon: const Icon(Icons.save_outlined), label: const Text('Save draft')),
          FilledButton.icon(
            key: const Key('website-custom-publish'),
            onPressed: () => _publish(page),
            icon: const Icon(Icons.public),
            label: const Text('Publish'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
          ),
        ],
      ];

  /// Restore (archived), or save draft, publish, unpublish, discard and
  /// archive — the existing service calls and their checks.
  List<Widget> _actions(CustomPage draft, CustomPage? live, CustomPage page, bool unsaved) => [
        ..._mainActions(draft, live, page),
        if (!draft.archived) ...[
          if (live != null)
            TextButton.icon(key: const Key('website-custom-unpublish'), onPressed: _unpublish, icon: const Icon(Icons.visibility_off_outlined), label: const Text('Unpublish')),
          if (unsaved)
            TextButton.icon(key: const Key('website-custom-discard'), onPressed: _discard, icon: const Icon(Icons.undo), label: const Text('Discard changes')),
          TextButton.icon(key: const Key('website-custom-archive'), onPressed: _archive, icon: const Icon(Icons.archive_outlined), label: const Text('Archive')),
        ],
      ];

  /// On a phone, the toolbar's less used controls, in a menu: the version
  /// and width shown, Preview, and unpublish, discard and archive (the
  /// same actions, with the same confirmations).
  Widget _moreMenu(CustomPage draft, CustomPage? live, bool unsaved) {
    final previewingLive = _previewSource == WebsitePreviewSource.live;
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(key: Key('website-custom-more-$value'), value: value, child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(label))]));
    return PopupMenuButton<String>(
      key: const Key('website-custom-more'),
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'live':
            setState(() => _previewSource = previewingLive ? WebsitePreviewSource.editing : WebsitePreviewSource.live);
          case 'preview':
            setState(() => _previewOnly = !_previewOnly);
          case 'width':
            setState(() => _previewMobile = !_previewMobile);
          case 'unpublish':
            _unpublish();
          case 'discard':
            _discard();
          case 'archive':
            _archive();
        }
      },
      itemBuilder: (context) => [
        item('live', Icons.public, previewingLive ? 'Back to the version being edited' : 'Show the published version'),
        if (!previewingLive) item('preview', _previewOnly ? Icons.edit_outlined : Icons.visibility_outlined, _previewOnly ? 'Back to editing' : 'Preview as visitors see it'),
        item('width', _previewMobile ? Icons.desktop_windows_outlined : Icons.phone_iphone, _previewMobile ? 'Show at desktop width' : 'Show at phone width'),
        if (!draft.archived) ...[
          if (live != null) item('unpublish', Icons.visibility_off_outlined, 'Unpublish'),
          if (unsaved) item('discard', Icons.undo, 'Discard changes'),
          item('archive', Icons.archive_outlined, 'Archive'),
        ],
      ],
    );
  }

  Widget _desktopMobileSwitch() => SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.desktop_windows_outlined), label: Text('Desktop', key: Key('website-custom-preview-desktop'))),
          ButtonSegment(value: true, icon: Icon(Icons.phone_iphone), label: Text('Mobile', key: Key('website-custom-preview-mobile'))),
        ],
        selected: {_previewMobile},
        onSelectionChanged: (s) => setState(() => _previewMobile = s.first),
      );

  /// Shows the page as visitors see it, with no editing aids.
  bool _previewOnly = false;

  /// A page built with blocks: the visual editor (structure, canvas,
  /// properties) under a toolbar with the page's status, language,
  /// version, width, preview and the existing save and publish actions.
  Widget _visualEditor(BuildContext context, CustomPage draft) {
    final live = _live;
    final page = _page;
    final unsaved = !page.sameContentAs(draft);
    final errors = page.validationErrors();
    final previewingLive = _previewSource == WebsitePreviewSource.live;
    final published = {for (final m in _library) if (m.isPublished) m.id: m};
    final warnings = _blockWarnings(_blocks!);
    final sources = TranslatableSources.forCustomPage(page);
    final title = page.title.en.trim().isEmpty ? 'Page' : page.title.en.trim();
    final chrome = PublicSiteChrome.resolve(_siteLayout, _publishedPages);
    // A phone: the same width at which the editor shows one panel at a time.
    final narrow = MediaQuery.sizeOf(context).width < narrowEditorWidth;

    Widget? previewView;
    final notLive = previewingLive && live == null;
    if (previewingLive) {
      previewView = live == null
          ? const Padding(
              key: Key('website-custom-preview-not-live'),
              padding: EdgeInsets.all(24),
              child: Text('This page is not published: visitors see “page not found”.', style: TextStyle(color: AppColors.textSecondary)),
            )
          : PublicCustomPageBody(page: live, media: published, language: _previewLanguage, interactive: false);
    } else if (_previewOnly) {
      previewView = PublicCustomPageBody(page: page, media: published, language: _previewLanguage, interactive: false);
    }
    // Previews show the page in the site's real header and footer.
    if (previewView != null && !notLive) {
      previewView = WebsiteChromeScope(
        chrome: chrome,
        language: _previewLanguage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [PublicHeader(currentRoute: page.route), Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: previewView), const PublicFooter()],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              key: const Key('website-custom-toolbar'),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._statusChips(draft, live, unsaved),
                    if (errors.isNotEmpty && !draft.archived)
                      WebsiteStatusChip(key: const Key('website-custom-fix-count'), label: '${errors.length} to fix', color: const Color(0xFFB3261E)),
                    if (narrow) ...[
                      WebsiteLanguagePicker(languages: _languages, selected: _previewLanguage, onChanged: (l) => setState(() => _previewLanguage = l), keyPrefix: 'website-preview'),
                      ..._mainActions(draft, live, page),
                      _moreMenu(draft, live, unsaved),
                    ] else ...[
                      SegmentedButton<WebsitePreviewSource>(
                        key: const Key('website-preview-source'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: WebsitePreviewSource.editing, label: Text('Editing', key: Key('website-preview-editing'))),
                          ButtonSegment(value: WebsitePreviewSource.live, label: Text('Live', key: Key('website-preview-live'))),
                        ],
                        selected: {_previewSource},
                        onSelectionChanged: (s) => setState(() => _previewSource = s.first),
                      ),
                      WebsiteLanguagePicker(languages: _languages, selected: _previewLanguage, onChanged: (l) => setState(() => _previewLanguage = l), keyPrefix: 'website-preview'),
                      _desktopMobileSwitch(),
                      if (!previewingLive)
                        OutlinedButton.icon(
                          key: const Key('website-custom-preview-toggle'),
                          onPressed: () => setState(() => _previewOnly = !_previewOnly),
                          icon: Icon(_previewOnly ? Icons.edit_outlined : Icons.visibility_outlined),
                          label: Text(_previewOnly ? 'Back to editing' : 'Preview'),
                        ),
                      ..._actions(draft, live, page, unsaved),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: WebsiteVisualEditor(
                key: const Key('website-custom-blocks'),
                blocks: _blocks!,
                pageHeader: PublicCustomPageBody(page: page.copyWith(blocks: () => const []), media: published, language: _previewLanguage, interactive: false),
                design: chrome.design,
                siteHeader: WebsiteChromeScope(chrome: chrome, language: _previewLanguage, child: PublicHeader(currentRoute: page.route)),
                siteFooter: WebsiteChromeScope(chrome: chrome, language: _previewLanguage, child: const PublicFooter()),
                siteChromeInfo: (part) => openSiteDesignButton(context, service: service, user: user, onReturn: _reloadSiteLayout),
                onChanged: (list) => setState(() => _blocks = list),
                library: _library,
                media: published,
                language: _previewLanguage,
                generation: _generation,
                mobilePreview: _previewMobile,
                previewView: previewView,
                banner: WebsiteEditSourceBanner(key: const Key('website-custom-source'), text: _sourceText(draft, live), chips: const []),
                pageSettings: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [..._pageFields(live), ..._navigation(), ?_readinessBox(sources)],
                ),
                checks: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [?_errorsBox(errors, draft), ?_warningsBox(warnings, draft)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A page made of sections: the form editor, exactly as before, with the
  /// offer to convert it to blocks.
  Widget _sectionsEditor(BuildContext context, CustomPage draft) {
    final live = _live;
    final page = _page;
    final unsaved = !page.sameContentAs(draft);
    final errors = page.validationErrors();
    final previewingLive = _previewSource == WebsitePreviewSource.live;
    final published = {for (final m in _library) if (m.isPublished) m.id: m};
    final previewMedia = previewingLive ? published : {for (final m in _library) m.id: m};
    final sources = TranslatableSources.forCustomPage(page);

    return WebsiteEditorFrame(
      title: page.title.en.trim().isEmpty ? 'Page' : page.title.en.trim(),
      busy: _busy,
      children: [
        WebsiteEditSourceBanner(key: const Key('website-custom-source'), text: _sourceText(draft, live), chips: _statusChips(draft, live, unsaved)),
        const WebsiteEditorSectionTitle('Page'),
        ..._pageFields(live),
        const WebsiteEditorSectionTitle('Sections'),
        if (_sections.isEmpty) const Text('No sections yet.', style: TextStyle(color: AppColors.textSecondary)),
        for (var i = 0; i < _sections.length; i++)
          _SectionEditor(
            key: ValueKey('website-custom-section-${_sections[i].id}-$_generation'),
            section: _sections[i],
            index: i,
            count: _sections.length,
            library: _library,
            onChanged: (s) => _updateSection(i, s),
            onMove: (delta) => _moveSection(i, delta),
            onRemove: () => setState(() => _sections = [..._sections]..removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<CustomSectionType>(
            key: const Key('website-custom-add-section'),
            enabled: _sections.length < CustomPage.maxSections,
            onSelected: (type) => setState(() => _sections = [..._sections, CustomPageSection.create(type)]),
            itemBuilder: (context) => [
              for (final type in CustomSectionType.values) PopupMenuItem(key: Key('website-custom-add-${type.id}'), value: type, child: Text(type.adminLabel)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: AppColors.primary), SizedBox(width: 6), Text('Add section', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))]),
            ),
          ),
        ),
        if (!draft.archived)
          Container(
            key: const Key('website-custom-convert-offer'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Use the page builder (columns, buttons, dividers and more) for this page.', style: TextStyle(fontSize: 13)),
                OutlinedButton.icon(
                  key: const Key('website-custom-convert'),
                  onPressed: () => _convert(published),
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
                  label: const Text('Convert to blocks…'),
                ),
              ],
            ),
          ),
        ..._navigation(),
        WebsitePreviewControls(
          languages: _languages,
          source: _previewSource,
          language: _previewLanguage,
          onSource: (s) => setState(() => _previewSource = s),
          onLanguage: (l) => setState(() => _previewLanguage = l),
        ),
        Padding(padding: const EdgeInsets.only(bottom: 8), child: _desktopMobileSwitch()),
        if (previewingLive && live == null)
          const Padding(
            key: Key('website-custom-preview-not-live'),
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('This page is not published: visitors see “page not found”.', style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          Container(
            key: const Key('website-custom-preview'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(color: PublicColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: PublicColors.line)),
            child: _previewMobile
                ? Center(
                    child: SizedBox(
                      key: const Key('website-custom-preview-mobile-frame'),
                      width: 390,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
                        child: PublicCustomPageBody(page: previewingLive ? live! : page, media: previewMedia, language: _previewLanguage, interactive: false),
                      ),
                    ),
                  )
                : PublicCustomPageBody(page: previewingLive ? live! : page, media: previewMedia, language: _previewLanguage, interactive: false),
          ),
        ?_readinessBox(sources),
        ?_errorsBox(errors, draft),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: _actions(draft, live, page, unsaved)),
      ],
    );
  }
}

class _ImageChooser extends StatelessWidget {
  const _ImageChooser({required this.keyPrefix, required this.media, required this.hasSelection, required this.onChoose, required this.onRemove});

  final String keyPrefix;
  final WebsiteMedia? media;
  final bool hasSelection;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final media = this.media;
    return Row(
      children: [
        WebsiteMediaThumb(media: media, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                media == null ? (hasSelection ? 'The chosen image no longer exists.' : 'No image') : (media.alt.en.isNotEmpty ? media.alt.en : 'No alt text yet'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (media != null && !media.isPublished)
                const Text('Not published yet — publish it before publishing the page.', style: TextStyle(fontSize: 12, color: Color(0xFF8A6A33))),
              Wrap(
                children: [
                  TextButton(key: Key('$keyPrefix-choose'), onPressed: onChoose, child: Text(hasSelection ? 'Change image' : 'Choose image')),
                  if (hasSelection) TextButton(key: Key('$keyPrefix-remove'), onPressed: onRemove, child: const Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One section's fields. Text fields keep their own text (initialised from
/// [section]) and report every change through [onChanged].
class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    super.key,
    required this.section,
    required this.index,
    required this.count,
    required this.library,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
  });

  final CustomPageSection section;
  final int index;
  final int count;
  final List<WebsiteMedia> library;
  final ValueChanged<CustomPageSection> onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  WebsiteMedia? _media(String? id) {
    for (final m in library) {
      if (m.id == id) return m;
    }
    return null;
  }

  Widget _field(String name, String label, String initial, ValueChanged<String> onText, {int maxLines = 1, int? maxLength, String? helper, String? error}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(
          key: Key('website-section-${section.id}-$name'),
          initialValue: initial,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: websiteField(label, helper: helper).copyWith(errorText: error),
          onChanged: onText,
        ),
      );

  /// English and Tamil fields for one [LocalizedText] of the section;
  /// [apply] returns the section with that text replaced.
  List<Widget> _pair(String name, String label, LocalizedText value, CustomPageSection Function(LocalizedText) apply, {int maxLines = 1, int? maxLength}) => [
        // Other languages in [value] are kept.
        _field('$name-en', '$label (English)', value.en, (v) => onChanged(apply(value.copyWith(en: v))), maxLines: maxLines, maxLength: maxLength),
        _field('$name-ta', '$label (Tamil)', value.ta, (v) => onChanged(apply(value.copyWith(ta: v))), maxLines: maxLines, maxLength: maxLength),
      ];

  @override
  Widget build(BuildContext context) {
    final s = section;
    final heading = _pair('heading', 'Heading', s.heading, (t) => s.copyWith(heading: t), maxLength: CustomPage.maxHeadingLength);
    final body = _pair('body', 'Text', s.body, (t) => s.copyWith(body: t), maxLines: 5, maxLength: CustomPage.maxBodyLength);
    return Card(
      key: Key('website-custom-section-$index'),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('${index + 1}. ${s.type.adminLabel}', style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(key: Key('website-section-${s.id}-up'), tooltip: 'Move up', onPressed: index == 0 ? null : () => onMove(-1), icon: const Icon(Icons.arrow_upward)),
                IconButton(key: Key('website-section-${s.id}-down'), tooltip: 'Move down', onPressed: index == count - 1 ? null : () => onMove(1), icon: const Icon(Icons.arrow_downward)),
                IconButton(key: Key('website-section-${s.id}-remove'), tooltip: 'Remove section', onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            ...switch (s.type) {
              CustomSectionType.text => [...heading, ...body],
              CustomSectionType.imageText => [
                  _ImageChooser(
                    keyPrefix: 'website-section-${s.id}-image',
                    media: _media(s.mediaId),
                    hasSelection: s.mediaId != null,
                    onChoose: () async {
                      final chosen = await showWebsiteImagePicker(context, library, selected: s.mediaId);
                      if (chosen != null) onChanged(s.copyWith(mediaId: () => chosen));
                    },
                    onRemove: () => onChanged(s.copyWith(mediaId: () => null)),
                  ),
                  SwitchListTile(
                    key: Key('website-section-${s.id}-image-right'),
                    contentPadding: EdgeInsets.zero,
                    value: s.imageOnRight,
                    onChanged: (v) => onChanged(s.copyWith(imageOnRight: v)),
                    title: const Text('Image on the right (wide screens)'),
                  ),
                  ...heading,
                  ...body,
                ],
              CustomSectionType.imageGrid => [
                  ...heading,
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in s.mediaIds)
                        Stack(
                          children: [
                            WebsiteMediaThumb(media: _media(id), size: 64),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                key: Key('website-section-${s.id}-grid-remove-$id'),
                                onTap: () => onChanged(s.copyWith(mediaIds: [...s.mediaIds]..remove(id))),
                                child: Container(
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      OutlinedButton.icon(
                        key: Key('website-section-${s.id}-grid-add'),
                        onPressed: s.mediaIds.length >= CustomPage.maxGridImages
                            ? null
                            : () async {
                                final chosen = await showWebsiteImagePicker(context, [for (final m in library) if (!s.mediaIds.contains(m.id)) m]);
                                if (chosen != null) onChanged(s.copyWith(mediaIds: [...s.mediaIds, chosen]));
                              },
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add image'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Each image shows its own caption and alt text from the Media library.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ],
              CustomSectionType.callToAction => [
                  ...heading,
                  ...body,
                  ..._pair('button', 'Button label', s.buttonLabel, (t) => s.copyWith(buttonLabel: t), maxLength: CustomPage.maxButtonLength),
                  _field(
                    'target',
                    'Button link',
                    s.target,
                    (v) => onChanged(s.copyWith(target: v)),
                    helper: 'A page of this website (e.g. /admissions or /pages/open-day), or an https://, mailto: or tel: link.',
                    error: s.target.trim().isEmpty ? null : SafeLinkTarget.validate(s.target),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }
}

/// "Open Site layout & design": the shared header, footer and design are
/// edited (and previewed and published) there; [onReturn] reloads the
/// editor afterwards so its canvas shows the latest draft.
Widget openSiteDesignButton(BuildContext context, {required WebsiteContentAdminService service, required AppUser user, required VoidCallback onReturn}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      key: const Key('website-open-site-design'),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebsiteSiteLayoutEditorScreen(service: service, user: user)));
        onReturn();
      },
      icon: const Icon(Icons.palette_outlined),
      label: const Text('Open Site layout & design'),
    ),
  );
}
