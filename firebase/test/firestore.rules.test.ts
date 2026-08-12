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

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    // Deliberately a distinct project ID per test file (still emulator-
    // only — see the demo- prefix convention documented in
    // packages/firebase_adapters/lib/src/demo_firebase_options.dart).
    // When Jest runs multiple test files that each call
    // initializeTestEnvironment for the *same* projectId in the same
    // worker process, the second call can fail with "Firestore has
    // already been started and its settings can no longer be changed" —
    // a real failure caught by CI (GitHub Actions, JDK 21), not a
    // theoretical one. The Firestore/Storage emulators are multi-project
    // regardless of which project ID started them via `firebase
    // emulators:exec --project`, so distinct IDs per file are safe.
    projectId: 'demo-montessori-2d-firestore-rules',
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

  it('allows a suspended user to read their own profile (so the app can show them why they are blocked)', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'suspended' });
    const u1 = testEnv.authenticatedContext('u1', { role: 'editor', status: 'suspended' });
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

  it('allows an active Super Admin (Firestore-verified, not just claimed) to read any profile', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertSucceeds(getDoc(doc(admin.firestore(), 'users', 'u1')));
  });

  // This is the critical regression test for the inconsistency found at
  // the Foundation Verification checkpoint (see
  // docs/architecture/decisions.md "Security-rule inconsistency found and
  // resolved"): a Super Admin's ID token can still carry role=superAdmin,
  // status=active for up to ~1 hour after they are suspended, because
  // Firebase does not push claim changes to already-signed-in clients.
  // The rule must re-verify status against Firestore — the caller's own
  // *current* record, not the token they happen to be holding — for any
  // cross-user read, or a just-suspended Super Admin keeps full read
  // access to every profile until their stale token expires.
  it('denies a Super Admin cross-user read when their cached token is stale (token says active, Firestore says suspended)', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'suspended' });
    // authenticatedContext's claims simulate a token issued *before* the
    // suspension above — exactly the stale-token scenario.
    const staleAdmin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(getDoc(doc(staleAdmin.firestore(), 'users', 'u1')));
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

  it('denies a user promoting their own role directly', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    const u1 = testEnv.authenticatedContext('u1', ACTIVE_EDITOR);
    await assertFails(setDoc(doc(u1.firestore(), 'users', 'u1'), { role: 'superAdmin' }, { merge: true }));
  });

  it('denies a user reactivating their own suspended status directly', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'suspended' });
    const u1 = testEnv.authenticatedContext('u1', { role: 'editor', status: 'suspended' });
    await assertFails(setDoc(doc(u1.firestore(), 'users', 'u1'), { status: 'active' }, { merge: true }));
  });

  it('denies a user clearing their own mustChangePassword flag directly', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active', mustChangePassword: true });
    const u1 = testEnv.authenticatedContext('u1', ACTIVE_EDITOR);
    await assertFails(setDoc(doc(u1.firestore(), 'users', 'u1'), { mustChangePassword: false }, { merge: true }));
  });

  it('denies a Super Admin writing another user’s role directly (must go through setUserRole)', async () => {
    await seedUserDoc('u1', { email: 'u1@example.test', role: 'editor', status: 'active' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(setDoc(doc(admin.firestore(), 'users', 'u1'), { role: 'superAdmin' }, { merge: true }));
  });

  it('denies a client creating a new user document directly (must go through createUser)', async () => {
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
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
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    await assertFails(deleteDoc(doc(admin.firestore(), 'users', 'u1')));
  });
});

describe('auditLogs — Admin-SDK-only, no client access at all', () => {
  it('denies a Super Admin reading audit logs directly', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'auditLogs', 'e1'), { eventType: 'create' });
    });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
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
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    // Call .firestore() once and reuse it — calling it a second time on
    // the same context threw "Firestore has already been started and its
    // settings can no longer be changed" in CI (this was the only test
    // in the file calling .firestore() twice on one context; every other
    // test does one operation per context). Whatever RulesTestContext
    // does internally on each .firestore() call, it isn't safe to call
    // more than once per context.
    const db = admin.firestore();
    await assertFails(getDoc(doc(db, 'programs', 'p1')));
    await assertFails(setDoc(doc(db, 'programs', 'p1'), { title: 'x' }));
  });
});
