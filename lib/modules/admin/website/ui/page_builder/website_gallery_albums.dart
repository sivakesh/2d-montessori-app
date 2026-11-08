import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/album_source.dart';
import '../../../../public_website/content/blocks/field_spec.dart';
import '../../../../public_website/content/blocks/website_block.dart';
import '../../../../public_website/content/website_content_models.dart';
import '../../data/album_galleries.dart';
import '../../data/website_albums_service.dart';
import '../website_content_screen.dart' show WebsiteMediaThumb;

String _images(int n) => '$n image${n == 1 ? '' : 's'}';

/// A Photo gallery's or Asymmetric gallery's image source, first in its
/// properties: which albums it takes images from (each with what it gives,
/// what it can't and why), Add albums, Remove, the images it brings, and
/// "Update from albums" when the albums have changed since. Images chosen
/// by hand are listed under Images as before and never changed here.
class GalleryAlbumsPanel extends StatelessWidget {
  const GalleryAlbumsPanel({super.key, required this.prefix, required this.block, required this.albums, required this.library, required this.onChanged});

  final String prefix;
  final StructuredBlock block;

  /// The school's albums; null when they couldn't be read.
  final List<WebsiteAlbum>? albums;

  /// The whole media library.
  final List<WebsiteMedia> library;
  final ValueChanged<WebsiteBlock> onChanged;

  void _setAlbums(List<String> ids) {
    var next = block.withValue(AlbumSource.albumIds, List<String>.unmodifiable(ids));
    // With albums, the empty slot a new gallery starts with isn't needed:
    // dropped if nothing was set on it (any other slot is kept).
    if (ids.isNotEmpty) {
      final fields = (block.definition.field('images') as ItemsFieldSpec).itemFields;
      final items = next.items('images');
      final kept = [for (final i in items) if (!AlbumSource.isUntouched(i, fields)) i];
      if (kept.length != items.length) next = next.withValue('images', List<BlockItem>.unmodifiable(kept));
    }
    onChanged(AlbumGalleries.update(next, albums: albums, library: library).block);
  }

