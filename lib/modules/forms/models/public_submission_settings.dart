import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a school's public website accepts form submissions: an
/// administrator's switch (Settings → Public form submissions), OFF until
/// one turns it on.
///
/// Stored in two places, always written together in one transaction
/// (`PublicSubmissionSettingsService`):
/// - [PublicSubmissionSettings.field] of `school_settings/{schoolId}`: the
///   school's own settings record, with who changed it last (admins only);
/// - `website_public_settings/{schoolId}` ([PublicSubmissionStatus]): what
///   visitors' browsers and the submission check read, with no
///   administrator details (visitors can't read `school_settings`).
///
/// The switch is not a security boundary by itself: a submission also
/// needs a submission path (`FormSubmissionGateway`), and the service and
/// the rules check the setting again.
class PublicSubmissionSettings {
  const PublicSubmissionSettings({
    required this.schoolId,
    required this.enabled,
    this.closedMessage = '',
    this.revision = 0,
    this.updatedAt,
    this.updatedById,
    this.updatedByName,
  });

  /// No saved setting (or one that can't be read): closed.
  const PublicSubmissionSettings.closed(this.schoolId)
      : enabled = false,
        closedMessage = '',
        revision = 0,
        updatedAt = null,
        updatedById = null,
        updatedByName = null;

  static const schoolSettingsCollection = 'school_settings';
  static const field = 'publicFormSubmissions';
  static const publicCollection = 'website_public_settings';
  static const auditCollection = 'audit';
  static const maxClosedMessage = 300;

  final String schoolId;
  final bool enabled;

  /// Shown to visitors while submissions are closed; blank: the website's
  /// own wording.
  final String closedMessage;

  /// Counts saved changes: a change made from an older revision is refused
  /// (two administrators at once).
  final int revision;
  final DateTime? updatedAt;
  final String? updatedById;
  final String? updatedByName;

  /// [map] is the [field] map of `school_settings/{schoolId}`. Anything
  /// but `enabled: true` is closed.
  factory PublicSubmissionSettings.fromMap(String schoolId, Object? map) {
    if (map is! Map) return PublicSubmissionSettings.closed(schoolId);
    final at = map['updatedAt'];
    final revision = map['revision'];
    return PublicSubmissionSettings(
      schoolId: schoolId,
      enabled: map['enabled'] == true,
      closedMessage: map['closedMessage'] is String ? (map['closedMessage'] as String).trim() : '',
      revision: revision is int && revision >= 0 ? revision : 0,
      updatedAt: at is Timestamp ? at.toDate() : (at is DateTime ? at : null),
      updatedById: map['updatedById']?.toString(),
      updatedByName: map['updatedByName']?.toString(),
    );
  }

  /// Null when [message] can be saved.
  static String? validateClosedMessage(String message) =>
      message.trim().length > maxClosedMessage ? 'Keep the message to $maxClosedMessage characters or fewer.' : null;
}

/// What visitors' browsers read: `website_public_settings/{schoolId}`.
class PublicSubmissionStatus {
  const PublicSubmissionStatus({required this.schoolId, required this.open, this.closedMessage = '', this.revision = 0});

  const PublicSubmissionStatus.closed(this.schoolId)
      : open = false,
        closedMessage = '',
        revision = 0;

  final String schoolId;
  final bool open;
  final String closedMessage;
  final int revision;

  /// Open only when [data] is this school's and says so.
  factory PublicSubmissionStatus.fromMap(String schoolId, Map<String, dynamic>? data) {
    if (data == null || data['schoolId'] != schoolId) return PublicSubmissionStatus.closed(schoolId);
    final revision = data['revision'];
    return PublicSubmissionStatus(
      schoolId: schoolId,
      open: data['submissionsOpen'] == true,
      closedMessage: data['closedMessage'] is String ? (data['closedMessage'] as String).trim() : '',
      revision: revision is int ? revision : 0,
    );
  }
}
