import 'package:meta/meta.dart';

/// PRD §5.3 CTA/link object — reused by every section type that can carry
/// a call to action (SRS's "Call-to-action section" and the CTA fields
/// several other approved sections carry).
enum CallToActionLinkType {
  internal('internal'),
  external('external'),
  phone('phone'),
  email('email'),
  anchor('anchor');

  const CallToActionLinkType(this.storageValue);

  final String storageValue;

  static CallToActionLinkType fromStorageValue(String? value) =>
      CallToActionLinkType.values.firstWhere(
        (v) => v.storageValue == value,
        orElse: () => CallToActionLinkType.internal,
      );
}

@immutable
class CallToAction {
  const CallToAction({
    required this.label,
    required this.linkType,
    required this.target,
    this.openInNewTab = false,
  });

  final String label;
  final CallToActionLinkType linkType;

  /// A validated internal route, an `https://` URL, a `tel:` URI, a
  /// `mailto:` URI, or an in-page anchor id, depending on [linkType].
  /// Format is validated server-side per [linkType]; this type carries
  /// whichever raw string was validated, not a parsed URI, so it can
  /// round-trip through Firestore without a custom codec.
  final String target;

  /// SRS/PRD: only meaningful (and only allowed) for external links.
  final bool openInNewTab;

  Map<String, Object?> toMap() => {
    'label': label,
    'linkType': linkType.storageValue,
    'target': target,
    'openInNewTab': openInNewTab,
  };

  factory CallToAction.fromMap(Map<String, Object?> map) => CallToAction(
    label: map['label'] as String? ?? '',
    linkType: CallToActionLinkType.fromStorageValue(map['linkType'] as String?),
    target: map['target'] as String? ?? '',
    openInNewTab: map['openInNewTab'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is CallToAction &&
      other.label == label &&
      other.linkType == linkType &&
      other.target == target &&
      other.openInNewTab == openInNewTab;

  @override
  int get hashCode => Object.hash(label, linkType, target, openInNewTab);
}
