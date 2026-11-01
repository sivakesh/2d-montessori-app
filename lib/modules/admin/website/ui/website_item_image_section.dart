import 'package:flutter/material.dart';

import '../../../auth/models/app_user.dart';
import '../../../public_website/content/website_content_models.dart';
import '../data/website_content_admin_service.dart';
import '../data/website_copy_status.dart';
import 'website_content_editors.dart';
import 'website_content_screen.dart';

/// The image of a record's website copy (a calendar event or an
/// announcement), chosen from the website media library: a preview, its
/// status ([websiteImageStatus]) and Choose / Upload / Edit / Remove.
///
/// The library's own workflow does the rest: an upload goes in as a draft
/// (outside the gallery) and opens in the library's editor for alt text,
/// consent and publishing; Edit image reopens it there. Only the chosen
/// media id is reported ([onChanged]); nothing is written to the record
/// here. Keys: `<keyPrefix>`, `-preview`, `-status`, `-detail`, `-choose`,
/// `-upload`, `-edit`, `-remove`, `-error`.
class WebsiteItemImageSection extends StatefulWidget {
  const WebsiteItemImageSection({
    super.key,
    required this.media,
    required this.requesterRole,
    required this.actor,
    required this.initialMediaId,
    required this.onChanged,
    required this.keyPrefix,
    this.what = 'event',
  });

  /// The media library; null when it isn't available here (shown as such).
  final WebsiteContentAdminService? media;
  final String requesterRole;

  /// The signed-in admin, recorded in an upload's audit trail. Without one,
  /// images can be chosen but not uploaded or edited here.
  final AppUser? actor;
  final String? initialMediaId;

  /// The chosen media id, or null for no image.
  final ValueChanged<String?> onChanged;
  final String keyPrefix;

  /// "event" or "announcement", for the status text.
  final String what;

  @override
  State<WebsiteItemImageSection> createState() => _WebsiteItemImageSectionState();
}

class _WebsiteItemImageSectionState extends State<WebsiteItemImageSection> {
  late String? _imageId = widget.initialMediaId;
  List<WebsiteMedia>? _library;
  String? _libraryError;
  bool _busy = false;

  String get _k => widget.keyPrefix;

  WebsiteMedia? get _imageMedia {
    for (final m in _library ?? const <WebsiteMedia>[]) {
      if (m.id == _imageId) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final media = widget.media;
    if (media == null) {
      setState(() => _libraryError = 'it isn’t available here.');
      return;
    }
    try {
      final library = await media.listMedia(requesterRole: widget.requesterRole);
      if (mounted) setState(() => _library = library);
    } catch (e) {
      if (mounted) setState(() => _libraryError = '$e');
    }
  }

  void _set(String? id) {
    setState(() => _imageId = id);
    widget.onChanged(id);
  }

  Future<void> _choose() async {
    final chosen = await showWebsiteImagePicker(context, _library ?? const [], selected: _imageId);
    if (chosen != null) _set(chosen);
  }

  /// Uploads a new image to the library (a draft, outside the gallery) and
  /// opens it there for alt text, consent and publishing. It is chosen
  /// either way; saving needs it published.
  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final picked = await widget.media!.pickImage();
      if (picked == null) return;
      final uploaded = await widget.media!.uploadMedia(requesterRole: widget.requesterRole, actor: widget.actor!, image: picked, inGallery: false);
      _set(uploaded.id);
      await _loadLibrary();
      await _edit();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the chosen image in the library's editor (alt text, consent,
  /// publish), then shows where it stands.
  Future<void> _edit() async {
    final image = _imageMedia;
    final actor = widget.actor;
    if (image == null || actor == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebsiteMediaEditorScreen(service: widget.media!, user: actor, media: image),
    ));
    await _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final status = websiteImageStatus(_imageId, _imageMedia, what: widget.what);
    final loading = _library == null && _libraryError == null;
    final unavailable = _busy || loading || _libraryError != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        key: Key(_k),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.what[0].toUpperCase()}${widget.what.substring(1)} image', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_libraryError != null)
            Text('The media library couldn’t be loaded: $_libraryError', key: Key('$_k-error'), style: const TextStyle(fontSize: 13))
          else if (loading)
            const LinearProgressIndicator()
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WebsiteMediaThumb(key: Key('$_k-preview'), media: _imageId == null ? null : _imageMedia, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WebsiteStatusChip(key: Key('$_k-status'), label: status.label, color: status.color),
                      const SizedBox(height: 4),
                      Text(status.detail, key: Key('$_k-detail'), style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: Key('$_k-choose'),
                onPressed: unavailable ? null : _choose,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_imageId == null ? 'Choose image' : 'Replace image'),
              ),
              if (widget.actor != null)
                TextButton.icon(
                  key: Key('$_k-upload'),
                  onPressed: unavailable ? null : _upload,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const Text('Upload image'),
                ),
              if (_imageMedia != null && widget.actor != null)
                TextButton.icon(
                  key: Key('$_k-edit'),
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(status.visible ? 'Edit alt text' : 'Edit image'),
                ),
              if (_imageId != null)
                TextButton.icon(
                  key: Key('$_k-remove'),
                  onPressed: _busy ? null : () => _set(null),
                  icon: const Icon(Icons.hide_image_outlined, size: 18),
                  label: const Text('Remove image'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