  Future<void> _add(BuildContext context) async {
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AlbumPickerDialog(albums: albums ?? const [], library: library, selected: AlbumSource.albumsOf(block)),
    );
    if (chosen != null) _setAlbums(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final selected = AlbumSource.albumsOf(block);
    final items = block.items('images');
    final fromAlbums = items.where(AlbumSource.fromAlbum).toList();
    final blank = items.where((i) => !AlbumSource.fromAlbum(i) && AlbumSource.isBlank(i)).length;
    final byHand = items.length - fromAlbums.length - blank;
    final result = AlbumGalleries.update(block, albums: albums, library: library);
    final takenOut = AlbumSource.excludedOf(block);
    final mediaById = {for (final m in library) m.id: m};
    final mode = switch ((selected.isNotEmpty || fromAlbums.isNotEmpty, byHand > 0)) {
      (true, true) => 'Albums and images chosen by hand',
      (true, false) => 'Albums',
      (false, true) => 'Images chosen by hand',
      (false, false) => 'No images yet',
    };
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      key: Key('$prefix-albums'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.photo_album_outlined, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Image source', style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(
            '$mode: ${_images(fromAlbums.length)} from albums, ${_images(byHand)} chosen by hand.'
            '${blank == 0 ? '' : ' ${blank == 1 ? 'One empty image slot isn’t' : '$blank empty image slots aren’t'} used${fromAlbums.isNotEmpty || byHand > 0 ? '' : ' yet'}: choose an image there, or remove it.'}',
            key: Key('$prefix-albums-mode'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          if (AlbumSource.imageWarning(block) case final warning?)
            Container(
              key: Key('$prefix-albums-no-images'),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF8A6A33)),
                const SizedBox(width: 6),
                Expanded(child: Text(warning, style: const TextStyle(fontSize: 12, color: Color(0xFF6B4F1D)))),
              ]),
            ),
          if (albums == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Albums couldn’t be loaded. The album images already in this gallery stay as they are.',
                  key: Key('$prefix-albums-unavailable'), style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A33))),
            ),
          for (final c in result.albums)
            Container(
              key: Key('$prefix-album-${c.albumId}'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.album?.name ?? (c.unavailable ? 'Album (couldn’t be loaded)' : 'Deleted album'),
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.album == null && !c.unavailable ? const Color(0xFFB3261E) : null),
                        ),
                        Text(
                          [
                            '${_images(c.included)} in the gallery',
                            if (c.alsoChosen > 0) '${c.alsoChosen} also chosen by hand',
                            if (c.excludedCount > 0) '${c.excludedCount} not included: ${[for (final e in c.excluded.entries) '${e.value} ${e.key.label}'].join(', ')}',
                            if (c.album == null && !c.unavailable) 'its images stay until you remove it',
                          ].join(' · '),
                          key: Key('$prefix-album-${c.albumId}-count'),
                          style: small,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('$prefix-album-${c.albumId}-remove'),
                    tooltip: 'Remove this album (its images leave the gallery; images chosen by hand stay)',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _setAlbums([for (final id in selected) if (id != c.albumId) id]),
                  ),
                ],
              ),
            ),
          if (selected.isEmpty && fromAlbums.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_images(fromAlbums.length)} from removed albums: update to take them out.', style: small),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: Key('$prefix-albums-add'),
                onPressed: albums == null || albums!.isEmpty || selected.length >= AlbumSource.maxAlbums ? null : () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(selected.isEmpty ? 'Use albums' : 'Change albums'),
              ),
              if (result.changed)
                FilledButton.icon(
                  key: Key('$prefix-albums-update'),
                  onPressed: () => onChanged(result.block),
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text('Update from albums (${[if (result.added > 0) '${result.added} new', if (result.removed > 0) '${result.removed} to take out'].join(', ')})'),
                ),
              if (takenOut.isNotEmpty)
                TextButton(
                  key: Key('$prefix-albums-include-again'),
                  onPressed: () {
                    final next = block.withValue(AlbumSource.excludedKey, const <String>[]);
                    onChanged(AlbumGalleries.update(next, albums: albums, library: library).block);
                  },
                  child: Text('Include ${_images(takenOut.length)} taken out again'),
                ),
            ],
          ),
          if (albums != null && albums!.isEmpty)
            Text('No albums yet: create them in the Media library.', key: Key('$prefix-albums-none'), style: small),
          if (fromAlbums.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              key: Key('$prefix-albums-preview'),
              spacing: 4,
              runSpacing: 4,
              children: [for (final i in fromAlbums) WebsiteMediaThumb(media: mediaById[i.string('mediaId')], size: 40)],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Album images are listed under Images (marked “From an album”) with all their settings. Removing one there keeps it out of this gallery. '
            'To add images by hand as well, use Add images under Images: they are kept as they are when albums change. '
            'Only published images with consent confirmed are used. Album changes reach the website when this page is published again: publishing updates this gallery from its albums.',
            key: Key('$prefix-albums-publish-note'),
            style: small,
          ),
        ],
      ),
    );
  }
}

/// Choose albums: search by name or description, each with the images
/// visitors may see of all it holds. Pops the chosen ids (in the order
/// already chosen, then as ticked), or null.
class _AlbumPickerDialog extends StatefulWidget {
  const _AlbumPickerDialog({required this.albums, required this.library, required this.selected});

  final List<WebsiteAlbum> albums;
  final List<WebsiteMedia> library;
  final List<String> selected;

  @override
  State<_AlbumPickerDialog> createState() => _AlbumPickerDialogState();
}

class _AlbumPickerDialogState extends State<_AlbumPickerDialog> {
  late final List<String> _chosen = [...widget.selected];
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = {for (final m in widget.library) m.id: m};
    final shown = [for (final a in widget.albums) if (a.matches(_search.text)) a];
    return AlertDialog(
      key: const Key('website-album-picker'),
      title: const Text('Albums for this gallery'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('website-album-picker-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search albums', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No album matches your search.'))
                  : ListView(
                      children: [
                        for (final a in shown)
                          () {
                            final all = a.availableIn(widget.library);
                            final usable = all.where((id) => AlbumGalleries.exclusionFor(media[id]) == null).length;
                            final on = _chosen.contains(a.id);
                            return CheckboxListTile(
                              key: Key('website-album-picker-${a.id}'),
                              value: on,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: on || _chosen.length < AlbumSource.maxAlbums ? (v) => setState(() => v == true ? _chosen.add(a.id) : _chosen.remove(a.id)) : null,
                              title: Text(a.name),
                              subtitle: Text(
                                '${_images(all.length)}${usable == all.length ? '' : ', $usable visitors may see (others not published or without consent)'}${a.description.isEmpty ? '' : ' · ${a.description}'}',
                                key: Key('website-album-picker-${a.id}-count'),
                              ),
                            );
                          }(),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(key: const Key('website-album-picker-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('website-album-picker-done'), onPressed: () => Navigator.pop(context, List<String>.of(_chosen)), child: const Text('Use these albums')),
      ],
    );
  }
}
