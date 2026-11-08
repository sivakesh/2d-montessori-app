import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../auth/models/app_user.dart';
import '../../settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../../public_website/content/website_content_models.dart';
import 'website_content_admin_service.dart';

/// An album of the media library (in [WebsiteCollections.albums]): a
/// named, organisational group of images, admin only. Membership is held
/// here, as the images' ids ([mediaIds], in the order added), never on the
/// images: a published image record is publicly readable, and editing an
/// image never touches its albums. An image may be in any number of
/// albums, or none. Being in an album changes nothing about an image's
/// publication, consent or gallery visibility.
///
/// Built so a later phase can let a Photo gallery show an album: that
/// would publish a public copy of the album's published images (as forms
/// have public copies), never this record.
@immutable
class WebsiteAlbum {
  const WebsiteAlbum({
    required this.id,
    required this.schoolId,
    required this.name,
    this.description = '',
    this.mediaIds = const [],
    this.schemaVersion = currentSchemaVersion,
    this.updatedAt,
  });

  static const currentSchemaVersion = 1;
  static const maxName = 80;
  static const maxDescription = 300;

  /// Images in one album (its record stays far below Firestore's size
  /// limit).
  static const maxImages = 2000;

  factory WebsiteAlbum.fromMap(String id, Map<String, dynamic> map) {
    final updatedAt = map['updatedAt'];
    return WebsiteAlbum(
      id: id,
      schoolId: map['schoolId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      mediaIds: [
        for (final id in (map['mediaIds'] is List ? map['mediaIds'] as List : const []))
          if (id is String && id.isNotEmpty) id,
      ],
      schemaVersion: map['schemaVersion'] is int ? map['schemaVersion'] as int : 1,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }

  final String id;
  final String schoolId;
  final String name;
  final String description;

  /// The images' ids as stored, possibly including images since deleted
  /// (see [availableIn]).
  final List<String> mediaIds;
  final int schemaVersion;
  final DateTime? updatedAt;

  /// The ids of this album's images that are still in [library], in album
  /// order: a deleted or unreadable image is simply left out.
  List<String> availableIn(Iterable<WebsiteMedia> library) {
    final known = {for (final m in library) m.id};
    return [for (final id in mediaIds) if (known.contains(id)) id];
  }

  /// Whether [query] (any case) is in its name or description.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || description.toLowerCase().contains(q);
  }
}

