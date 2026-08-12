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
// environment.
// Distinct project ID from firestore.rules.test.ts / storage.rules.test.ts
// — see firestore.rules.test.ts's comment on its projectId line for why
// (a real cross-file SDK-state collision caught by CI).
const clientApp = initializeApp(
  { projectId: 'demo-montessori-2d-auth-status', apiKey: 'demo-api-key' },
  'auth-status-test-client',
);
const clientAuth = getAuth(clientApp);
connectAuthEmulator(clientAuth, 'http://localhost:9099', { disableWarnings: true });

// Admin SDK, for setting up and disabling the test account.
const adminApp = initializeAdminApp({ projectId: 'demo-montessori-2d-auth-status' }, 'auth-status-test-admin');
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
