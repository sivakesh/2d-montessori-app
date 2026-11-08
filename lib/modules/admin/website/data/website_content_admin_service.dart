
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../auth/models/app_user.dart';
import '../../../public_website/content/blocks/block_limits.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_public_item.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_page_style.dart';
import '../../../public_website/content/website_languages.dart';
import '../../../public_website/content/website_site_layout.dart';
import 'website_image_processor.dart';
import 'album_galleries.dart';
import 'website_albums_service.dart';
import 'website_templates_service.dart';
import 'website_editor_settings.dart';

class UnauthorizedWebsiteContentException implements Exception {
  UnauthorizedWebsiteContentException(this.role);

  final String role;

  @override
  String toString() => 'Only administrators can manage website content.';
}

/// A website-content change that can't be made as asked; [message] is
/// shown to the admin as is.
class WebsiteContentException implements Exception {
  WebsiteContentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The site layout was published (or its draft saved), but removing the
/// default design, header or footer from the saved draft afterwards
/// failed. [message] says what did happen.
class WebsiteLayoutCleanupException extends WebsiteContentException {
  WebsiteLayoutCleanupException(super.message);
}

/// An image chosen in the file picker, not yet uploaded.
class PickedWebsiteImage {
  const PickedWebsiteImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// One file chosen for a bulk upload: the image, or why it can't be
/// uploaded ([problem]; each file is checked on its own).
class PickedWebsiteFile {
  const PickedWebsiteFile({required this.name, required this.size, this.image, this.problem});

  final String name;
  final int size;
  final PickedWebsiteImage? image;
  final String? problem;
}

/// What a bulk action did to one image.
enum WebsiteBulkStatus {
  /// Changed as asked.
  done,

  /// Already so; nothing to change.
  unchanged,

  /// Not changed: [WebsiteBulkOutcome.message] says why.
  failed,
}

/// The actions the media library can apply to several images at once.
/// Each is the single-image workflow, image by image, with its own checks.
enum WebsiteBulkAction {
  confirmConsent('Confirm consent'),
  publish('Publish'),
  unpublish('Unpublish'),
  addToGallery('Add to gallery'),
  removeFromGallery('Remove from gallery'),
  delete('Delete');

  const WebsiteBulkAction(this.label);
  final String label;
}

/// One image's result of a bulk action.
@immutable
class WebsiteBulkOutcome {
  const WebsiteBulkOutcome(this.mediaId, this.status, [this.message = '']);

  final String mediaId;
  final WebsiteBulkStatus status;
  final String message;
}

/// Manages the website's media library and page content (Settings ->
/// Website). Same shape as SchoolSettingsService: constructor-injected
/// Firestore/Storage/FilePicker defaulting to the platform singletons, and
/// every method re-checks that `requesterRole` is 'admin' itself, so a UI
/// slip can never let Staff/Parent change the public website. (Security
/// rules must enforce the same — see docs/website_content.md.)
///
/// Visitors only ever read published media and live pages
/// ([WebsiteContentRepository]); drafts, unpublished images and the audit
/// trail stay in admin-only places.
class WebsiteContentAdminService {
  WebsiteContentAdminService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FilePicker? filePicker,
    WebsiteImageProcessor? imageProcessor,
    WebsiteEditorSettingsService? editorSettings,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _editorSettings = editorSettings,
        _storage = storage ?? FirebaseStorage.instance,
        _filePicker = filePicker,
        _imageProcessor = imageProcessor ?? WebsiteImageProcessor();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FilePicker? _filePicker;
  final WebsiteImageProcessor _imageProcessor;

  static const maxUploadBytes = 15 * 1024 * 1024;
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const maxAltLength = 250;
  static const maxCaptionLength = 300;
  static const maxHeadlineLength = 120;
  static const maxIntroLength = 600;

  /// Why a draft was saved but its live page wasn't written.
  static const publishFailedMessage = 'Draft saved, but publication failed. Visitors still see the previous version. Check your connection and try publishing again.';

  /// Why a page built with blocks can't be published.
  static const nothingVisibleMessage = 'Nothing on this page would be shown to visitors. Add visible content before publishing.';

  /// Uploaded files never change in place (a replacement is a new path), so
  /// browsers and the CDN may cache them for a long time.
  static const _cacheControl = 'public, max-age=31536000, immutable';

  /// The school's Website editor settings (its page block limit).
  late final WebsiteEditorSettingsService editorSettings = _editorSettings ?? WebsiteEditorSettingsService(firestore: _firestore);
  final WebsiteEditorSettingsService? _editorSettings;

  /// Why a page can't be saved with [count] blocks under the school's
  /// limit [limit].
  static String pageLimitMessage(int count, int limit) =>
      'This page would have $count blocks, more than this school\'s limit of $limit blocks per page. '
      'Remove blocks, or raise the limit in Website → Pages → Editor settings.';

  /// The school's page limit, on save: a page may not grow past it. A page
  /// that already had more ([saved], after the limit was lowered) may be
  /// saved and published as long as it doesn't grow, so lowering the limit
  /// never locks existing content. If the setting can't be read, only the
  /// fixed safety ceiling applies ([BlockRegistry.validate]).
  Future<void> _requireWithinPageLimit(List<WebsiteBlock> blocks, {List<WebsiteBlock>? saved}) async {
    final count = BlockRegistry.flatten(blocks).length;
    if (count <= BlockLimits.minPageMaxBlocks) return; // within any allowed setting
    final int limit;
    try {
      limit = (await editorSettings.load()).maxBlocksPerPage;
    } catch (_) {
      return;
    }
    if (count <= limit) return;
    final before = saved == null ? 0 : BlockRegistry.flatten(saved).length;
    if (count <= before) return;
    throw WebsiteContentException(pageLimitMessage(count, limit));
  }

  /// The school's template library (same database).
  late final WebsiteTemplatesService templates = WebsiteTemplatesService(firestore: _firestore);

  /// The media library's albums (same database).
  late final WebsiteAlbumsService albums = WebsiteAlbumsService(firestore: _firestore);

  CollectionReference<Map<String, dynamic>> get _media => _firestore.collection(WebsiteCollections.media);
  CollectionReference<Map<String, dynamic>> get _drafts => _firestore.collection(WebsiteCollections.pageDrafts);
  CollectionReference<Map<String, dynamic>> get _live => _firestore.collection(WebsiteCollections.livePages);

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') throw UnauthorizedWebsiteContentException(requesterRole);
  }

  // ---------------------------------------------------------------- media

