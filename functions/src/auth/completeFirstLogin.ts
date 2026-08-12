/**
 * SRS AUTH-03: clears `mustChangePassword` once the signed-in user has
 * changed their password client-side (via the Firebase Auth SDK's own
 * `updatePassword`, which requires a recent sign-in). Any authenticated
 * user may call this for *themselves only* — there is no `uid` argument;
 * the target is always `request.auth.uid`.
 *
 * Known limitation: this function trusts that the client actually called
 * `updatePassword` before invoking it — it has no way to independently
 * verify a password change happened. `mustChangePassword` is a UX/policy
 * gate, not an authorization boundary (the role/status claims are checked
 * independently by every other guard), so a client that calls this
 * without changing its password only skips its own forced-change nag
 * screen, gaining no additional privilege. Documented here rather than
 * over-engineered for Phase 1.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { requireAuthenticatedCaller } from './guards';

export const completeFirstLogin = onCall<unknown, Promise<null>>(async (request) => {
  const caller = requireAuthenticatedCaller(request);
  const db = getFirestore();

  const userRef = db.collection('users').doc(caller.uid);
  const snapshot = await userRef.get();
  const current = snapshot.data();
  if (!snapshot.exists || !current) {
    throw new HttpsError('not-found', 'User profile not found.');
  }

  if (current.mustChangePassword !== true) {
    return null; // Idempotent no-op — nothing to clear.
  }

  await userRef.update({
    mustChangePassword: false,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: caller.uid,
  });

  await writeAuditEvent({
    eventType: 'update',
    entityType: 'user',
    entityId: caller.uid,
    actorId: caller.uid,
    actorRole: caller.role ?? 'unknown',
    changeSummary: 'Completed forced password change',
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? caller.uid,
    source: 'function',
  });

  return null;
});
