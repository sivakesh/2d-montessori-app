import 'package:core_contracts/core_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('UserRole', () {
    test('fromClaimValue round-trips every role', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromClaimValue(role.claimValue), role);
      }
    });

    test('fromClaimValue returns null for unknown values', () {
      expect(UserRole.fromClaimValue('owner'), isNull);
      expect(UserRole.fromClaimValue(null), isNull);
    });
  });

  group('AccountStatus', () {
    test('fromClaimValue round-trips every status', () {
      for (final status in AccountStatus.values) {
        expect(AccountStatus.fromClaimValue(status.claimValue), status);
      }
    });

    test('fromClaimValue returns null for unknown values', () {
      expect(AccountStatus.fromClaimValue('pending'), isNull);
    });
  });

  group('RolePermissionMatrix — SRS §3', () {
    test('Editor cannot approve/reject/publish', () {
      expect(
        RolePermissionMatrix.levelFor(
          UserRole.editor,
          Capability.approveRejectPublish,
        ),
        CapabilityLevel.none,
      );
    });

    test('Editor may only suggest scheduling, not schedule directly', () {
      expect(
        RolePermissionMatrix.levelFor(
          UserRole.editor,
          Capability.schedulePublishing,
        ),
        CapabilityLevel.limited,
      );
      expect(
        RolePermissionMatrix.hasFull(
          UserRole.editor,
          Capability.schedulePublishing,
        ),
        isFalse,
      );
    });

    test('Editor content access is limited to assigned/permitted content', () {
      expect(
        RolePermissionMatrix.levelFor(
          UserRole.editor,
          Capability.editAllContent,
        ),
        CapabilityLevel.limited,
      );
    });

    test(
      'Editor media library access is limited to their own uploads; Publisher/Super Admin have full access',
      () {
        expect(
          RolePermissionMatrix.levelFor(
            UserRole.editor,
            Capability.manageMediaLibrary,
          ),
          CapabilityLevel.limited,
        );
        expect(
          RolePermissionMatrix.hasFull(
            UserRole.publisher,
            Capability.manageMediaLibrary,
          ),
          isTrue,
        );
        expect(
          RolePermissionMatrix.hasFull(
            UserRole.superAdmin,
            Capability.manageMediaLibrary,
          ),
          isTrue,
        );
      },
    );

    test('Publisher has full publishing capability but no user management', () {
      expect(
        RolePermissionMatrix.hasFull(
          UserRole.publisher,
          Capability.approveRejectPublish,
        ),
        isTrue,
      );
      expect(
        RolePermissionMatrix.levelFor(
          UserRole.publisher,
          Capability.manageUsersAndRoles,
        ),
        CapabilityLevel.none,
      );
    });

    test(
      'Only Super Admin manages users/roles, exports and deletes enquiries, and manages system settings',
      () {
        for (final capability in [
          Capability.manageUsersAndRoles,
          Capability.deleteEnquiriesPermanently,
          Capability.exportEnquiriesContent,
          Capability.manageBrandSystemSettings,
        ]) {
          expect(
            RolePermissionMatrix.hasAny(UserRole.editor, capability),
            isFalse,
          );
          expect(
            RolePermissionMatrix.hasAny(UserRole.publisher, capability),
            isFalse,
          );
          expect(
            RolePermissionMatrix.hasFull(UserRole.superAdmin, capability),
            isTrue,
          );
        }
      },
    );

    test(
      'Activity log visibility narrows from Editor to Publisher to Super Admin',
      () {
        expect(
          RolePermissionMatrix.levelFor(
            UserRole.editor,
            Capability.viewActivityLog,
          ),
          CapabilityLevel.limited,
        );
        expect(
          RolePermissionMatrix.levelFor(
            UserRole.publisher,
            Capability.viewActivityLog,
          ),
          CapabilityLevel.limited,
        );
        expect(
          RolePermissionMatrix.levelFor(
            UserRole.superAdmin,
            Capability.viewActivityLog,
          ),
          CapabilityLevel.full,
        );
      },
    );

    test('Every role/capability pair is defined (no silent gaps)', () {
      for (final capability in Capability.values) {
        for (final role in UserRole.values) {
          expect(
            () => RolePermissionMatrix.levelFor(role, capability),
            returnsNormally,
            reason: '$role x $capability must resolve to an explicit level',
          );
        }
      }
    });
  });
}
