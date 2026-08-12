import 'package:core_contracts/core_contracts.dart';

import '../../auth_failures.dart';
import '../../user_admin_repository.dart';

/// SRS AUTH-05: "reset access with a temporary password". See
/// CreateUserUseCase's doc comment re: [actingRole] being a defense-in-
/// depth check, not the security boundary.
class ResetUserPasswordUseCase {
  const ResetUserPasswordUseCase(this._repository);

  final UserAdminRepository _repository;

  Future<Result<ResetPasswordResult>> call({
    required UserRole actingRole,
    required String uid,
  }) async {
    if (!RolePermissionMatrix.hasFull(
      actingRole,
      Capability.manageUsersAndRoles,
    )) {
      return const Result.failure(PermissionFailure());
    }
    if (uid.trim().isEmpty) {
      return const Result.failure(ValidationFailure('Missing target user.'));
    }
    return _repository.resetUserPassword(uid);
  }
}
