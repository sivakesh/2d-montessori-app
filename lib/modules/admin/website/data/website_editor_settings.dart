import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../auth/models/app_user.dart';
import '../../../public_website/content/blocks/block_limits.dart';
import '../../settings/models/school_settings_model.dart';

/// The Website visual editor's settings for a school: today, how many
/// blocks a page may have ([maxBlocksPerPage]). Stored as the
/// `websiteEditor` part of the school's School Settings record
/// (`school_settings/{schoolId}`), beside its other settings; none saved
/// means [BlockLimits.defaultPageMaxBlocks].
@immutable
class WebsiteEditorSettings {
  const WebsiteEditorSettings({
    required this.schoolId,
    this.maxBlocksPerPage = BlockLimits.defaultPageMaxBlocks,
    this.revision = 0,
    this.updatedAt,
    this.updatedByName = '',
    this.storedValueInvalid = false,
  });

  static const field = 'websiteEditor';
  static const schoolSettingsCollection = 'school_settings';
  static const auditCollection = 'audit';

  /// Reads the stored map. A value that isn't a whole number in range
  /// (edited by hand, or by a newer version) falls back to the default
  /// and is reported ([storedValueInvalid]) rather than used.
  factory WebsiteEditorSettings.fromMap(String schoolId, Object? raw) {
    final map = raw is Map ? raw : const {};
    final value = map['maxBlocksPerPage'];
    final whole = value is int ? value : (value is double && value == value.roundToDouble() ? value.toInt() : null);
    final valid = whole != null && validateMaxBlocks(whole) == null;
    final revision = map['revision'];
    final at = map['updatedAt'];
    return WebsiteEditorSettings(
      schoolId: schoolId,
      maxBlocksPerPage: valid ? whole : BlockLimits.defaultPageMaxBlocks,
      revision: revision is int ? revision : 0,
      updatedAt: at is Timestamp ? at.toDate() : null,
      updatedByName: map['updatedByName']?.toString() ?? '',
      storedValueInvalid: value != null && !valid,
    );
  }

  final String schoolId;
  final int maxBlocksPerPage;

  /// Bumped by each save; a save is refused when it changed meanwhile.
  final int revision;
  final DateTime? updatedAt;
  final String updatedByName;

  /// A value is stored but unusable, so the default applies.
  final bool storedValueInvalid;

  /// Never saved: the default applies.
  bool get isDefault => revision == 0;

  BlockLimits get limits => BlockLimits.forPage(maxBlocksPerPage);

  /// Why [value] can't be the page limit, or null.
  static String? validateMaxBlocks(int? value) {
    if (value == null) return 'Enter a whole number of blocks.';
    if (value < BlockLimits.minPageMaxBlocks || value > BlockLimits.safetyMaxBlocks) {
      return 'Enter a number from ${BlockLimits.minPageMaxBlocks} to ${BlockLimits.safetyMaxBlocks}.';
    }
    return null;
  }
}

/// Another administrator saved a change first: [current] is what is saved
/// now. Nothing was written.
class WebsiteEditorSettingsConflict implements Exception {
  WebsiteEditorSettingsConflict(this.current);

  final WebsiteEditorSettings current;

  @override
  String toString() => 'Another administrator changed this setting. Review it and try again.';
}

/// Reads and changes a school's [WebsiteEditorSettings], following
/// PublicSubmissionSettingsService:
/// - reading is for the website editors (who are admins); changing is for
///   an admin of that school only ([UnauthorizedSchoolSettingsException]).
///   The app serves one school today ([kDefaultSchoolId]);
/// - a change is one transaction: the settings part and an audit entry
///   (`school_settings/{schoolId}/audit`), or nothing; refused when the
///   setting changed since it was read ([WebsiteEditorSettingsConflict]).
///   The school's name, contact details, logo and other settings are kept.
class WebsiteEditorSettingsService {
  WebsiteEditorSettingsService({FirebaseFirestore? firestore, this.schoolId = kDefaultSchoolId}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String schoolId;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _record => _db.collection(WebsiteEditorSettings.schoolSettingsCollection).doc(schoolId);

  void _requireAdminOf(String requesterRole, String requesterSchoolId) {
    if (requesterRole.toLowerCase() != 'admin' || requesterSchoolId != schoolId || schoolId.isEmpty) {
      throw UnauthorizedSchoolSettingsException(requesterRole);
    }
  }

  WebsiteEditorSettings _from(DocumentSnapshot<Map<String, dynamic>> doc) => WebsiteEditorSettings.fromMap(schoolId, doc.data()?[WebsiteEditorSettings.field]);

  Future<WebsiteEditorSettings> load() async => _from(await _record.get());

  /// The settings now and after each change (the editors' limits follow it
  /// while they are open).
  Stream<WebsiteEditorSettings> watch() => _record.snapshots().map(_from);

  /// Saves [maxBlocksPerPage] if the saved revision is still
  /// [expectedRevision]; returns what is saved afterwards. Lowering it
  /// changes no page: pages with more blocks keep them.
  Future<WebsiteEditorSettings> update({
    required String requesterRole,
    required String requesterSchoolId,
    required AppUser actor,
    required int maxBlocksPerPage,
    required int expectedRevision,
  }) async {
    _requireAdminOf(requesterRole, requesterSchoolId);
    if (WebsiteEditorSettings.validateMaxBlocks(maxBlocksPerPage) case final error?) throw ArgumentError(error);
    final audit = _record.collection(WebsiteEditorSettings.auditCollection).doc();
    await _db.runTransaction((tx) async {
      final saved = await tx.get(_record);
      final current = _from(saved);
      if (current.revision != expectedRevision) throw WebsiteEditorSettingsConflict(current);
      final revision = current.revision + 1;
      final change = <String, dynamic>{
        'schoolId': schoolId,
        WebsiteEditorSettings.field: {
          'maxBlocksPerPage': maxBlocksPerPage,
          'revision': revision,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedById': actor.id,
          'updatedByName': actor.name ?? '',
        },
      };
      // Only this part of the school's record.
      saved.exists ? tx.update(_record, change) : tx.set(_record, change);
      tx.set(audit, {
        'action': 'website_page_block_limit',
        'maxBlocksPerPage': maxBlocksPerPage,
        'previousMaxBlocksPerPage': current.maxBlocksPerPage,
        'revision': revision,
        'byId': actor.id,
        'byName': actor.name ?? '',
        'at': FieldValue.serverTimestamp(),
      });
    });
    return load();
  }
}
