import 'package:core_contracts/core_contracts.dart';

import '../../auth_failures.dart';
import '../../user_admin_repository.dart';

/// SRS AUTH-01: only the Super Admin creates accounts. [actingRole] is a
/// client-side, defense-in-depth check only — the callable Cloud Function
/// behind [UserAdminRepository.createUser] re-verifies the caller's role
/// and active status from the server-trusted ID token before doing
/// anything (see functions/src/auth/guards.ts). A UI that is only ever
/// reachable by a Super Admin (see feature_identity presentation's
/// AuthGate) makes this check redundant in practice, but it costs nothing
/// and fails closed if that ever changes.
class CreateUserUseCase {
  const CreateUserUseCase(this._repository);

  final UserAdminRepository _repository;

  Future<Result<CreateUserResult>> call({
    required UserRole actingRole,
    required String email,
    required String displayName,
    required UserRole role,
  }) async {
    if (!RolePermissionMatrix.hasFull(
      actingRole,
      Capability.manageUsersAndRoles,
    )) {
      return const Result.failure(PermissionFailure());
    }

    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return const Result.failure(
        ValidationFailure('Enter a valid email address.'),
      );
    }
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return const Result.failure(
        ValidationFailure('Enter a name for this user.'),
      );
    }

    return _repository.createUser(
      email: trimmedEmail,
      displayName: trimmedName,
      role: role,
    );
  }
}
