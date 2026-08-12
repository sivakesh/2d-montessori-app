/**
 * Authorization guards shared by every privileged callable in this
 * module. `db` is always passed in explicitly (never read from
 * `admin.firestore()` internally) so these are unit-testable with a
 * hand-written fake Firestore instead of the emulator — see
 * functions/test/auth.guards.test.ts.
 */
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';
import type { Firestore } from 'firebase-admin/firestore';

export interface CallerContext {
  uid: string;
  role: string | undefined;
}

export function requireAuthenticatedCaller(request: CallableRequest<unknown>): CallerContext {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const role = typeof auth.token.role === 'string' ? auth.token.role : undefined;
  return { uid: auth.uid, role };
}

/**
 * The full authorization check for every user-administration callable
 * (createUser, setUserRole, setUserStatus, resetUserPassword): caller
 * must be authenticated, hold the `superAdmin` custom claim, AND be
 * currently active per Firestore. The Firestore re-check exists because
 * custom claims are cached in the ID token for up to ~1 hour — without
 * it, a Super Admin suspended moments ago could keep administering users
 * until their token naturally expires.
 */
export async function assertCallerIsActiveSuperAdmin(request: CallableRequest<unknown>, db: Firestore): Promise<string> {
  const caller = requireAuthenticatedCaller(request);
  if (caller.role !== 'superAdmin') {
    throw new HttpsError('permission-denied', 'Super Admin role required.');
  }
  const snapshot = await db.collection('users').doc(caller.uid).get();
  if (snapshot.data()?.status !== 'active') {
    throw new HttpsError('permission-denied', 'Your account is not active.');
  }
  return caller.uid;
}

export async function countActiveSuperAdmins(db: Firestore): Promise<number> {
  const snapshot = await db.collection('users').where('role', '==', 'superAdmin').where('status', '==', 'active').get();
  return snapshot.size;
}

interface CurrentUserState {
  role: string;
  status: string;
}

const LAST_SUPER_ADMIN_MESSAGE =
  'This is the last active Super Admin — demoting, suspending or deleting this account is blocked.';

/**
 * Blocks a role change that would leave zero active Super Admins. Must be
 * called with the *current* (pre-change) role/status of the target user.
 */
export async function assertRoleChangeAllowed(db: Firestore, current: CurrentUserState, newRole: string): Promise<void> {
  const isDemotingTheOnlyActiveSuperAdmin = current.role === 'superAdmin' && current.status === 'active' && newRole !== 'superAdmin';
  if (!isDemotingTheOnlyActiveSuperAdmin) return;

  const count = await countActiveSuperAdmins(db);
  if (count <= 1) {
    throw new HttpsError('failed-precondition', LAST_SUPER_ADMIN_MESSAGE, { reason: 'last-super-admin' });
  }
}

/**
 * Blocks a status change that would leave zero active Super Admins. Must
 * be called with the *current* (pre-change) role/status of the target user.
 */
export async function assertStatusChangeAllowed(db: Firestore, current: CurrentUserState, newStatus: string): Promise<void> {
  const isSuspendingTheOnlyActiveSuperAdmin =
    current.role === 'superAdmin' && current.status === 'active' && newStatus === 'suspended';
  if (!isSuspendingTheOnlyActiveSuperAdmin) return;

  const count = await countActiveSuperAdmins(db);
  if (count <= 1) {
    throw new HttpsError('failed-precondition', LAST_SUPER_ADMIN_MESSAGE, { reason: 'last-super-admin' });
  }
}
