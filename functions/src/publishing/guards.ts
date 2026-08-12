/**
 * Authorization guard for the publishing callables. Reuses
 * `requireAuthenticatedCaller` from ../auth/guards (a plain claims read,
 * not auth-specific logic) rather than duplicating it — Cloud Functions
 * in this repo are one Node package, not separately-isolated Dart
 * packages, so this cross-folder import is not a package-boundary
 * violation the way a feature-to-feature Dart import would be.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

import { requireAuthenticatedCaller } from '../auth/guards';
import { isUserRole, type UserRole } from './capabilities';

export interface ActiveCaller {
  uid: string;
  role: UserRole;
}

/**
 * Every publishing callable's first check: authenticated, holds a valid
 * role claim, and — re-checked live against Firestore, not the cached
 * claim, for the same reason as the auth module's
 * `assertCallerIsActiveSuperAdmin` — currently active. Does not itself
 * check any specific capability; `applyTransition.ts` does that once it
 * knows which transition rule applies.
 */
export async function assertActiveCaller(request: CallableRequest<unknown>, db: Firestore): Promise<ActiveCaller> {
  const caller = requireAuthenticatedCaller(request);
  if (!isUserRole(caller.role)) {
    throw new HttpsError('permission-denied', 'No valid role assigned.');
  }
  const snapshot = await db.collection('users').doc(caller.uid).get();
  if (snapshot.data()?.status !== 'active') {
    throw new HttpsError('permission-denied', 'Your account is not active.');
  }
  return { uid: caller.uid, role: caller.role };
}
