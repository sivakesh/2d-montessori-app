import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../settings/ui/access_restricted_view.dart';
import '../data/website_content_admin_service.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_languages.dart';
import '../../../public_website/content/website_site_layout.dart';
import 'website_built_in_page_editor.dart';
import 'website_content_editors.dart';
import 'website_custom_page_editor.dart';
import 'website_languages_editor.dart';
import 'website_site_layout_editor.dart';

/// Settings -> Website: the public website's media library, gallery order,
/// page content and site layout (header, navigation and footer). Admin only (the screen shows the locked view to
/// anyone else, and every service call re-checks the role).
class WebsiteContentScreen extends ConsumerWidget {
  const WebsiteContentScreen({super.key, this.service});

  final WebsiteContentAdminService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = (user?.role ?? '').toLowerCase() == 'admin';
    if (!isAdmin || user == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(title: const Text('Website Content')),
        body: const AccessRestrictedView(),
      );
    }
    return _WebsiteContentBody(service: service ?? WebsiteContentAdminService(), user: user);
  }
}

/// Shared helpers for the website-content screens.
mixin WebsiteContentActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  WebsiteContentAdminService get service;
  AppUser get user;

  String get role => user.role.toLowerCase();

  /// Makes this session's public pages pick up a published change at once
  /// (other visitors get it on their next page load).
  void refreshPublicSite() {
    ref.invalidate(publishedWebsiteMediaProvider);
    // The built-in pages' content, additional pages and navigation all
    // derive from this one read.
    ref.invalidate(liveWebsiteContentProvider);
  }

  void showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Colors.red.shade700 : null),
    );
  }

  /// Runs [action], reporting a [WebsiteContentException]'s own message (or
  /// a generic one) instead of throwing. Returns whether it succeeded.
  Future<bool> attempt(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) showMessage(success);
      return true;
    } on WebsiteContentException catch (e) {
      showMessage(e.message, error: true);
    } on UnauthorizedWebsiteContentException catch (e) {
      showMessage(e.toString(), error: true);
    } catch (_) {
      showMessage('Something went wrong. Please try again.', error: true);
    }
    return false;
  }
}

class _WebsiteContentBody extends ConsumerStatefulWidget {
  const _WebsiteContentBody({required this.service, required this.user});

  final WebsiteContentAdminService service;
  final AppUser user;

  @override
  ConsumerState<_WebsiteContentBody> createState() => _WebsiteContentBodyState();
}

class _WebsiteContentBodyState extends ConsumerState<_WebsiteContentBody> with WebsiteContentActions {
  @override
  WebsiteContentAdminService get service => widget.service;
  @override
  AppUser get user => widget.user;

