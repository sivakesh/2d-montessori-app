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

function unauthenticatedRequest(data: unknown = {}): CallableRequest<never> {
  return { data, auth: undefined, rawRequest: {} } as unknown as CallableRequest<never>;
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

async function auditLogCount(): Promise<number> {
  const snapshot = await db.collection('auditLogs').count().get();
  return snapshot.data().count;
}

async function auditEntriesFor(entityId: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snapshot = await db.collection('auditLogs').where('entityId', '==', entityId).get();
  return snapshot.docs.map((doc) => doc.data());
}

/**
 * `HttpsError`'s `.message` is the human-readable text (e.g. "Sign in
 * required."), not the machine-readable `.code` (e.g. "unauthenticated")
 * — `jest`'s `.rejects.toThrow(/pattern/)` matches against `.message`, so
 * asserting on the code needs `.toMatchObject({ code })` instead. This
 * was itself a bug caught by actually running these tests: every
 * `.rejects.toThrow(/some-code/)` in an earlier version of this file
 * failed, not because the callables were wrong, but because the
 * assertion was checking the wrong field.
 */
async function expectHttpsErrorCode(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

describe('createUser', () => {
  const callerUid = 'super-admin-createUser';

  beforeAll(() => seedSuperAdmin(callerUid, 'super-admin-createuser@example.test'));
  afterAll(() => cleanupUser(callerUid));

  it('rejects an unauthenticated caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      createUser.run(unauthenticatedRequest({ email: 'x@example.test', displayName: 'X', role: 'editor' })),
      'unauthenticated',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('rejects a non-Super-Admin caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      createUser.run(requestAs('someone', 'editor', { email: 'x@example.test', displayName: 'X', role: 'editor' })),
      'permission-denied',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('creates an active user requiring a password change, and writes exactly one audit entry', async () => {
    const email = `new-user-${Date.now()}@example.test`;
    const response = await createUser.run(
      requestAs(callerUid, 'superAdmin', { email, displayName: 'New User', role: 'editor' }),
    );

    expect(response.temporaryPassword).toHaveLength(12);

    const record = await auth.getUser(response.uid);
    expect(record.customClaims).toEqual({ role: 'editor', status: 'active' });

    const doc = await db.collection('users').doc(response.uid).get();
    expect(doc.data()).toMatchObject({ email, role: 'editor', status: 'active', mustChangePassword: true });

    const auditEntries = await auditEntriesFor(response.uid);
    expect(auditEntries).toHaveLength(1);
    expect(auditEntries[0]).toMatchObject({ eventType: 'create', entityType: 'user', actorId: callerUid, source: 'function' });

    await cleanupUser(response.uid);
  });

  it('rejects a duplicate email', async () => {
    const email = `dupe-${Date.now()}@example.test`;
    const first = await createUser.run(requestAs(callerUid, 'superAdmin', { email, displayName: 'A', role: 'editor' }));

    await expectHttpsErrorCode(
      createUser.run(requestAs(callerUid, 'superAdmin', { email, displayName: 'B', role: 'editor' })),
      'already-exists',
    );

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

  it('rejects an unauthenticated caller for setUserRole', async () => {
    await expectHttpsErrorCode(
      setUserRole.run(unauthenticatedRequest({ uid: soleSuperAdminUid, role: 'editor' })),
      'unauthenticated',
    );
  });

  it('rejects a non-Super-Admin caller for setUserStatus', async () => {
    await db.collection('users').doc(editorUid).set({
      email: 'editor-caller@example.test',
      displayName: 'Editor Caller',
      photoUrl: null,
      role: 'editor',
      status: 'active',
      mustChangePassword: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'seed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: 'seed',
    });
    await expectHttpsErrorCode(
      setUserStatus.run(requestAs(editorUid, 'editor', { uid: soleSuperAdminUid, status: 'suspended' })),
      'permission-denied',
    );
  });

  it('blocks demoting the only active Super Admin and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      setUserRole.run(requestAs(soleSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, role: 'editor' })),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.customClaims).toMatchObject({ role: 'superAdmin' });
  });

  it('blocks suspending the only active Super Admin and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      setUserStatus.run(requestAs(soleSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, status: 'suspended' })),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.disabled).toBe(false);
  });

  it('allows demoting a Super Admin when a second active one exists, and writes an audit entry', async () => {
    await seedSuperAdmin(secondSuperAdminUid, 'second-super-admin@example.test');

    await expect(
      setUserRole.run(requestAs(secondSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, role: 'editor' })),
    ).resolves.toBeNull();

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.customClaims).toMatchObject({ role: 'editor' });

    const auditEntries = await auditEntriesFor(soleSuperAdminUid);
    expect(auditEntries.some((e) => e.eventType === 'roleChange' && e.actorId === secondSuperAdminUid)).toBe(true);
  });

  it('suspending sets the Auth user disabled, the status claim to suspended, and writes an audit entry', async () => {
    await seedSuperAdmin(secondSuperAdminUid, 'second-super-admin-2@example.test');

    await setUserStatus.run(requestAs(secondSuperAdminUid, 'superAdmin', { uid: soleSuperAdminUid, status: 'suspended' }));

    const record = await auth.getUser(soleSuperAdminUid);
    expect(record.disabled).toBe(true);
    expect(record.customClaims).toMatchObject({ status: 'suspended' });

    const auditEntries = await auditEntriesFor(soleSuperAdminUid);
    expect(auditEntries.some((e) => e.eventType === 'statusChange' && e.actorId === secondSuperAdminUid)).toBe(true);
  });
});

describe('setUserRole / setUserStatus concurrency — last active Super Admin guard under a race', () => {
  const adminAUid = 'race-admin-a';
  const adminBUid = 'race-admin-b';

  beforeEach(() =>
    Promise.all([seedSuperAdmin(adminAUid, 'race-admin-a@example.test'), seedSuperAdmin(adminBUid, 'race-admin-b@example.test')]),
  );

  afterEach(() => Promise.all([cleanupUser(adminAUid), cleanupUser(adminBUid)]));

  it('never suspends both of the last two active Super Admins concurrently (item 4: "including under concurrent requests")', async () => {
    const [resultA, resultB] = await Promise.allSettled([
      setUserStatus.run(requestAs(adminAUid, 'superAdmin', { uid: adminBUid, status: 'suspended' })),
      setUserStatus.run(requestAs(adminBUid, 'superAdmin', { uid: adminAUid, status: 'suspended' })),
    ]);

    const statuses = [resultA.status, resultB.status];
    // Firestore transactions serialize on the active-Super-Admin count
    // query both requests read: whichever commits first sees count=2 and
    // succeeds; the other is forced to retry, then sees count=1 and is
    // correctly blocked. Exactly one of each is expected — not "at most
    // one succeeds" (too weak) and not "both must be rejected" (which
    // would mean the guard is now too strict to ever demote anyone).
    expect(statuses.filter((s) => s === 'fulfilled')).toHaveLength(1);
    expect(statuses.filter((s) => s === 'rejected')).toHaveLength(1);

    const [recordA, recordB] = await Promise.all([auth.getUser(adminAUid), auth.getUser(adminBUid)]);
    expect([recordA.disabled, recordB.disabled].filter((disabled) => !disabled)).toHaveLength(1);
  });

  it('never demotes both of the last two active Super Admins concurrently', async () => {
    const [resultA, resultB] = await Promise.allSettled([
      setUserRole.run(requestAs(adminAUid, 'superAdmin', { uid: adminBUid, role: 'editor' })),
      setUserRole.run(requestAs(adminBUid, 'superAdmin', { uid: adminAUid, role: 'editor' })),
    ]);

    const statuses = [resultA.status, resultB.status];
    expect(statuses.filter((s) => s === 'fulfilled')).toHaveLength(1);
    expect(statuses.filter((s) => s === 'rejected')).toHaveLength(1);

    const [recordA, recordB] = await Promise.all([auth.getUser(adminAUid), auth.getUser(adminBUid)]);
    const remainingSuperAdmins = [recordA, recordB].filter((r) => r.customClaims?.role === 'superAdmin');
    expect(remainingSuperAdmins).toHaveLength(1);
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

  it('rejects a non-Super-Admin caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      resetUserPassword.run(requestAs(targetUid, 'editor', { uid: callerUid })),
      'permission-denied',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('sets a new temporary password, requires a change at next sign-in, and writes an audit entry', async () => {
    const response = await resetUserPassword.run(requestAs(callerUid, 'superAdmin', { uid: targetUid }));
    expect(response.temporaryPassword).toHaveLength(12);

    const doc = await db.collection('users').doc(targetUid).get();
    expect(doc.data()?.mustChangePassword).toBe(true);

    const auditEntries = await auditEntriesFor(targetUid);
    expect(auditEntries.some((e) => e.eventType === 'update' && e.actorId === callerUid)).toBe(true);
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

  it('rejects an unauthenticated caller', async () => {
    await expectHttpsErrorCode(completeFirstLogin.run(unauthenticatedRequest()), 'unauthenticated');
  });

  it('clears mustChangePassword for the calling user and writes an audit entry', async () => {
    await expect(completeFirstLogin.run(requestAs(uid, 'editor'))).resolves.toBeNull();
    const doc = await db.collection('users').doc(uid).get();
    expect(doc.data()?.mustChangePassword).toBe(false);

    const auditEntries = await auditEntriesFor(uid);
    expect(auditEntries.some((e) => e.eventType === 'update' && e.actorId === uid)).toBe(true);
  });

  it('is idempotent when called again, without writing a second audit entry', async () => {
    await completeFirstLogin.run(requestAs(uid, 'editor'));
    const afterFirst = await auditLogCount();

    await expect(completeFirstLogin.run(requestAs(uid, 'editor'))).resolves.toBeNull();
    expect(await auditLogCount()).toBe(afterFirst);
  });
});
