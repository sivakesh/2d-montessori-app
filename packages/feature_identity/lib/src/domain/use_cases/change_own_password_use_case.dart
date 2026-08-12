import 'package:core_contracts/core_contracts.dart';

import '../auth_failures.dart';
import '../auth_repository.dart';
import '../password_policy.dart';

/// Voluntary password change (e.g. from a future My Profile screen).
/// Does not touch `mustChangePassword` — use
/// [CompleteForcedPasswordChangeUseCase] for the first-login flow.
class ChangeOwnPasswordUseCase {
  const ChangeOwnPasswordUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call(String newPassword) async {
    final violations = PasswordPolicy.validate(newPassword);
    if (violations.isNotEmpty) {
      return Result.failure(WeakPasswordFailure(violations));
    }
    return _repository.changeOwnPassword(newPassword);
  }
}
