import 'user_role.dart';

/// Every capability row from the SRS §3 role/permission matrix. Content-
/// module capabilities (publishing, media, enquiries, ...) are listed now
/// even though the modules that enforce them at the data level don't exist
/// until later phases, so the matrix stays a single source of truth as
/// those modules get built — see docs/architecture/decisions.md.
enum Capability {
  createEditOwnDrafts,
  editAllContent,
  submitForReview,
  approveRejectPublish,
  schedulePublishing,
  manageRedirectsSeo,
  manageUsersAndRoles,
  deleteEnquiriesPermanently,
  exportEnquiriesContent,
  manageBrandSystemSettings,
  viewActivityLog,
}

/// SRS §3 uses three shades of access for several cells ("Assigned/
/// permitted", "Suggest only", "Limited content fields", "Own/relevant"
/// vs. "Relevant" vs. "All") that a plain boolean would flatten and lose.
/// [full] means unrestricted for that capability; [limited] means the SRS
/// cell names a narrower scope (documented per-capability below) that the
/// owning feature must additionally enforce; [none] means denied.
enum CapabilityLevel { none, limited, full }

/// The SRS §3 matrix, verbatim. [limitedMeaning] documents exactly what
/// the SRS cell says for `limited` entries, since the scope narrowing
/// itself (e.g. "only content assigned to this editor") is enforced by
/// the owning feature/Firestore rules once that module exists — this
/// table only records *which* capabilities are limited and why.
abstract final class RolePermissionMatrix {
  static const Map<Capability, Map<UserRole, CapabilityLevel>> _matrix = {
    Capability.createEditOwnDrafts: {
      UserRole.editor: CapabilityLevel.full,
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.editAllContent: {
      UserRole.editor:
          CapabilityLevel.limited, // Assigned/permitted content only
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.submitForReview: {
      UserRole.editor: CapabilityLevel.full,
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.approveRejectPublish: {
      UserRole.editor: CapabilityLevel.none,
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.schedulePublishing: {
      UserRole.editor:
          CapabilityLevel.limited, // Suggest a date only; cannot schedule
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.manageRedirectsSeo: {
      UserRole.editor: CapabilityLevel.limited, // Limited content fields only
      UserRole.publisher: CapabilityLevel.full,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.manageUsersAndRoles: {
      UserRole.editor: CapabilityLevel.none,
      UserRole.publisher: CapabilityLevel.none,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.deleteEnquiriesPermanently: {
      UserRole.editor: CapabilityLevel.none,
      UserRole.publisher: CapabilityLevel.none,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.exportEnquiriesContent: {
      UserRole.editor: CapabilityLevel.none,
      UserRole.publisher: CapabilityLevel.none,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.manageBrandSystemSettings: {
      UserRole.editor: CapabilityLevel.none,
      UserRole.publisher: CapabilityLevel.none,
      UserRole.superAdmin: CapabilityLevel.full,
    },
    Capability.viewActivityLog: {
      UserRole.editor: CapabilityLevel.limited, // Own/relevant entries only
      UserRole.publisher: CapabilityLevel.limited, // Relevant entries only
      UserRole.superAdmin: CapabilityLevel.full, // All entries
    },
  };

  static CapabilityLevel levelFor(UserRole role, Capability capability) =>
      _matrix[capability]?[role] ?? CapabilityLevel.none;

  /// True if [role] has `limited` or `full` access to [capability] — use
  /// this for "can this role even attempt the action" gates (e.g. show/
  /// hide a menu item); still check [levelFor] before deciding *how much*
  /// of the action to allow.
  static bool hasAny(UserRole role, Capability capability) =>
      levelFor(role, capability) != CapabilityLevel.none;

  static bool hasFull(UserRole role, Capability capability) =>
      levelFor(role, capability) == CapabilityLevel.full;
}
