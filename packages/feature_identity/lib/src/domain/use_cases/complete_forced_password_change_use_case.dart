import 'package:core_contracts/core_contracts.dart';

import '../auth_failures.dart';
import '../auth_repository.dart';
import '../password_policy.dart';

/// The SRS AUTH-03 first-login flow: change the temporary password, then
/// clear `mustChangePassword` via the trusted `completeFirstLogin`
/// callable. If the password change succeeds but clearing the flag fails
/// (e.g. a transient network error), the password *is* already changed —
/// the returned failure reflects only the second step, and the caller
/// should let the user retry rather than re-prompt for a new password.
class CompleteForcedPasswordChangeUseCase {
  const CompleteForcedPasswordChangeUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call(String newPassword) async {
    final violations = PasswordPolicy.validate(newPassword);
    if (violations.isNotEmpty) {
      return Result.failure(WeakPasswordFailure(violations));
    }

    final changeResult = await _repository.changeOwnPassword(newPassword);
    if (changeResult.isFailure) return changeResult;

    return _repository.completeFirstLogin();
  }
}
