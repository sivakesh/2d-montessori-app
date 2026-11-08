import 'package:flutter/foundation.dart';

import '../../../public_website/content/blocks/album_source.dart';
import '../../../public_website/content/blocks/block_ids.dart';
import '../../../public_website/content/blocks/field_spec.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/website_content_models.dart';
import 'website_albums_service.dart';

/// Why an album image isn't in the gallery.
enum AlbumImageExclusion {
  notInLibrary('no longer in the Media library'),
  notPublished('not published'),
  hidden('hidden from the website'),
  noConsent('consent not confirmed'),
  noFile('its file is missing'),
  galleryFull('the gallery is full'),
  leftOut('taken out of this gallery');

  const AlbumImageExclusion(this.label);
  final String label;
}

/// What one selected album gives a gallery.
@immutable
class AlbumContribution {
  const AlbumContribution({required this.albumId, this.album, required this.included, required this.excluded, required this.alsoChosen, required this.unavailable});

  final String albumId;

  /// Null when the album was deleted, or the albums couldn't be read.
  final WebsiteAlbum? album;

  /// Whether the albums couldn't be read (rather than the album deleted).
  final bool unavailable;

  /// Its images in the gallery (also those other selected albums share).
  final int included;

  /// Its images not in the gallery, and why.
  final Map<AlbumImageExclusion, int> excluded;

  /// Its images the gallery already has, chosen by hand.
  final int alsoChosen;

  int get excludedCount => excluded.values.fold(0, (a, b) => a + b);
}

/// A gallery brought up to date from its albums, and what that did.
@immutable
class AlbumGalleryResult {
  const AlbumGalleryResult({required this.block, required this.added, required this.removed, required this.albums, required this.excluded});

  final StructuredBlock block;

  /// Album images added and taken out by this update.
  final int added;
  final int removed;

  /// Each selected album, in the gallery's order.
  final List<AlbumContribution> albums;

  /// Album images not in the gallery (media id → why).
  final Map<String, AlbumImageExclusion> excluded;

  bool get changed => added > 0 || removed > 0;
}

/// Brings galleries' album images up to date ([AlbumSource]).
///
/// The rules, applied the same in the editor and when publishing:
/// - Images chosen by hand are never changed, moved or removed.
/// - An album image is in the gallery while it is in a selected album, in
///   the library, visible to visitors (published, consent confirmed, with a
///   file) and not taken out of this gallery. Otherwise it leaves.
/// - New album images are added at the end, in album order (the selected
///   albums in turn). Album images already there keep their place and every
///   per-image setting.
/// - An image is in a gallery once: in several selected albums, it is one
///   image marked with all of them; already chosen by hand, the hand-chosen
///   one stays and the album adds nothing.
/// - A deleted album, or albums that can't be read: the images that came
///   from it stay as they are (still only while visible to visitors) until
///   the album is removed from the gallery.
/// - Never more images than the gallery holds.
class AlbumGalleries {
  AlbumGalleries._();

  /// Why [media] can't be shown to visitors, or null when it can.
  static AlbumImageExclusion? exclusionFor(WebsiteMedia? media) {
    if (media == null) return AlbumImageExclusion.notInLibrary;
    if (media.status == WebsiteMediaStatus.hidden) return AlbumImageExclusion.hidden;
    if (!media.isPublished) return AlbumImageExclusion.notPublished;
    if (!media.consentConfirmed) return AlbumImageExclusion.noConsent;
    if (media.url.isEmpty) return AlbumImageExclusion.noFile;
    return null;
  }

  static ItemsFieldSpec _imagesField(StructuredBlock block) => block.definition.field('images') as ItemsFieldSpec;

  /// Whether [block] is a gallery with albums, or with album images left
  /// from albums since removed (either needs an update).
  static bool usesAlbums(WebsiteBlock block) =>
      block is StructuredBlock && AlbumSource.appliesTo(block.type) && (AlbumSource.albumsOf(block).isNotEmpty || block.items('images').any(AlbumSource.fromAlbum));

