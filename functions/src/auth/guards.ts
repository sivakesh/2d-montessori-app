/**
 * Authorization guards shared by every privileged callable in this
 * module. `db` is always passed in explicitly (never read from
 * `admin.firestore()` internally) so these are unit-testable with a
 * hand-written fake Firestore/Transaction instead of the emulator — see
 * functions/test/auth.guards.test.ts.
 */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

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
 * until their token naturally expires. This is a single-document read
 * (the caller's own doc), not a check-then-act sequence, so it does not
 * need transactional protection the way the last-Super-Admin guards below
 * do.
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

interface CurrentUserState {
  role: string;
  status: string;
}

const LAST_SUPER_ADMIN_MESSAGE =
  'This is the last active Super Admin — demoting, suspending or deleting this account is blocked.';

/**
 * Reads the active-Super-Admin count as part of [transaction], not as a
 * standalone query. Firestore transactions track queries read this way as
 * part of the transaction's read set: if any write that could change this
 * query's result set commits before this transaction does, Firestore
 * aborts and retries this transaction automatically. That is exactly the
 * guarantee the last-Super-Admin guards below need — see
 * docs/architecture/decisions.md "Concurrency: last-active-Super-Admin
 * guard" for the race this closes and why the previous, non-transactional
 * version of this check was vulnerable to it.
 */
async function countActiveSuperAdminsInTransaction(transaction: Transaction, db: Firestore): Promise<number> {
  const query = db.collection('users').where('role', '==', 'superAdmin').where('status', '==', 'active');
  const snapshot = await transaction.get(query);
  return snapshot.size;
}

/**
 * Blocks a role change that would leave zero active Super Admins. Must be
 * called from within the same Firestore transaction that performs the
 * eventual write, with the *current* (pre-change) role/status of the
 * target user as read inside that same transaction.
 */
export async function assertRoleChangeAllowed(
  transaction: Transaction,
  db: Firestore,
  current: CurrentUserState,
  newRole: string,
): Promise<void> {
  const isDemotingTheOnlyActiveSuperAdmin =
    current.role === 'superAdmin' && current.status === 'active' && newRole !== 'superAdmin';
  if (!isDemotingTheOnlyActiveSuperAdmin) return;

  const count = await countActiveSuperAdminsInTransaction(transaction, db);
  if (count <= 1) {
    throw new HttpsError('failed-precondition', LAST_SUPER_ADMIN_MESSAGE, { reason: 'last-super-admin' });
  }
}

/**
 * Blocks a status change that would leave zero active Super Admins. Must
 * be called from within the same Firestore transaction that performs the
 * eventual write, with the *current* (pre-change) role/status of the
 * target user as read inside that same transaction.
 */
export async function assertStatusChangeAllowed(
  transaction: Transaction,
  db: Firestore,
  current: CurrentUserState,
  newStatus: string,
): Promise<void> {
  const isSuspendingTheOnlyActiveSuperAdmin =
    current.role === 'superAdmin' && current.status === 'active' && newStatus === 'suspended';
  if (!isSuspendingTheOnlyActiveSuperAdmin) return;

  const count = await countActiveSuperAdminsInTransaction(transaction, db);
  if (count <= 1) {
    throw new HttpsError('failed-precondition', LAST_SUPER_ADMIN_MESSAGE, { reason: 'last-super-admin' });
  }
}
