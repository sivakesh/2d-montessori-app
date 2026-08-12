import 'package:core_contracts/core_contracts.dart';

import '../auth_failures.dart';
import '../auth_repository.dart';

class SendPasswordResetUseCase {
  const SendPasswordResetUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return const Result.failure(
        ValidationFailure('Enter a valid email address.'),
      );
    }
    return _repository.sendPasswordResetEmail(trimmedEmail);
  }
}
