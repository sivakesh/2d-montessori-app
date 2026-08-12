import 'package:meta/meta.dart';

/// Base type for cross-feature notifications (e.g. "content published")
/// that other features may react to without a direct import, preserving
/// the no-feature-to-feature-dependency rule in PRD §11.1.
@immutable
abstract class DomainEvent {
  const DomainEvent({required this.occurredAt});

  final DateTime occurredAt;
}
