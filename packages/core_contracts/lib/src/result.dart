import 'package:meta/meta.dart';

/// A domain-level failure. Feature packages define specific subclasses
/// (e.g. `ValidationFailure`, `PermissionDeniedFailure`) rather than
/// leaking Firebase exceptions or stack traces past the data layer.
@immutable
abstract class Failure {
  const Failure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null ? message : '$code: $message';
}

/// Explicit success/failure result type used at every domain and use-case
/// boundary instead of throwing, so presentation code cannot accidentally
/// ignore an error state.
@immutable
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.failure(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isFailure => this is Err<T>;

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onFailure) {
    final self = this;
    if (self is Ok<T>) return onOk(self.value);
    if (self is Err<T>) return onFailure(self.failure);
    throw StateError('Unreachable: Result must be Ok or Err');
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