/// The media library's albums.
/// - Admin only, and scoped to [schoolId] like the template library:
///   another school's album is never listed, read or changed.
/// - Every change is a field update ([FieldValue.arrayUnion] /
///   [FieldValue.arrayRemove] for membership), so properties this version
///   doesn't know are kept and two admins adding images at once don't
///   overwrite each other.
/// - Never changes an image: deleting an album leaves its images as they
///   are.
///
/// The security rules need a matching `website_albums` rule (admin with
/// the school claim, never public) before this works against them; it is
/// not in the rules proposal yet (pending approval).
class WebsiteAlbumsService {
  WebsiteAlbumsService({FirebaseFirestore? firestore, this.schoolId = kDefaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _albums => _db.collection(WebsiteCollections.albums);

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') throw UnauthorizedWebsiteContentException(requesterRole);
  }

  Map<String, dynamic> _stamp(AppUser actor) => {'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''};

  /// The school's albums, by name.
  Future<List<WebsiteAlbum>> list({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _albums.where('schoolId', isEqualTo: schoolId).get();
    return [for (final doc in snapshot.docs) WebsiteAlbum.fromMap(doc.id, doc.data())]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<WebsiteAlbum> _requireOwn(String albumId) async {
    final doc = await _albums.doc(albumId).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['schoolId'] != schoolId) throw WebsiteContentException('This album no longer exists.');
    return WebsiteAlbum.fromMap(doc.id, data);
  }

  /// [name] and [description] trimmed, or why they can't be used.
  static (String, String) _checked(String name, String description) {
    final n = name.trim();
    final d = description.trim();
    if (n.isEmpty) throw WebsiteContentException('Enter a name for the album.');
    if (n.length > WebsiteAlbum.maxName) throw WebsiteContentException('Album names must be ${WebsiteAlbum.maxName} characters or fewer.');
    if (d.length > WebsiteAlbum.maxDescription) throw WebsiteContentException('Album descriptions must be ${WebsiteAlbum.maxDescription} characters or fewer.');
    return (n, d);
  }

  /// A new, empty album.
  Future<WebsiteAlbum> create({required String requesterRole, required AppUser actor, required String name, String description = ''}) async {
    _requireAdmin(requesterRole);
    final (n, d) = _checked(name, description);
    final doc = _albums.doc();
    await doc.set({
      'schoolId': schoolId,
      'schemaVersion': WebsiteAlbum.currentSchemaVersion,
      'name': n,
      if (d.isNotEmpty) 'description': d,
      'mediaIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'createdById': actor.id,
      'createdByName': actor.name ?? '',
      ..._stamp(actor),
    });
    return _requireOwn(doc.id);
  }

  /// Renames the album and sets its description (its images unchanged).
  Future<void> update({required String requesterRole, required AppUser actor, required String albumId, required String name, required String description}) async {
    _requireAdmin(requesterRole);
    final (n, d) = _checked(name, description);
    await _requireOwn(albumId);
    await _albums.doc(albumId).update({'name': n, 'description': d.isEmpty ? FieldValue.delete() : d, ..._stamp(actor)});
  }

  /// Deletes the album only: its images stay in the library as they are.
  Future<void> delete({required String requesterRole, required String albumId}) async {
    _requireAdmin(requesterRole);
    await _requireOwn(albumId);
    await _albums.doc(albumId).delete();
  }

  /// Adds [mediaIds] to the album (ones already in it stay where they are).
  /// Returns how many were new.
  Future<int> addMedia({required String requesterRole, required AppUser actor, required String albumId, required Iterable<String> mediaIds}) async {
    _requireAdmin(requesterRole);
    final album = await _requireOwn(albumId);
    final adding = {for (final id in mediaIds) if (id.isNotEmpty && !album.mediaIds.contains(id)) id}.toList();
    if (adding.isEmpty) return 0;
    if (album.mediaIds.length + adding.length > WebsiteAlbum.maxImages) {
      throw WebsiteContentException('An album can hold at most ${WebsiteAlbum.maxImages} images; “${album.name}” has room for ${WebsiteAlbum.maxImages - album.mediaIds.length} more.');
    }
    await _albums.doc(albumId).update({'mediaIds': FieldValue.arrayUnion(adding), ..._stamp(actor)});
    return adding.length;
  }

  /// Removes [mediaIds] from the album (the images themselves unchanged).
  /// Returns how many were in it.
  Future<int> removeMedia({required String requesterRole, required AppUser actor, required String albumId, required Iterable<String> mediaIds}) async {
    _requireAdmin(requesterRole);
    final album = await _requireOwn(albumId);
    final removing = {for (final id in mediaIds) if (album.mediaIds.contains(id)) id}.toList();
    if (removing.isEmpty) return 0;
    await _albums.doc(albumId).update({'mediaIds': FieldValue.arrayRemove(removing), ..._stamp(actor)});
    return removing.length;
  }

  /// Takes a deleted image out of every album of the school. Best effort:
  /// an album that still lists it just leaves it out ([WebsiteAlbum.availableIn]).
  Future<void> forgetMedia({required String requesterRole, required String mediaId}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _albums.where('schoolId', isEqualTo: schoolId).get();
    for (final doc in snapshot.docs) {
      if ((doc.data()['mediaIds'] as List?)?.contains(mediaId) ?? false) {
        await doc.reference.update({'mediaIds': FieldValue.arrayRemove([mediaId]), 'updatedAt': FieldValue.serverTimestamp()});
      }
    }
  }
}
