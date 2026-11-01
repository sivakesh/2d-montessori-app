import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/public_strings.dart';
import '../../../public_website/public_website_theme.dart';
import '../../../public_website/widgets/public_website_image.dart';
import '../data/website_content_admin_service.dart';
import 'website_built_in_page_editor.dart';
import 'website_content_screen.dart';

/// Shared frame: a centred, scrollable column at a comfortable width.
class WebsiteEditorFrame extends StatelessWidget {
  const WebsiteEditorFrame({super.key, required this.title, required this.children, this.busy = false});

  final String title;
  final List<Widget> children;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(title),
        bottom: busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebsiteEditorSectionTitle extends StatelessWidget {
  const WebsiteEditorSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );
}

InputDecoration websiteField(String label, {String? helper, String? hint}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      hintText: hint,
      hintMaxLines: 3,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    );

/// Whether admins edit website and form text in more than one language.
///
/// English only for now: Tamil (and other languages) will come back with
/// the language module, which enables a language, translates the English
/// with AI and lets admins review it. Meanwhile no editor shows a Tamil
/// field or a preview-language switch. Text already stored in another
/// language is kept as it is (the editors still carry it when saving),
/// and the public website still shows it.
const multilingualEditing = false;

// ------------------------------------------------------------------ media

/// Edits one library image: focal point (with crop previews at each
/// aspect ratio the website uses), alt text and captions in English and
/// Tamil, category, gallery listing and consent; publish/hide, replace the
/// file, or delete it.
class WebsiteMediaEditorScreen extends ConsumerStatefulWidget {
  const WebsiteMediaEditorScreen({super.key, required this.service, required this.user, required this.media});

  final WebsiteContentAdminService service;
  final AppUser user;
  final WebsiteMedia media;

  @override
  ConsumerState<WebsiteMediaEditorScreen> createState() => _WebsiteMediaEditorScreenState();
}

