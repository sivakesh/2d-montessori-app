/**
 * SRS AUTH-05: Super Admin resets access with a temporary password. No
 * notification email is sent in Phase 1 — the password is returned once
 * to the caller.
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { assertCallerIsActiveSuperAdmin } from './guards';
import { generateTemporaryPassword, validateUid } from './validators';

interface ResetUserPasswordRequestData {
  uid?: unknown;
}

interface ResetUserPasswordResponse {
  temporaryPassword: string;
}

export const resetUserPassword = onCall<ResetUserPasswordRequestData, Promise<ResetUserPasswordResponse>>(async (request) => {
  const db = getFirestore();
  const auth = getAuth();
  const callerUid = await assertCallerIsActiveSuperAdmin(request, db);

  const targetUid = validateUid(request.data.uid);
  const userRef = db.collection('users').doc(targetUid);
  const snapshot = await userRef.get();
  if (!snapshot.exists) {
    throw new HttpsError('not-found', 'User not found.');
  }

  const temporaryPassword = generateTemporaryPassword();
  await auth.updateUser(targetUid, { password: temporaryPassword });
  // Force re-authentication with the new password on this user's next
  // token refresh — see setUserStatus.ts's doc comment for the same
  // revokeRefreshTokens timing caveat.
  await auth.revokeRefreshTokens(targetUid);

  await userRef.update({
    mustChangePassword: true,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: callerUid,
  });

  await writeAuditEvent({
    eventType: 'update',
    entityType: 'user',
    entityId: targetUid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: 'Password reset by Super Admin',
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? targetUid,
    source: 'function',
  });

  return { temporaryPassword };
});
