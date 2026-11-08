import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_content_models.dart';
import '../data/website_albums_service.dart';
import '../data/website_content_admin_service.dart';
import 'website_content_screen.dart' show WebsiteMediaThumb, WebsiteStatusChip;

/// How an image is named in lists: its English alt text, else its caption,
/// else that it has neither (never the original file name, which may name
/// a child).
String mediaLabel(WebsiteMedia m) {
  if (m.alt.en.trim().isNotEmpty) return m.alt.en.trim();
  if (m.caption.en.trim().isNotEmpty) return m.caption.en.trim();
  return m.decorative ? 'Decorative image' : 'Image without alt text';
}

/// What the admin agrees to before approval and consent are confirmed for
/// every image of an upload.
const uploadConsentStatement = 'I confirm that all selected photographs are approved by the school and that the required consent has been obtained.';

String _images(int n) => '$n image${n == 1 ? '' : 's'}';

String _size(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

// ------------------------------------------------------------------ upload

enum _UploadState { waiting, uploading, done, failed, invalid, cancelled }

/// One file of a bulk upload, its own settings (empty: the shared
/// defaults) and where it stands. Its media id is reserved up front, so a
/// retry (or a second tap) never makes a second record.
class _UploadItem {
  _UploadItem(this.file, this.mediaId) : state = file.problem == null ? _UploadState.waiting : _UploadState.invalid, message = file.problem ?? '';

  final PickedWebsiteFile file;
  final String mediaId;
  _UploadState state;
  String message;
  /// Starts as the default alt text (new uploads only); the admin may
  /// change or clear it here, or later in the library.
  final alt = TextEditingController(text: WebsiteMedia.defaultAlt);
  final caption = TextEditingController();

  /// Null: the shared default.
  GalleryCategory? category;
  bool? decorative;
  bool removed = false;

  /// The admin's attestation that this photograph is school-approved and
  /// consent was obtained (the record's `consentConfirmed`): never set
  /// automatically, only by ticking it or by the confirmed "all" action
  /// ([consentForAll]: recorded in the audit as a bulk confirmation).
  bool consent = false;
  bool consentForAll = false;

  bool get editable => state == _UploadState.waiting || state == _UploadState.failed || state == _UploadState.cancelled;
  bool get pending => !removed && editable;
}

/// Opens the review step for [files] (from [WebsiteContentAdminService.pickImages]):
/// shared defaults, each file's own alt text, caption and settings, then
/// the upload with each file's progress and result. Pops the ids of the
/// images uploaded.
Future<List<String>> showBulkUpload(
  BuildContext context, {
  required WebsiteContentAdminService service,
  required AppUser user,
  required List<PickedWebsiteFile> files,
  List<WebsiteAlbum> albums = const [],
}) async {
  final uploaded = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => WebsiteBulkUploadScreen(service: service, user: user, files: files, albums: albums),
    ),
  );
  return uploaded ?? const [];
}

/// Review and upload several images: every file checked on its own (JPEG,
/// PNG or WebP, at most 15 MB), shared defaults (category, gallery,
/// caption, decorative, albums) with per-image changes, then one upload
/// at a time with its progress and result. Failed or cancelled files can
/// be retried, alone or together; uploaded ones are never sent again.
/// Images are uploaded as drafts: consent is confirmed, and images
/// published, in the library afterwards.
class WebsiteBulkUploadScreen extends StatefulWidget {
  const WebsiteBulkUploadScreen({super.key, required this.service, required this.user, required this.files, this.albums = const []});

  final WebsiteContentAdminService service;
  final AppUser user;
  final List<PickedWebsiteFile> files;
  final List<WebsiteAlbum> albums;

  @override
  State<WebsiteBulkUploadScreen> createState() => _WebsiteBulkUploadScreenState();
}

class _WebsiteBulkUploadScreenState extends State<WebsiteBulkUploadScreen> {
  late final List<_UploadItem> _items = [for (final f in widget.files) _UploadItem(f, widget.service.newMediaId())];
  GalleryCategory _category = GalleryCategory.general;
  bool _inGallery = true;
  bool _decorative = false;
  final _caption = TextEditingController();
  final Set<String> _albums = {};
  bool _running = false;
  bool _stop = false;
  bool _started = false;
  final List<String> _uploaded = [];

  String get _role => widget.user.role.toLowerCase();

  @override
  void dispose() {
    for (final i in _items) {
      i.alt.dispose();
      i.caption.dispose();
    }
    _caption.dispose();
    super.dispose();
  }