  List<WebsiteMedia>? _media;
  Map<WebsitePageSlot, ({WebsitePageContent? draft, WebsitePageContent? live})> _pages = {};
  List<({CustomPage draft, CustomPage? live})> _customPages = const [];
  ({SiteLayout? draft, SiteLayout? live, bool liveUnreadable})? _layout;
  ({SiteLanguageRegistry? draft, SiteLanguageRegistry? live, bool liveUnreadable})? _languages;
  Object? _loadError;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final media = await service.listMedia(requesterRole: role);
      final pages = <WebsitePageSlot, ({WebsitePageContent? draft, WebsitePageContent? live})>{};
      for (final slot in WebsitePageSlot.values) {
        pages[slot] = (
          draft: await service.getSavedDraft(requesterRole: role, slot: slot),
          live: await service.getLive(requesterRole: role, slot: slot),
        );
      }
      final customPages = await service.listCustomPages(requesterRole: role);
      final layout = await service.getSiteLayout(requesterRole: role);
      final languages = await service.getLanguageRegistry(requesterRole: role);
      if (!mounted) return;
      setState(() {
        _media = media;
        _pages = pages;
        _customPages = customPages;
        _layout = layout;
        _languages = languages;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _upload() async {
    PickedWebsiteImage? picked;
    try {
      picked = await service.pickImage();
    } on WebsiteContentException catch (e) {
      showMessage(e.message, error: true);
      return;
    }
    if (picked == null) return;
    setState(() => _uploading = true);
    WebsiteMedia? created;
    await attempt(() async {
      created = await service.uploadMedia(requesterRole: role, actor: user, image: picked!);
    });
    if (!mounted) return;
    setState(() => _uploading = false);
    await _load();
    if (created != null && mounted) await _openMedia(created!);
  }

  Future<void> _openMedia(WebsiteMedia media) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteMediaEditorScreen(service: service, user: user, media: media),
    ));
    await _load();
  }

  Future<void> _openPage(WebsitePageSlot slot) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsitePageEditorScreen(service: service, user: user, slot: slot),
    ));
    await _load();
  }

  Future<void> _openBuiltInVisual(BuiltInPage page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteBuiltInPageEditorScreen(service: service, user: user, page: page),
    ));
    await _load();
  }

  Future<void> _openCustomPage(String pageId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteCustomPageEditorScreen(service: service, user: user, pageId: pageId),
    ));
    await _load();
  }

  Future<void> _openLayout() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteSiteLayoutEditorScreen(service: service, user: user),
    ));
    await _load();
  }

  Future<void> _openLanguages() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteLanguagesEditorScreen(service: service, user: user),
    ));
    await _load();
  }

  Future<void> _createCustomPage() async {
    final created = await showCreateCustomPageDialog(context, service: service, user: user);
    if (created == null || !mounted) return;
    await _load();
    if (mounted) await _openCustomPage(created.id);
  }

  /// Moves an active page one place in the navigation order.
  Future<void> _moveCustomPage(List<CustomPage> active, int from, int to) async {
    if (to < 0 || to >= active.length) return;
    final reordered = [...active];
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    final ok = await attempt(() => service.reorderCustomPages(requesterRole: role, actor: user, orderedIds: [for (final p in reordered) p.id]));
    if (ok) refreshPublicSite();
    await _load();
  }

  Future<void> _move(List<WebsiteMedia> gallery, int from, int to) async {
    if (to < 0 || to >= gallery.length || from == to) return;
    final reordered = [...gallery];
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    setState(() {
      // Optimistic: show the new order straight away.
      final others = _media!.where((m) => !m.inGallery).toList();
      _media = [...reordered, ...others];
    });
    final ok = await attempt(() => service.reorderGallery(requesterRole: role, actor: user, orderedIds: [for (final m in reordered) m.id]));
    if (ok) refreshPublicSite();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Website Content'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: Key('website-tab-media'), text: 'Media library'),
              Tab(key: Key('website-tab-gallery'), text: 'Gallery order'),
              Tab(key: Key('website-tab-pages'), text: 'Pages'),
              Tab(key: Key('website-tab-layout'), text: 'Site layout'),
              Tab(key: Key('website-tab-languages'), text: 'Languages'),
            ],
          ),
        ),
        body: _loadError != null
            ? _LoadFailed(onRetry: () {
                setState(() => _loadError = null);
                _load();
              })
            : media == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _MediaLibraryTab(media: media, uploading: _uploading, onUpload: _upload, onOpen: _openMedia),
                      _GalleryOrderTab(gallery: [for (final m in media) if (m.inGallery) m], onMove: _move),
                      _PagesTab(
                        pages: _pages,
                        customPages: _customPages,
                        media: media,
                        onOpen: _openPage,
                        onOpenVisual: _openBuiltInVisual,
                        onOpenCustom: _openCustomPage,
                        onCreateCustom: _createCustomPage,
                        onMoveCustom: _moveCustomPage,
                        layoutPublished: _layout?.live != null,
                      ),
                      _SiteLayoutTab(layout: _layout, onOpen: _openLayout),
                      _LanguagesTab(languages: _languages, onOpen: _openLanguages),
                    ],
                  ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Website content could not be loaded.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Status chip shared by the library, gallery and page lists.
class WebsiteStatusChip extends StatelessWidget {
  const WebsiteStatusChip({super.key, required this.label, required this.color});

