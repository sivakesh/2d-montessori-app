import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../auth/models/app_user.dart';
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/built_in_pages.dart';
import '../../../public_website/content/website_content_models.dart';
import '../../../public_website/content/website_content_repository.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_languages.dart';
import '../../../public_website/content/website_site_layout.dart';
import 'website_image_processor.dart';

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

/// An image chosen in the file picker, not yet uploaded.
class PickedWebsiteImage {
  const PickedWebsiteImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
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
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
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

  /// Uploaded files never change in place (a replacement is a new path), so
  /// browsers and the CDN may cache them for a long time.
  static const _cacheControl = 'public, max-age=31536000, immutable';

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

  /// Throws [WebsiteContentException] unless [name] is a JPEG/PNG/WebP
  /// image no larger than [maxUploadBytes].
  static void validateImageFile(String name, int length) {
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!allowedExtensions.contains(extension)) {
      throw WebsiteContentException('Choose a JPEG, PNG or WebP image.');
    }
    if (length == 0) throw WebsiteContentException('The selected file is empty.');
    if (length > maxUploadBytes) throw WebsiteContentException('Choose an image smaller than 15 MB.');
  }

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
  /// the gallery order.
  Future<WebsiteMedia> uploadMedia({
    required String requesterRole,
    required AppUser actor,
    required PickedWebsiteImage image,
    GalleryCategory category = GalleryCategory.general,
    LocalizedText alt = const LocalizedText(),
    LocalizedText caption = const LocalizedText(),
    bool inGallery = true,
  }) async {
    _requireAdmin(requesterRole);
    _validateMediaText(alt, caption);
    final existing = await _media.get();
    var nextOrder = 0;
    for (final doc in existing.docs) {
      final order = doc.data()['galleryOrder'];
      if (order is num && order.toInt() >= nextOrder) nextOrder = order.toInt() + 1;
    }
    final doc = _media.doc();
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
  }) async {
    _requireAdmin(requesterRole);
    _validateMediaText(alt, caption);
    final current = await _requireMedia(mediaId);
    if (current.isPublished && alt.en.trim().isEmpty) {
      throw WebsiteContentException('A published image needs English alt text.');
    }
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
  /// page using it). Requires English alt text and consent confirmation.
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
  }

  /// Labels of the pages (built-in or additional, draft or live) whose
  /// content uses [mediaId].
  Future<Set<String>> pagesUsing({required String requesterRole, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final labels = <String>{};
    for (final collection in [_drafts, _live]) {
      labels.addAll(await _labelsUsing(collection, mediaId));
    }
    return labels;
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
    final labels = await _labelsUsing(_live, mediaId);
    if (labels.isNotEmpty) {
      throw WebsiteContentException('You can’t $verb this image while the published ${labels.join(', ')} page shows it. Choose a different image there, or unpublish that page, first.');
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
    final data = {
      ...content.normalized().toContentMap(),
      'mediaIds': await _slotMediaIds(ref, content),
      'publishedAt': FieldValue.serverTimestamp(),
    };
    await _writeFields(ref, data);
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
  Future<({List<WebsiteBlock>? draft, List<WebsiteBlock>? live, WebsitePageContent? content})> getBuiltInPage({required String requesterRole, required BuiltInPage page}) async {
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
    return (draft: builtInPageBlocks(draft), live: builtInPageBlocks(live), content: content);
  }

  void _validateBlocks(List<WebsiteBlock> blocks) {
    final errors = BlockRegistry.validate(blocks);
    if (errors.isNotEmpty) throw WebsiteContentException(errors.first);
  }

  /// [blocks] as fields of built-in page document [ref], with every image
  /// the document uses (its managed image too). The live page leaves out
  /// hidden blocks ([BlockRegistry.withoutHidden]).
  Future<Map<String, dynamic>> _builtInFields(DocumentReference<Map<String, dynamic>> ref, List<WebsiteBlock> all, {bool live = false}) async {
    final blocks = live ? BlockRegistry.withoutHidden(all) : all;
    final existing = (await ref.get()).data();
    final image = existing?['imageMediaId'];
    return {
      'schemaVersion': 2,
      'blocks': BlockRegistry.toMapList(blocks),
      'mediaIds': {if (image is String && image.isNotEmpty) image, ...BlockRegistry.referencedMedia(blocks)}.toList(),
    };
  }

  /// Saves [blocks] as built-in [page]'s draft. Only the blocks fields are
  /// written: the page's managed headline, introduction and image (what
  /// older versions of the app show) are kept as they are. Visitors keep
  /// seeing the published page.
  Future<void> saveBuiltInPageDraft({required String requesterRole, required AppUser actor, required BuiltInPage page, required List<WebsiteBlock> blocks}) async {
    _requireAdmin(requesterRole);
    _validateBlocks(blocks);
    final ref = _drafts.doc(page.id);
    final data = {
      ...await _builtInFields(ref, blocks),
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
  Future<void> publishBuiltInPage({required String requesterRole, required AppUser actor, required BuiltInPage page, required List<WebsiteBlock> blocks}) async {
    _requireAdmin(requesterRole);
    _validateBlocks(blocks);
    await _requirePublishedMedia(BlockRegistry.referencedMedia(blocks));
    await saveBuiltInPageDraft(requesterRole: requesterRole, actor: actor, page: page, blocks: blocks);
    final ref = _live.doc(page.id);
    try {
      final data = {...await _builtInFields(ref, blocks, live: true), 'publishedAt': FieldValue.serverTimestamp()};
      await _writeFields(ref, data);
    } catch (_) {
      throw WebsiteContentException('The draft was saved, but the page could not be published: visitors still see the previous version. Check your connection and try publishing again.');
    }
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
    await _requireAvailableSlug(page.slug.trim(), exceptPageId: page.id);
    await _drafts.doc(page.id).set({
      ...page.copyWith(navOrder: current.draft.navOrder).toContentMap(),
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
    final current = await getCustomPage(requesterRole: requesterRole, pageId: page.id);
    if (current == null) throw WebsiteContentException('This page no longer exists.');
    if (current.draft.archived) throw WebsiteContentException('Restore this page before publishing it.');
    _validateCustomPage(page);
    await _requirePublishedMedia(page.referencedMedia);
    await saveCustomPageDraft(requesterRole: requesterRole, actor: actor, page: page);
    await _live.doc(page.id).set({
      ...page.forVisitors.copyWith(navOrder: current.draft.navOrder).toContentMap(),
      'publishedAt': FieldValue.serverTimestamp(),
    });
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
    await _clearDefaultStyles(_drafts.doc(SiteLayout.docId), layout);
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
    await _clearDefaultStyles(_drafts.doc(SiteLayout.docId), layout);
  }

  /// The draft's design, header and footer are written only while they
  /// differ from the site's own look; back to it, they are removed (the
  /// live copy is replaced whole, so it never keeps them).
  Future<void> _clearDefaultStyles(DocumentReference<Map<String, dynamic>> ref, SiteLayout layout) async {
    final stale = {
      if (layout.design.isDefault) 'design': FieldValue.delete(),
      if (layout.header.isDefault) 'header': FieldValue.delete(),
      if (layout.footer.isDefault) 'footer': FieldValue.delete(),
    };
    if (stale.isNotEmpty) await ref.update(stale);
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