class _WebsiteMediaEditorScreenState extends ConsumerState<WebsiteMediaEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  late WebsiteMedia _media = widget.media;
  late final _altEn = TextEditingController(text: _media.alt.en);
  late final _altTa = TextEditingController(text: _media.alt.ta);
  late final _captionEn = TextEditingController(text: _media.caption.en);
  late final _captionTa = TextEditingController(text: _media.caption.ta);
  late GalleryCategory _category = _media.category;
  late bool _inGallery = _media.inGallery;
  late bool _consent = _media.consentConfirmed;
  late double _focalX = _media.focalX;
  late double _focalY = _media.focalY;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_altEn, _altTa, _captionEn, _captionTa]) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetFrom(WebsiteMedia media) {
    _media = media;
    _altEn.text = media.alt.en;
    _altTa.text = media.alt.ta;
    _captionEn.text = media.caption.en;
    _captionTa.text = media.caption.ta;
    _category = media.category;
    _inGallery = media.inGallery;
    _consent = media.consentConfirmed;
    _focalX = media.focalX;
    _focalY = media.focalY;
  }

  Future<void> _reload() async {
    final fresh = await service.getMedia(requesterRole: role, mediaId: _media.id);
    if (fresh != null && mounted) setState(() => _resetFrom(fresh));
  }

  Future<void> _run(Future<void> Function() action, {String? success, bool reload = true, bool refreshSite = true}) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok && refreshSite) refreshPublicSite();
    if (ok && reload) await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveDetails() => service.updateMediaDetails(
        requesterRole: role,
        actor: user,
        mediaId: _media.id,
        // English and Tamil from the form; other languages kept as saved.
        alt: _media.alt.copyWith(en: _altEn.text, ta: _altTa.text),
        caption: _media.caption.copyWith(en: _captionEn.text, ta: _captionTa.text),
        category: _category,
        inGallery: _inGallery,
        focalX: _focalX,
        focalY: _focalY,
        consentConfirmed: _consent,
      );

  /// Saves the details; when this unticks consent, first confirms what that
  /// does (the image leaves the website at once, everywhere it is used).
  Future<void> _save() async {
    if (_media.consentConfirmed && !_consent) {
      Set<String> pages = const {};
      try {
        pages = await service.pagesUsing(requesterRole: role, mediaId: _media.id);
      } catch (_) {}
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Withdraw consent for this photograph?'),
          content: Text(
            'It is removed from the website straight away — from the gallery and from every page that uses it'
            '${pages.isEmpty ? '' : ' (${pages.join(', ')})'}. Those pages stay published and show a placeholder instead. '
            'The image stays in the library (not on the website) until you delete it.',
            key: const Key('website-media-withdraw-text'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('website-media-withdraw-confirm'),
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Withdraw consent'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _run(_saveDetails, success: 'Consent withdrawn. The image is no longer shown on the website.');
      return;
    }
    await _run(_saveDetails, success: _media.isPublished ? 'Saved. The website shows the new details.' : 'Saved.');
  }

  Future<void> _publish() => _run(() async {
        await _saveDetails();
        await service.publishMedia(requesterRole: role, actor: user, mediaId: _media.id);
      }, success: 'Published. It now appears on the website.');

  Future<void> _replace() async {
    PickedWebsiteImage? picked;
    try {
      picked = await service.pickImage();
    } on WebsiteContentException catch (e) {
      showMessage(e.message, error: true);
      return;
    }
    if (picked == null) return;
    await _run(
      () => service.replaceMediaImage(requesterRole: role, actor: user, mediaId: _media.id, image: picked!),
      success: 'Image replaced. Check the focal point, confirm consent for the new photograph, then publish it.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this image?'),
        content: const Text('The image and its files are removed permanently. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('website-media-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await attempt(() => service.deleteMedia(requesterRole: role, actor: user, mediaId: _media.id), success: 'Image deleted.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshPublicSite();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _media.withFocal(_focalX, _focalY);
    final published = _media.isPublished;
    return WebsiteEditorFrame(
      title: 'Edit image',
      busy: _busy,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WebsiteStatusChip.forMedia(_media.status),
            Text(
              switch (_media.status) {
                WebsiteMediaStatus.published => 'Visible on the website wherever it is used.',
                WebsiteMediaStatus.hidden => 'Hidden from the website.',
                WebsiteMediaStatus.draft => 'Not on the website yet.',
              },
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (_media.width > 0) Text('${_media.width} × ${_media.height} px', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const WebsiteEditorSectionTitle('Focal point'),
        const Text('Tap the part of the photograph that must stay in view when it is cropped.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 10),
        _FocalPointPicker(
          media: _media,
          focalX: _focalX,
          focalY: _focalY,
          onChanged: (x, y) => setState(() {
            _focalX = x;
            _focalY = y;
          }),
        ),
        const SizedBox(height: 14),
        Wrap(
          key: const Key('website-media-crops'),
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, ratio) in [('Homepage (square)', 1.0), ('Gallery (4:3)', 4 / 3), ('Page banner (16:9)', 16 / 9)])
              SizedBox(
                width: 170,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PublicWebsiteImage(media: preview, aspectRatio: ratio, borderRadius: 10, semanticLabel: '$label preview'),
                    const SizedBox(height: 4),
                    Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
        const WebsiteEditorSectionTitle('Description'),
        TextField(
          key: const Key('website-media-alt-en'),
          controller: _altEn,
          maxLength: WebsiteContentAdminService.maxAltLength,
          decoration: websiteField('Alt text (English) — required to publish',
              helper: 'Describe what the photograph shows for people using screen readers, e.g. “Children arranging coloured beads on a mat”. Do not include names.'),
        ),
        const SizedBox(height: 8),
        if (multilingualEditing)
          TextField(key: const Key('website-media-alt-ta'), controller: _altTa, maxLength: WebsiteContentAdminService.maxAltLength, decoration: websiteField('Alt text (Tamil, optional)')),
        const SizedBox(height: 8),
        TextField(
          key: const Key('website-media-caption-en'),
          controller: _captionEn,
          maxLength: WebsiteContentAdminService.maxCaptionLength,
          maxLines: 2,
          decoration: websiteField('Caption (English, optional)', helper: 'Shown under the photograph in the gallery.'),
        ),
        const SizedBox(height: 8),
        if (multilingualEditing)
          TextField(
          key: const Key('website-media-caption-ta'),
          controller: _captionTa,
          maxLength: WebsiteContentAdminService.maxCaptionLength,
          maxLines: 2,
          decoration: websiteField('Caption (Tamil, optional)'),
        ),
        const WebsiteEditorSectionTitle('Gallery'),
        DropdownButtonFormField<GalleryCategory>(
          key: const Key('website-media-category'),
          initialValue: _category,
          decoration: websiteField('Category'),
          items: [for (final c in GalleryCategory.values) DropdownMenuItem(value: c, child: Text(c.en))],
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
        SwitchListTile(
          key: const Key('website-media-in-gallery'),
          contentPadding: EdgeInsets.zero,
          value: _inGallery,
          onChanged: (value) => setState(() => _inGallery = value),
          title: const Text('Show in the gallery'),
          subtitle: const Text('Turn off to use this image only on pages.'),
        ),
        const WebsiteEditorSectionTitle('Consent'),
        CheckboxListTile(
          key: const Key('website-media-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _consent,
          onChanged: (value) => setState(() => _consent = value ?? false),
          title: const Text('This photograph is approved by the school, and consent has been obtained for every child who can be identified in it.'),
          subtitle: const Text('Required to publish. Unticking it and saving removes the image from the website at once, wherever it is used.'),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const Key('website-media-save'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
            if (published)
              OutlinedButton.icon(
                key: const Key('website-media-hide'),
                onPressed: () => _run(() => service.hideMedia(requesterRole: role, actor: user, mediaId: _media.id), success: 'Hidden from the website.'),
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('Hide from website'),
              )
            else
              FilledButton.icon(
                key: const Key('website-media-publish'),
                onPressed: _publish,
                icon: const Icon(Icons.public),
                label: const Text('Save and publish'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
              ),
            OutlinedButton.icon(key: const Key('website-media-replace'), onPressed: _replace, icon: const Icon(Icons.swap_horiz), label: const Text('Replace image')),
            TextButton.icon(
              key: const Key('website-media-delete'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
        ),
      ],
    );
  }
}

class _FocalPointPicker extends StatelessWidget {
  const _FocalPointPicker({required this.media, required this.focalX, required this.focalY, required this.onChanged});

  final WebsiteMedia media;
  final double focalX;
  final double focalY;
  final void Function(double x, double y) onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 360, maxWidth: 360 * media.aspectRatio),
        child: AspectRatio(
          aspectRatio: media.aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void set(Offset position) => onChanged(
                    (position.dx / constraints.maxWidth).clamp(0.0, 1.0),
                    (position.dy / constraints.maxHeight).clamp(0.0, 1.0),
                  );
              return GestureDetector(
                key: const Key('website-media-focal'),
                onTapDown: (details) => set(details.localPosition),
                onPanUpdate: (details) => set(details.localPosition),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        media.url,
                        fit: BoxFit.fill,
                        cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).ceil(),
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (_, _, _) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Text('Preview unavailable', style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: focalX * constraints.maxWidth - 14,
                      top: focalY * constraints.maxHeight - 14,
                      child: IgnorePointer(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ pages

/// Which version a page editor's preview shows.
enum WebsitePreviewSource { editing, live }

/// Where the text in a page editor came from when it opened.
enum WebsitePageEditSource {
  /// Nothing saved: the fields hold the site's built-in copy.
  builtIn,

  /// A saved draft that isn't published (visitors see the built-in copy).
  unpublishedDraft,

  /// A saved draft that differs from what is published.
  draftWithChanges,

  /// The published content (no different draft).
  published;

  static WebsitePageEditSource of(WebsitePageContent? draft, WebsitePageContent? live) {
    if (draft == null && live == null) return builtIn;
    if (live == null) return unpublishedDraft;
    if (draft != null && !draft.sameContentAs(live)) return draftWithChanges;
    return published;
  }

  String get description => switch (this) {
        builtIn => 'You are editing the built-in content. Nothing has been saved for this page yet; visitors see this text.',
        unpublishedDraft => 'You are editing a saved draft that is not published. Visitors see the built-in content.',
        draftWithChanges => 'You are editing a saved draft with unpublished changes. Visitors still see the published version.',
        published => 'You are editing the published content that visitors see.',
      };
}

/// Edits one built-in page's managed content — its image (from the media
/// library) and its heading/introduction in English and Tamil — with a
/// live preview of either the version being edited or the live one, then
/// saves it as a draft, publishes it, or unpublishes it.
///
/// Text that hasn't been changed from the site's built-in copy is shown in
/// the fields (prefilled from [WebsitePageSlot.builtInHeadline]/
/// [WebsitePageSlot.builtInIntro]) and saved as "use built-in", so nothing
/// is ever invented and the page keeps following the site's own copy.
///
/// A page converted in the visual editor says so. While its blocks are
/// published, visitors don't see this content, so Publish and Unpublish
/// are unavailable here (the service refuses them too) and the visual
/// editor is one tap away.
class WebsitePageEditorScreen extends ConsumerStatefulWidget {
  const WebsitePageEditorScreen({super.key, required this.service, required this.user, required this.slot});

  final WebsiteContentAdminService service;
  final AppUser user;
  final WebsitePageSlot slot;

  @override
  ConsumerState<WebsitePageEditorScreen> createState() => _WebsitePageEditorScreenState();
}

class _WebsitePageEditorScreenState extends ConsumerState<WebsitePageEditorScreen> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  final _headlineEn = TextEditingController();
  final _headlineTa = TextEditingController();
  final _introEn = TextEditingController();
  final _introTa = TextEditingController();
  String? _imageId;
  WebsitePageContent? _savedDraft;
  WebsitePageContent? _live;

  /// The page is built with blocks in the visual editor: in its draft, and
  /// on the website (visitors then see the blocks, not this content).
  bool _draftHasBlocks = false;
  bool _liveHasBlocks = false;
  List<WebsiteMedia> _library = const [];
  bool _loading = true;

  /// Loading failed: the form isn't shown, so blank fields can never be
  /// published over the page's real content.
  bool _loadFailed = false;
  bool _busy = false;
  PublicLanguage _previewLanguage = PublicLanguage.english;
  WebsitePreviewSource _previewSource = WebsitePreviewSource.editing;

  /// The website's enabled languages (for the preview).
  List<PublicLanguage> _languages = PublicLanguage.builtIn;

  @override
  void initState() {
    super.initState();
    for (final c in [_headlineEn, _headlineTa, _introEn, _introTa]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_headlineEn, _headlineTa, _introEn, _introTa]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A saved pair, or the built-in copy when no English or Tamil was saved
  /// for it. Text in other languages is kept either way.
  static LocalizedText _prefill(LocalizedText saved, LocalizedText builtIn) =>
      saved.en.trim().isEmpty && saved.ta.trim().isEmpty ? LocalizedText(en: builtIn.en, ta: builtIn.ta, others: saved.others) : saved;

  /// The loaded heading and introduction: the form edits their English and
  /// Tamil; any other language is saved back unchanged.
  LocalizedText _baseHeadline = const LocalizedText();
  LocalizedText _baseIntro = const LocalizedText();

  void _fill(WebsitePageContent? content) {
    final slot = widget.slot;
    final headline = _prefill(content?.headline ?? const LocalizedText(), slot.builtInHeadline);
    final intro = _prefill(content?.intro ?? const LocalizedText(), slot.builtInIntro);
    _baseHeadline = headline;
    _baseIntro = intro;
    _headlineEn.text = headline.en;
    _headlineTa.text = headline.ta;
    _introEn.text = intro.en;
    _introTa.text = intro.ta;
    _imageId = content?.imageMediaId;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final ok = await attempt(() async {
      final draft = await service.getSavedDraft(requesterRole: role, slot: widget.slot);
      final live = await service.getLive(requesterRole: role, slot: widget.slot);
      final blocks = await _blocksState();
      final library = await service.listMedia(requesterRole: role);
      final languages = (await service.editorLanguageRegistry(requesterRole: role)).editorLanguages;
      if (!mounted) return;
      setState(() {
        _savedDraft = draft;
        _live = live;
        _draftHasBlocks = blocks.$1;
        _liveHasBlocks = blocks.$2;
        _library = library;
        _languages = languages;
        _fill(draft ?? live);
      });
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = !ok;
      });
    }
  }

  WebsitePageContent get _content => WebsitePageContent(
        slot: widget.slot,
        imageMediaId: _imageId,
        headline: _baseHeadline.copyWith(en: _headlineEn.text, ta: _headlineTa.text),
        intro: _baseIntro.copyWith(en: _introEn.text, ta: _introTa.text),
      );

  WebsiteMedia? _mediaById(String? id) {
    for (final m in _library) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Whether the page's draft and live page are built with blocks.
  Future<(bool, bool)> _blocksState() async {
    final page = BuiltInPage.parse(widget.slot.id);
    if (page == null) return (false, false);
    final saved = await service.getBuiltInPage(requesterRole: role, page: page);
    return (saved.draft != null, saved.live != null);
  }

  /// Runs [action]; afterwards — even when it failed part-way, e.g. the
  /// draft saved but publication failed — the saved draft and live page
  /// are read again, so the status shows what is actually stored. The form
  /// fields are never touched here.
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await attempt(action, success: success);
    if (ok) refreshPublicSite();
    try {
      final draft = await service.getSavedDraft(requesterRole: role, slot: widget.slot);
      final live = await service.getLive(requesterRole: role, slot: widget.slot);
      final blocks = await _blocksState();
      if (mounted) {
        setState(() {
          _savedDraft = draft;
          _live = live;
          _draftHasBlocks = blocks.$1;
          _liveHasBlocks = blocks.$2;
        });
      }
    } catch (_) {
      // Offline: the status stays as last read; the error is shown.
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Publishes the form; over published content, only once confirmed.
  Future<void> _publish() async {
    if (_live != null && !await confirmReplacePublished(const Key('website-page-publish-confirm'))) return;
    await _run(() => service.publishPage(requesterRole: role, actor: user, content: _content), 'Published.');
  }

  Future<void> _openVisualEditor() async {
    final page = BuiltInPage.parse(widget.slot.id);
    if (page == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteBuiltInPageEditorScreen(service: service, user: user, page: page),
    ));
    if (mounted) await _load();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to built-in content?'),
        content: const Text(
          'The heading and introduction return to the website’s built-in text, and the page image is removed '
          '(the page shows its decorative placeholder). Nothing changes on the website until you save a draft or publish.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-page-reset-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Built-in English and Tamil; text in other languages is kept.
    setState(() => _fill(WebsitePageContent(
          slot: widget.slot,
          headline: LocalizedText(others: _baseHeadline.others),
          intro: LocalizedText(others: _baseIntro.others),
        )));
    showMessage('Reset in the editor. Save a draft or publish to apply it.');
  }

  Future<void> _chooseImage() async {
    final chosen = await showWebsiteImagePicker(context, _library, selected: _imageId);
    if (chosen != null) setState(() => _imageId = chosen);
  }

  /// "Built-in text" under a field that still holds the site's own copy.
  String? _builtInHelper(String value, String builtIn) => value.trim() == builtIn.trim() ? 'Built-in text' : null;

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final live = _live;
    final source = WebsitePageEditSource.of(_savedDraft, live);
    final saved = (_savedDraft ?? live ?? WebsitePageContent(slot: slot)).normalized();
    final unsaved = !_content.normalized().sameContentAs(saved);
    final isBuiltIn = _content.normalized().sameContentAs(WebsitePageContent(slot: slot));

    if (_loading || _loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(slot.adminLabel)),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('This page’s content could not be loaded.'),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('website-page-retry'), onPressed: _load, child: const Text('Try again')),
                  ],
                ),
        ),
      );
    }

    final image = _mediaById(_imageId);
    // The live preview shows what visitors get: only a published image.
    final liveContent = live ?? WebsitePageContent(slot: slot);
    final liveImage = _mediaById(liveContent.imageMediaId);
    final previewingLive = _previewSource == WebsitePreviewSource.live;

    return WebsiteEditorFrame(
      title: slot.adminLabel,
      busy: _busy,
      children: [
        WebsiteEditSourceBanner(
          key: const Key('website-page-source'),
          text: source.description,
          chips: [
            live == null
                ? const WebsiteStatusChip(label: 'Not published', color: Color(0xFF6E6E73))
                : const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
            if (source == WebsitePageEditSource.draftWithChanges || source == WebsitePageEditSource.unpublishedDraft)
              const WebsiteStatusChip(label: 'Draft saved', color: Color(0xFF8A6A33)),
            if (unsaved) const WebsiteStatusChip(key: Key('website-page-unsaved'), label: 'Unsaved edits', color: Color(0xFFB3261E)),
          ],
        ),
        if (_draftHasBlocks || _liveHasBlocks)
          Container(
            key: const Key('website-page-blocks-notice'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _liveHasBlocks
                      ? 'Visitors see the visual editor’s version of this page, so this heading, introduction and image are not shown. '
                          'Change or unpublish the page in the visual editor. What you save here is used again if the page returns to its built-in content.'
                      : 'This page has a visual editor draft. Visitors see the content below until that draft is published, which replaces it.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('website-page-open-visual'),
                  onPressed: _openVisualEditor,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('Open the visual editor'),
                ),
              ],
            ),
          ),
        const WebsiteEditorSectionTitle('Image'),
        Row(
          children: [
            WebsiteMediaThumb(media: image, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image == null ? (_imageId == null ? 'No image — the page shows a decorative placeholder.' : 'The chosen image no longer exists.') : (image.alt.en.isNotEmpty ? image.alt.en : 'No alt text yet'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (image != null && !image.isPublished)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Not published yet — publish it in the Media library before publishing this page.', style: TextStyle(fontSize: 12, color: Color(0xFF8A6A33))),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(key: const Key('website-page-choose-image'), onPressed: _chooseImage, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose image')),
            if (_imageId != null)
              TextButton(key: const Key('website-page-remove-image'), onPressed: () => setState(() => _imageId = null), child: const Text('Remove image')),
          ],
        ),
        const WebsiteEditorSectionTitle('Text'),
        const Text(
          'Fields start with the website’s built-in wording. Text left exactly as built-in keeps following the site’s own copy.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('website-page-headline-en'),
          controller: _headlineEn,
          maxLength: WebsiteContentAdminService.maxHeadlineLength,
          decoration: websiteField('Heading (English)', helper: _builtInHelper(_headlineEn.text, slot.builtInHeadline.en)),
        ),
        const SizedBox(height: 8),
        if (multilingualEditing)
          TextField(
          key: const Key('website-page-headline-ta'),
          controller: _headlineTa,
          maxLength: WebsiteContentAdminService.maxHeadlineLength,
          decoration: websiteField('Heading (Tamil)', helper: _builtInHelper(_headlineTa.text, slot.builtInHeadline.ta)),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('website-page-intro-en'),
          controller: _introEn,
          maxLength: WebsiteContentAdminService.maxIntroLength,
          maxLines: 3,
          decoration: websiteField('Introduction (English)', helper: _builtInHelper(_introEn.text, slot.builtInIntro.en)),
        ),
        const SizedBox(height: 8),
        if (multilingualEditing)
          TextField(
          key: const Key('website-page-intro-ta'),
          controller: _introTa,
          maxLength: WebsiteContentAdminService.maxIntroLength,
          maxLines: 3,
          decoration: websiteField('Introduction (Tamil)', helper: _builtInHelper(_introTa.text, slot.builtInIntro.ta)),
        ),
        WebsitePreviewControls(
          languages: _languages,
          source: _previewSource,
          language: _previewLanguage,
          onSource: (s) => setState(() => _previewSource = s),
          onLanguage: (l) => setState(() => _previewLanguage = l),
        ),
        if (previewingLive && live == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Nothing is published for this page: visitors see the built-in content.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        WebsitePagePreview(
          key: const Key('website-page-preview'),
          content: previewingLive ? liveContent : _content,
          image: previewingLive ? (liveImage?.isPublished == true ? liveImage : null) : image,
          language: _previewLanguage,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              key: const Key('website-page-save-draft'),
              onPressed: () => _run(
                () => service.saveDraft(requesterRole: role, actor: user, content: _content),
                _liveHasBlocks
                    ? 'Draft saved. Visitors see the visual editor’s version of this page, which doesn’t show this content.'
                    : live == null
                        ? 'Draft saved. It is not on the website yet.'
                        : 'Draft saved. Visitors still see the published version.',
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save draft'),
            ),
            FilledButton.icon(
              key: const Key('website-page-publish'),
              onPressed: _liveHasBlocks ? null : _publish,
              icon: const Icon(Icons.public),
              label: const Text('Publish'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            ),
            if (live != null && !_liveHasBlocks)
              TextButton.icon(
                key: const Key('website-page-unpublish'),
                onPressed: () => _run(() => service.unpublishPage(requesterRole: role, actor: user, slot: slot), 'Unpublished. The page shows its built-in content again.'),
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('Unpublish'),
              ),
            TextButton.icon(
              key: const Key('website-page-reset'),
              onPressed: isBuiltIn ? null : _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset to built-in content'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The "what am I editing" banner at the top of a page editor.
class WebsiteEditSourceBanner extends StatelessWidget {
  const WebsiteEditSourceBanner({super.key, required this.text, required this.chips});

  final String text;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: chips),
          const SizedBox(height: 8),
          Text(text, key: const Key('website-edit-source-text'), style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

/// Chooses one of [languages] — the website's enabled languages — for a
/// preview: segments for up to three, otherwise a menu. Each option is keyed
/// `<keyPrefix>-<code>` (e.g. `website-preview-ta`).
class WebsiteLanguagePicker extends StatelessWidget {
  const WebsiteLanguagePicker({super.key, required this.languages, required this.selected, required this.onChanged, required this.keyPrefix});

  final List<PublicLanguage> languages;
  final PublicLanguage selected;
  final ValueChanged<PublicLanguage> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    // English only for now ([multilingualEditing]): nothing to choose.
    if (!multilingualEditing) return const SizedBox.shrink();
    final options = languages.isEmpty ? PublicLanguage.builtIn : languages;
    final current = options.contains(selected) ? selected : options.first;
    if (options.length <= 3) {
      return SegmentedButton<PublicLanguage>(
        showSelectedIcon: false,
        segments: [
          for (final l in options) ButtonSegment(value: l, label: Text(l.shortLabel, key: Key('$keyPrefix-${l.code}'))),
        ],
        selected: {current},
        onSelectionChanged: (s) => onChanged(s.first),
      );
    }
    return DropdownButton<PublicLanguage>(
      key: Key('$keyPrefix-menu'),
      value: current,
      items: [
        for (final l in options) DropdownMenuItem(value: l, child: Text(l.nativeName, key: Key('$keyPrefix-${l.code}'))),
      ],
      onChanged: (l) {
        if (l != null) onChanged(l);
      },
    );
  }
}

/// Preview header: which version (being edited / live) and which language
/// (of the website's enabled [languages]).
class WebsitePreviewControls extends StatelessWidget {
  const WebsitePreviewControls({
    super.key,
    required this.source,
    required this.language,
    required this.onSource,
    required this.onLanguage,
    this.languages = PublicLanguage.builtIn,
  });

  final WebsitePreviewSource source;
  final PublicLanguage language;
  final ValueChanged<WebsitePreviewSource> onSource;
  final ValueChanged<PublicLanguage> onLanguage;
  final List<PublicLanguage> languages;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SegmentedButton<WebsitePreviewSource>(
            key: const Key('website-preview-source'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: WebsitePreviewSource.editing, label: Text('Editing', key: Key('website-preview-editing'))),
              ButtonSegment(value: WebsitePreviewSource.live, label: Text('Live', key: Key('website-preview-live'))),
            ],
            selected: {source},
            onSelectionChanged: (s) => onSource(s.first),
          ),
          WebsiteLanguagePicker(languages: languages, selected: language, onChanged: onLanguage, keyPrefix: 'website-preview'),
        ],
      ),
    );
  }
}

/// Lets the admin pick one image from [library] (any status — publishing a
/// page checks its images are published). Returns the chosen id, or null.
Future<String?> showWebsiteImagePicker(BuildContext context, List<WebsiteMedia> library, {String? selected}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Choose an image'),
      content: SizedBox(
        width: 520,
        child: library.isEmpty
            ? const Text('The media library is empty. Upload an image in the Media library tab first.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final m in library)
                    ListTile(
                      key: Key('website-choose-${m.id}'),
                      leading: WebsiteMediaThumb(media: m, size: 48),
                      title: Text(m.alt.en.isNotEmpty ? m.alt.en : 'No alt text yet', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Align(alignment: Alignment.centerLeft, child: WebsiteStatusChip.forMedia(m.status)),
                      selected: m.id == selected,
                      onTap: () => Navigator.pop(context, m.id),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    ),
  );
}

/// Chooses several images from the media library, in the order ticked
/// (at most [max]); null when cancelled. Images [already] in the list are
/// marked and can't be chosen again (a gallery shows each image once). Keys: `website-choose-many-<id>`,
/// `website-choose-many-add`.
Future<List<String>?> showWebsiteImagesPicker(BuildContext context, List<WebsiteMedia> library, {Set<String> already = const {}, required int max}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) {
      final chosen = <String>[];
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add images'),
          content: SizedBox(
            width: 560,
            child: library.isEmpty
                ? const Text('The media library is empty. Upload an image in the Media library tab first.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tick the images to add, in the order they should appear (at most $max). Only published images are shown to visitors.',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final m in library)
                              CheckboxListTile(
                                key: Key('website-choose-many-${m.id}'),
                                value: chosen.contains(m.id),
                                onChanged: already.contains(m.id) || (!chosen.contains(m.id) && chosen.length >= max)
                                    ? null
                                    : (v) => setState(() => v == true ? chosen.add(m.id) : chosen.remove(m.id)),
                                secondary: WebsiteMediaThumb(media: m, size: 48),
                                title: Text(m.alt.en.isNotEmpty ? m.alt.en : 'No alt text yet', maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    WebsiteStatusChip.forMedia(m.status),
                                    if (chosen.contains(m.id)) Text('#${chosen.indexOf(m.id) + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    if (already.contains(m.id)) const Text('Already in this gallery', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              key: const Key('website-choose-many-add'),
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, List<String>.of(chosen)),
              child: Text(chosen.isEmpty ? 'Add' : 'Add ${chosen.length}'),
            ),
          ],
        ),
      );
    },
  );
}

/// How [content] will look on the website (image placement, text with
/// built-in fallbacks), drawn with the public site's own styles.
class WebsitePagePreview extends StatelessWidget {
  const WebsitePagePreview({super.key, required this.content, required this.image, required this.language});

  final WebsitePageContent content;
  final WebsiteMedia? image;
  final PublicLanguage language;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final slot = content.slot;
    final isHome = slot == WebsitePageSlot.home;
    final headline = content.headline.resolve(language);
    final intro = content.intro.resolve(language);
    final title = headline.isNotEmpty ? headline : (isHome ? strings.heroTitle : strings.labelFor(slot.route));
    final body = intro.isNotEmpty ? intro : (isHome ? strings.heroBody : strings.introFor(slot.route));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: PublicColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: PublicColors.line)),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isHome) ...[Text(strings.heroEyebrow, style: PublicText.eyebrow), const SizedBox(height: 10)],
            Text(title, key: const Key('website-preview-title'), style: (narrow ? PublicText.displayMobile : PublicText.display).copyWith(fontSize: narrow ? 24 : 30)),
            const SizedBox(height: 10),
            Text(body, key: const Key('website-preview-intro'), style: PublicText.body),
          ],
        );
        final image = this.image;
        final visual = PublicWebsiteImage(
          media: image,
          aspectRatio: isHome ? (narrow ? 4 / 3 : 1) : 16 / 9,
          borderRadius: isHome ? 24 : 16,
          semanticLabel: image?.alt.resolve(language) ?? '',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isHome && !narrow)
              Row(children: [Expanded(flex: 3, child: text), const SizedBox(width: 24), Expanded(flex: 2, child: visual)])
            else ...[
              text,
              // The mobile homepage shows no placeholder, only a real image.
              if (!isHome || image != null) ...[const SizedBox(height: 16), visual],
            ],
            if (image != null && !image.isPublished)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Preview only: this image is not published, so visitors would see the placeholder.', style: TextStyle(fontSize: 12, color: Color(0xFF8A6A33))),
              ),
          ],
        );
      }),
    );
  }
}
