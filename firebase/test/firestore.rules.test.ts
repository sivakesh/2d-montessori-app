/**
 * Positive/negative tests for firestore.rules — SRS §14 "Role/permission
 * matrix and Firebase Security Rules tested with positive and negative
 * cases". Runs only against the Firestore emulator: `npm run
 * test:against-emulators` from this directory (needs JDK 21+ — see the
 * repository root README's "Prerequisites"). Authored and statically
 * checked here but not executed — see docs/architecture/decisions.md
 * "Phase 1 Foundation — test execution status".
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc } from 'firebase/firestore';

let testEnv: RulesTestEnvironment;

const ACTIVE_EDITOR = { role: 'editor', status: 'active' };
const ACTIVE_SUPER_ADMIN = { role: 'superAdmin', status: 'active' };
const SUSPENDED_SUPER_ADMIN_CLAIMS = { role: 'superAdmin', status: 'suspended' };

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-montessori-2d',
    firestore: {
      rules: readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedUserDoc(uid: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', uid), data);
  });
}

describe('users/{uid} read access', () => {
  it('allows a signed-in user to read their own profile', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const u1 = testEnv.authenticatedContext('u1', ACTIVE_EDITOR);
    await assertSucceeds(getDoc(doc(u1.firestore(), 'users', 'u1')));
  });

  it('denies a signed-in user reading a different profile', async () => {
    await seedUserDoc('u2', { email: 'u2@example.test', role: 'editor', status: 'active' });
    const u1 = testEnv.authenticatedContext('u1', ACTIVE_EDITOR);
    await assertFails(getDoc(doc(u1.firestore(), 'users', 'u2')));
  });

  it('denies an unauthenticated read', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'users', 'u1')));
  });

  it('allows an active Super Admin to read any profile', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertSucceeds(getDoc(doc(admin.firestore(), 'users', 'u1')));
  });

  it('denies a Super Admin whose own claims say suspended from reading other profiles', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const suspendedAdmin = testEnv.authenticatedContext('admin1', SUSPENDED_SUPER_ADMIN_CLAIMS);
    await assertFails(getDoc(doc(suspendedAdmin.firestore(), 'users', 'u1')));
  });

  it('denies a non-Super-Admin role reading another profile', async () => {
    await seedUserDoc('u2', { email: 'u2@example.test', role: 'editor', status: 'active' });
    const publisher = testEnv.authenticatedContext('pub1', { role: 'publisher', status: 'active' });
    await assertFails(getDoc(doc(publisher.firestore(), 'users', 'u2')));
  });
});

describe('users/{uid} write access — everything goes through Cloud Functions', () => {
  it('denies a user updating even their own profile directly', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active', displayName: 'Old Name' });
    const u1 = testEnv.authenticatedContext('u1', ACTIVE_EDITOR);
    await assertFails(setDoc(doc(u1.firestore(), 'users', 'u1'), { displayName: 'New Name' }, { merge: true }));
  });

  it('denies a Super Admin writing another user’s role directly (must go through setUserRole)', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(setDoc(doc(admin.firestore(), 'users', 'u1'), { role: 'superAdmin' }, { merge: true }));
  });

  it('denies a client creating a new user document directly (must go through createUser)', async () => {
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(
      setDoc(doc(admin.firestore(), 'users', 'new-user'), {
        email: 'new@example.test',
        role: 'editor',
        status: 'active',
        mustChangePassword: true,
      }),
    );
  });

  it('denies a client deleting a user document directly', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(deleteDoc(doc(admin.firestore(), 'users', 'u1')));
  });
});

describe('auditLogs — Admin-SDK-only, no client access at all', () => {
  it('denies a Super Admin reading audit logs directly', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'auditLogs', 'e1'), { eventType: 'create' });
    });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(getDoc(doc(admin.firestore(), 'auditLogs', 'e1')));
  });

  it('denies any client write to audit logs', async () => {
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(setDoc(doc(admin.firestore(), 'auditLogs', 'e2'), { eventType: 'create' }));
  });
});

describe('published* collections — unchanged public-read baseline', () => {
  it('allows unauthenticated read of publishedPages', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'publishedPages', 'home'), { title: 'Home' });
    });
    const anon = testEnv.unauthenticatedContext();
    await assertSucceeds(getDoc(doc(anon.firestore(), 'publishedPages', 'home')));
  });

  it('denies any client write to publishedPages, even as Super Admin', async () => {
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(setDoc(doc(admin.firestore(), 'publishedPages', 'home'), { title: 'Hacked' }));
  });
});

describe('everything else — default deny', () => {
  it('denies read/write on an undeclared collection even for an active Super Admin', async () => {
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(getDoc(doc(admin.firestore(), 'programs', 'p1')));
    await assertFails(setDoc(doc(admin.firestore(), 'programs', 'p1'), { title: 'x' }));
  });
});
