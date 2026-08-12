import 'package:core_contracts/core_contracts.dart';

import '../auth_failures.dart';
import '../auth_repository.dart';
import '../password_policy.dart';

class ConfirmPasswordResetUseCase {
  const ConfirmPasswordResetUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call({
    required String oobCode,
    required String newPassword,
  }) async {
    if (oobCode.trim().isEmpty) {
      return const Result.failure(InvalidResetCodeFailure());
    }
    final violations = PasswordPolicy.validate(newPassword);
    if (violations.isNotEmpty) {
      return Result.failure(WeakPasswordFailure(violations));
    }
    return _repository.confirmPasswordReset(
      oobCode: oobCode,
      newPassword: newPassword,
    );
  }
}
