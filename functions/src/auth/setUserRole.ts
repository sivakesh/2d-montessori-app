/**
 * SRS AUTH-05: Super Admin can change a user's role. Blocked if it would
 * demote the last active Super Admin — see guards.ts. The Firestore read
 * (current role/status), the last-Super-Admin check and the Firestore
 * write all happen inside one transaction so two concurrent requests
 * demoting different Super Admins can never both succeed when only one
 * active Super Admin would remain — see
 * docs/architecture/decisions.md "Concurrency: last-active-Super-Admin
 * guard".
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { assertCallerIsActiveSuperAdmin, assertRoleChangeAllowed } from './guards';
import { validateRole, validateUid } from './validators';

interface SetUserRoleRequestData {
  uid?: unknown;
  role?: unknown;
}

export const setUserRole = onCall<SetUserRoleRequestData, Promise<null>>(async (request) => {
  const db = getFirestore();
  const auth = getAuth();
  const callerUid = await assertCallerIsActiveSuperAdmin(request, db);

  const targetUid = validateUid(request.data.uid);
  const newRole = validateRole(request.data.role);
  const userRef = db.collection('users').doc(targetUid);

  const { previousRole, status } = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'User not found.');
    }

    await assertRoleChangeAllowed(transaction, db, { role: current.role, status: current.status }, newRole);

    transaction.update(userRef, { role: newRole, updatedAt: FieldValue.serverTimestamp(), updatedBy: callerUid });
    return { previousRole: current.role as string, status: current.status as string };
  });

  // Auth Admin SDK calls can't participate in a Firestore transaction —
  // this only runs once the Firestore write above has committed, so a
  // blocked (last-Super-Admin) attempt never reaches here.
  await auth.setCustomUserClaims(targetUid, { role: newRole, status });

  await writeAuditEvent({
    eventType: 'roleChange',
    entityType: 'user',
    entityId: targetUid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: `Role changed from ${previousRole} to ${newRole}`,
    changedFields: ['role'],
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? targetUid,
    source: 'function',
  });

  return null;
});
