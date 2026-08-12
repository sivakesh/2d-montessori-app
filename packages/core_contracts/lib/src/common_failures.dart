import 'result.dart';

/// Generic failures useful across every feature, not specific to any one
/// domain (contrast with e.g. feature_identity's `AuthFailure` subtypes,
/// which stay local to that feature). Moved here from feature_identity at
/// the Phase 1 — CMS Core milestone once feature_publishing needed the
/// same two shapes and re-declaring them per feature would have meant
/// permission/validation failures compared unequal (`is`) across features
/// that each defined their own.
final class PermissionFailure extends Failure {
  const PermissionFailure([
    super.message = 'You do not have permission to perform this action.',
  ]) : super(code: 'permission-denied');
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message) : super(code: 'validation');
}
