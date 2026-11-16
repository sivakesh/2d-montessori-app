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
    this.gstin = '',
    this.addressLine2 = '',
    this.locality = '',
    this.city = '',
    this.state = '',
    this.pinCode = '',
  });

  final String schoolId;
  final String name;
  final String logoUrl;

  /// Address Line 1 (the original single address field, `address`, kept
  /// as it is: no second copy of the address).
  final String address;

  /// The rest of the postal address (each optional, '' when not set).
  final String addressLine2;
  final String locality;
  final String city;
  final String state;
  final String pinCode;

  /// The postal address as printed: Line 1 (its own lines), Line 2, then
  /// "Area, City, State – PIN", leaving out whatever isn't set.
  List<String> get postalAddressLines {
    final place = [locality, city, state].map((v) => v.trim()).where((v) => v.isNotEmpty).join(', ');
    final pin = pinCode.trim();
    return [
      ...address.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty),
      if (addressLine2.trim().isNotEmpty) addressLine2.trim(),
      if (place.isNotEmpty || pin.isNotEmpty) [place, pin].where((v) => v.isNotEmpty).join(' - '),
    ];
  }

  final String phone;
  final String email;
  final String website;
  final String description;

  /// The school's GSTIN ('' when none is configured), normalised
  /// ([SchoolSettingsValidation.normalizeGstin]). Shown only on a
  /// regenerated fee receipt the administrator explicitly opts in to; never
  /// a tax calculation.
  final String gstin;
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
      gstin: SchoolSettingsValidation.normalizeGstin(map['gstin']?.toString()),
      addressLine2: map['addressLine2']?.toString() ?? '',
      locality: map['locality']?.toString() ?? '',
      city: map['city']?.toString() ?? '',
      state: map['state']?.toString() ?? '',
      pinCode: map['pinCode']?.toString() ?? '',
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
        if (gstin.isNotEmpty) 'gstin': gstin,
        if (addressLine2.isNotEmpty) 'addressLine2': addressLine2,
        if (locality.isNotEmpty) 'locality': locality,
        if (city.isNotEmpty) 'city': city,
        if (state.isNotEmpty) 'state': state,
        if (pinCode.isNotEmpty) 'pinCode': pinCode,
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

  // GSTIN: 2-digit state code, the 10-character PAN, the entity number
  // (1-9, A-Z), 'Z', then a check character.
  static final RegExp _gstinPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
  static const _gstinChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// [value] trimmed, without spaces, in capitals ('' for null).
  static String normalizeGstin(String? value) => (value ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// Null when valid or blank (optional field): 15 characters in the GSTIN
  /// format whose last character is its check character (the GSTN
  /// base-36 checksum), so a mistyped character is caught.
  static String? validateGstin(String? value) {
    final g = normalizeGstin(value);
    if (g.isEmpty) return null;
    if (g.length != 15 || !_gstinPattern.hasMatch(g)) {
      return 'Enter a valid 15-character GSTIN.';
    }
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final product = _gstinChars.indexOf(g[i]) * (i.isEven ? 1 : 2);
      sum += product ~/ 36 + product % 36;
    }
    final check = _gstinChars[(36 - sum % 36) % 36];
    if (g[14] != check) return 'This GSTIN\'s check character does not match. Please check it for typing mistakes.';
    return null;
  }

  static final RegExp _pinPattern = RegExp(r'^[1-9][0-9]{5}$');

  /// Null when valid or blank (optional field): an Indian 6-digit PIN code.
  static String? validatePinCode(String? value) {
    final trimmed = (value ?? '').replaceAll(' ', '');
    if (trimmed.isEmpty) return null;
    if (!_pinPattern.hasMatch(trimmed)) return 'Enter a valid 6-digit PIN code.';
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
