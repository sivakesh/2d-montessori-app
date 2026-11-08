import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../auth/models/app_user.dart';
import '../../settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../../public_website/content/blocks/block_registry.dart';
import '../../../public_website/content/blocks/website_block.dart';
import '../../../public_website/content/website_content_models.dart';
import 'website_content_admin_service.dart';

/// What a template holds: a whole section, or one block (a section is
/// inserted on the page; a block on the page or, unless it holds columns
/// itself, into a column).
enum WebsiteTemplateKind {
  section('section', 'Section'),
  block('block', 'Block');

  const WebsiteTemplateKind(this.id, this.label);
  final String id;
  final String label;

  static WebsiteTemplateKind? parse(Object? v) => values.where((k) => k.id == v).firstOrNull;
}

/// A reusable section or block of the school's website (in
/// [WebsiteCollections.templates]): the block exactly as pages store it
/// (`block`, with its columns, nested blocks, items, style, responsive
/// settings and image references), its name, description and optional
/// thumbnail (a media library image). Inserting makes an independent copy
/// with new ids throughout ([WebsiteTemplatesService.instantiate]); the
/// template and pages never share anything afterwards.
@immutable
class WebsiteTemplate {
  const WebsiteTemplate({
    required this.id,
    required this.schoolId,
    required this.kind,
    required this.name,
    required this.block,
    this.schemaVersion = WebsiteTemplate.currentSchemaVersion,
    this.description = '',
    this.thumbnailMediaId,
    this.mediaIds = const [],
    this.updatedAt,
    this.updatedByName = '',
  });

  /// The version of this record's shape. A template from a newer version
  /// is listed but can't be inserted (see [insertProblem]).
  static const currentSchemaVersion = 1;

  static const maxName = 80;
  static const maxDescription = 300;

  /// The stored block's largest size (its JSON, in characters): well
  /// within a Firestore document.
  static const maxBlockSize = 400000;

  factory WebsiteTemplate.fromMap(String id, Map<String, dynamic> map) => WebsiteTemplate(
        id: id,
        schoolId: map['schoolId']?.toString() ?? '',
        schemaVersion: map['schemaVersion'] is int ? map['schemaVersion'] as int : 0,
        kind: WebsiteTemplateKind.parse(map['kind']) ?? WebsiteTemplateKind.block,
        name: map['name']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        thumbnailMediaId: map['thumbnailMediaId'] is String && (map['thumbnailMediaId'] as String).isNotEmpty ? map['thumbnailMediaId'] as String : null,
        block: BlockRegistry.parse(map['block']),
        mediaIds: map['mediaIds'] is List ? [for (final m in map['mediaIds'] as List) if (m is String) m] : const [],
        updatedAt: map['updatedAt'] is Timestamp ? (map['updatedAt'] as Timestamp).toDate() : null,
        updatedByName: map['updatedByName']?.toString() ?? '',
      );

  final String id;
  final String schoolId;
  final int schemaVersion;
  final WebsiteTemplateKind kind;
  final String name;
  final String description;
  final String? thumbnailMediaId;

  /// The section or block, as stored on pages.
  final WebsiteBlock block;

  /// Every media library image it uses (its blocks' and its thumbnail).
  final List<String> mediaIds;
  final DateTime? updatedAt;
  final String updatedByName;

  /// "Section", or the block's type ("Text", "Columns", …).
  String get typeLabel => kind == WebsiteTemplateKind.section ? 'Section' : (block is StructuredBlock ? (block as StructuredBlock).definition.label : 'Block');

  /// Whether it holds columns itself (a section or columns block), so it
  /// can't go inside a column.
  bool get isContainer => block is StructuredBlock && containerTypes.contains(block.type);

  /// Why it can't be inserted, or null when it can.
  String? get insertProblem {
    if (schemaVersion > currentSchemaVersion) return 'Made with a newer version of the website editor. Update the app to use it.';
    if (BlockRegistry.flatten([block]).any((b) => b is UnsupportedBlock)) return 'It holds a block this version of the editor can’t show.';
    return null;
  }

  /// Whether [query] (any words, any case) is in its name, description or
  /// type.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final text = '$name $description $typeLabel ${kind.label}'.toLowerCase();
    return words.every(text.contains);
  }
}

/// The school's template library: save a section or block as a template,
/// list and search them, rename, describe, change or remove the
/// thumbnail, delete, and make an independent copy to insert.
///
/// - Admin only, and scoped to [schoolId]: another school's template is
///   never listed, read or changed. Every method checks; the security
///   rules enforce the same (`website_templates` in
///   test/firebase_rules/website_content.firestore.rules).
/// - Pages never refer to a template: an inserted copy is ordinary page
///   content, so changing or deleting the template never changes a page.
class WebsiteTemplatesService {
  WebsiteTemplatesService({FirebaseFirestore? firestore, this.schoolId = kDefaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _templates => _db.collection(WebsiteCollections.templates);

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') throw UnauthorizedWebsiteContentException(requesterRole);
  }

  Map<String, dynamic> _stamp(AppUser actor) => {'updatedAt': FieldValue.serverTimestamp(), 'updatedById': actor.id, 'updatedByName': actor.name ?? ''};

  /// The school's templates, by name.
  Future<List<WebsiteTemplate>> list({required String requesterRole}) async {
    _requireAdmin(requesterRole);
    final snapshot = await _templates.where('schoolId', isEqualTo: schoolId).get();
    final templates = [for (final d in snapshot.docs) WebsiteTemplate.fromMap(d.id, d.data())];
    templates.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return templates;
  }

  /// One of the school's templates, or null (also for another school's).
  Future<WebsiteTemplate?> get({required String requesterRole, required String templateId}) async {
    _requireAdmin(requesterRole);
    final doc = await _templates.doc(templateId).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['schoolId'] != schoolId) return null;
    return WebsiteTemplate.fromMap(doc.id, data);
  }

