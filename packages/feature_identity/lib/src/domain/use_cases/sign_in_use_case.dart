import 'package:core_contracts/core_contracts.dart';

import '../auth_repository.dart';

class SignInUseCase {
  const SignInUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return const Result.failure(
        ValidationFailure('Enter a valid email address.'),
      );
    }
    if (password.isEmpty) {
      return const Result.failure(ValidationFailure('Enter your password.'));
    }
    return _repository.signInWithEmailAndPassword(
      email: trimmedEmail,
      password: password,
    );
  }
}
