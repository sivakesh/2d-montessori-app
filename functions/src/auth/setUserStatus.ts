/**
 * SRS AUTH-05: Super Admin can suspend/reactivate accounts. Blocked if it
 * would suspend the last active Super Admin — see guards.ts. The
 * Firestore read (current role/status), the last-Super-Admin check and
 * the Firestore write all happen inside one transaction so two concurrent
 * requests suspending different Super Admins can never both succeed when
 * only one active Super Admin would remain — see
 * docs/architecture/decisions.md "Concurrency: last-active-Super-Admin
 * guard".
 *
 * Suspension effect timing: Firestore/Storage rules re-check `status` via
 * a `get()` on the user's own doc for any cross-user access (see
 * firebase/firestore.rules), so suspension takes effect on this user's
 * very next Firestore/Storage request. `auth.updateUser(disabled)` blocks
 * new sign-ins immediately. `revokeRefreshTokens` forces re-authentication
 * on the next token refresh, but — a known Firebase limitation — does not
 * itself invalidate an already-issued ID token already in the client's
 * memory until it expires (up to ~1 hour); the rules-level status check
 * is what closes that gap for Firestore/Storage access specifically.
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { assertCallerIsActiveSuperAdmin, assertStatusChangeAllowed } from './guards';
import { validateStatus, validateUid } from './validators';

interface SetUserStatusRequestData {
  uid?: unknown;
  status?: unknown;
}

export const setUserStatus = onCall<SetUserStatusRequestData, Promise<null>>(async (request) => {
  const db = getFirestore();
  const auth = getAuth();
  const callerUid = await assertCallerIsActiveSuperAdmin(request, db);

  const targetUid = validateUid(request.data.uid);
  const newStatus = validateStatus(request.data.status);
  const userRef = db.collection('users').doc(targetUid);

  const { previousStatus, role } = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'User not found.');
    }

    await assertStatusChangeAllowed(transaction, db, { role: current.role, status: current.status }, newStatus);

    transaction.update(userRef, { status: newStatus, updatedAt: FieldValue.serverTimestamp(), updatedBy: callerUid });
    return { previousStatus: current.status as string, role: current.role as string };
  });

  // Auth Admin SDK calls can't participate in a Firestore transaction —
  // these only run once the Firestore write above has committed, so a
  // blocked (last-Super-Admin) attempt never reaches here.
  await auth.setCustomUserClaims(targetUid, { role, status: newStatus });
  await auth.updateUser(targetUid, { disabled: newStatus === 'suspended' });
  if (newStatus === 'suspended') {
    await auth.revokeRefreshTokens(targetUid);
  }

  await writeAuditEvent({
    eventType: 'statusChange',
    entityType: 'user',
    entityId: targetUid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: `Status changed from ${previousStatus} to ${newStatus}`,
    changedFields: ['status'],
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? targetUid,
    source: 'function',
  });

  return null;
});
