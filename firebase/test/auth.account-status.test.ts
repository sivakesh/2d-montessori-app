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
const clientApp = initializeApp({ projectId: 'demo-montessori-2d', apiKey: 'demo-api-key' }, 'auth-status-test-client');
const clientAuth = getAuth(clientApp);
connectAuthEmulator(clientAuth, 'http://localhost:9099', { disableWarnings: true });

// Admin SDK, for setting up and disabling the test account.
const adminApp = initializeAdminApp({ projectId: 'demo-montessori-2d' }, 'auth-status-test-admin');
const adminAuth = getAdminAuth(adminApp);

const TEST_EMAIL = 'disabled-account-test@example.test';
const TEST_PASSWORD = 'original-pw-1';

afterEach(async () => {
  await signOut(clientAuth).catch(() => undefined);
});

describe('disabled account sign-in (SRS AUTH-05 suspend/reactivate)', () => {
  it('allows sign-in while the account is enabled', async () => {
    await createUserWithEmailAndPassword(clientAuth, TEST_EMAIL, TEST_PASSWORD);
    await signOut(clientAuth);

    await expect(signInWithEmailAndPassword(clientAuth, TEST_EMAIL, TEST_PASSWORD)).resolves.toBeDefined();
  });

  it('rejects sign-in once setUserStatus has disabled the account', async () => {
    const record = await adminAuth.getUserByEmail(TEST_EMAIL);
    // Mirrors what functions/src/auth/setUserStatus.ts does when
    // suspending — see that file for why disabling the Auth user (not
    // just flipping the Firestore/claims status) matters: it blocks new
    // sign-ins immediately, independent of any cached ID token.
    await adminAuth.updateUser(record.uid, { disabled: true });

    await expect(signInWithEmailAndPassword(clientAuth, TEST_EMAIL, TEST_PASSWORD)).rejects.toThrow(/user-disabled/);

    // Cleanup: re-enable and delete so this test is independently
    // re-runnable.
    await adminAuth.updateUser(record.uid, { disabled: false });
    await adminAuth.deleteUser(record.uid);
  });
});
