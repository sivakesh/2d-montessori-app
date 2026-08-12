import 'package:meta/meta.dart';

/// A typed wrapper around a Firestore document ID. Prevents passing a
/// program ID where an experience ID is expected, since every collection
/// in the Firestore Logical Model uses immutable document IDs (see SRS
/// §10.1 and PRD §5).
@immutable
class EntityId<T> {
  const EntityId(this.value)
    : assert(value != '', 'EntityId must not be empty');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is EntityId<T> && other.value == value;

  @override
  int get hashCode => Object.hash(T, value);

  @override
  String toString() => value;
}
