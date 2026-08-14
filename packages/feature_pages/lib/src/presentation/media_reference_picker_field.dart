import 'package:feature_media/feature_media.dart';
import 'package:flutter/material.dart';

import '../domain/media_reference.dart';

/// Replaces raw image-URL text entry with a Media Library selection (SRS
/// "Media selection/reuse from Pages" — the Pages-side half of
/// `feature_media`'s "Replace raw image-URL entry in Pages with Media
/// Library selection where appropriate" boundary). Alt text is no longer
/// typed per-use here: it lives on the [MediaAsset] itself (required at
/// upload time — see `feature_media`'s own SRS "accessible alt text"),
/// so picking an asset carries its alt text along automatically.
class MediaReferencePickerField extends StatelessWidget {
  const MediaReferencePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.mediaRepository,
  });

  final String label;
  final MediaReference? value;
  final ValueChanged<MediaReference?> onChanged;
  final MediaRepository mediaRepository;

  Future<void> _pick(BuildContext context) async {
    final asset = await showDialog<MediaAsset>(
      context: context,
      builder: (_) => MediaPickerDialog(repository: mediaRepository),
    );
    if (asset == null) return;
    final variant = asset.largestVariant;
    if (variant == null) return;
    onChanged(
      MediaReference(
        url: variant.url,
        altText: asset.altText,
        storagePath: asset.storagePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (current != null && current.url.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  current.url,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  semanticLabel: current.altText,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                Text(
                  current == null || current.url.isEmpty
                      ? 'No image selected'
                      : current.altText,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pick(context),
            child: Text(current == null ? 'Choose' : 'Change'),
          ),
          if (current != null && current.url.isNotEmpty)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}