  /// Uploads [items] one at a time (each with its reserved id). A second
  /// call while running does nothing.
  Future<void> _run(List<_UploadItem> items) async {
    if (_running || items.isEmpty) return;
    setState(() {
      _running = true;
      _started = true;
      _stop = false;
    });
    for (final item in items) {
      if (!mounted) return;
      if (_stop) {
        setState(() {
          item.state = _UploadState.cancelled;
          item.message = 'Not uploaded: cancelled.';
        });
        continue;
      }
      setState(() {
        item.state = _UploadState.uploading;
        item.message = 'Uploading…';
      });
      try {
        final caption = item.caption.text.trim().isNotEmpty ? item.caption.text.trim() : _caption.text.trim();
        final media = await widget.service.uploadMedia(
          requesterRole: _role,
          actor: widget.user,
          image: item.file.image!,
          mediaId: item.mediaId,
          category: item.category ?? _category,
          alt: LocalizedText(en: item.alt.text.trim()),
          caption: LocalizedText(en: caption),
          inGallery: _inGallery,
          decorative: item.decorative ?? _decorative,
        );
        final notes = <String>[];
        for (final albumId in _albums) {
          final album = widget.albums.where((a) => a.id == albumId).firstOrNull;
          try {
            await widget.service.albums.addMedia(requesterRole: _role, actor: widget.user, albumId: albumId, mediaIds: [media.id]);
          } on WebsiteContentException catch (e) {
            notes.add('not added to “${album?.name ?? 'album'}”: ${e.message}');
          } catch (_) {
            notes.add('not added to “${album?.name ?? 'album'}” (it couldn’t be changed)');
          }
        }
        // Approval and consent, only as the admin set them for this image,
        // through the library's own confirmation (and its audit entry).
        var confirmed = media.consentConfirmed;
        String? consentProblem;
        if (item.consent && !confirmed) {
          try {
            await widget.service.confirmConsent(requesterRole: _role, actor: widget.user, mediaId: media.id, bulk: item.consentForAll);
            confirmed = true;
          } on WebsiteContentException catch (e) {
            consentProblem = e.message;
          } catch (_) {
            consentProblem = 'it couldn’t be saved';
          }
        }
        if (!_uploaded.contains(media.id)) _uploaded.add(media.id);
        if (!mounted) return;
        setState(() {
          item.state = _UploadState.done;
          final uploaded = notes.isEmpty ? 'Uploaded (draft).' : 'Uploaded (draft), but ${notes.join('; ')}. Add it from the library.';
          final consent = confirmed
              ? 'Approval and consent confirmed.'
              : consentProblem != null
                  ? 'Approval and consent NOT recorded ($consentProblem): confirm them in the library before publishing.'
                  : 'Approval and consent not confirmed: it can’t be published until they are confirmed in the library.';
          item.message = '$uploaded $consent';
        });
      } on WebsiteContentException catch (e) {
        if (mounted) setState(() => (item..state = _UploadState.failed).message = e.message);
      } catch (_) {
        if (mounted) setState(() => (item..state = _UploadState.failed).message = 'The image could not be uploaded. Check your connection and try again.');
      }
    }
    if (mounted) setState(() => _running = false);
  }

  List<_UploadItem> get _toUpload => [
    for (final i in _items)
      if (i.pending && i.file.image != null) i,
  ];
  List<_UploadItem> get _retryable => [
    for (final i in _items)
      if (!i.removed && (i.state == _UploadState.failed || i.state == _UploadState.cancelled)) i,
  ];

  int _count(_UploadState s) => _items.where((i) => !i.removed && i.state == s).length;

  /// The images of this upload whose approval and consent can still be set
  /// here (not left out, not invalid, not yet uploaded).
  List<_UploadItem> get _consentable => [
    for (final i in _items)
      if (i.pending && i.file.image != null) i,
  ];