  Future<WebsiteTemplate> _requireOwn(String templateId) async =>
      await get(requesterRole: 'admin', templateId: templateId) ?? (throw WebsiteContentException('This template no longer exists.'));

  /// Why [name] can't be a template's name, or null.
  static String? nameProblem(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Give the template a name.';
    if (n.length > WebsiteTemplate.maxName) return 'The name must be ${WebsiteTemplate.maxName} characters or fewer.';
    return null;
  }

  static String? _descriptionProblem(String description) =>
      description.trim().length > WebsiteTemplate.maxDescription ? 'The description must be ${WebsiteTemplate.maxDescription} characters or fewer.' : null;

  /// Why [block] can't be saved as a template, or null: blocks this
  /// version can't show (they couldn't be copied safely), and size.
  static String? blockProblem(WebsiteBlock block) {
    if (block is! StructuredBlock || BlockRegistry.flatten([block]).any((b) => b is UnsupportedBlock)) {
      return 'This block, or one inside it, was made with a newer version of the editor and can’t be saved as a template.';
    }
    if (jsonEncode(block.toMap()).length > WebsiteTemplate.maxBlockSize) return 'This is too large to save as a template.';
    return null;
  }

  /// Every image [block] and [thumbnailMediaId] use.
  static List<String> _mediaOf(WebsiteBlock block, String? thumbnailMediaId) => {
        ...BlockRegistry.referencedMedia([block]),
        if (thumbnailMediaId != null && thumbnailMediaId.isNotEmpty) thumbnailMediaId,
      }.toList();

  /// Saves a copy of [block] (a section, or any block) as a new template:
  /// the block exactly as it is now, nested blocks, settings, style and
  /// image references included. Later changes to the page don't change
  /// the template.
  Future<WebsiteTemplate> save({
    required String requesterRole,
    required AppUser actor,
    required WebsiteBlock block,
    required String name,
    String description = '',
    String? thumbnailMediaId,
  }) async {
    _requireAdmin(requesterRole);
    final problem = nameProblem(name) ?? _descriptionProblem(description) ?? blockProblem(block);
    if (problem != null) throw WebsiteContentException(problem);
    final ref = _templates.doc();
    final kind = block.type == 'section' ? WebsiteTemplateKind.section : WebsiteTemplateKind.block;
    final thumbnail = thumbnailMediaId != null && thumbnailMediaId.isNotEmpty ? thumbnailMediaId : null;
    final media = _mediaOf(block, thumbnail);
    await ref.set({
      'schoolId': schoolId,
      'schemaVersion': WebsiteTemplate.currentSchemaVersion,
      'kind': kind.id,
      'blockType': block.type,
      'name': name.trim(),
      'description': description.trim(),
      'thumbnailMediaId': thumbnail,
      'block': block.toMap(),
      'mediaIds': media,
      'createdAt': FieldValue.serverTimestamp(),
      'createdById': actor.id,
      'createdByName': actor.name ?? '',
      ..._stamp(actor),
    });
    return WebsiteTemplate(
      id: ref.id,
      schoolId: schoolId,
      kind: kind,
      name: name.trim(),
      description: description.trim(),
      thumbnailMediaId: thumbnail,
      block: block,
      mediaIds: media,
      updatedByName: actor.name ?? '',
    );
  }

  /// Renames [templateId] and sets its description.
  Future<void> updateDetails({required String requesterRole, required AppUser actor, required String templateId, required String name, required String description}) async {
    _requireAdmin(requesterRole);
    final problem = nameProblem(name) ?? _descriptionProblem(description);
    if (problem != null) throw WebsiteContentException(problem);
    await _requireOwn(templateId);
    await _templates.doc(templateId).update({'name': name.trim(), 'description': description.trim(), ..._stamp(actor)});
  }

  /// Sets (or, with null, removes) [templateId]'s thumbnail: an image
  /// from the media library, by id.
  Future<void> setThumbnail({required String requesterRole, required AppUser actor, required String templateId, required String? mediaId}) async {
    _requireAdmin(requesterRole);
    final template = await _requireOwn(templateId);
    final thumbnail = mediaId != null && mediaId.isNotEmpty ? mediaId : null;
    await _templates.doc(templateId).update({'thumbnailMediaId': thumbnail, 'mediaIds': _mediaOf(template.block, thumbnail), ..._stamp(actor)});
  }

  /// Deletes [templateId]. Pages that used it keep their copies.
  Future<void> delete({required String requesterRole, required String templateId}) async {
    _requireAdmin(requesterRole);
    await _requireOwn(templateId);
    await _templates.doc(templateId).delete();
  }

  /// A copy of [template]'s block to insert: everything as saved, with new
  /// ids for it and everything inside it (columns, nested blocks, items),
  /// so it never shares an id with the template, other copies or the page.
  /// Image references are kept as they are (the same media library
  /// images; no files are copied).
  static WebsiteBlock instantiate(WebsiteTemplate template) {
    final problem = template.insertProblem;
    if (problem != null) throw WebsiteContentException(problem);
    return BlockRegistry.duplicate(BlockRegistry.parse(template.block.toMap()));
  }
}
