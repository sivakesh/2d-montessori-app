#!/usr/bin/env node
/**
 * One-time local bootstrap: creates the first Super Admin account
 * directly via the Admin SDK, against the local Emulator Suite only.
 *
 * Why this exists: functions/src/auth/createUser.ts requires the caller
 * to already be an *active Super Admin* (assertCallerIsActiveSuperAdmin),
 * and firebase/firestore.rules denies every client write to users/{uid}.
 * On a freshly started emulator (or a brand-new real project) there is no
 * Super Admin yet, so nothing can call createUser — a chicken-and-egg
 * problem this script exists solely to break. It bypasses the callable
 * entirely and writes with full Admin SDK trust, exactly like the
 * callable itself does once one Super Admin exists.
 *
 * Usage (with the emulators already running via `firebase emulators:start`):
 *   node scripts/seed-super-admin.js <email> <password> ["Display Name"]
 *
 * Refuses to run unless FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST
 * are set (defaulted below to the local emulator ports if unset) — this
 * script must never be pointed at a real project; creating the first real
 * Super Admin on dev/staging/prod is a deliberate, audited, one-off
 * action for whoever owns that project's console access, not a rerun of
 * this script.
 */
process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';

const admin = require('firebase-admin');

async function main() {
  const [, , email, password, displayName = 'Super Admin'] = process.argv;

  if (!email || !password) {
    console.error('Usage: node scripts/seed-super-admin.js <email> <password> ["Display Name"]');
    process.exitCode = 1;
    return;
  }

  admin.initializeApp({ projectId: 'demo-montessori-2d' });

  const userRecord = await admin.auth().createUser({
    email,
    password,
    displayName,
    disabled: false,
  });

  await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'superAdmin', status: 'active' });

  const now = admin.firestore.FieldValue.serverTimestamp();
  await admin.firestore().collection('users').doc(userRecord.uid).set({
    email,
    displayName,
    photoUrl: null,
    role: 'superAdmin',
    status: 'active',
    // false: this is a deliberately chosen password for local development,
    // not a generated temporary one — nothing to force a change of.
    mustChangePassword: false,
    createdAt: now,
    createdBy: 'seed-super-admin-script',
    updatedAt: now,
    updatedBy: 'seed-super-admin-script',
  });

  console.log(`Created Super Admin ${email} (uid=${userRecord.uid}) against ${process.env.FIRESTORE_EMULATOR_HOST}.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
