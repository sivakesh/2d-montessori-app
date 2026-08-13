/// Controlled page type/template (SRS WEB-03 "structured sections... and
/// publishing workflow"; PRD §3 route table distinguishes system pages
/// like `/` and `/404` from CMS-managed pages). Only the two types a
/// Super Admin/Publisher can actually *create through the CMS* are
/// modeled here — `home` and other system routes are fixed, code-owned
/// shells outside this milestone's scope, not administrator-authorable
/// [PageType] values.
enum PageType {
  /// A standalone editorial page (e.g. About, Montessori Way) — SRS
  /// WEB-03's "core editorial pages".
  standard('standard'),

  /// A page intended to introduce/anchor a future collection listing
  /// (Programs, Experiences, ...). Reserved for forward compatibility
  /// with those not-yet-built modules; behaves identically to
  /// [standard] in this milestone.
  collectionLanding('collectionLanding');

  const PageType(this.storageValue);

  final String storageValue;

  static PageType? fromStorageValue(String? value) {
    for (final type in PageType.values) {
      if (type.storageValue == value) return type;
    }
    return null;
  }
}