  /// [block] brought up to date from [albums] (the school's albums; null
  /// when they couldn't be read) and [library] (the whole media library).
  static AlbumGalleryResult update(StructuredBlock block, {required List<WebsiteAlbum>? albums, required Iterable<WebsiteMedia> library}) {
    if (!usesAlbums(block)) return AlbumGalleryResult(block: block, added: 0, removed: 0, albums: const [], excluded: const {});
    final media = {for (final m in library) m.id: m};
    final byId = albums == null ? null : {for (final a in albums) a.id: a};
    final items = block.items('images');
    final selected = AlbumSource.albumsOf(block);
    final takenOut = AlbumSource.excludedOf(block).toSet();
    final field = _imagesField(block);

    // Each selected album's images: its own, or (deleted or unreadable)
    // those it gave the gallery before.
    final ofAlbum = <String, List<String>>{};
    for (final id in selected) {
      final album = byId?[id];
      ofAlbum[id] = album != null
          ? album.mediaIds
          : [for (final i in items) if (AlbumSource.itemAlbums(i).contains(id)) i.string('mediaId')];
    }
    final memberOf = <String, List<String>>{};
    final order = <String>[];
    for (final id in selected) {
      for (final m in ofAlbum[id]!) {
        if (m.isEmpty) continue;
        if (!memberOf.containsKey(m)) order.add(m);
        (memberOf[m] ??= []).add(id);
      }
    }

    final chosen = {for (final i in items) if (!AlbumSource.fromAlbum(i)) i.string('mediaId')};
    final out = <BlockItem>[];
    final inGallery = <String>{...chosen};
    var removed = 0;
    for (final item in items) {
      if (!AlbumSource.fromAlbum(item)) {
        out.add(item);
        continue;
      }
      final m = item.string('mediaId');
      final keep = memberOf.containsKey(m) && !takenOut.contains(m) && !chosen.contains(m) && exclusionFor(media[m]) == null && !inGallery.contains(m);
      if (keep) {
        final marks = memberOf[m]!;
        out.add(listEquals(AlbumSource.itemAlbums(item), marks) ? item : item.withValue(AlbumSource.itemAlbumsKey, List<String>.unmodifiable(marks)));
        inGallery.add(m);
      } else {
        removed++;
      }
    }

    final excluded = <String, AlbumImageExclusion>{};
    var added = 0;
    for (final m in order) {
      if (inGallery.contains(m)) continue;
      final why = takenOut.contains(m) ? AlbumImageExclusion.leftOut : exclusionFor(media[m]);
      if (why != null) {
        excluded[m] = why;
        continue;
      }
      if (out.length >= field.maxItems) {
        excluded[m] = AlbumImageExclusion.galleryFull;
        continue;
      }
      out.add(BlockItem(id: BlockIds.item(), values: {
        for (final f in field.itemFields) f.key: f.newValue,
        'mediaId': m,
        AlbumSource.itemAlbumsKey: List<String>.unmodifiable(memberOf[m]!),
      }));
      inGallery.add(m);
      added++;
    }

    final contributions = [
      for (final id in selected)
        AlbumContribution(
          albumId: id,
          album: byId?[id],
          unavailable: byId == null,
          included: ofAlbum[id]!.where((m) => inGallery.contains(m) && !chosen.contains(m)).toSet().length,
          alsoChosen: ofAlbum[id]!.where(chosen.contains).toSet().length,
          excluded: {
            for (final why in AlbumImageExclusion.values)
              if (ofAlbum[id]!.where((m) => excluded[m] == why).toSet().length case final n when n > 0) why: n,
          },
        ),
    ];
    final changed = added > 0 || removed > 0 || !listEquals([for (final i in out) i.values[AlbumSource.itemAlbumsKey]], [for (final i in items) i.values[AlbumSource.itemAlbumsKey]]);
    return AlbumGalleryResult(
      block: changed ? block.withValue('images', List<BlockItem>.unmodifiable(out)) : block,
      added: added,
      removed: removed,
      albums: contributions,
      excluded: excluded,
    );
  }

  /// [blocks] with every gallery that uses albums brought up to date, at
  /// any depth (in sections, rows and columns); everything else is the
  /// same object as before.
  static List<WebsiteBlock> updateAll(List<WebsiteBlock> blocks, {required List<WebsiteAlbum>? albums, required Iterable<WebsiteMedia> library}) {
    final lib = library.toList();
    WebsiteBlock one(WebsiteBlock b) {
      if (b is! StructuredBlock) return b;
      var out = usesAlbums(b) ? update(b, albums: albums, library: lib).block : b;
      for (final f in out.definition.fields.whereType<ColumnsFieldSpec>()) {
        final cols = out.columns(f.key);
        final next = [for (final c in cols) c.copyWith(blocks: [for (final x in c.blocks) one(x)])];
        var same = true;
        for (var i = 0; i < cols.length; i++) {
          for (var j = 0; j < cols[i].blocks.length; j++) {
            if (!identical(cols[i].blocks[j], next[i].blocks[j])) same = false;
          }
        }
        if (!same) out = out.withValue(f.key, next);
      }
      return out;
    }

    return [for (final b in blocks) one(b)];
  }

  /// Whether any of [blocks] (at any depth) is a gallery using albums.
  static bool anyUsesAlbums(List<WebsiteBlock> blocks) {
    for (final b in blocks) {
      if (usesAlbums(b)) return true;
      if (b is StructuredBlock) {
        for (final f in b.definition.fields.whereType<ColumnsFieldSpec>()) {
          for (final c in b.columns(f.key)) {
            if (anyUsesAlbums(c.blocks)) return true;
          }
        }
      }
    }
    return false;
  }

  /// [after] (an edit of gallery [before]) with each album image the edit
  /// removed taken out of the gallery for good ([AlbumSource.excludedKey]),
  /// so the next update doesn't bring it back.
  static StructuredBlock rememberRemovals(StructuredBlock before, StructuredBlock after) {
    if (!AlbumSource.appliesTo(after.type)) return after;
    final kept = {for (final i in after.items('images')) i.string('mediaId')};
    final gone = [
      for (final i in before.items('images'))
        if (AlbumSource.fromAlbum(i) && !kept.contains(i.string('mediaId'))) i.string('mediaId'),
    ];
    if (gone.isEmpty) return after;
    final excluded = {...AlbumSource.excludedOf(after), ...gone}.toList();
    return after.withValue(AlbumSource.excludedKey, List<String>.unmodifiable(excluded));
  }
}
