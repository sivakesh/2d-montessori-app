/**
 * SRS AUTH-05: Super Admin can change a user's role. Blocked if it would
 * demote the last active Super Admin — see guards.ts.
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
  const snapshot = await userRef.get();
  const current = snapshot.data();
  if (!snapshot.exists || !current) {
    throw new HttpsError('not-found', 'User not found.');
  }

  await assertRoleChangeAllowed(db, { role: current.role, status: current.status }, newRole);

  await auth.setCustomUserClaims(targetUid, { role: newRole, status: current.status });
  await userRef.update({ role: newRole, updatedAt: FieldValue.serverTimestamp(), updatedBy: callerUid });

  await writeAuditEvent({
    eventType: 'roleChange',
    entityType: 'user',
    entityId: targetUid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: `Role changed from ${current.role} to ${newRole}`,
    changedFields: ['role'],
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? targetUid,
    source: 'function',
  });

  return null;
});
