import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../auth/models/app_user.dart';
import '../../../forms/models/public_submission_settings.dart';
import '../models/school_settings_model.dart';

/// Another administrator saved a change first: [current] is what is saved
/// now. Nothing was written.
class PublicSubmissionSettingsConflict implements Exception {
  PublicSubmissionSettingsConflict(this.current);

  final PublicSubmissionSettings current;

  @override
  String toString() => 'Another administrator changed this setting. Review it and try again.';
}

/// Reads and changes a school's [PublicSubmissionSettings], the part of
/// its School Settings record (`school_settings/{schoolId}`) that decides
/// whether its public website accepts form submissions.
///
/// - Admins only, and only their own school's: every method takes the
///   requester's role and school and refuses ([UnauthorizedSchoolSettingsException])
///   anything else. The app serves one school today ([kDefaultSchoolId]),
///   so the requester's school is that one.
/// - A change is one transaction: the settings record, the visitor copy
///   (`website_public_settings/{schoolId}`) and an audit entry
///   (`school_settings/{schoolId}/audit`), or nothing. It is refused when
///   the record changed since it was read ([PublicSubmissionSettingsConflict]).
/// - No saved setting is OFF.
class PublicSubmissionSettingsService {
  PublicSubmissionSettingsService({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _record(String schoolId) =>
      _db.collection(PublicSubmissionSettings.schoolSettingsCollection).doc(schoolId);

  void _requireAdminOf(String schoolId, String requesterRole, String requesterSchoolId) {
    if (requesterRole.toLowerCase() != 'admin' || requesterSchoolId != schoolId || schoolId.isEmpty) {
      throw UnauthorizedSchoolSettingsException(requesterRole);
    }
  }

  Future<PublicSubmissionSettings> load({required String schoolId, required String requesterRole, required String requesterSchoolId}) async {
    _requireAdminOf(schoolId, requesterRole, requesterSchoolId);
    final doc = await _record(schoolId).get();
    return PublicSubmissionSettings.fromMap(schoolId, doc.data()?[PublicSubmissionSettings.field]);
  }

  /// Saves [enabled] and [closedMessage], if the saved revision is still
  /// [expectedRevision]; returns what is saved afterwards.
  Future<PublicSubmissionSettings> update({
    required String schoolId,
    required String requesterRole,
    required String requesterSchoolId,
    required AppUser actor,
    required bool enabled,
    required String closedMessage,
    required int expectedRevision,
  }) async {
    _requireAdminOf(schoolId, requesterRole, requesterSchoolId);
    final messageError = PublicSubmissionSettings.validateClosedMessage(closedMessage);
    if (messageError != null) throw ArgumentError(messageError);
    final message = closedMessage.trim();

    final record = _record(schoolId);
    final visitorCopy = _db.collection(PublicSubmissionSettings.publicCollection).doc(schoolId);
    final audit = record.collection(PublicSubmissionSettings.auditCollection).doc();
    await _db.runTransaction((tx) async {
      final saved = await tx.get(record);
      final current = PublicSubmissionSettings.fromMap(schoolId, saved.data()?[PublicSubmissionSettings.field]);
      if (current.revision != expectedRevision) throw PublicSubmissionSettingsConflict(current);
      final revision = current.revision + 1;
      final change = <String, dynamic>{
        'schoolId': schoolId,
        PublicSubmissionSettings.field: {
          'enabled': enabled,
          'closedMessage': message,
          'revision': revision,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedById': actor.id,
          'updatedByName': actor.name ?? '',
        },
      };
      // Only this part of the school's record: its name, contact details
      // and logo are kept.
      saved.exists ? tx.update(record, change) : tx.set(record, change);
      tx.set(visitorCopy, {
        'schoolId': schoolId,
        'submissionsOpen': enabled,
        'closedMessage': message,
        'revision': revision,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(audit, {
        'action': 'public_form_submissions',
        'enabled': enabled,
        'previousEnabled': current.enabled,
        'closedMessageChanged': message != current.closedMessage,
        'revision': revision,
        'byId': actor.id,
        'byName': actor.name ?? '',
        'at': FieldValue.serverTimestamp(),
      });
    });
    return load(schoolId: schoolId, requesterRole: requesterRole, requesterSchoolId: requesterSchoolId);
  }
}
