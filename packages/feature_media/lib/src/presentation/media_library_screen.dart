import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/approved_media_types.dart';
import '../domain/media_asset.dart';
import '../domain/media_mime_category.dart';
import '../domain/media_repository.dart';
import '../domain/media_upload_request.dart';
import '../domain/media_usage_reference.dart';
import 'media_library_controller.dart';
import 'media_metadata_dialog.dart';

/// The Media Library management screen (SRS MED-01..MED-06): search/
/// filter, upload with progress feedback, and per-asset management
/// (edit metadata, archive/restore, usage references, permanent
/// delete). No own [Scaffold]/[AppBar] — embedded like
/// `PagesListScreen`/`UserManagementScreen`.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key, required this.controller});

  final MediaLibraryController controller;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  final _searchController = TextEditingController();
  MediaMimeCategory? _categoryFilter;
  bool _showArchived = false;

  /// Set when [FilePicker.platform.pickFiles] itself throws (a real
  /// platform/browser-level failure — permission denied, an
  /// unregistered/misconfigured web implementation, an unsupported
  /// browser, etc.) or returns a file with no readable bytes. Rendered
  /// as a [MaterialBanner] the same way [MediaLibraryController]'s own
  /// [MediaLibraryController.lastErrorMessage] already is — deliberately
  /// NOT a [SnackBar]: this screen has no ancestor [Scaffold] of its own
  /// (see the class doc comment), and a banner stays visible until
  /// dismissed rather than auto-disappearing, which matters for an error
  /// an administrator needs time to read and act on.
  String? _pickerErrorMessage;

  @override
  void initState() {
    super.initState();
    widget.controller.loadAssets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    widget.controller.loadAssets(
      query: MediaFilter(
        searchText: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        category: _categoryFilter,
        includeArchived: _showArchived,
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _pickerErrorMessage = null);

    final FilePickerResult? result;
    try {
      // Called as the very first statement of this handler (nothing
      // awaited before it) so the platform file-input is triggered
      // synchronously within the button's click — required on Web,
      // where some browsers refuse to open a file picker that wasn't
      // triggered directly by a user gesture.
      result = await FilePicker.platform.pickFiles(withData: true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _pickerErrorMessage = 'Could not open the file picker: $error',
      );
      return;
    }

    if (result == null) return; // User cancelled — not an error.
    final file = result.files.singleOrNull;
    if (file == null || file.bytes == null) {
      if (!mounted) return;
      setState(
        () => _pickerErrorMessage =
            'The selected file could not be read. Please try again.',
      );
      return;
    }
    if (!mounted) return;

    final mimeType = _guessMimeType(file.extension);
    final metadata = await showDialog<MediaMetadataDialogResult>(
      context: context,
      builder: (_) => MediaMetadataDialog(initialTitle: file.name),
    );
    if (metadata == null || !mounted) return;

    await widget.controller.uploadFile(
      MediaUploadRequest(
        bytes: file.bytes!,
        fileName: file.name,
        mimeType: mimeType,
        title: metadata.title,
        altText: metadata.altText,
        description: metadata.description,
      ),
    );
    if (!mounted) return;
    _reload();
  }

  static String _guessMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _editMetadata(MediaAsset asset) async {
    final metadata = await showDialog<MediaMetadataDialogResult>(
      context: context,
      builder: (_) => MediaMetadataDialog(
        initialTitle: asset.title,
        initialAltText: asset.altText,
        initialDescription: asset.description,
      ),
    );
    if (metadata == null) return;
    await widget.controller.updateMetadata(
      asset,
      title: metadata.title,
      altText: metadata.altText,
      description: metadata.description,
    );
  }

  Future<void> _showUsages(MediaAsset asset) async {
    final usages = await widget.controller.loadUsages(asset.mediaId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _UsagesDialog(asset: asset, usages: usages),
    );
  }

  Future<void> _confirmDelete(MediaAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete this asset?'),
        content: Text(
          'This cannot be undone. "${asset.title}" will be removed from Storage and Firestore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.delete(asset);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search media',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _reload(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<MediaMimeCategory?>(
                    value: _categoryFilter,
                    hint: const Text('All types'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All types'),
                      ),
                      ...MediaMimeCategory.values.map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.storageValue),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _categoryFilter = value);
                      _reload();
                    },
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('Recycle bin'),
                    selected: _showArchived,
                    onSelected: (selected) {
                      setState(() => _showArchived = selected);
                      _reload();
                    },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: controller.uploadProgress != null
                        ? null
                        : _pickAndUpload,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Upload'),
                  ),
                ],
              ),
            ),
            if (controller.uploadProgress != null ||
                controller.uploadStatusMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (controller.uploadProgress != null)
                      Expanded(
                        child: LinearProgressIndicator(
                          value: controller.uploadProgress,
                        ),
                      )
                    else
                      Expanded(
                        child: Text(controller.uploadStatusMessage ?? ''),
                      ),
                  ],
                ),
              ),
            if (controller.lastErrorMessage != null)
              MaterialBanner(
                content: Text(controller.lastErrorMessage!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            if (_pickerErrorMessage != null)
              MaterialBanner(
                content: Text(_pickerErrorMessage!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _pickerErrorMessage = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            if (controller.isBusy)
              const LinearProgressIndicator()
            else if (controller.assets.isEmpty)
              const Expanded(child: Center(child: Text('No media yet.')))
            else
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: controller.assets.length,
                  itemBuilder: (context, index) => _MediaCard(
                    asset: controller.assets[index],
                    canManage: controller.canManageAsset(
                      controller.assets[index],
                    ),
                    isArchived: _showArchived,
                    approvedType: approvedMediaTypeFor(
                      controller.assets[index].mimeType,
                    ),
                    onEdit: () => _editMetadata(controller.assets[index]),
                    onArchive: () =>
                        controller.archive(controller.assets[index]),
                    onRestore: () =>
                        controller.restore(controller.assets[index]),
                    onShowUsages: () => _showUsages(controller.assets[index]),
                    onDelete: () => _confirmDelete(controller.assets[index]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.asset,
    required this.canManage,
    required this.isArchived,
    required this.approvedType,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onShowUsages,
    required this.onDelete,
  });

  final MediaAsset asset;
  final bool canManage;
  final bool isArchived;
  final ApprovedMediaType? approvedType;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onShowUsages;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final thumbnail = asset.thumbnailVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: thumbnail != null
                ? Image.network(
                    thumbnail.url,
                    fit: BoxFit.cover,
                    semanticLabel: asset.altText,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  )
                : Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Icon(switch (asset.mimeCategory) {
                      MediaMimeCategory.video => Icons.videocam_outlined,
                      MediaMimeCategory.document => Icons.description_outlined,
                      _ => Icons.image_outlined,
                    }),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.title.isEmpty ? asset.fileName : asset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Chip(
                      label: Text(asset.status.storageValue),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (asset.usageCount > 0) ...[
                      const SizedBox(width: 4),
                      Text('Used ${asset.usageCount}×'),
                    ],
                  ],
                ),
                if (canManage)
                  Wrap(
                    spacing: 4,
                    children: [
                      if (!isArchived) ...[
                        IconButton(
                          tooltip: 'Edit metadata',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: onEdit,
                        ),
                        IconButton(
                          tooltip: 'Where is this used?',
                          icon: const Icon(Icons.link, size: 18),
                          onPressed: onShowUsages,
                        ),
                        IconButton(
                          tooltip: 'Archive',
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          onPressed: onArchive,
                        ),
                      ] else ...[
                        IconButton(
                          tooltip: 'Restore',
                          icon: const Icon(Icons.unarchive_outlined, size: 18),
                          onPressed: onRestore,
                        ),
                        IconButton(
                          tooltip: asset.usageCount > 0
                              ? 'In use — cannot permanently delete'
                              : 'Permanently delete',
                          icon: const Icon(Icons.delete_forever, size: 18),
                          onPressed: asset.usageCount > 0 ? null : onDelete,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsagesDialog extends StatelessWidget {
  const _UsagesDialog({required this.asset, required this.usages});

  final MediaAsset asset;
  final List<MediaUsageReference> usages;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Where "${asset.title}" is used'),
      content: SizedBox(
        width: 360,
        child: usages.isEmpty
            ? const Text('Not currently used on any page.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final usage in usages)
                    ListTile(
                      title: Text(usage.contentTitle),
                      subtitle: Text(usage.fieldPaths.join(', ')),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
