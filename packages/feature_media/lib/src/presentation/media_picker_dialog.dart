import 'package:flutter/material.dart';

import '../domain/media_asset.dart';
import '../domain/media_repository.dart';
import '../domain/media_status.dart';
import '../domain/use_cases/list_media_use_case.dart';

/// Lets an editor pick an existing, [MediaStatus.ready], non-archived
/// asset from the library — the replacement for typing a raw URL (SRS
/// "Media selection/reuse from Pages"). Returns the selected
/// [MediaAsset] itself, not a `MediaReference` — this package has no
/// concept of that type (it belongs to `feature_pages`, which depends on
/// this package, never the reverse); the caller converts the selected
/// asset's own fields (see [MediaAsset.largestVariant]/`storagePath`/
/// `altText`) into whatever reference shape it needs.
class MediaPickerDialog extends StatefulWidget {
  const MediaPickerDialog({super.key, required this.repository});

  final MediaRepository repository;

  @override
  State<MediaPickerDialog> createState() => _MediaPickerDialogState();
}

class _MediaPickerDialogState extends State<MediaPickerDialog> {
  late final _listMedia = ListMediaUseCase(widget.repository);
  final _searchController = TextEditingController();
  bool _loading = true;
  List<MediaAsset> _assets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await _listMedia(
      query: MediaFilter(
        searchText: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      ),
    );
    if (!mounted) return;
    result.fold(
      (page) => setState(() {
        _assets = page.items
            .where((a) => a.status == MediaStatus.ready)
            .toList();
        _loading = false;
      }),
      (_) => setState(() => _loading = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search media',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_assets.isEmpty)
              const Expanded(
                child: Center(child: Text('No ready media assets found.')),
              )
            else
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _assets.length,
                  itemBuilder: (context, index) {
                    final asset = _assets[index];
                    final thumbnail = asset.thumbnailVariant;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(asset),
                      child: GridTile(
                        footer: Container(
                          color: Colors.black45,
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            asset.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        child: thumbnail != null
                            ? Image.network(
                                thumbnail.url,
                                fit: BoxFit.cover,
                                semanticLabel: asset.altText,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Colors.black12,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              )
                            : const ColoredBox(
                                color: Colors.black12,
                                child: Icon(Icons.insert_drive_file_outlined),
                              ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