  /// Every image in the library (any status), in gallery order.
  Future<List<WebsiteMedia>> listMedia({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _media.get();
    return sortForGallery([for (final doc in snapshot.docs) WebsiteMedia.fromMap(doc.id, doc.data())]);
  }

  /// One library image, or null if it no longer exists.
  Future<WebsiteMedia?> getMedia({required String requesterRole, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final doc = await _media.doc(mediaId).get();
    final data = doc.data();
    return !doc.exists || data == null ? null : WebsiteMedia.fromMap(doc.id, data);
  }

  /// Opens the file picker for one image; null when cancelled. Throws
  /// [WebsiteContentException] for an unsupported or oversized file.
  Future<PickedWebsiteImage?> pickImage() async {
    final picker = _filePicker ?? FilePicker.platform;
    final result = await picker.pickFiles(withData: true, type: FileType.custom, allowedExtensions: allowedExtensions);
    final file = result == null || result.files.isEmpty ? null : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    validateImageFile(file.name, bytes.length);
    return PickedWebsiteImage(name: file.name, bytes: bytes);
  }

  /// Opens the file picker for several images at once; empty when
  /// cancelled. Every file is checked on its own ([imageFileProblem]): one
  /// that can't be uploaded is returned with its reason, never dropped.
  Future<List<PickedWebsiteFile>> pickImages() async {
    final picker = _filePicker ?? FilePicker.platform;
    final result = await picker.pickFiles(withData: true, allowMultiple: true, type: FileType.custom, allowedExtensions: allowedExtensions);
    if (result == null) return const [];
    return [
      for (final file in result.files)
        () {
          final bytes = file.bytes;
          final problem = bytes == null ? 'The file could not be read.' : imageFileProblem(file.name, bytes.length);
          return PickedWebsiteFile(
            name: file.name,
            size: bytes?.length ?? file.size,
            image: problem == null ? PickedWebsiteImage(name: file.name, bytes: bytes!) : null,
            problem: problem,
          );
        }(),
    ];
  }

  /// Why [name] (of [length] bytes) can't be uploaded, or null: JPEG, PNG
  /// or WebP only, not empty, at most [maxUploadBytes].
  static String? imageFileProblem(String name, int length) {
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!allowedExtensions.contains(extension)) return 'Choose a JPEG, PNG or WebP image.';
    if (length == 0) return 'The selected file is empty.';
    if (length > maxUploadBytes) return 'Choose an image smaller than 15 MB.';
    return null;
  }

  /// Throws [WebsiteContentException] unless [name] is a JPEG/PNG/WebP
  /// image no larger than [maxUploadBytes].
  static void validateImageFile(String name, int length) {
    final problem = imageFileProblem(name, length);
    if (problem != null) throw WebsiteContentException(problem);
  }

  /// A new media id, reserved before uploading: uploading with it again
  /// (a retry) never makes a second record ([uploadMedia]).
  String newMediaId() => _media.doc().id;

  static String _contentTypeFor(String name) => switch (name.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  static String _extensionFor(String contentType) => switch (contentType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };

  /// Resizes and uploads [image]'s files under `website_media/{id}/`.
  Future<Map<String, dynamic>> _storeFiles(String mediaId, PickedWebsiteImage image) async {
    validateImageFile(image.name, image.bytes.length);
    final ProcessedWebsiteImage processed;
    try {
      processed = await _imageProcessor.process(image.bytes, contentType: _contentTypeFor(image.name));
    } catch (_) {
      throw WebsiteContentException('This image could not be read. Try a different file.');
    }
    // A neutral name: the original file name may identify a child.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final displayPath = '${WebsiteCollections.media}/$mediaId/${stamp}_display.${_extensionFor(processed.displayContentType)}';
    final thumbPath = '${WebsiteCollections.media}/$mediaId/${stamp}_thumb.${_extensionFor(processed.thumbContentType)}';
    final displayRef = _storage.ref(displayPath);
    final thumbRef = _storage.ref(thumbPath);
    try {
      await displayRef.putData(processed.display, SettableMetadata(contentType: processed.displayContentType, cacheControl: _cacheControl));
      await thumbRef.putData(processed.thumb, SettableMetadata(contentType: processed.thumbContentType, cacheControl: _cacheControl));
      return {
        'url': await displayRef.getDownloadURL(),
        'storagePath': displayPath,
        'thumbUrl': await thumbRef.getDownloadURL(),
        'thumbStoragePath': thumbPath,
        'contentType': processed.displayContentType,
        'sizeBytes': processed.display.length,
        'width': processed.width,
        'height': processed.height,
      };
    } catch (e) {
      await _deleteFiles([displayPath, thumbPath]);
      if (e is WebsiteContentException) rethrow;
      throw WebsiteContentException('The image could not be uploaded. Please try again.');
    }
  }

  /// Best-effort: a missing object never blocks the change around it.
  Future<void> _deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      if (path.isEmpty) continue;
      try {
        await _storage.ref(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _audit(String mediaId, String action, AppUser actor, [Map<String, dynamic> details = const {}]) async {
    await _media.doc(mediaId).collection('audit').add({
      'action': action,
      'byId': actor.id,
      'byName': actor.name ?? '',
      'at': FieldValue.serverTimestamp(),
      ...details,
    });
  }

  /// Adds [image] to the library as a draft (not on the website), last in
  /// the gallery order. [alt] defaults to [WebsiteMedia.defaultAlt] (an
  /// explicit value, even empty, is kept as given); [decorative] marks an
  /// image screen readers should skip. Consent is never confirmed here.
  ///
  /// With [mediaId] (from [newMediaId]) the upload is idempotent: when that
  /// record already exists (an earlier attempt got that far) it is
  /// returned as it is and nothing is uploaded again, so retrying or
  /// submitting twice never makes a duplicate.
  Future<WebsiteMedia> uploadMedia({
    required String requesterRole,
    required AppUser actor,
    required PickedWebsiteImage image,
    GalleryCategory category = GalleryCategory.general,
    LocalizedText alt = const LocalizedText(en: WebsiteMedia.defaultAlt),
    LocalizedText caption = const LocalizedText(),
    bool inGallery = true,
    bool decorative = false,
    String? mediaId,
  }) async {
    _requireAdmin(requesterRole);
    _validateMediaText(alt, caption);
    if (mediaId != null) {
      final already = await _media.doc(mediaId).get();
      if (already.exists && already.data() != null) return WebsiteMedia.fromMap(already.id, already.data()!);
    }
    final existing = await _media.get();
    var nextOrder = 0;
    for (final doc in existing.docs) {
      final order = doc.data()['galleryOrder'];
      if (order is num && order.toInt() >= nextOrder) nextOrder = order.toInt() + 1;
    }
    final doc = mediaId == null ? _media.doc() : _media.doc(mediaId);
    final files = await _storeFiles(doc.id, image);
    try {
      await doc.set({
        ...files,
        'focalX': 0.5,
        'focalY': 0.5,
        'alt': alt.toMap(),
        'caption': caption.toMap(),
        'category': category.id,
        'status': WebsiteMediaStatus.draft.name,
        'inGallery': inGallery,
        'galleryOrder': nextOrder,
        'consentConfirmed': false,
        if (decorative) 'decorative': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await _deleteFiles([files['storagePath'] as String, files['thumbStoragePath'] as String]);
      rethrow;
    }
    await _audit(doc.id, 'uploaded', actor);
    final saved = await doc.get();
    return WebsiteMedia.fromMap(doc.id, saved.data()!);
  }

  /// Swaps the image file of [mediaId], keeping its id so every page that
  /// uses it follows. The new photograph needs its own consent
  /// confirmation, so a published image goes back to draft (pages using it
  /// show their placeholder until it is published again) and the focal
  /// point resets to the centre. The old files are deleted afterwards.
  Future<WebsiteMedia> replaceMediaImage({
    required String requesterRole,
    required AppUser actor,
    required String mediaId,
    required PickedWebsiteImage image,
  }) async {
    _requireAdmin(requesterRole);
    final current = await _requireMedia(mediaId);
    final files = await _storeFiles(mediaId, image);
    await _media.doc(mediaId).update({
      ...files,
      'focalX': 0.5,
      'focalY': 0.5,
      'consentConfirmed': false,
      if (current.isPublished) 'status': WebsiteMediaStatus.draft.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Never delete a path the new upload is now using.
    final kept = {files['storagePath'], files['thumbStoragePath']};
    await _deleteFiles([current.storagePath, current.thumbStoragePath].where((path) => !kept.contains(path)));
    await _audit(mediaId, 'replaced', actor, {'wasPublished': current.isPublished});
    return _requireMedia(mediaId);
  }

  /// Limits apply to every language (English, Tamil and any other).
  void _validateMediaText(LocalizedText alt, LocalizedText caption) {
    if (alt.values.values.any((t) => t.trim().length > maxAltLength)) {
      throw WebsiteContentException('Alt text must be $maxAltLength characters or fewer.');
    }
    if (caption.values.values.any((t) => t.trim().length > maxCaptionLength)) {
      throw WebsiteContentException('Captions must be $maxCaptionLength characters or fewer.');
    }
  }

  Future<WebsiteMedia> _requireMedia(String mediaId) async {
    final doc = await _media.doc(mediaId).get();
    final data = doc.data();
    if (!doc.exists || data == null) throw WebsiteContentException('This image no longer exists.');
    return WebsiteMedia.fromMap(doc.id, data);
  }

  /// Saves an image's descriptive details. Editing a published image's
  /// details updates the website directly.
  ///
  /// Withdrawing consent (unticking it) is a privacy action and always takes
  /// effect at once, unlike [hideMedia]: a published image becomes `hidden`
  /// so it leaves the gallery and every page straight away, while each page
  /// using it stays published and shows its placeholder (and can't be
  /// republished with that image). The Storage files are kept; only
  /// [deleteMedia] removes them. The withdrawal, and the pages it affected,
  /// are recorded in the audit trail.
  Future<void> updateMediaDetails({
    required String requesterRole,
    required AppUser actor,
    required String mediaId,
    required LocalizedText alt,
    required LocalizedText caption,
    required GalleryCategory category,
    required bool inGallery,
    required double focalX,
    required double focalY,
    required bool consentConfirmed,
    bool? decorative,
  }) async {
    _requireAdmin(requesterRole);
    _validateMediaText(alt, caption);
    final current = await _requireMedia(mediaId);
    final withdrawn = current.consentConfirmed && !consentConfirmed;
    final unpublish = current.isPublished && !consentConfirmed;
    final affected = withdrawn ? await pagesUsing(requesterRole: requesterRole, mediaId: mediaId) : const <String>{};
    await _media.doc(mediaId).update({
      'alt': alt.toMap(),
      'caption': caption.toMap(),
      'category': category.id,
      'inGallery': inGallery,
      'focalX': focalX.clamp(0.0, 1.0),
      'focalY': focalY.clamp(0.0, 1.0),
      'consentConfirmed': consentConfirmed,
      // Unset (null): kept as stored.
      'decorative': ?decorative,
      if (unpublish) 'status': WebsiteMediaStatus.hidden.name,
      if (withdrawn) 'consentWithdrawnAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (withdrawn) {
      await _audit(mediaId, 'consent-withdrawn', actor, {
        'wasPublished': current.isPublished,
        'affectedPages': affected.toList()..sort(),
      });
    }
    await _audit(mediaId, 'details-updated', actor, {
      if (consentConfirmed != current.consentConfirmed) 'consentConfirmed': consentConfirmed,
      if (unpublish) 'hidden': true,
    });
  }

  /// Puts an image on the website (gallery, if listed there, and any live
  /// page using it). Requires the file and consent confirmation; alt text
  /// is optional.
  Future<void> publishMedia({required String requesterRole, required AppUser actor, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final media = await _requireMedia(mediaId);
    final blocker = media.publishBlocker;
    if (blocker != null) throw WebsiteContentException(blocker);
    await _media.doc(mediaId).update({
      'status': WebsiteMediaStatus.published.name,
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit(mediaId, 'published', actor);
  }

  /// Takes an image off the website, keeping it in the library. An
  /// editorial action, so it is refused while a live page shows it (change
  /// or unpublish that page first) and no published page silently loses its
  /// image. To remove a photograph for privacy reasons regardless of where
  /// it is used, withdraw consent instead ([updateMediaDetails]).
  Future<void> hideMedia({required String requesterRole, required AppUser actor, required String mediaId}) async {
    _requireAdmin(requesterRole);
    await _requireMedia(mediaId);
    await _requireNotUsedByLivePage(mediaId, 'hide');
    await _media.doc(mediaId).update({
      'status': WebsiteMediaStatus.hidden.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit(mediaId, 'hidden', actor);
  }

  /// Deletes an image and its files. Refused while any page (draft or
  /// live) uses it.
  Future<void> deleteMedia({required String requesterRole, required AppUser actor, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final media = await _requireMedia(mediaId);
    final users = await pagesUsing(requesterRole: requesterRole, mediaId: mediaId);
    // Never deleted while it might be in a template (fails closed).
    if (users.contains(templatesUncheckedLabel)) {
      throw WebsiteContentException('This image can’t be deleted now: the template library couldn’t be checked for it. Try again later; if this keeps happening, your account may not be set up for templates yet.');
    }
    if (users.isNotEmpty) {
      throw WebsiteContentException('This image is used on ${users.join(', ')}. Choose a different image there first.');
    }
    final audit = await _media.doc(mediaId).collection('audit').get();
    final batch = _firestore.batch();
    for (final entry in audit.docs) {
      batch.delete(entry.reference);
    }
    batch.delete(_media.doc(mediaId));
    await batch.commit();
    await _deleteFiles([media.storagePath, media.thumbStoragePath]);
    // Best effort: an album still listing it leaves it out.
    try {
      await albums.forgetMedia(requesterRole: requesterRole, mediaId: mediaId);
    } catch (_) {}
  }

  /// [blocks] with every Photo gallery and Asymmetric gallery that takes
  /// images from albums brought up to date ([AlbumGalleries]), as
  /// publishing does: the page's own copy of the album images visitors may
  /// see (published, consent confirmed), never the albums themselves. The
  /// same list when no gallery uses albums (nothing is read). When the
  /// albums can't be read, each gallery keeps the album images it has
  /// (still only those visitors may see).
  Future<List<WebsiteBlock>> updateAlbumGalleries({required String requesterRole, required List<WebsiteBlock> blocks}) async {
    _requireAdmin(requesterRole);
    if (!AlbumGalleries.anyUsesAlbums(blocks)) return blocks;
    List<WebsiteAlbum>? albumList;
    try {
      albumList = await albums.list(requesterRole: requesterRole);
    } catch (_) {
      albumList = null;
    }
    final library = await listMedia(requesterRole: requesterRole);
    return AlbumGalleries.updateAll(blocks, albums: albumList, library: library);
  }

  /// Lists the image in the public gallery (once published) or takes it
  /// out; its publication, consent and the pages using it are unchanged.
  Future<void> setInGallery({required String requesterRole, required AppUser actor, required String mediaId, required bool inGallery}) async {
    _requireAdmin(requesterRole);
    await _requireMedia(mediaId);
    await _media.doc(mediaId).update({'inGallery': inGallery, 'updatedAt': FieldValue.serverTimestamp()});
    await _audit(mediaId, inGallery ? 'gallery-added' : 'gallery-removed', actor);
  }

  /// Records that the admin confirmed the photograph is school-approved and
  /// consent was obtained for any identifiable child ([bulk]: as one of
  /// several, after the bulk warning). It doesn't publish anything.
  Future<void> confirmConsent({required String requesterRole, required AppUser actor, required String mediaId, bool bulk = false}) async {
    _requireAdmin(requesterRole);
    await _requireMedia(mediaId);
    await _media.doc(mediaId).update({'consentConfirmed': true, 'updatedAt': FieldValue.serverTimestamp()});
    await _audit(mediaId, 'consent-confirmed', actor, {if (bulk) 'bulk': true});
  }

  /// [action] applied to each of [mediaIds] in turn through the
  /// single-image workflow, with all of its checks (consent to publish,
  /// pages showing an image before it is unpublished or deleted, the
  /// template check before deleting). One image's failure never stops the
  /// others, and every image gets an outcome: done, unchanged (already so,
  /// with the reason) or failed (with the reason).
  Future<List<WebsiteBulkOutcome>> applyBulk({
    required String requesterRole,
    required AppUser actor,
    required WebsiteBulkAction action,
    required List<String> mediaIds,
  }) async {
    _requireAdmin(requesterRole);
    final outcomes = <WebsiteBulkOutcome>[];
    for (final id in {...mediaIds}) {
      try {
        final media = await getMedia(requesterRole: requesterRole, mediaId: id);
        if (media == null) {
          outcomes.add(WebsiteBulkOutcome(id, WebsiteBulkStatus.failed, 'This image no longer exists.'));
          continue;
        }
        String? unchanged;
        switch (action) {
          case WebsiteBulkAction.confirmConsent:
            if (media.consentConfirmed) {
              unchanged = 'Consent was already confirmed.';
            } else {
              await confirmConsent(requesterRole: requesterRole, actor: actor, mediaId: id, bulk: true);
            }
          case WebsiteBulkAction.publish:
            if (media.isPublished) {
              unchanged = 'Already published.';
            } else {
              await publishMedia(requesterRole: requesterRole, actor: actor, mediaId: id);
            }
          case WebsiteBulkAction.unpublish:
            if (!media.isPublished) {
              unchanged = 'Not published.';
            } else {
              await hideMedia(requesterRole: requesterRole, actor: actor, mediaId: id);
            }
          case WebsiteBulkAction.addToGallery:
            if (media.inGallery) {
              unchanged = 'Already in the gallery.';
            } else {
              await setInGallery(requesterRole: requesterRole, actor: actor, mediaId: id, inGallery: true);
            }
          case WebsiteBulkAction.removeFromGallery:
            if (!media.inGallery) {
              unchanged = 'Not in the gallery.';
            } else {
              await setInGallery(requesterRole: requesterRole, actor: actor, mediaId: id, inGallery: false);
            }
          case WebsiteBulkAction.delete:
            await deleteMedia(requesterRole: requesterRole, actor: actor, mediaId: id);
        }
        outcomes.add(unchanged == null ? WebsiteBulkOutcome(id, WebsiteBulkStatus.done) : WebsiteBulkOutcome(id, WebsiteBulkStatus.unchanged, unchanged));
      } on WebsiteContentException catch (e) {
        outcomes.add(WebsiteBulkOutcome(id, WebsiteBulkStatus.failed, e.message));
      } on UnauthorizedWebsiteContentException {
        rethrow;
      } catch (_) {
        outcomes.add(WebsiteBulkOutcome(id, WebsiteBulkStatus.failed, 'It couldn’t be changed. Check your connection and try again.'));
      }
    }
    return outcomes;
  }

  /// Labels of the pages (built-in or additional, draft or live) whose
  /// content uses [mediaId], of the events and announcements on the
  /// website showing it, of the website forms (any status) and of the
  /// templates using it (so a template's images stay available to insert).
  Future<Set<String>> pagesUsing({required String requesterRole, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final labels = <String>{};
    for (final collection in [_drafts, _live]) {
      labels.addAll(await _labelsUsing(collection, mediaId));
    }
    labels.addAll((await _websiteItemsUsing(mediaId)).labels);
    labels.addAll(await _formsUsing(_formsCollection, mediaId));
    labels.addAll(await _templatesUsing(mediaId));
    return labels;
  }

  // Website forms (`website_forms`, `website_public_forms`), named here so
  // this service doesn't depend on the forms module.
  static const _formsCollection = 'website_forms';
  static const _publicFormsCollection = 'website_public_forms';

  /// In [pagesUsing] when the templates couldn't be read (say, an admin
  /// account without the school claim the rules need): deleting the image
  /// is refused, and other uses of [pagesUsing] (withdrawing consent,
  /// which must always work) go ahead.
  static const templatesUncheckedLabel = 'the template library (it couldn’t be checked)';

  /// The school's templates whose blocks or thumbnail use [mediaId]. By
  /// school only (filtered here), so the query needs no composite index
  /// and stays within the rules, which allow listing by school. Never
  /// throws: when they can't be read, [templatesUncheckedLabel].
  Future<Set<String>> _templatesUsing(String mediaId) async {
    try {
      final snapshot = await _firestore.collection(WebsiteCollections.templates).where('schoolId', isEqualTo: templates.schoolId).get();
      return {
        for (final doc in snapshot.docs)
          if ((doc.data()['mediaIds'] as List?)?.contains(mediaId) ?? false) 'the “${doc.data()['name'] ?? 'untitled'}” template',
      };
    } catch (_) {
      return {templatesUncheckedLabel};
    }
  }

  /// Website forms in [collection] whose cover or image blocks use
  /// [mediaId] (by their `mediaIds`).
  Future<Set<String>> _formsUsing(String collection, String mediaId) async {
    final snapshot = await _firestore.collection(collection).where('mediaIds', arrayContains: mediaId).get();
    return {for (final doc in snapshot.docs) 'the “${LocalizedText.fromMap(doc.data()['title']).en}” form'};
  }

  /// The events and announcements on the website (their public copies,
  /// which are live) whose image is [mediaId]: labels such as "the “Annual
  /// Day” event", and where each is changed (Calendar, Notifications).
  Future<({Set<String> labels, Set<String> places})> _websiteItemsUsing(String mediaId) async {
    final snapshot = await _firestore.collection(WebsitePublicItem.collection).where('imageMediaId', isEqualTo: mediaId).get();
    final labels = <String>{};
    final places = <String>{};
    for (final doc in snapshot.docs) {
      final kind = WebsitePublicItemKind.parse(doc.data()['kind']);
      final title = LocalizedText.fromMap(doc.data()['title']).en;
      switch (kind) {
        case WebsitePublicItemKind.announcement:
          labels.add('the “$title” announcement');
          places.add('Notifications');
        case WebsitePublicItemKind.event || null:
          labels.add('the “$title” event');
          places.add('Calendar');
      }
    }
    return (labels: labels, places: places);
  }

  /// Pages in [collection] using [mediaId]: by `mediaIds` (every image a
  /// page shows) and, for content saved before that field existed, by the
  /// built-in pages' `imageMediaId`.
  Future<Set<String>> _labelsUsing(CollectionReference<Map<String, dynamic>> collection, String mediaId) async {
    final byList = await collection.where('mediaIds', arrayContains: mediaId).get();
    final bySingle = await collection.where('imageMediaId', isEqualTo: mediaId).get();
    return {
      for (final doc in [...byList.docs, ...bySingle.docs])
        CustomPage.isCustomDoc(doc.data())
            ? 'the “${LocalizedText.fromMap(doc.data()['title']).en}” page'
            : (WebsitePageSlot.parse(doc.id)?.adminLabel ?? BuiltInPage.parse(doc.id)?.label ?? doc.id),
    };
  }

  Future<void> _requireNotUsedByLivePage(String mediaId, String verb) async {
    final items = await _websiteItemsUsing(mediaId);
    if (items.labels.isNotEmpty) {
      throw WebsiteContentException(
        'You can’t $verb this image while ${items.labels.join(', ')} on the website shows it. '
        'Choose a different image for it, or remove the image, in the ${(items.places.toList()..sort()).join(' or ')} first.',
      );
    }
    final labels = await _labelsUsing(_live, mediaId);
    if (labels.isNotEmpty) {
      throw WebsiteContentException('You can’t $verb this image while the published ${labels.join(', ')} page shows it. Choose a different image there, or unpublish that page, first.');
    }
    final forms = await _formsUsing(_publicFormsCollection, mediaId);
    if (forms.isNotEmpty) {
      throw WebsiteContentException(
        'You can’t $verb this image while the active ${forms.join(', ')} shows it. Choose a different image in Website forms (and activate the change), or deactivate the form, first.',
      );
    }
  }

  /// Throws unless every image in [mediaIds] exists and is published.
  Future<void> _requirePublishedMedia(Iterable<String> mediaIds) async {
    for (final id in mediaIds) {
      final doc = await _media.doc(id).get();
      final data = doc.data();
      if (!doc.exists || data == null) throw WebsiteContentException('An image on this page no longer exists. Choose a different one.');
      if (!WebsiteMedia.fromMap(id, data).isPublished) {
        throw WebsiteContentException('Publish every image on this page first (Media library), or choose published ones.');
      }
    }
  }

  /// Sets the gallery order to [orderedIds] (first shown first).
  Future<void> reorderGallery({required String requesterRole, required AppUser actor, required List<String> orderedIds}) async {
    _requireAdmin(requesterRole);
    final batch = _firestore.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_media.doc(orderedIds[i]), {'galleryOrder': i});
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------- pages

  /// The page's editable content: its draft, else what is live, else empty
  /// (blank text = the built-in wording).
  Future<WebsitePageContent> getDraft({required String requesterRole, required WebsitePageSlot slot}) async {
    return await getSavedDraft(requesterRole: requesterRole, slot: slot) ??
        await getLive(requesterRole: requesterRole, slot: slot) ??
        WebsitePageContent(slot: slot);
  }

  /// The page's saved draft, or null when none has been saved.
  Future<WebsitePageContent?> getSavedDraft({required String requesterRole, required WebsitePageSlot slot}) async {
    _requireAdmin(requesterRole);
    final draft = await _drafts.doc(slot.id).get();
    // A draft holding only the visual editor's blocks has no managed
    // content of its own: the published content is what to edit.
    if (!draft.exists || !_hasManagedContent(draft.data())) return null;
    return WebsitePageContent.fromMap(slot, draft.data()!);
  }

  /// Whether built-in page document [data] holds managed content (a
  /// heading, introduction or image), not only blocks.
  static bool _hasManagedContent(Map<String, dynamic>? data) => data != null && data.keys.any(_managedFields.contains);

  static const _managedFields = {'headline', 'intro', 'imageMediaId'};

  /// Throws while [slot]'s live page is built with blocks: visitors see
  /// the blocks, so the form's heading, introduction and image would not
  /// reach them, and unpublishing here would take the blocks down too.
  Future<void> _requireLiveNotBlocks(WebsitePageSlot slot, String verb) async {
    if (builtInPageBlocks((await _live.doc(slot.id).get()).data()) != null) {
      throw WebsiteContentException(
        'Visitors see the visual editor’s version of this page, so you can’t $verb it here. '
        'Use Edit a built-in page visually to change or unpublish it.',
      );
    }
  }

  /// What visitors currently see for [slot], or null when nothing is
  /// published (the page uses its built-in text and placeholder).
  Future<WebsitePageContent?> getLive({required String requesterRole, required WebsitePageSlot slot}) async {
    _requireAdmin(requesterRole);
    final live = await _live.doc(slot.id).get();
    if (!live.exists || live.data() == null) return null;
    return WebsitePageContent.fromMap(slot, live.data()!);
  }

  /// Limits and "English first" apply to every language.
  void _validatePage(WebsitePageContent content) {
    if (content.headline.values.values.any((t) => t.trim().length > maxHeadlineLength)) {
      throw WebsiteContentException('Headings must be $maxHeadlineLength characters or fewer.');
    }
    if (content.intro.values.values.any((t) => t.trim().length > maxIntroLength)) {
      throw WebsiteContentException('Introductions must be $maxIntroLength characters or fewer.');
    }
    if (content.headline.languageMissingSource ?? content.intro.languageMissingSource case final name?) {
      throw WebsiteContentException('Enter the English text as well as the $name text.');
    }
  }

  /// Saves [content] as the page's draft (not visible to visitors). Text
  /// identical to the built-in copy is stored blank ("use built-in").
  Future<void> saveDraft({required String requesterRole, required AppUser actor, required WebsitePageContent content}) async {
    _requireAdmin(requesterRole);
    _validatePage(content);
    final ref = _drafts.doc(content.slot.id);
    final data = {
      ...content.normalized().toContentMap(),
      'mediaIds': await _slotMediaIds(ref, content),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
    };
    // Its own fields only: a page built with blocks keeps its blocks.
    await _writeFields(ref, data);
  }

  /// Writes [data]'s top-level fields exactly as given and leaves every
  /// other field of the document as it is: an update of an existing
  /// document (each listed field replaced whole), or a new document.
  static Future<void> _writeFields(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final existing = await ref.get();
    existing.exists ? await ref.update(data) : await ref.set(data);
  }

  /// The images a built-in page's document uses: [content]'s image and
  /// those of the blocks it holds, if any.
  Future<List<String>> _slotMediaIds(DocumentReference<Map<String, dynamic>> ref, WebsitePageContent content) async {
    final blocks = builtInPageBlocks((await ref.get()).data()) ?? const <WebsiteBlock>[];
    return {?content.imageMediaId, ...BlockRegistry.referencedMedia(blocks)}.toList();
  }

  /// Saves [content] as the draft and publishes it: the live page gets the
  /// visitor-facing fields only. Its image, if any, must be published.
  Future<void> publishPage({required String requesterRole, required AppUser actor, required WebsitePageContent content}) async {
    _requireAdmin(requesterRole);
    _validatePage(content);
    await _requireLiveNotBlocks(content.slot, 'publish');
    final imageId = content.imageMediaId;
    if (imageId != null) {
      final image = await _requireMedia(imageId);
      if (!image.isPublished) throw WebsiteContentException('Publish the selected image first (Media library), or choose a published one.');
    }
    await saveDraft(requesterRole: requesterRole, actor: actor, content: content);
    final ref = _live.doc(content.slot.id);
    await _publishAfterDraft(() async {
      final data = {
        ...content.normalized().toContentMap(),
        'mediaIds': await _slotMediaIds(ref, content),
        'publishedAt': FieldValue.serverTimestamp(),
      };
      await _writeFields(ref, data);
    });
  }

  /// Runs a publication's live write, once its draft is saved: a failure
  /// says the draft was saved ([publishFailedMessage]).
  static Future<void> _publishAfterDraft(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {
      throw WebsiteContentException(publishFailedMessage);
    }
  }

  /// Throws unless [blocks] show visitors something: a block that isn't
  /// hidden (sections and columns only hold blocks, so they count by what
  /// they hold). Unsupported blocks aren't shown, so they don't count.
  static void _requireVisibleContent(List<WebsiteBlock> blocks) {
    if (!showsVisitorsSomething(blocks)) throw WebsiteContentException(nothingVisibleMessage);
  }

  /// Whether [blocks] show visitors something (see [_requireVisibleContent]):
  /// publishing pages built with blocks is refused otherwise.
  static bool showsVisitorsSomething(List<WebsiteBlock> blocks) =>
      BlockRegistry.flatten(BlockRegistry.withoutHidden(blocks)).any((b) => b is StructuredBlock && !containerTypes.contains(b.type));

  /// Whether visitors see something published for a built-in page that
  /// publishing blocks would replace: published blocks ([liveBlocks]), or
  /// a heading, introduction or (published) image published with the form
  /// editor ([liveContent]). Text stored blank means the site's own
  /// wording, which is not a published version.
  static bool builtInHasPublishedVersion({List<WebsiteBlock>? liveBlocks, WebsitePageContent? liveContent, required Iterable<WebsiteMedia> media}) {
    if (liveBlocks != null) return true;
    if (liveContent == null) return false;
    final image = liveContent.imageMediaId;
    return !liveContent.headline.isEmpty || !liveContent.intro.isEmpty || (image != null && media.any((m) => m.id == image && m.isPublished));
  }

  /// Removes the page's published content; the page returns to its
  /// built-in text and placeholder. The draft is kept.
  Future<void> unpublishPage({required String requesterRole, required AppUser actor, required WebsitePageSlot slot}) async {
    _requireAdmin(requesterRole);
    await _requireLiveNotBlocks(slot, 'unpublish');
    await _live.doc(slot.id).delete();
  }

  // ------------------------------------------ built-in pages as blocks

  /// Built-in [page]'s blocks: the draft's and what is live (null when it
  /// isn't built with blocks there), and its managed content (the draft,
  /// else what is live; null for Contact or when there is none) — what a
  /// conversion starts from.
  ///
  /// `liveContent` is the managed content of the live page as published
  /// (null for Contact, or when nothing is published): what visitors see
  /// on the built-in page while no blocks are published.
  ///
  /// `draftStyle` and `liveStyle` are the page's own look ([PageStyle]) in
  /// each.
  Future<({List<WebsiteBlock>? draft, List<WebsiteBlock>? live, WebsitePageContent? content, WebsitePageContent? liveContent, PageStyle draftStyle, PageStyle liveStyle})> getBuiltInPage(
      {required String requesterRole, required BuiltInPage page}) async {
    _requireAdmin(requesterRole);
    final draft = (await _drafts.doc(page.id).get()).data();
    final live = (await _live.doc(page.id).get()).data();
    final slot = page.slot;
    final content = slot == null
        ? null
        : _hasManagedContent(draft)
            ? WebsitePageContent.fromMap(slot, draft!)
            : live != null
                ? WebsitePageContent.fromMap(slot, live)
                : null;
    return (
      draft: builtInPageBlocks(draft),
      live: builtInPageBlocks(live),
      content: content,
      liveContent: slot != null && _hasManagedContent(live) ? WebsitePageContent.fromMap(slot, live!) : null,
      draftStyle: PageStyle.fromMap(draft?[PageStyle.field]),
      liveStyle: PageStyle.fromMap(live?[PageStyle.field]),
    );
  }

  void _validateBlocks(List<WebsiteBlock> blocks) {
    final errors = BlockRegistry.validate(blocks);
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// What a draft may have but a published page can't: a gallery with no
  /// image ([BlockRegistry.publishProblems]).
  static void _requirePublishable(List<WebsiteBlock> blocks) {
    final errors = BlockRegistry.publishProblems(blocks);
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// [blocks] and [style] as fields of built-in page document [ref], with
  /// every image the document uses (its managed image too). The live page
  /// leaves out hidden blocks and galleries' empty image slots
  /// ([BlockRegistry.forVisitors]). A page
  /// without its own look stores none (a stored one is removed).
  Future<Map<String, dynamic>> _builtInFields(DocumentReference<Map<String, dynamic>> ref, List<WebsiteBlock> all, PageStyle style, {bool live = false}) async {
    final blocks = live ? BlockRegistry.forVisitors(all) : all;
    final existing = (await ref.get()).data();
    final image = existing?['imageMediaId'];
    return {
      'schemaVersion': 2,
      'blocks': BlockRegistry.toMapList(blocks),
      'mediaIds': {if (image is String && image.isNotEmpty) image, ...BlockRegistry.referencedMedia(blocks)}.toList(),
      if (!style.isDefault)
        PageStyle.field: style.toMap()
      else if (existing?.containsKey(PageStyle.field) ?? false)
        PageStyle.field: FieldValue.delete(),
    };
  }

  void _validatePageStyle(PageStyle style) {
    final errors = style.validationErrors();
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// Saves [blocks] as built-in [page]'s draft. Only the blocks fields are
  /// written: the page's managed headline, introduction and image (what
  /// older versions of the app show) are kept as they are. Visitors keep
  /// seeing the published page.
  Future<void> saveBuiltInPageDraft({required String requesterRole, required AppUser actor, required BuiltInPage page, required List<WebsiteBlock> blocks, PageStyle style = const PageStyle()}) async {
    _requireAdmin(requesterRole);
    _validateBlocks(blocks);
    _validatePageStyle(style);
    final ref = _drafts.doc(page.id);
    await _requireWithinPageLimit(blocks, saved: builtInPageBlocks((await ref.get()).data()));
    final data = {
      ...await _builtInFields(ref, blocks, style),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
    };
    await _writeFields(ref, data);
  }

  /// Saves [blocks] as the draft and publishes them: visitors then see the
  /// page built with blocks (the live copy leaves out hidden blocks). Every
  /// image must be published. If the draft is saved but the live page
  /// can't be written, the error says so.
  Future<void> publishBuiltInPage({required String requesterRole, required AppUser actor, required BuiltInPage page, required List<WebsiteBlock> blocks, PageStyle style = const PageStyle()}) async {
    _requireAdmin(requesterRole);
    blocks = await updateAlbumGalleries(requesterRole: requesterRole, blocks: blocks);
    _validateBlocks(blocks);
    _validatePageStyle(style);
    _requirePublishable(blocks);
    _requireVisibleContent(blocks);
    await _requirePublishedMedia(BlockRegistry.referencedMedia(blocks));
    await saveBuiltInPageDraft(requesterRole: requesterRole, actor: actor, page: page, blocks: blocks, style: style);
    final ref = _live.doc(page.id);
    await _publishAfterDraft(() async {
      final data = {...await _builtInFields(ref, blocks, style, live: true), 'publishedAt': FieldValue.serverTimestamp()};
      await _writeFields(ref, data);
    });
  }

  /// Takes the blocks off the website: visitors see the built-in page
  /// again (with its published headline, introduction and image, if any).
  /// The draft keeps its blocks.
  Future<void> unpublishBuiltInPage({required String requesterRole, required AppUser actor, required BuiltInPage page}) async {
    _requireAdmin(requesterRole);
    await _removeBlocks(_live.doc(page.id));
  }

  /// Returns built-in [page] to its built-in content everywhere: its
  /// blocks are removed from the draft and the live page. Its managed
  /// headline, introduction and image are kept.
  Future<void> revertBuiltInPage({required String requesterRole, required AppUser actor, required BuiltInPage page}) async {
    _requireAdmin(requesterRole);
    await _removeBlocks(_live.doc(page.id));
    await _removeBlocks(_drafts.doc(page.id), actor: actor);
  }

  Future<void> _removeBlocks(DocumentReference<Map<String, dynamic>> ref, {AppUser? actor}) async {
    final data = (await ref.get()).data();
    if (data == null) return;
    final image = data['imageMediaId'];
    // A document that only held blocks (e.g. Contact) is removed.
    if (!_hasManagedContent(data)) {
      await ref.delete();
      return;
    }
    await ref.update({
      'schemaVersion': FieldValue.delete(),
      'blocks': FieldValue.delete(),
      // The page's look goes with its blocks: the built-in page looks as
      // it always has.
      PageStyle.field: FieldValue.delete(),
      'mediaIds': [if (image is String && image.isNotEmpty) image],
      if (actor != null) ...{'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''},
    });
  }

  // ------------------------------------------------------ additional pages

  /// Every additional page (archived ones included), with what is live for
  /// each, in navigation order.
  Future<List<({CustomPage draft, CustomPage? live})>> listCustomPages({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final drafts = await _drafts.where('kind', isEqualTo: CustomPage.kind).get();
    final live = await _live.where('kind', isEqualTo: CustomPage.kind).get();
    final liveById = {for (final doc in live.docs) doc.id: CustomPage.fromMap(doc.id, doc.data())};
    final pages = [
      for (final doc in drafts.docs) (draft: CustomPage.fromMap(doc.id, doc.data()), live: liveById[doc.id]),
    ];
    pages.sort((a, b) => a.draft.navOrder != b.draft.navOrder ? a.draft.navOrder.compareTo(b.draft.navOrder) : a.draft.slug.compareTo(b.draft.slug));
    return pages;
  }

  /// One additional page's draft and live copy, or null if it doesn't exist.
  Future<({CustomPage draft, CustomPage? live})?> getCustomPage({required String requesterRole, required String pageId}) async {
    _requireAdmin(requesterRole);
    final draft = await _drafts.doc(pageId).get();
    final data = draft.data();
    if (!draft.exists || data == null || !CustomPage.isCustomDoc(data)) return null;
    final live = await _live.doc(pageId).get();
    return (draft: CustomPage.fromMap(pageId, data), live: live.exists && live.data() != null ? CustomPage.fromMap(pageId, live.data()!) : null);
  }

  /// Throws unless [slug] is well formed and not used by any other
  /// additional page (archived pages keep their slug reserved, so an old
  /// link never starts showing a different page). Checked against drafts
  /// and live pages; two admins saving the same new slug at the same moment
  /// is not prevented (Firestore can't query inside a transaction).
  Future<void> _requireAvailableSlug(String slug, {String? exceptPageId}) async {
    final error = CustomPage.validateSlugFormat(slug);
    if (error != null) throw WebsiteContentException(error);
    for (final collection in [_drafts, _live]) {
      final snapshot = await collection.where('slug', isEqualTo: slug).get();
      if (snapshot.docs.any((doc) => doc.id != exceptPageId)) {
        throw WebsiteContentException('Another page already uses the web address /pages/$slug. Choose a different one.');
      }
    }
  }

  void _validateCustomPage(CustomPage page) {
    final errors = page.validationErrors();
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// Creates a draft additional page (not on the website, not in the
  /// navigation) with [title] at `/pages/<slug>`. New pages are built with
  /// blocks (no blocks yet); existing pages made of sections are unchanged.
  Future<CustomPage> createCustomPage({required String requesterRole, required AppUser actor, required LocalizedText title, required String slug}) async {
    _requireAdmin(requesterRole);
    final cleanSlug = slug.trim();
    final draftRef = _drafts.doc();
    final page = CustomPage(id: draftRef.id, slug: cleanSlug, title: title.trimmed(), blocks: const []);
    _validateCustomPage(page);
    await _requireAvailableSlug(cleanSlug);
    final existing = await _drafts.where('kind', isEqualTo: CustomPage.kind).get();
    var nextOrder = 0;
    for (final doc in existing.docs) {
      final order = doc.data()['navOrder'];
      if (order is num && order.toInt() >= nextOrder) nextOrder = order.toInt() + 1;
    }
    final created = page.copyWith(navOrder: nextOrder);
    await draftRef.set({
      ...created.toContentMap(),
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
    });
    return created;
  }

  /// Saves [page] as its draft (visitors keep seeing the live copy).
  Future<void> saveCustomPageDraft({required String requesterRole, required AppUser actor, required CustomPage page}) async {
    _requireAdmin(requesterRole);
    final current = await getCustomPage(requesterRole: requesterRole, pageId: page.id);
    if (current == null) throw WebsiteContentException('This page no longer exists.');
    _validateCustomPage(page);
    if (page.blocks case final blocks?) await _requireWithinPageLimit(blocks, saved: current.draft.blocks);
    await _requireAvailableSlug(page.slug.trim(), exceptPageId: page.id);
    await _drafts.doc(page.id).set({
      ...page.copyWith(navOrder: current.draft.navOrder).toContentMap(),
      // A merge keeps fields that aren't written: a cleared page look is
      // removed explicitly.
      if (page.pageStyle.isDefault) PageStyle.field: FieldValue.delete(),
      'archived': current.draft.archived,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
    }, SetOptions(merge: true));
  }

  /// Saves [page] as the draft and publishes it at `/pages/<slug>`: the
  /// live copy holds the visitor-facing fields only, without hidden blocks.
  /// Every image on it must be published; archived pages must be restored
  /// first.
  Future<void> publishCustomPage({required String requesterRole, required AppUser actor, required CustomPage page}) async {
    _requireAdmin(requesterRole);
    if (page.blocks case final blocks?) {
      final updated = await updateAlbumGalleries(requesterRole: requesterRole, blocks: blocks);
      if (!identical(updated, blocks)) page = page.copyWith(blocks: () => updated);
    }
    final current = await getCustomPage(requesterRole: requesterRole, pageId: page.id);
    if (current == null) throw WebsiteContentException('This page no longer exists.');
    if (current.draft.archived) throw WebsiteContentException('Restore this page before publishing it.');
    _validateCustomPage(page);
    // Pages made of sections (the older format) are unchanged.
    if (page.blocks case final blocks?) {
      _requirePublishable(blocks);
      _requireVisibleContent(blocks);
    }
    await _requirePublishedMedia(page.referencedMedia);
    await saveCustomPageDraft(requesterRole: requesterRole, actor: actor, page: page);
    await _publishAfterDraft(() => _live.doc(page.id).set({
          ...page.forVisitors.copyWith(navOrder: current.draft.navOrder).toContentMap(),
          'publishedAt': FieldValue.serverTimestamp(),
        }));
  }

  /// Takes the page off the website (its address shows "page not found");
  /// the draft is kept.
  Future<void> unpublishCustomPage({required String requesterRole, required AppUser actor, required String pageId}) async {
    _requireAdmin(requesterRole);
    await _live.doc(pageId).delete();
  }

  /// Unpublishes the page and moves it out of the active list. Its slug
  /// stays reserved.
  Future<void> archiveCustomPage({required String requesterRole, required AppUser actor, required String pageId}) async {
    _requireAdmin(requesterRole);
    if (await getCustomPage(requesterRole: requesterRole, pageId: pageId) == null) throw WebsiteContentException('This page no longer exists.');
    await _live.doc(pageId).delete();
    await _drafts.doc(pageId).update({'archived': true, 'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''});
  }

  /// Brings an archived page back as an unpublished draft.
  Future<void> restoreCustomPage({required String requesterRole, required AppUser actor, required String pageId}) async {
    _requireAdmin(requesterRole);
    if (await getCustomPage(requesterRole: requesterRole, pageId: pageId) == null) throw WebsiteContentException('This page no longer exists.');
    await _drafts.doc(pageId).update({'archived': false, 'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''});
  }

  /// Sets the navigation order of additional pages to [orderedIds]. This
  /// is a site setting rather than page content, so it applies at once to
  /// published pages as well as drafts.
  Future<void> reorderCustomPages({required String requesterRole, required AppUser actor, required List<String> orderedIds}) async {
    _requireAdmin(requesterRole);
    final live = await _live.where('kind', isEqualTo: CustomPage.kind).get();
    final liveIds = {for (final doc in live.docs) doc.id};
    final batch = _firestore.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_drafts.doc(orderedIds[i]), {'navOrder': i});
      if (liveIds.contains(orderedIds[i])) batch.update(_live.doc(orderedIds[i]), {'navOrder': i});
    }
    await batch.commit();
  }

  // ----------------------------------------------------------- site layout

  /// The saved layout draft and the published layout. `liveUnreadable` is
  /// true when a published layout exists but can't be used (visitors then
  /// see the built-in layout).
  Future<({SiteLayout? draft, SiteLayout? live, bool liveUnreadable})> getSiteLayout({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final draft = await _drafts.doc(SiteLayout.docId).get();
    final live = await _live.doc(SiteLayout.docId).get();
    final liveLayout = live.exists ? SiteLayout.tryParse(live.data()) : null;
    return (
      draft: draft.exists ? SiteLayout.tryParse(draft.data()) : null,
      live: liveLayout,
      liveUnreadable: live.exists && liveLayout == null,
    );
  }

  /// The published additional pages, exactly as visitors get them (what a
  /// layout's page links resolve against).
  Future<List<CustomPage>> publishedCustomPages({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    return WebsiteContentRepository(firestore: _firestore).liveCustomPages();
  }

  /// A first layout that reproduces the current navigation.
  Future<SiteLayout> initialSiteLayout({required String requesterRole}) async =>
      SiteLayout.fromCurrentNavigation(await publishedCustomPages(requesterRole: requesterRole));

  void _validateLayout(SiteLayout layout) {
    final errors = layout.validationErrors();
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// Writes [data]'s top-level fields exactly as given (a text map that
  /// no longer has a language loses it), keeping the document's other
  /// fields (e.g. who last published). `merge: true` would instead merge
  /// nested maps key by key, so a language could never be cleared.
  static SetOptions _exactFields(Map<String, dynamic> data) => SetOptions(mergeFields: data.keys.toList());

  /// Saves [layout] as the draft; visitors keep seeing the published (or
  /// built-in) layout.
  Future<void> saveSiteLayoutDraft({required String requesterRole, required AppUser actor, required SiteLayout layout}) async {
    _requireAdmin(requesterRole);
    _validateLayout(layout);
    final data = {
      ...layout.toDraftMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
    };
    await _drafts.doc(SiteLayout.docId).set(data, _exactFields(data));
    await _clearDefaultStyles(_drafts.doc(SiteLayout.docId), layout, done: 'The draft was saved');
  }

  /// Saves [layout] as the draft and publishes it, in one atomic batch:
  /// the live copy holds the visitor-facing fields only, and the draft
  /// records who published it. Refused while a visible link leads to an
  /// additional page that isn't published.
  Future<void> publishSiteLayout({required String requesterRole, required AppUser actor, required SiteLayout layout}) async {
    _requireAdmin(requesterRole);
    _validateLayout(layout);
    final published = await publishedCustomPages(requesterRole: requesterRole);
    final unpublished = layout.unpublishedLinkErrors({for (final p in published) p.id});
    if (unpublished.isNotEmpty) throw WebsiteContentException(unpublished.first);
    final batch = _firestore.batch();
    final draft = {
      ...layout.toDraftMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': actor.id,
      'updatedByName': actor.name ?? '',
      'lastPublishedAt': FieldValue.serverTimestamp(),
      'lastPublishedById': actor.id,
      'lastPublishedByName': actor.name ?? '',
    };
    batch.set(_drafts.doc(SiteLayout.docId), draft, _exactFields(draft));
    batch.set(_live.doc(SiteLayout.docId), {...layout.toMap(), 'publishedAt': FieldValue.serverTimestamp()});
    await batch.commit();
    await _clearDefaultStyles(_drafts.doc(SiteLayout.docId), layout, done: 'The layout was published and visitors see it');
  }

  /// The draft's design, header and footer are written only while they
  /// differ from the site's own look; back to it, they are removed (the
  /// live copy is replaced whole, so it never keeps them).
  ///
  /// Runs after the write described by [done] succeeded, so a failure here
  /// is a [WebsiteLayoutCleanupException] saying so, never a failed save or
  /// publication.
  Future<void> _clearDefaultStyles(DocumentReference<Map<String, dynamic>> ref, SiteLayout layout, {required String done}) async {
    final stale = {
      if (layout.design.isDefault) 'design': FieldValue.delete(),
      if (layout.header.isDefault) 'header': FieldValue.delete(),
      if (layout.footer.isDefault) 'footer': FieldValue.delete(),
    };
    if (stale.isEmpty) return;
    try {
      await ref.update(stale);
    } catch (_) {
      throw WebsiteLayoutCleanupException(
        '$done, but the saved draft still holds the old design, header or footer settings, so the editor may show changes that aren’t there. Save the draft again to clear them.',
      );
    }
  }

  /// Removes the published layout: the site returns to its built-in header
  /// and footer. The draft is kept.
  Future<void> unpublishSiteLayout({required String requesterRole, required AppUser actor}) async {
    _requireAdmin(requesterRole);
    await _live.doc(SiteLayout.docId).delete();
  }

  // ------------------------------------------------------------- languages

  /// The saved language registry draft and the published one.
  /// `liveUnreadable` is true when a published registry exists but can't
  /// be used (visitors then get English and Tamil).
  Future<({SiteLanguageRegistry? draft, SiteLanguageRegistry? live, bool liveUnreadable})> getLanguageRegistry({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final draft = await _drafts.doc(SiteLanguageRegistry.docId).get();
    final live = await _live.doc(SiteLanguageRegistry.docId).get();
    final liveRegistry = live.exists ? SiteLanguageRegistry.tryParse(live.data()) : null;
    return (
      draft: draft.exists ? SiteLanguageRegistry.tryParse(draft.data()) : null,
      live: liveRegistry,
      liveUnreadable: live.exists && liveRegistry == null,
    );
  }

  /// The registry the editors use: the saved draft, else the published
  /// one, else the initial registry (English and Tamil).
  Future<SiteLanguageRegistry> editorLanguageRegistry({required String requesterRole}) async {
    final saved = await getLanguageRegistry(requesterRole: requesterRole);
    return saved.draft ?? saved.live ?? SiteLanguageRegistry.defaults;
  }

  void _validateRegistry(SiteLanguageRegistry registry) {
    final errors = registry.validationErrors();
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  Map<String, dynamic> _registryDraftFields(SiteLanguageRegistry registry, AppUser actor) => {
        ...registry.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedById': actor.id,
        'updatedByName': actor.name ?? '',
      };

  /// Saves [registry] as the draft; visitors keep the published (or
  /// built-in) languages. Only the registry changes — no text in any
  /// language is touched.
  Future<void> saveLanguageRegistryDraft({required String requesterRole, required AppUser actor, required SiteLanguageRegistry registry}) async {
    _requireAdmin(requesterRole);
    _validateRegistry(registry);
    final data = _registryDraftFields(registry, actor);
    await _drafts.doc(SiteLanguageRegistry.docId).set(data, _exactFields(data));
  }

  /// Saves [registry] as the draft and publishes it, in one atomic batch:
  /// the live copy holds the visitor-facing fields only.
  Future<void> publishLanguageRegistry({required String requesterRole, required AppUser actor, required SiteLanguageRegistry registry}) async {
    _requireAdmin(requesterRole);
    _validateRegistry(registry);
    final batch = _firestore.batch();
    final draft = {
      ..._registryDraftFields(registry, actor),
      'lastPublishedAt': FieldValue.serverTimestamp(),
      'lastPublishedById': actor.id,
      'lastPublishedByName': actor.name ?? '',
    };
    batch.set(_drafts.doc(SiteLanguageRegistry.docId), draft, _exactFields(draft));
    batch.set(_live.doc(SiteLanguageRegistry.docId), {...registry.toMap(), 'publishedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  /// Removes the published registry: visitors get English and Tamil again.
  /// The draft is kept, and no text in any language is deleted.
  Future<void> unpublishLanguageRegistry({required String requesterRole, required AppUser actor}) async {
    _requireAdmin(requesterRole);
    await _live.doc(SiteLanguageRegistry.docId).delete();
  }
}
