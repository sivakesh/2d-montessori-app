import 'package:core_contracts/core_contracts.dart';

import '../../auth_failures.dart';
import '../../user_admin_repository.dart';

/// SRS AUTH-05: suspend/reactivate accounts. The server additionally
/// blocks suspending the last active Super Admin — see
/// functions/src/auth/lastSuperAdminGuard.ts — surfaced here as
/// [LastSuperAdminFailure]. See CreateUserUseCase's doc comment re:
/// [actingRole] being a defense-in-depth check, not the security boundary.
class SetUserStatusUseCase {
  const SetUserStatusUseCase(this._repository);

  final UserAdminRepository _repository;

  Future<Result<void>> call({
    required UserRole actingRole,
    required String uid,
    required AccountStatus status,
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
    return _repository.setUserStatus(uid: uid, status: status);
  }
}
