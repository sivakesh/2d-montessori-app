/**
 * SRS §3's Media Library capability slice (`manageMediaLibrary` in
 * `core_contracts`' `Capability` enum — not an original SRS §3 row; the
 * matrix predates feature_media, see
 * docs/architecture/decisions.md). Editor: limited to their own uploads
 * (`ownerId == caller.uid`); Publisher/Super Admin: the whole library,
 * including any editor's uploads. Kept as its own narrow module, the
 * same pattern `pages/permissions.ts` established for `editAllContent` —
 * this is a distinct action from editing page content, not a reuse of
 * that capability.
 */
import type { UserRole } from '../publishing/capabilities';

const MANAGE_ALL_MEDIA_ROLES: readonly UserRole[] = ['publisher', 'superAdmin'];

export function canManageAllMedia(role: UserRole): boolean {
  return MANAGE_ALL_MEDIA_ROLES.includes(role);
}

/** True if `role` may modify (edit metadata / archive / restore / delete) an asset uploaded by `ownerUid`. */
export function canManageMediaAsset(role: UserRole, callerUid: string, ownerUid: string): boolean {
  return canManageAllMedia(role) || callerUid === ownerUid;
}
