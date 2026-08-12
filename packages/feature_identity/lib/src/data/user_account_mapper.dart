import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/user_account.dart';

/// Maps between the `users/{uid}` Firestore document shape (SRS §10.1
/// "users / roles") and the domain [UserAccount]. The document is the
/// authoritative store for profile fields and `mustChangePassword`; role
/// and status are mirrored here from custom claims by the Cloud Functions
/// that set them (see functions/src/auth), never written by the client.
abstract final class UserAccountMapper {
  static UserAccount fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('users/${snapshot.id} has no data');
    }
    return UserAccount(
      uid: snapshot.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      role: UserRole.fromClaimValue(data['role'] as String?) ?? UserRole.editor,
      status:
          AccountStatus.fromClaimValue(data['status'] as String?) ??
          AccountStatus.suspended,
      mustChangePassword: data['mustChangePassword'] as bool? ?? true,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: data['createdBy'] as String? ?? '',
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedBy: data['updatedBy'] as String? ?? '',
    );
  }
}