  /// The "all" action: only after the admin agrees to the statement, and
  /// only for this upload's images; each can be unticked afterwards.
  Future<void> _confirmAll() async {
    final items = _consentable;
    if (items.isEmpty || _running) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('website-upload-consent-all-dialog'),
        title: const Text('Confirm approval and consent'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                uploadConsentStatement,
                key: Key('website-upload-consent-all-statement'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'This applies to the ${_images(items.length)} in this upload only, not to any other image in the library. '
                'It is your confirmation, not a check: untick any photograph that isn’t approved or whose consent you don’t have.',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(key: const Key('website-upload-consent-all-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-upload-consent-all-confirm'), onPressed: () => Navigator.pop(context, true), child: Text('Confirm for ${_images(items.length)}')),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      for (final i in items) {
        i
          ..consent = true
          ..consentForAll = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _items.where((i) => !i.removed && i.state != _UploadState.invalid).length;
    final done = _count(_UploadState.done);
    final failed = _count(_UploadState.failed);
    final invalid = _count(_UploadState.invalid);
    final cancelled = _count(_UploadState.cancelled);
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Wait for the current image to finish, or stop the upload first.')));
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(title: Text(_started ? 'Uploading images' : 'Review ${_images(_items.where((i) => !i.removed).length)}'), automaticallyImplyLeading: !_running),
        body: ListView(
          key: const Key('website-upload-review'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '$valid ready to upload${invalid == 0 ? '' : ', $invalid can’t be uploaded'}. Images are uploaded as drafts: nothing is on the website until consent is confirmed and they are published in the library.',
              key: const Key('website-upload-summary'),
              style: const TextStyle(fontSize: 13),
            ),
            if (_started) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(key: const Key('website-upload-progress'), value: valid == 0 ? 0 : (done + failed + cancelled) / valid),
              const SizedBox(height: 4),
              Text(
                '$done uploaded · $failed failed${cancelled == 0 ? '' : ' · $cancelled cancelled'}${_running ? ' · uploading…' : ''}',
                key: const Key('website-upload-status'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            _defaults(),
            const SizedBox(height: 12),
            for (final (i, item) in _items.indexed)
              if (!item.removed) _row(i, item),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_running)
                  OutlinedButton(key: const Key('website-upload-stop'), onPressed: _stop ? null : () => setState(() => _stop = true), child: Text(_stop ? 'Stopping after this image…' : 'Stop'))
                else ...[
                  TextButton(key: const Key('website-upload-cancel'), onPressed: () => Navigator.of(context).pop(List<String>.of(_uploaded)), child: Text(_started ? 'Done' : 'Cancel')),
                  if (_started && _retryable.isNotEmpty)
                    OutlinedButton.icon(
                      key: const Key('website-upload-retry-failed'),
                      onPressed: () => _run(_retryable),
                      icon: const Icon(Icons.refresh),
                      label: Text('Retry ${_images(_retryable.length)}'),
                    ),
                  if (!_started)
                    FilledButton.icon(
                      key: const Key('website-upload-confirm'),
                      onPressed: _toUpload.isEmpty ? null : () => _run(_toUpload),
                      icon: const Icon(Icons.upload_outlined),
                      label: Text('Upload ${_images(_toUpload.length)}'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaults() {
    final locked = _started;
    return Card(
      key: const Key('website-upload-defaults'),
      color: AppColors.card,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Settings for every image', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text(
              'Change any image below to give it its own. Alt text is per image (optional): describe each photograph, or mark it decorative.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GalleryCategory>(
              key: const Key('website-upload-default-category'),
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder(), isDense: true),
              items: [for (final c in GalleryCategory.values) DropdownMenuItem(value: c, child: Text(c.en))],
              onChanged: locked ? null : (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('website-upload-default-caption'),
              controller: _caption,
              enabled: !locked,
              maxLength: WebsiteContentAdminService.maxCaptionLength,
              decoration: const InputDecoration(labelText: 'Caption (English, optional)', border: OutlineInputBorder(), isDense: true),
            ),
            SwitchListTile(
              key: const Key('website-upload-default-gallery'),
              contentPadding: EdgeInsets.zero,
              value: _inGallery,
              onChanged: locked ? null : (v) => setState(() => _inGallery = v),
              title: const Text('Show in the gallery'),
              subtitle: const Text('Once published. Off: only for use on pages.'),
            ),
            SwitchListTile(
              key: const Key('website-upload-default-decorative'),
              contentPadding: EdgeInsets.zero,
              value: _decorative,
              onChanged: locked ? null : (v) => setState(() => _decorative = v),
              title: const Text('Decorative images'),
              subtitle: const Text('Screen readers skip them.'),
            ),
            if (widget.albums.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('Add to albums', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final a in widget.albums)
                    FilterChip(
                      key: Key('website-upload-default-album-${a.id}'),
                      label: Text(a.name),
                      selected: _albums.contains(a.id),
                      onSelected: locked ? null : (on) => setState(() => on ? _albums.add(a.id) : _albums.remove(a.id)),
                    ),
                ],
              ),
            ],
            const Divider(height: 24),
            const Text('Photo approval and consent', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text(
              'Uploading never confirms them. Tick each image below that is approved by the school and has the required consent, or use the button for all of them; '
              'images left unticked upload as drafts that can’t be published until confirmed in the library. Alt text is only a description for screen readers.',
              key: Key('website-upload-consent-note'),
              style: TextStyle(fontSize: 12, color: Color(0xFF8A6A33)),
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final shown = [for (final i in _items) if (!i.removed && i.state != _UploadState.invalid) i];
              final yes = shown.where((i) => i.consent).length;
              return Text(
                '$yes of ${_images(shown.length)} confirmed · ${shown.length - yes} not confirmed',
                key: const Key('website-upload-consent-summary'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: yes < shown.length ? const Color(0xFFB3261E) : const Color(0xFF2E7D5B)),
              );
            }),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('website-upload-consent-all'),
                onPressed: _running || _consentable.isEmpty ? null : _confirmAll,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Apply approval and consent confirmation to all selected images'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int i, _UploadItem item) {
    final k = 'website-upload-file-$i';
    final (icon, color) = switch (item.state) {
      _UploadState.waiting => (Icons.schedule, AppColors.textSecondary),
      _UploadState.uploading => (Icons.cloud_upload_outlined, AppColors.primary),
      _UploadState.done => (Icons.check_circle, const Color(0xFF2E7D5B)),
      _UploadState.failed => (Icons.error_outline, const Color(0xFFB3261E)),
      _UploadState.invalid => (Icons.block, const Color(0xFFB3261E)),
      _UploadState.cancelled => (Icons.pause_circle_outline, const Color(0xFF8A6A33)),
    };
    final editable = item.editable && !_running;
    return Card(
      key: Key(k),
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                if (item.file.image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      item.file.image!.bytes,
                      key: Key('$k-thumb'),
                      width: 56,
                      height: 56,
                      cacheWidth: 112,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Container(width: 56, height: 56, color: Colors.black12, child: const Icon(Icons.image_outlined, size: 22, color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The file name is shown here only; it is never stored.
                      Text(
                        item.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_size(item.file.size)}${item.message.isEmpty ? '' : ' · ${item.message}'}',
                        key: Key('$k-status'),
                        style: TextStyle(fontSize: 12, color: item.state == _UploadState.failed || item.state == _UploadState.invalid ? const Color(0xFFB3261E) : AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (_started && !_running && (item.state == _UploadState.failed || item.state == _UploadState.cancelled))
                  TextButton(key: Key('$k-retry'), onPressed: () => _run([item]), child: const Text('Retry')),
                if (!_started) IconButton(key: Key('$k-remove'), tooltip: 'Leave this file out', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => item.removed = true)),
              ],
            ),
            if (item.state == _UploadState.uploading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
            if (item.state != _UploadState.invalid && item.state != _UploadState.done)
              CheckboxListTile(
                key: Key('$k-consent'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: item.consent,
                onChanged: editable
                    ? (v) => setState(() {
                          item
                            ..consent = v ?? false
                            ..consentForAll = false;
                        })
                    : null,
                title: const Text('Photo approved by the school and consent obtained'),
                subtitle: Text(
                  item.consent ? 'Confirmed${item.consentForAll ? ' (for all images)' : ''}.' : 'Not confirmed: it can’t be published until confirmed.',
                  key: Key('$k-consent-state'),
                  style: TextStyle(fontSize: 12, color: item.consent ? const Color(0xFF2E7D5B) : const Color(0xFFB3261E)),
                ),
              ),
            if (item.state != _UploadState.invalid && item.state != _UploadState.done)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: Key('$k-details'),
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    item.alt.text.trim().isEmpty ? 'Alt text, caption and settings (optional)' : 'Alt text: ${item.alt.text.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  children: [
                    TextField(
                      key: Key('$k-alt'),
                      controller: item.alt,
                      enabled: editable,
                      maxLength: WebsiteContentAdminService.maxAltLength,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Alt text (English, optional)', border: OutlineInputBorder(), isDense: true),
                    ),
                    TextField(
                      key: Key('$k-caption'),
                      controller: item.caption,
                      enabled: editable,
                      maxLength: WebsiteContentAdminService.maxCaptionLength,
                      decoration: const InputDecoration(labelText: 'Caption (empty: the shared caption)', border: OutlineInputBorder(), isDense: true),
                    ),
                    DropdownButtonFormField<GalleryCategory?>(
                      key: Key('$k-category'),
                      initialValue: item.category,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder(), isDense: true),
                      items: [
                        DropdownMenuItem<GalleryCategory?>(value: null, child: Text('As set for every image (${_category.en})')),
                        for (final c in GalleryCategory.values) DropdownMenuItem<GalleryCategory?>(value: c, child: Text(c.en)),
                      ],
                      onChanged: editable ? (v) => setState(() => item.category = v) : null,
                    ),
                    CheckboxListTile(
                      key: Key('$k-decorative'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: item.decorative ?? _decorative,
                      onChanged: editable ? (v) => setState(() => item.decorative = v) : null,
                      title: const Text('Decorative image'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ albums

/// Asks for an album's name (required) and description (optional); null
/// when cancelled.
Future<(String, String)?> showAlbumDetailsDialog(BuildContext context, {WebsiteAlbum? album}) => showDialog<(String, String)>(
  context: context,
  builder: (context) => _AlbumDetailsDialog(album: album),
);

class _AlbumDetailsDialog extends StatefulWidget {
  const _AlbumDetailsDialog({this.album});

  final WebsiteAlbum? album;

  @override
  State<_AlbumDetailsDialog> createState() => _AlbumDetailsDialogState();
}

class _AlbumDetailsDialogState extends State<_AlbumDetailsDialog> {
  late final _name = TextEditingController(text: widget.album?.name ?? '');
  late final _description = TextEditingController(text: widget.album?.description ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('website-album-dialog'),
      title: Text(widget.album == null ? 'New album' : 'Edit album'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('website-album-name'),
              controller: _name,
              autofocus: true,
              maxLength: WebsiteAlbum.maxName,
              decoration: InputDecoration(labelText: 'Name', border: const OutlineInputBorder(), errorText: _error),
            ),
            TextField(
              key: const Key('website-album-description'),
              controller: _description,
              maxLength: WebsiteAlbum.maxDescription,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
            const Text('Albums only organise the library: they don’t publish, hide or change any image, and visitors never see them.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      actions: [
        TextButton(key: const Key('website-album-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('website-album-save'),
          onPressed: () {
            if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter a name for the album.');
            Navigator.pop(context, (_name.text.trim(), _description.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The library's albums: search, create, rename and describe, delete
/// (the images stay), each with its number of images. Pops the id of an
/// album to show in the library ("Show images"), or null.
class WebsiteAlbumsScreen extends StatefulWidget {
  const WebsiteAlbumsScreen({super.key, required this.service, required this.user, required this.media});

  final WebsiteContentAdminService service;
  final AppUser user;
  final List<WebsiteMedia> media;

  @override
  State<WebsiteAlbumsScreen> createState() => _WebsiteAlbumsScreenState();
}

class _WebsiteAlbumsScreenState extends State<WebsiteAlbumsScreen> {
  List<WebsiteAlbum>? _albums;
  String? _error;
  final _search = TextEditingController();

  String get _role => widget.user.role.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final albums = await widget.service.albums.list(requesterRole: _role);
      if (mounted) {
        setState(() {
          _albums = albums;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Albums could not be loaded. ${e is WebsiteContentException ? e.message : 'Check your connection and try again.'}');
    }
  }

  Future<void> _do(Future<void> Function() action) async {
    String? problem;
    try {
      await action();
    } on WebsiteContentException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = 'The album couldn’t be changed. Check your connection and try again.';
    }
    if (problem != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problem)));
    await _load();
  }

  Future<void> _create() async {
    final details = await showAlbumDetailsDialog(context);
    if (details == null || !mounted) return;
    await _do(() => widget.service.albums.create(requesterRole: _role, actor: widget.user, name: details.$1, description: details.$2));
  }

  Future<void> _edit(WebsiteAlbum album) async {
    final details = await showAlbumDetailsDialog(context, album: album);
    if (details == null || !mounted) return;
    await _do(() => widget.service.albums.update(requesterRole: _role, actor: widget.user, albumId: album.id, name: details.$1, description: details.$2));
  }

  Future<void> _delete(WebsiteAlbum album) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${album.name}”?'),
        content: const Text('Only the album is deleted. Its images stay in the library, with their publication, gallery and consent settings unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('website-album-delete-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Delete album')),
        ],
      ),
    );
    if (ok == true && mounted) await _do(() => widget.service.albums.delete(requesterRole: _role, albumId: album.id));
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final shown = [
      for (final a in albums ?? const <WebsiteAlbum>[])
        if (a.matches(_search.text)) a,
    ];
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Albums')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('website-albums-create'),
        onPressed: _create,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New album'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          TextField(
            key: const Key('website-albums-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search albums', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(
              _error!,
              key: const Key('website-albums-error'),
              style: const TextStyle(color: Color(0xFFB3261E)),
            )
          else if (albums == null)
            const Center(child: CircularProgressIndicator())
          else if (albums.isEmpty)
            const Text('No albums yet. Albums group library images, for example by term or event; an image can be in several.', key: Key('website-albums-empty'))
          else if (shown.isEmpty)
            const Text('No album matches your search.', key: Key('website-albums-no-match'))
          else
            for (final a in shown)
              Card(
                key: Key('website-album-${a.id}'),
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.photo_album_outlined),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [
                      _images(a.availableIn(widget.media).length),
                      if (a.mediaIds.length > a.availableIn(widget.media).length) '${a.mediaIds.length - a.availableIn(widget.media).length} no longer in the library',
                      if (a.description.isNotEmpty) a.description,
                    ].join(' · '),
                    key: Key('website-album-${a.id}-count'),
                  ),
                  onTap: () => Navigator.of(context).pop(a.id),
                  trailing: Wrap(
                    children: [
                      IconButton(key: Key('website-album-${a.id}-edit'), tooltip: 'Rename or describe', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(a)),
                      IconButton(key: Key('website-album-${a.id}-delete'), tooltip: 'Delete album (images are kept)', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(a)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ library

/// The filter values that aren't an album id.
const _allImages = '__all__';
const _noAlbum = '__none__';

/// The media library list: upload (several at once), albums, an album
/// filter, selection (one by one, all shown, clear) and bulk actions. Each
/// bulk action goes image by image through the single-image workflow, so
/// every check still applies, and reports each image's result.
class WebsiteMediaLibraryTab extends StatefulWidget {
  const WebsiteMediaLibraryTab({
    super.key,
    required this.service,
    required this.user,
    required this.media,
    required this.albums,
    required this.albumsError,
    required this.uploading,
    required this.onUpload,
    required this.onOpen,
    required this.onChanged,
    required this.note,
  });

  final WebsiteContentAdminService service;
  final AppUser user;
  final List<WebsiteMedia> media;
  final List<WebsiteAlbum> albums;

  /// Why the albums couldn't be loaded (the library still works).
  final String? albumsError;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<WebsiteMedia> onOpen;

  /// After a bulk change or an albums change: reload ([publicChange]: the
  /// website may have changed too).
  final Future<void> Function({bool publicChange}) onChanged;

  /// Shown above the list (the privacy note).
  final Widget note;

  @override
  State<WebsiteMediaLibraryTab> createState() => _WebsiteMediaLibraryTabState();
}

class _WebsiteMediaLibraryTabState extends State<WebsiteMediaLibraryTab> {
  final Set<String> _selected = {};
  String _filter = _allImages;
  bool _busy = false;

  String get _role => widget.user.role.toLowerCase();

  Set<String> get _inSomeAlbum => {for (final a in widget.albums) ...a.mediaIds};

  List<WebsiteMedia> get _visible {
    final album = widget.albums.where((a) => a.id == _filter).firstOrNull;
    return switch (_filter) {
      _allImages => widget.media,
      _noAlbum => [
        for (final m in widget.media)
          if (!_inSomeAlbum.contains(m.id)) m,
      ],
      _ => album == null ? widget.media : [for (final id in album.availableIn(widget.media)) widget.media.firstWhere((m) => m.id == id)],
    };
  }

  List<WebsiteMedia> get _selection => [
    for (final m in widget.media)
      if (_selected.contains(m.id)) m,
  ];

  @override
  void didUpdateWidget(WebsiteMediaLibraryTab old) {
    super.didUpdateWidget(old);
    // Forget images that are gone, and an album filter whose album is.
    final known = {for (final m in widget.media) m.id};
    _selected.retainWhere(known.contains);
    if (_filter != _allImages && _filter != _noAlbum && !widget.albums.any((a) => a.id == _filter)) _filter = _allImages;
  }

  Future<void> _openAlbums() async {
    final show = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WebsiteAlbumsScreen(service: widget.service, user: widget.user, media: widget.media),
      ),
    );
    await widget.onChanged();
    if (show != null && mounted) {
      setState(() {
        _filter = show;
        final shown = {for (final m in _visible) m.id};
        _selected.retainWhere(shown.contains);
      });
    }
  }

  /// Why each bulk action can or can't be done for the selection.
  String _explain(WebsiteBulkAction action, List<WebsiteMedia> sel) {
    int count(bool Function(WebsiteMedia) test) => sel.where(test).length;
    String also(int n, String what) => n == 0 ? '' : '; ${_images(n)} $what';
    switch (action) {
      case WebsiteBulkAction.confirmConsent:
        final todo = count((m) => !m.consentConfirmed);
        return todo == 0 ? 'Consent is already confirmed for all of them' : '${_images(todo)} to confirm${also(sel.length - todo, 'already confirmed')}';
      case WebsiteBulkAction.publish:
        final ready = count((m) => !m.isPublished && m.publishBlocker == null);
        return '${_images(ready)} can be published${also(count((m) => !m.isPublished && !m.consentConfirmed), 'need consent confirmed first')}${also(count((m) => m.isPublished), 'already published')}';
      case WebsiteBulkAction.unpublish:
        return '${_images(count((m) => m.isPublished))} published${also(count((m) => !m.isPublished), 'not published')}. Images shown on a published page, event or form are kept until that changes.';
      case WebsiteBulkAction.addToGallery:
        return '${_images(count((m) => !m.inGallery))} to add${also(count((m) => m.inGallery), 'already in it')}. Shown there once published.';
      case WebsiteBulkAction.removeFromGallery:
        return '${_images(count((m) => m.inGallery))} to remove${also(count((m) => !m.inGallery), 'not in it')}. Pages using them are unchanged.';
      case WebsiteBulkAction.delete:
        return 'Images used on pages, forms, events or templates are kept (each is checked).';
    }
  }

  Future<bool> _confirm(String key, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 440, child: Text(body)),
          actions: [
            TextButton(key: Key('$key-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(key: Key(key), onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _bulk(WebsiteBulkAction action) async {
    final sel = _selection;
    if (sel.isEmpty || _busy) return;
    if (action == WebsiteBulkAction.delete &&
        !await _confirm(
          'website-bulk-delete-confirm',
          'Delete ${_images(sel.length)}?',
          'Each image and its files are deleted for good. An image used on a page (draft or published), form, event, announcement or template is not deleted, and is listed with where it is used.',
          'Delete',
        )) {
      return;
    }
    if (action == WebsiteBulkAction.confirmConsent) {
      final todo = sel.where((m) => !m.consentConfirmed).length;
      if (!mounted ||
          !await _confirm(
            'website-bulk-consent-confirm',
            'Confirm consent for ${_images(todo)}?',
            'You confirm that every one of these photographs is approved by the school and that consent has been obtained for each child who can be identified in it. '
                'Look at each image before confirming. This is recorded, with your name, in each image’s history. It doesn’t publish anything.',
            'I confirm for all ${_images(todo)}',
          )) {
        return;
      }
    }
    setState(() => _busy = true);
    List<WebsiteBulkOutcome> outcomes;
    try {
      outcomes = await widget.service.applyBulk(requesterRole: _role, actor: widget.user, action: action, mediaIds: [for (final m in sel) m.id]);
    } catch (_) {
      outcomes = [for (final m in sel) WebsiteBulkOutcome(m.id, WebsiteBulkStatus.failed, 'It couldn’t be changed. Check your connection and try again.')];
    }
    final labels = {for (final m in sel) m.id: m};
    await widget.onChanged(publicChange: action != WebsiteBulkAction.confirmConsent);
    if (!mounted) return;
    setState(() => _busy = false);
    await _showResults(action.label, outcomes, labels);
  }

  Future<void> _album({required bool add}) async {
    final sel = _selection;
    if (sel.isEmpty || _busy || widget.albums.isEmpty) return;
    final album = await showDialog<WebsiteAlbum>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(add ? 'Add ${_images(sel.length)} to album' : 'Remove ${_images(sel.length)} from album'),
        children: [
          for (final a in widget.albums)
            SimpleDialogOption(key: Key('website-album-pick-${a.id}'), onPressed: () => Navigator.pop(context, a), child: Text('${a.name} (${_images(a.availableIn(widget.media).length)})')),
        ],
      ),
    );
    if (album == null || !mounted) return;
    setState(() => _busy = true);
    final ids = [for (final m in sel) m.id];
    List<WebsiteBulkOutcome> outcomes;
    try {
      final changing = [
        for (final id in ids)
          if (album.mediaIds.contains(id) != add) id,
      ];
      if (add) {
        await widget.service.albums.addMedia(requesterRole: _role, actor: widget.user, albumId: album.id, mediaIds: changing);
      } else {
        await widget.service.albums.removeMedia(requesterRole: _role, actor: widget.user, albumId: album.id, mediaIds: changing);
      }
      outcomes = [
        for (final id in ids)
          changing.contains(id) ? WebsiteBulkOutcome(id, WebsiteBulkStatus.done) : WebsiteBulkOutcome(id, WebsiteBulkStatus.unchanged, add ? 'Already in “${album.name}”.' : 'Not in “${album.name}”.'),
      ];
    } on WebsiteContentException catch (e) {
      outcomes = [for (final id in ids) WebsiteBulkOutcome(id, WebsiteBulkStatus.failed, e.message)];
    } catch (_) {
      outcomes = [for (final id in ids) WebsiteBulkOutcome(id, WebsiteBulkStatus.failed, 'The album couldn’t be changed. Check your connection and try again.')];
    }
    final labels = {for (final m in sel) m.id: m};
    await widget.onChanged();
    if (!mounted) return;
    setState(() => _busy = false);
    await _showResults(add ? 'Add to “${album.name}”' : 'Remove from “${album.name}”', outcomes, labels);
  }

  Future<void> _showResults(String title, List<WebsiteBulkOutcome> outcomes, Map<String, WebsiteMedia> media) {
    int n(WebsiteBulkStatus s) => outcomes.where((o) => o.status == s).length;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('website-bulk-results'),
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${n(WebsiteBulkStatus.done)} done · ${n(WebsiteBulkStatus.unchanged)} unchanged · ${n(WebsiteBulkStatus.failed)} failed',
                key: const Key('website-bulk-summary'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in outcomes)
                      ListTile(
                        key: Key('website-bulk-result-${o.mediaId}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (o.status) {
                            WebsiteBulkStatus.done => Icons.check_circle,
                            WebsiteBulkStatus.unchanged => Icons.remove_circle_outline,
                            WebsiteBulkStatus.failed => Icons.error_outline,
                          },
                          color: switch (o.status) {
                            WebsiteBulkStatus.done => const Color(0xFF2E7D5B),
                            WebsiteBulkStatus.unchanged => AppColors.textSecondary,
                            WebsiteBulkStatus.failed => const Color(0xFFB3261E),
                          },
                        ),
                        title: Text(media[o.mediaId] == null ? 'Image' : mediaLabel(media[o.mediaId]!), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(o.status == WebsiteBulkStatus.done ? 'Done.' : o.message),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [FilledButton(key: const Key('website-bulk-results-close'), onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _bulkMenu() {
    final sel = _selection;
    final enabled = sel.isNotEmpty && !_busy;
    PopupMenuItem<String> item(String value, String title, String subtitle, {bool on = true}) => PopupMenuItem<String>(
      key: Key('website-media-bulk-$value'),
      value: value,
      enabled: on,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
    );
    return PopupMenuButton<String>(
      key: const Key('website-media-bulk'),
      enabled: enabled,
      tooltip: sel.isEmpty ? 'Select images first' : 'Actions for ${_images(sel.length)}',
      onSelected: (v) {
        if (v == 'add-album') {
          _album(add: true);
        } else if (v == 'remove-album') {
          _album(add: false);
        } else {
          _bulk(WebsiteBulkAction.values.firstWhere((a) => a.name == v));
        }
      },
      itemBuilder: (context) => [
        for (final a in WebsiteBulkAction.values) item(a.name, a == WebsiteBulkAction.delete ? 'Delete…' : (a == WebsiteBulkAction.confirmConsent ? 'Confirm consent…' : a.label), _explain(a, sel)),
        const PopupMenuDivider(),
        item('add-album', 'Add to album…', widget.albums.isEmpty ? 'Create an album first (Albums).' : 'Choose an album; images already in it stay.', on: widget.albums.isNotEmpty),
        item('remove-album', 'Remove from album…', widget.albums.isEmpty ? 'No albums yet.' : 'The images themselves are unchanged.', on: widget.albums.isNotEmpty),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(Icons.checklist, color: enabled ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              _busy ? 'Working…' : 'Actions',
              style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? AppColors.primary : AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final inAlbum = _inSomeAlbum;
    final allVisibleSelected = visible.isNotEmpty && visible.every((m) => _selected.contains(m.id));
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
              onPressed: widget.uploading ? null : widget.onUpload,
              icon: widget.uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_outlined),
              label: Text(widget.uploading ? 'Uploading…' : 'Upload images'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
            OutlinedButton.icon(key: const Key('website-albums-manage'), onPressed: _openAlbums, icon: const Icon(Icons.photo_album_outlined), label: const Text('Albums')),
            const Text('JPEG, PNG or WebP, up to 15 MB each. Choose several at once.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        widget.note,
        const SizedBox(height: 12),
        if (widget.albumsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.albumsError!,
              key: const Key('website-media-albums-error'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A33)),
            ),
          ),
        if (widget.media.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: DropdownButton<String>(
                  isExpanded: true,
                  key: const Key('website-media-album-filter'),
                  value: _filter,
                  onChanged: (v) => setState(() {
                    _filter = v ?? _allImages;
                    // Bulk actions act only on images that are shown.
                    final shown = {for (final m in _visible) m.id};
                    _selected.retainWhere(shown.contains);
                  }),
                  items: [
                    DropdownMenuItem(
                      value: _allImages,
                      child: Text('All images (${widget.media.length})', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: _noAlbum,
                      child: Text('Not in an album (${widget.media.where((m) => !inAlbum.contains(m.id)).length})', overflow: TextOverflow.ellipsis),
                    ),
                    for (final a in widget.albums)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (${a.availableIn(widget.media).length})', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('website-media-select-all'),
                onPressed: visible.isEmpty || allVisibleSelected ? null : () => setState(() => _selected.addAll(visible.map((m) => m.id))),
                child: Text('Select all shown (${visible.length})'),
              ),
              TextButton(key: const Key('website-media-clear-selection'), onPressed: _selected.isEmpty ? null : () => setState(_selected.clear), child: const Text('Clear selection')),
              Text(
                '${_selected.length} selected',
                key: const Key('website-media-selection-count'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _bulkMenu(),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (widget.media.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('No images yet. Uploaded images stay private (draft) until you publish them.', textAlign: TextAlign.center),
          )
        else if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No images here.', key: Key('website-media-filter-empty'), textAlign: TextAlign.center),
          )
        else
          for (final item in visible)
            Card(
              key: Key('website-media-${item.id}'),
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Checkbox(
                    key: Key('website-media-${item.id}-select'),
                    value: _selected.contains(item.id),
                    onChanged: (on) => setState(() => on == true ? _selected.add(item.id) : _selected.remove(item.id)),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
                      leading: WebsiteMediaThumb(media: item),
                      title: Text(
                        item.alt.en.isNotEmpty ? item.alt.en : (item.decorative ? 'Decorative image' : 'No alt text (optional)'),
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
                            for (final a in widget.albums)
                              if (a.mediaIds.contains(item.id))
                                Text(
                                  '▪ ${a.name}',
                                  key: Key('website-media-${item.id}-album-${a.id}'),
                                  style: const TextStyle(fontSize: 12, color: AppColors.primary),
                                ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onOpen(item),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
