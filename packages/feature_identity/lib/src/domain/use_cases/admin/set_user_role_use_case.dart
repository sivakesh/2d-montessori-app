import 'package:core_contracts/core_contracts.dart';

import '../../auth_failures.dart';
import '../../user_admin_repository.dart';

/// See CreateUserUseCase's doc comment re: [actingRole] being a defense-
/// in-depth check, not the security boundary. The server additionally
/// blocks demoting the last active Super Admin — see
/// functions/src/auth/lastSuperAdminGuard.ts — surfaced here as
/// [LastSuperAdminFailure].
class SetUserRoleUseCase {
  const SetUserRoleUseCase(this._repository);

  final UserAdminRepository _repository;

  Future<Result<void>> call({
    required UserRole actingRole,
    required String uid,
    required UserRole role,
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
    return _repository.setUserRole(uid: uid, role: role);
  }
}
