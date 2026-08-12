/**
 * SRS AUTH-05: Super Admin can suspend/reactivate accounts. Blocked if it
 * would suspend the last active Super Admin — see guards.ts.
 *
 * Suspension effect timing: Firestore/Storage rules re-check `status` via
 * a `get()` on the user's own doc (see firebase/firestore.rules), so
 * suspension takes effect on this user's very next Firestore/Storage
 * request. `auth.updateUser(disabled)` blocks new sign-ins immediately.
 * `revokeRefreshTokens` forces re-authentication on the next token
 * refresh, but — a known Firebase limitation — does not itself invalidate
 * an already-issued ID token already in the client's memory until it
 * expires (up to ~1 hour); the rules-level status check is what closes
 * that gap for Firestore/Storage access specifically.
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
  const snapshot = await userRef.get();
  const current = snapshot.data();
  if (!snapshot.exists || !current) {
    throw new HttpsError('not-found', 'User not found.');
  }

  await assertStatusChangeAllowed(db, { role: current.role, status: current.status }, newStatus);

  await auth.setCustomUserClaims(targetUid, { role: current.role, status: newStatus });
  await auth.updateUser(targetUid, { disabled: newStatus === 'suspended' });
  if (newStatus === 'suspended') {
    await auth.revokeRefreshTokens(targetUid);
  }
  await userRef.update({ status: newStatus, updatedAt: FieldValue.serverTimestamp(), updatedBy: callerUid });

  await writeAuditEvent({
    eventType: 'statusChange',
    entityType: 'user',
    entityId: targetUid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: `Status changed from ${current.status} to ${newStatus}`,
    changedFields: ['status'],
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? targetUid,
    source: 'function',
  });

  return null;
});
