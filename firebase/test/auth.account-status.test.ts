/**
 * Verifies actual Firebase Auth sign-in behavior for disabled/suspended
 * accounts (SRS AUTH-05) against the Auth emulator — distinct from the
 * Firestore rules tests, since this exercises real
 * `signInWithEmailAndPassword`, not a rules simulation. Run via `npm run
 * test:against-emulators` from this directory — needs JDK 21+; not
 * executed in this environment (see README "Prerequisites").
 */
import { initializeApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import { initializeApp as initializeAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';

// Client SDK, pointed at the Auth emulator only — this file intentionally
// does not touch Firestore, so it doesn't need a rules-unit-testing
// environment, and does NOT use a distinct project ID the way
// firestore.rules.test.ts / storage.rules.test.ts do. That was tried
// here too and made things *worse*: CI showed `createUserWithEmailAndPassword`
// (client SDK) succeeding while the immediately-following
// `adminAuth.getUserByEmail` (Admin SDK) failed with "no user record
// corresponding to the provided identifier" against the same non-default
// project ID — unlike the Firestore emulator, the Auth emulator does not
// reliably treat an arbitrary demo-* project ID as an independent,
// fully-functional namespace shared consistently between the client and
// Admin SDKs. Using the same project ID `firebase emulators:exec
// --project` was started with avoids that; the named app instances
// below (`auth-status-test-client`/`-admin`) already provide enough
// isolation from the *Firestore*-side SDK state that was the actual
// problem in the other two files.
const clientApp = initializeApp({ projectId: 'demo-montessori-2d', apiKey: 'demo-api-key' }, 'auth-status-test-client');
const clientAuth = getAuth(clientApp);
connectAuthEmulator(clientAuth, 'http://localhost:9099', { disableWarnings: true });

// Admin SDK, for setting up and disabling the test account.
const adminApp = initializeAdminApp({ projectId: 'demo-montessori-2d' }, 'auth-status-test-admin');
const adminAuth = getAdminAuth(adminApp);

const TEST_PASSWORD = 'original-pw-1';

/**
 * Each test creates and tears down its own account with a unique email,
 * deliberately not sharing a fixture across tests. An earlier version of
 * this file had "allows sign-in while enabled" create the account and a
 * second test look it up by a shared email — CI (GitHub Actions, JDK 21)
 * showed that second test failing with "There is no user record
 * corresponding to the provided identifier," a real cross-test
 * dependency this file should never have had regardless of what
 * ultimately caused the lookup to miss.
 */
function uniqueTestEmail(label: string): string {
  return `disabled-account-test-${label}-${Date.now()}-${Math.floor(Math.random() * 1e6)}@example.test`;
}

afterEach(async () => {
  await signOut(clientAuth).catch(() => undefined);
});

describe('disabled account sign-in (SRS AUTH-05 suspend/reactivate)', () => {
  it('allows sign-in while the account is enabled', async () => {
    const email = uniqueTestEmail('enabled');
    await createUserWithEmailAndPassword(clientAuth, email, TEST_PASSWORD);
    await signOut(clientAuth);

    await expect(signInWithEmailAndPassword(clientAuth, email, TEST_PASSWORD)).resolves.toBeDefined();

    const record = await adminAuth.getUserByEmail(email);
    await adminAuth.deleteUser(record.uid);
  });

  it('rejects sign-in once setUserStatus has disabled the account', async () => {
    const email = uniqueTestEmail('disabled');
    await createUserWithEmailAndPassword(clientAuth, email, TEST_PASSWORD);
    await signOut(clientAuth);
    const record = await adminAuth.getUserByEmail(email);

    // Mirrors what functions/src/auth/setUserStatus.ts does when
    // suspending — see that file for why disabling the Auth user (not
    // just flipping the Firestore/claims status) matters: it blocks new
    // sign-ins immediately, independent of any cached ID token.
    await adminAuth.updateUser(record.uid, { disabled: true });

    await expect(signInWithEmailAndPassword(clientAuth, email, TEST_PASSWORD)).rejects.toThrow(/user-disabled/);

    await adminAuth.deleteUser(record.uid);
  });
});
