import 'package:cloud_firestore/cloud_firestore.dart';

/// The app has no multi-tenant `schoolId` concept anywhere yet (no other
/// model/service in the codebase carries one) — this deployment serves
/// exactly one school. Rather than inventing a broader multi-tenancy
/// migration (out of scope for School Settings), this is the single default
/// id that scopes this feature's own document. Every [SchoolSettingsService]
/// call still takes an explicit `schoolId` rather than hardcoding this
/// constant internally, so the Firestore document path is always
/// `school_settings/{schoolId}` and never a bare/global path — the
/// isolation boundary this feature is built on is already correct for
/// whenever real multi-tenancy is added, without this feature's shape
/// needing to change.
const String kDefaultSchoolId = 'default_school';

/// Thrown when a non-admin role attempts to read or write School Settings
/// via [SchoolSettingsService] — enforced at the service layer itself (not
/// only by which screens a role's navigation exposes), the same shape as
/// [UnauthorizedStudentLeaveException] in the Leave module.
class UnauthorizedSchoolSettingsException implements Exception {
  UnauthorizedSchoolSettingsException(this.role);
  final String role;

  @override
  String toString() =>
      'You are not authorized to view or modify School Settings.';
}

/// School Settings — one document per `schoolId` in the `school_settings`
/// collection. All fields besides [name] are optional, matching the SETTINGS-01
/// spec exactly (School Name required; Logo/Address/Phone/Email/Website/
/// Description optional).
class SchoolSettingsModel {
  const SchoolSettingsModel({
    required this.schoolId,
    required this.name,
    required this.logoUrl,
    required this.address,
    required this.phone,
    required this.email,
    required this.website,
    required this.description,
    required this.updatedAt,
    required this.updatedBy,
    required this.updatedByName,
  });

  final String schoolId;
  final String name;
  final String logoUrl;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String description;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedByName;

  factory SchoolSettingsModel.empty(String schoolId) => SchoolSettingsModel(
        schoolId: schoolId,
        name: '',
        logoUrl: '',
        address: '',
        phone: '',
        email: '',
        website: '',
        description: '',
        updatedAt: null,
        updatedBy: null,
        updatedByName: null,
      );

  factory SchoolSettingsModel.fromMap(String schoolId, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return SchoolSettingsModel(
      schoolId: schoolId,
      name: map['name']?.toString() ?? '',
      logoUrl: map['logoUrl']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      website: map['website']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      updatedAt: parseDate(map['updatedAt']),
      updatedBy: map['updatedBy']?.toString(),
      updatedByName: map['updatedByName']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'name': name,
        'logoUrl': logoUrl,
        'address': address,
        'phone': phone,
        'email': email,
        'website': website,
        'description': description,
      };
}

/// Field-level validation for the School Settings form — the single source
/// of truth for both the form's own [TextFormField.validator]s (immediate
/// feedback) and [SchoolSettingsService.saveSettings]'s own re-check (so a
/// direct service call can never persist an invalid record even if a UI
/// slip skipped its own validation). Phone is deliberately never validated
/// here — SETTINGS-01 requires "normal school phone formats" (extensions,
/// country codes, spaces/dashes) to keep working, so no format is imposed.
class SchoolSettingsValidation {
  const SchoolSettingsValidation._();

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  // Optional scheme, at least one dot-separated host label, optional path —
  // permissive enough for "example.com", "www.example.com" and
  // "https://example.com/about" alike, while still rejecting obvious
  // non-URLs like "not a website".
  static final RegExp _websitePattern = RegExp(
    r'^(https?:\/\/)?([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(\/[^\s]*)?$',
  );

  /// Null when valid. School Name is the one required field. Accepts a
  /// nullable [value] so it can be used directly as a
  /// [FormFieldValidator]&lt;String&gt; without an adapter.
  static String? validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return 'School Name is required.';
    return null;
  }

  /// Null when valid or blank (optional field).
  static String? validateEmail(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  /// Null when valid or blank (optional field).
  static String? validateWebsite(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    if (!_websitePattern.hasMatch(trimmed)) return 'Enter a valid website URL.';
    return null;
  }
}