  factory WebsiteStatusChip.forMedia(WebsiteMediaStatus status) => switch (status) {
        WebsiteMediaStatus.published => const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
        WebsiteMediaStatus.hidden => const WebsiteStatusChip(label: 'Hidden', color: Color(0xFF8A6A33)),
        WebsiteMediaStatus.draft => const WebsiteStatusChip(label: 'Draft', color: Color(0xFF6E6E73)),
      };

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// A small library thumbnail (falls back to an icon if it can't load).
class WebsiteMediaThumb extends StatelessWidget {
  const WebsiteMediaThumb({super.key, required this.media, this.size = 56});

  final WebsiteMedia? media;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = media == null ? '' : (media!.thumbUrl.isNotEmpty ? media!.thumbUrl : media!.url);
    final fallback = Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      child: Icon(media == null ? Icons.image_outlined : Icons.broken_image_outlined, color: Colors.grey),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              alignment: media!.alignment,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _MediaLibraryTab extends StatelessWidget {
  const _MediaLibraryTab({required this.media, required this.uploading, required this.onUpload, required this.onOpen});

  final List<WebsiteMedia> media;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<WebsiteMedia> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('website-upload'),
              onPressed: uploading ? null : onUpload,
              icon: uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_outlined),
              label: Text(uploading ? 'Uploading…' : 'Upload image'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
            const Text('JPEG, PNG or WebP, up to 15 MB.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        const _PrivacyNote(),
        const SizedBox(height: 16),
        if (media.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('No images yet. Uploaded images stay private (draft) until you publish them.', textAlign: TextAlign.center),
          )
        else
          for (final item in media)
            Card(
              key: Key('website-media-${item.id}'),
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: WebsiteMediaThumb(media: item),
                title: Text(
                  item.alt.en.isNotEmpty ? item.alt.en : 'No alt text yet',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: item.alt.en.isNotEmpty ? AppColors.textPrimary : AppColors.textSecondary),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      WebsiteStatusChip.forMedia(item.status),
                      Text(item.category.en, style: const TextStyle(fontSize: 12)),
                      Text(item.inGallery ? 'In gallery' : 'Pages only', style: const TextStyle(fontSize: 12)),
                      if (!item.consentConfirmed) const Text('Consent not confirmed', style: TextStyle(fontSize: 12, color: Color(0xFF8A6A33))),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(item),
              ),
            ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF3EADB), borderRadius: BorderRadius.circular(10)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, size: 18, color: Color(0xFF8A6A33)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Use only photographs approved by the school. Before publishing, make sure consent has been obtained '
              'for any child who can be identified, and avoid names, uniforms with names, or other personal details in '
              'captions and alt text.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryOrderTab extends StatelessWidget {
  const _GalleryOrderTab({required this.gallery, required this.onMove});

  final List<WebsiteMedia> gallery;
  final Future<void> Function(List<WebsiteMedia> gallery, int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    if (gallery.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No gallery images yet. Images marked “Show in gallery” appear here.', textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Drag, or use the arrows, to set the order. Only published images appear on the website.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: gallery.length,
            onReorder: (from, to) => onMove(gallery, from, to > from ? to - 1 : to),
            itemBuilder: (context, i) {
              final item = gallery[i];
              return Card(
                key: Key('website-gallery-${item.id}'),
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator, color: Colors.grey)),
                      ),
                      WebsiteMediaThumb(media: item, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.caption.en.isNotEmpty ? item.caption.en : (item.alt.en.isNotEmpty ? item.alt.en : 'Untitled image'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            WebsiteStatusChip.forMedia(item.status),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('website-gallery-up-${item.id}'),
                        tooltip: 'Move up',
                        onPressed: i == 0 ? null : () => onMove(gallery, i, i - 1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: Key('website-gallery-down-${item.id}'),
                        tooltip: 'Move down',
                        onPressed: i == gallery.length - 1 ? null : () => onMove(gallery, i, i + 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PagesTab extends StatelessWidget {
  const _PagesTab({
    required this.pages,
    required this.customPages,
    required this.media,
    required this.onOpen,
    required this.onOpenVisual,
    required this.onOpenCustom,
    required this.onCreateCustom,
    required this.onMoveCustom,
    this.layoutPublished = false,
  });

  final Map<WebsitePageSlot, ({WebsitePageContent? draft, WebsitePageContent? live})> pages;
  final List<({CustomPage draft, CustomPage? live})> customPages;
  final List<WebsiteMedia> media;
  final ValueChanged<WebsitePageSlot> onOpen;

  /// Opens a built-in page in the visual editor.
  final ValueChanged<BuiltInPage> onOpenVisual;
  final ValueChanged<String> onOpenCustom;
  final VoidCallback onCreateCustom;
  final Future<void> Function(List<CustomPage> active, int from, int to) onMoveCustom;

  /// A site layout is published, so it — not "show in navigation" or this
  /// order — decides the navigation.
  final bool layoutPublished;

  /// A live page refers to an image that visitors no longer see (hidden,
  /// consent withdrawn, replaced or deleted): the page shows a placeholder.
  bool _showsUnpublishedImage(List<String> mediaIds) {
    for (final id in mediaIds) {
      final match = media.where((m) => m.id == id);
      if (match.isEmpty || !match.first.isPublished) return true;
    }
    return false;
  }

  Widget _customCard(({CustomPage draft, CustomPage? live}) entry, {int? index, List<CustomPage>? active}) {
    final draft = entry.draft;
    final live = entry.live;
    return Card(
      key: Key('website-custom-page-${draft.id}'),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        title: Text(draft.title.en.isNotEmpty ? draft.title.en : draft.slug, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(draft.route, style: const TextStyle(fontSize: 12)),
              if (draft.archived)
                const WebsiteStatusChip(label: 'Archived', color: Color(0xFF6E6E73))
              else if (live == null)
                const WebsiteStatusChip(label: 'Draft', color: Color(0xFF6E6E73))
              else
                const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
              if (live != null && !draft.samePublishedContentAs(live)) const WebsiteStatusChip(label: 'Unpublished changes', color: Color(0xFF8A6A33)),
              if (live != null && live.showInNavigation) const WebsiteStatusChip(label: 'In navigation', color: Color(0xFF2E7D5B)),
              if (live != null && _showsUnpublishedImage(live.referencedMedia))
                const WebsiteStatusChip(label: 'Image not shown', color: Color(0xFFB3261E)),
            ],
          ),
        ),
        trailing: index == null || active == null
            ? const Icon(Icons.chevron_right)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('website-custom-up-${draft.id}'),
                    tooltip: 'Earlier in navigation',
                    onPressed: index == 0 ? null : () => onMoveCustom(active, index, index - 1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    key: Key('website-custom-down-${draft.id}'),
                    tooltip: 'Later in navigation',
                    onPressed: index == active.length - 1 ? null : () => onMoveCustom(active, index, index + 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
        onTap: () => onOpenCustom(draft.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = [for (final p in customPages) if (!p.draft.archived) p];
    final archived = [for (final p in customPages) if (p.draft.archived) p];
    final activePages = [for (final p in active) p.draft];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Built-in pages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Choose each page’s image and, optionally, its heading and introduction. Pages without published content '
          'use the website’s built-in wording and a decorative placeholder.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final slot in WebsitePageSlot.values)
          Builder(builder: (context) {
            final entry = pages[slot];
            final live = entry?.live;
            final draft = entry?.draft;
            final imageId = (draft ?? live)?.imageMediaId;
            WebsiteMedia? image;
            for (final m in media) {
              if (m.id == imageId) image = m;
            }
            final hasChanges = draft != null && !draft.sameContentAs(live ?? WebsitePageContent(slot: slot));
            return Card(
              key: Key('website-page-${slot.id}'),
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: WebsiteMediaThumb(media: image),
                title: Text(slot.adminLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      live == null
                          ? const WebsiteStatusChip(label: 'Built-in content', color: Color(0xFF6E6E73))
                          : const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B)),
                      if (hasChanges) const WebsiteStatusChip(label: 'Unpublished changes', color: Color(0xFF8A6A33)),
                      if (live != null && _showsUnpublishedImage(live.imageMediaId == null ? const [] : [live.imageMediaId!]))
                        const WebsiteStatusChip(key: Key('website-page-image-not-shown'), label: 'Image not shown', color: Color(0xFFB3261E)),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(slot),
              ),
            );
          }),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Additional pages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            FilledButton.icon(
              key: const Key('website-new-page'),
              onPressed: onCreateCustom,
              icon: const Icon(Icons.add),
              label: const Text('New page'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Extra pages at /pages/<address>. They are visible only once published, and listed in the navigation only if you choose; '
          'the arrows set their navigation order (applied straight away).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (layoutPublished)
          const Padding(
            key: Key('website-pages-layout-note'),
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A site layout is published, so the header and footer links are managed in the Site layout tab. '
              '“Show in navigation” and this order apply only if the layout is unpublished.',
              style: TextStyle(color: Color(0xFF8A6A33), fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        if (active.isEmpty) const Text('No additional pages yet.', style: TextStyle(color: AppColors.textSecondary)),
        for (var i = 0; i < active.length; i++) _customCard(active[i], index: i, active: activePages),
        if (archived.isNotEmpty)
          ExpansionTile(
            key: const Key('website-archived-pages'),
            tilePadding: EdgeInsets.zero,
            title: Text('Archived pages (${archived.length})'),
            children: [for (final p in archived) _customCard(p)],
          ),
        const SizedBox(height: 20),
        Container(
          key: const Key('website-builtin-visual'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE6EDE2), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit a built-in page visually', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Rebuild a page from sections and blocks — compared side by side with today’s page first. Visitors see no change until you publish.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final page in BuiltInPage.values)
                    OutlinedButton.icon(
                      key: Key('website-builtin-open-${page.id}'),
                      onPressed: () => onOpenVisual(page),
                      icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
                      label: Text(page.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SiteLayoutTab extends StatelessWidget {
  const _SiteLayoutTab({required this.layout, required this.onOpen});

  final ({SiteLayout? draft, SiteLayout? live, bool liveUnreadable})? layout;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final draft = layout?.draft;
    final live = layout?.live;
    final hasChanges = draft != null && (live == null || !draft.sameContentAs(live));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Header, navigation and footer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'The site name and tagline, the links in the header, mobile menu and footer, the footer text and copyright. '
          'Login, Dashboard and Logout always stay as they are. Until a layout is published the website uses its built-in header and footer.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('website-layout-card'),
          color: AppColors.card,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: const Icon(Icons.web_outlined),
            title: const Text('Site layout', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (live != null)
                    const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B))
                  else if (layout?.liveUnreadable == true)
                    const WebsiteStatusChip(label: 'Published layout unreadable', color: Color(0xFFB3261E))
                  else
                    const WebsiteStatusChip(label: 'Built-in layout', color: Color(0xFF6E6E73)),
                  if (hasChanges) const WebsiteStatusChip(label: 'Unpublished changes', color: Color(0xFF8A6A33)),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpen,
          ),
        ),
      ],
    );
  }
}

class _LanguagesTab extends StatelessWidget {
  const _LanguagesTab({required this.languages, required this.onOpen});

  final ({SiteLanguageRegistry? draft, SiteLanguageRegistry? live, bool liveUnreadable})? languages;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final draft = languages?.draft;
    final live = languages?.live;
    final hasChanges = draft != null && (live == null || !draft.sameContentAs(live));
    final shown = live?.publicLanguages ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Website languages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Which languages the website editors offer and which visitors can choose, their order and the fallback language. '
          'English is the source language. Until languages are published, visitors are offered English and Tamil.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('website-languages-card'),
          color: AppColors.card,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: const Icon(Icons.translate),
            title: const Text('Languages', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (live != null)
                    const WebsiteStatusChip(label: 'Published', color: Color(0xFF2E7D5B))
                  else if (languages?.liveUnreadable == true)
                    const WebsiteStatusChip(label: 'Published languages unreadable', color: Color(0xFFB3261E))
                  else
                    const WebsiteStatusChip(label: 'English and Tamil (built-in)', color: Color(0xFF6E6E73)),
                  if (hasChanges) const WebsiteStatusChip(label: 'Unpublished changes', color: Color(0xFF8A6A33)),
                  if (shown.isNotEmpty) Text('Visitors: ${[for (final l in shown) l.nativeName].join(', ')}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpen,
          ),
        ),
      ],
    );
  }
}
