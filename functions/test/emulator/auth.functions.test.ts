/**
 * Integration tests for the auth callables against the real Firebase
 * Emulator Suite (Auth + Firestore) — NOT run by `npm test`. Run via
 * `npm run test:emulator`, which needs JDK 21+ (see README
 * "Prerequisites"). This file was authored and statically checked
 * (`tsc`, eslint) in an environment where the emulator itself could not
 * be started — see docs/architecture/decisions.md "Phase 1 Foundation —
 * test execution status" for exactly what has and hasn't been run.
 *
 * `firebase emulators:exec` sets FIRESTORE_EMULATOR_HOST /
 * FIREBASE_AUTH_EMULATOR_HOST / GCLOUD_PROJECT automatically, so
 * `admin.initializeApp()` below connects to the emulators with no
 * explicit config.
 *
 * These call `.run(request)` on the exported `CallableFunction` directly
 * — the documented way to invoke a 2nd-gen `onCall` function in tests
 * without going through the HTTPS layer or a real ID token. `auth` on the
 * request is therefore whatever this file constructs, not a verified
 * token; that is intentional and matches how Firebase's own test guidance
 * exercises callable business logic.
 */
import * as admin from 'firebase-admin';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { completeFirstLogin } from '../../src/auth/completeFirstLogin';
import { createUser } from '../../src/auth/createUser';
import { resetUserPassword } from '../../src/auth/resetUserPassword';
import { setUserRole } from '../../src/auth/setUserRole';
import { setUserStatus } from '../../src/auth/setUserStatus';

admin.initializeApp({ projectId: 'demo-montessori-2d' });
const db = admin.firestore();
const auth = admin.auth();

function requestAs(uid: string, role: string, data: unknown = {}): CallableRequest<never> {
  return { data, auth: { uid, token: { role } as never }, rawRequest: {} } as unknown as CallableRequest<never>;
}

async function seedSuperAdmin(uid: string, email: string): Promise<void> {
  await auth.createUser({ uid, email, password: 'seed-password-1' });
  await auth.setCustomUserClaims(uid, { role: 'superAdmin', status: 'active' });
  await db.collection('users').doc(uid).set({
    email,
    displayName: 'Seed Super Admin',
    photoUrl: null,
    role: 'superAdmin',
    status: 'active',
    mustChangePassword: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: 'seed',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: 'seed',
  });
}

async function cleanupUser(uid: string): Promise<void> {
  await Promise.allSettled([auth.deleteUser(uid), db.collection('users').doc(uid).delete()]);
}

describe('createUser', () => {
  const callerUid = 'super-admin-createUser';

  beforeAll(() => seedSuperAdmin(callerUid, 'super-admin-createuser@example.test'));
  afterAll(() => cleanupUser(callerUid));

  it('rejects a non-Super-Admin caller', async () => {
    await expect(
      createUser.run(requestAs('someone', 'editor', { email: 'x@example.test', displayName: 'X', role: 'editor' })),
    ).rejects.toThrow(/permission-denied/);
  });

  it('creates an active user requiring a password change, and returns a temporary password', async () => {
    const email = `new-user-${Date.now()}@example.test`;
    const response = await createUser.run(
      requestAs(callerUid, 'superAdmin', { email, displayName: 'New User', role: 'editor' }),
    );

    expect(response.temporaryPassword).toHaveLength(12);

    const record = await auth.getUser(response.uid);
    expect(record.customClaims).toEqual({ role: 'editor', status: 'active' });

    const doc = await db.collection('users').doc(response.uid).get();
    expect(doc.data()).toMatchObject({ email, role: 'editor', status: 'active', mustChangePassword: true });

    await cleanupUser(response.uid);
  });

  it('rejects a duplicate email', async () => {
    const email = `dupe-${Date.now()}@example.test`;
    const first = await createUser.run(requestAs(callerUid, 'superAdmin', { email, displayName: 'A', role: 'editor' }));

    await expect(
      createUser.run(requestAs(callerUid, 'superAdmin', { email, displayName: 'B', role: 'editor' })),
    ).rejects.toThrow(/already-exists/);

    await cleanupUser(first.uid);
  });
});

