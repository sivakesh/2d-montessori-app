import 'field_spec.dart';
import 'website_block.dart';

/// Albums as an image source for the Photo gallery (`gallery`) and the
/// Asymmetric gallery (`asymmetric_gallery`).
///
/// A gallery lists the albums it takes images from ([albumIds]) and the
/// album images the editor took out ([excludedKey]). The album images
/// themselves are ordinary items of its `images` list, each marked with the
/// selected albums it is in ([itemAlbumsKey]); images chosen by hand have
/// no mark. So every per-image setting (order, feature image, caption,
/// link, alt text, decorative, visibility, screen sizes) works for album
/// images exactly as for the others, and the website draws them with the
/// same code.
///
/// The album records stay admin only: the items are brought up to date
/// from the albums in the editor ("Update from albums") and again when the
/// page is published, keeping only images visitors may see (published,
/// consent confirmed). Visitors never read an album.
abstract final class AlbumSource {
  static const albumIds = 'albumIds';
  static const excludedKey = 'albumExcludedMediaIds';
  static const itemAlbumsKey = 'albums';

  /// Albums one gallery can take images from.
  static const maxAlbums = 10;

  static const blockFields = <FieldSpec>[
    IdListFieldSpec(albumIds, 'Albums', maxIds: maxAlbums),
    IdListFieldSpec(excludedKey, 'Album images left out', maxIds: 2000),
  ];

  static const itemField = IdListFieldSpec(itemAlbumsKey, 'From albums', maxIds: maxAlbums);

  static const types = {'gallery', 'asymmetric_gallery'};

  /// Whether blocks of [type] can take images from albums.
  static bool appliesTo(String type) => types.contains(type);

  static List<String> albumsOf(StructuredBlock block) => block.values[albumIds] as List<String>? ?? const [];
  static List<String> excludedOf(StructuredBlock block) => block.values[excludedKey] as List<String>? ?? const [];
  static List<String> itemAlbums(BlockItem item) => item.values[itemAlbumsKey] as List<String>? ?? const [];

  /// Whether [item] came from the gallery's albums (not chosen by hand).
  static bool fromAlbum(BlockItem item) => itemAlbums(item).isNotEmpty;

  /// Whether [item] is an image slot with no image chosen. It shows
  /// nothing; it is a problem only when the gallery has nothing else.
  static bool isBlank(BlockItem item) => item.string('mediaId').trim().isEmpty;

  /// Whether [item] is blank and nothing else is set on it either (the
  /// empty slot a new gallery starts with): safe to drop.
  static bool isUntouched(BlockItem item, List<FieldSpec> itemFields) =>
      isBlank(item) && item.toMap(itemFields).keys.every((k) => k == 'id' || k == 'mediaId');

  /// Whether [block] has no image at all (only empty slots, or none).
  static bool showsNothing(StructuredBlock block) => !block.items('images').any((i) => !isBlank(i));

  /// The images check of a gallery's draft, on what it shows: no problem
  /// while it has an image (chosen by hand, or from its albums); an empty
  /// slot beside images is simply unused. A gallery with albums may be
  /// saved while they have no image visitors may see ([imageWarning]);
  /// publishing needs one ([publishProblem]). With no image and no album:
  /// an empty slot is reported as before ("Image 1: choose an image"), and
  /// a gallery with no slot needs an image. (Whether chosen images may be
  /// shown, published with consent, is checked when publishing, as before.)
  static List<String> imageProblems(StructuredBlock block) {
    final items = block.items('images');
    if (!showsNothing(block) || albumsOf(block).isNotEmpty) return const [];
    if (items.isEmpty) return const ['add at least 1 image'];
    return [for (var i = 0; i < items.length; i++) 'Image ${i + 1}: choose an image'];
  }

  /// The editor's note (it doesn't stop saving) for a gallery whose albums
  /// give it no image yet and that has none chosen by hand; null otherwise.
  static String? imageWarning(StructuredBlock block) => appliesTo(block.type) && albumsOf(block).isNotEmpty && showsNothing(block)
      ? 'Its albums have no image visitors may see yet (published, with consent confirmed). You can save the draft; '
          'before it can be published, add such images to the albums or choose an image by hand.'
      : null;

  /// Why gallery [block] (brought up to date from its albums) can't be
  /// published: it has no image at all. Null otherwise, and for any other
  /// block. Each image it has is checked when publishing as before
  /// (published, consent confirmed, in the library).
  static String? publishProblem(StructuredBlock block) => appliesTo(block.type) && showsNothing(block)
      ? 'it needs at least one image visitors may see (published, with consent confirmed), from its albums or chosen by hand, before the page can be published'
      : null;

  /// The editor's mark for an album image.
  static String? badge(List<BlockItem> items, int index) => fromAlbum(items[index]) ? 'From an album' : null;
}
