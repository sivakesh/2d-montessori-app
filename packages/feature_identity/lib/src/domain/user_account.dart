import 'package:core_contracts/core_contracts.dart';
import 'package:meta/meta.dart';

/// A CMS user profile as shown in the admin User Management screen (SRS
/// AUTH-01/AUTH-05). Role and status here are the Firestore mirror of the
/// authoritative custom claims — see docs/architecture/decisions.md
/// "Identity data model" for why both exist.
@immutable
class UserAccount {
  const UserAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.role,
    required this.status,
    required this.mustChangePassword,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final AccountStatus status;
  final bool mustChangePassword;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;

  bool get isActive => status == AccountStatus.active;
}