describe('setUserRole / setUserStatus — last active Super Admin guard', () => {
  const soleSuperAdminUid = 'sole-super-admin';
  const secondSuperAdminUid = 'second-super-admin';
  const editorUid = 'editor-for-role-tests';

  beforeEach(async () => {
    await seedSuperAdmin(soleSuperAdminUid, 'sole-super-admin@example.test');
  });

  afterEach(() => Promise.all([cleanupUser(soleSuperAdminUid), cleanupUser(secondSuperAdminUid), cleanupUser(editorUid)]));

  it('blocks demoting the only active Super Admin', async () => {
    await expect(
      setUserRole.run(requestAs(soleSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, role: 'editor' })),
    ).rejects.toThrow(/failed-precondition/);
  });

  it('blocks suspending the only active Super Admin', async () => {
    await expect(
      setUserStatus.run(requestAs(soleSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, status: 'suspended' })),
    ).rejects.toThrow(/failed-precondition/);
  });

  it('allows demoting a Super Admin when a second active one exists', async () => {
    await seedSuperAdmin(secondSuperAdminUid, 'second-super-admin@example.test');

    await expect(
      setUserRole.run(requestAs(secondSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, role: 'editor' })),
    ).resolves.toBeNull();

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.customClaims).toMatchObject({ role: 'editor' });
  });

  it('suspending sets the Auth user disabled and the status claim to suspended', async () => {
    await seedSuperAdmin(secondSuperAdminUid, 'second-super-admin-2@example.test');

    await setUserStatus.run(requestAs(secondSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, status: 'suspended' }));

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.disabled).toBe(true);
    expect(record.customClaims).toMatchObject({ status: 'suspended' });
  });
});

describe('resetUserPassword', () => {
  const callerUid = 'super-admin-reset';
  const targetUid = 'target-for-reset';

  beforeAll(async () => {
    await seedSuperAdmin(callerUid, 'super-admin-reset@example.test');
    await admin.auth().createUser({ uid: targetUid, email: 'reset-target@example.test', password: 'original-pw-1' });
    await admin.auth().setCustomUserClaims(targetUid, { role: 'editor', status: 'active' });
    await db.collection('users').doc(targetUid).set({
      email: 'reset-target@example.test',
      displayName: 'Reset Target',
      photoUrl: null,
      role: 'editor',
      status: 'active',
      mustChangePassword: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'seed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: 'seed',
    });
  });

  afterAll(() => Promise.all([cleanupUser(callerUid), cleanupUser(targetUid)]));

  it('sets a new temporary password and requires a change at next sign-in', async () => {
    const response = await resetUserPassword.run(requestAs(callerUid, 'superAdmin', { uid: targetUid }));
    expect(response.temporaryPassword).toHaveLength(12);

    const doc = await db.collection('users').doc(targetUid).get();
    expect(doc.data()?.mustChangePassword).toBe(true);
  });
});

describe('completeFirstLogin', () => {
  const uid = 'first-login-user';

  beforeEach(async () => {
    await admin.auth().createUser({ uid, email: 'first-login@example.test', password: 'temp-password-1' });
    await admin.auth().setCustomUserClaims(uid, { role: 'editor', status: 'active' });
    await db.collection('users').doc(uid).set({
      email: 'first-login@example.test',
      displayName: 'First Login',
      photoUrl: null,
      role: 'editor',
      status: 'active',
      mustChangePassword: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'seed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: 'seed',
    });
  });

  afterEach(() => cleanupUser(uid));

  it('clears mustChangePassword for the calling user', async () => {
    await expect(completeFirstLogin.run(requestAs(uid, 'editor'))).resolves.toBeNull();
    const doc = await db.collection('users').doc(uid).get();
    expect(doc.data()?.mustChangePassword).toBe(false);
  });

  it('is idempotent when called again', async () => {
    await completeFirstLogin.run(requestAs(uid, 'editor'));
    await expect(completeFirstLogin.run(requestAs(uid, 'editor'))).resolves.toBeNull();
  });
});
