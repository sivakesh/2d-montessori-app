/**
 * SRS AUTH-01: only the Super Admin creates accounts, using name, email,
 * role and a temporary password. No invitation or notification email is
 * sent in Phase 1 — the temporary password is returned once to the caller
 * to communicate out-of-band.
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { assertCallerIsActiveSuperAdmin } from './guards';
import { generateTemporaryPassword, validateDisplayName, validateEmail, validateRole } from './validators';

interface CreateUserRequestData {
  email?: unknown;
  displayName?: unknown;
  role?: unknown;
}

interface CreateUserResponse {
  uid: string;
  temporaryPassword: string;
}

function isAuthErrorWithCode(error: unknown, code: string): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && (error as { code: unknown }).code === code;
}

export const createUser = onCall<CreateUserRequestData, Promise<CreateUserResponse>>(async (request) => {
  const db = getFirestore();
  const auth = getAuth();
  const callerUid = await assertCallerIsActiveSuperAdmin(request, db);

  const email = validateEmail(request.data.email);
  const displayName = validateDisplayName(request.data.displayName);
  const role = validateRole(request.data.role);
  const temporaryPassword = generateTemporaryPassword();

  let uid: string;
  try {
    const userRecord = await auth.createUser({ email, password: temporaryPassword, displayName, disabled: false });
    uid = userRecord.uid;
  } catch (error) {
    if (isAuthErrorWithCode(error, 'auth/email-already-exists')) {
      throw new HttpsError('already-exists', 'An account with this email already exists.');
    }
    throw new HttpsError('internal', 'Failed to create the account.');
  }

  // Claims are the authoritative source Firestore/Storage rules and other
  // callables check; the Firestore doc mirrors them for display/query.
  await auth.setCustomUserClaims(uid, { role, status: 'active' });

  const now = FieldValue.serverTimestamp();
  await db.collection('users').doc(uid).set({
    email,
    displayName,
    photoUrl: null,
    role,
    status: 'active',
    mustChangePassword: true,
    createdAt: now,
    createdBy: callerUid,
    updatedAt: now,
    updatedBy: callerUid,
  });

  await writeAuditEvent({
    eventType: 'create',
    entityType: 'user',
    entityId: uid,
    actorId: callerUid,
    actorRole: 'superAdmin',
    changeSummary: `Created user ${email} with role ${role}`,
    requestId: request.rawRequest?.headers['x-request-id']?.toString() ?? uid,
    source: 'function',
  });

  return { uid, temporaryPassword };
});
