#!/usr/bin/env node
/**
 * Bootstraps the FIRST Super Admin account on a REAL Firebase project
 * (dev, staging or prod) — the real-project counterpart to
 * `scripts/seed-super-admin.js`, which is emulator-only and must never be
 * pointed at a real project. This script is the deliberate, audited,
 * one-off action for whoever owns that project's console access; it is
 * not meant to be a routine or repeated operation (see the active-
 * Super-Admin guard below).
 *
 * Safety properties, each corresponding to a specific requirement this
 * script was reviewed against before being recommended for real use:
 *
 * - Requires an explicit `--project=<id>` with no default — never falls
 *   back to any project, real or emulator.
 * - Refuses any project id starting with `demo-` (the Emulator Suite's
 *   reserved, offline-only namespace — see
 *   packages/firebase_adapters/lib/src/demo_firebase_options.dart) so
 *   this script can never accidentally target the emulator, and
 *   `scripts/seed-super-admin.js` can never accidentally target a real
 *   project (it hardcodes `demo-montessori-2d` and takes no `--project`
 *   flag at all).
 * - Prints the target project/email and requires the operator to *type
 *   the project id back* before anything is created, plus a separate
 *   "yes" confirmation — two deliberate, distinct confirmations, not one
 *   generic y/N prompt.
 * - Never accepts a password as a CLI argument (arguments are visible in
 *   shell history and `ps`), and never logs one to a file. A temporary
 *   password is generated the same way `functions/src/auth/createUser.ts`
 *   generates one for every other account this system creates, and is
 *   printed to the terminal exactly once, purely so the operator can hand
 *   it to the new Super Admin — the account is created with
 *   `mustChangePassword: true`, so it cannot be used past first sign-in
 *   without being changed.
 * - Idempotent and resumable: if an Auth user with this email already
 *   exists (e.g. a prior run failed partway through), this script
 *   continues from claims/Firestore-doc reconciliation instead of erroring
 *   out or generating a second password.
 * - Refuses to create an *additional* Super Admin unless the caller
 *   passes `--i-understand-this-adds-another-super-admin` — checked by
 *   querying Firestore for existing `role == 'superAdmin' && status ==
 *   'active'` users first. Ordinary "add another admin" work belongs to
 *   the app's own `createUser` Cloud Function (called by an existing
 *   Super Admin through the UI), not this script.
 * - Writes an `auditLogs` entry (`source: 'migration'`) so the bootstrap
 *   itself is a documented, queryable event, the same shape
 *   `functions/src/lib/audit.ts`'s `writeAuditEvent` produces (this
 *   script writes the collection directly rather than importing compiled
 *   `lib/` output, but the field shape is kept identical on purpose).
 * - Uses Application Default Credentials (`admin.initializeApp({
 *   projectId })` with no `credential:` — no service-account JSON key is
 *   read, downloaded, or required). Run once beforehand, authenticated as
 *   yourself:
 *     gcloud auth application-default login
 *   Your Google account needs at least Firebase Authentication Admin and
 *   Cloud Datastore User (or an equivalent broader role like Editor/Owner)
 *   on the target project for this to succeed.
 *
 * Usage:
 *   node scripts/bootstrap-real-super-admin.js \
 *     --project=twod-montessori-dev \
 *     --email=admin@example.com \
 *     [--display-name="Full Name"] \
 *     [--i-understand-this-adds-another-super-admin]
 */
const admin = require('firebase-admin');
const crypto = require('crypto');
const readline = require('readline');

// Mirrors functions/src/auth/validators.ts's generateTemporaryPassword()
// exactly (excludes visually-ambiguous characters like 0/O/1/l/I) — kept
// as a plain reimplementation here rather than importing compiled
// `functions/lib/` output, since this script is meant to be runnable
// standalone without assuming a prior `npm run build`.
const TEMP_PASSWORD_LENGTH = 12;
const TEMP_PASSWORD_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
const TEMP_PASSWORD_DIGITS = '23456789';
const TEMP_PASSWORD_CHARSET = TEMP_PASSWORD_LETTERS + TEMP_PASSWORD_DIGITS;

function generateTemporaryPassword() {
  const chars = [
    TEMP_PASSWORD_LETTERS[crypto.randomInt(TEMP_PASSWORD_LETTERS.length)],
    TEMP_PASSWORD_DIGITS[crypto.randomInt(TEMP_PASSWORD_DIGITS.length)],
  ];
  while (chars.length < TEMP_PASSWORD_LENGTH) {
    chars.push(TEMP_PASSWORD_CHARSET[crypto.randomInt(TEMP_PASSWORD_CHARSET.length)]);
  }
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

function parseArgs(argv) {
  const args = { project: null, email: null, displayName: 'Super Admin', force: false };
  for (const arg of argv) {
    if (arg.startsWith('--project=')) {
      args.project = arg.slice('--project='.length).trim();
    } else if (arg.startsWith('--email=')) {
      args.email = arg.slice('--email='.length).trim();
    } else if (arg.startsWith('--display-name=')) {
      args.displayName = arg.slice('--display-name='.length).trim();
    } else if (arg === '--i-understand-this-adds-another-super-admin') {
      args.force = true;
    } else {
      console.error(`Unrecognized argument: ${arg}`);
      printUsage();
      process.exit(1);
    }
  }
  return args;
}

function printUsage() {
  console.error(`
Usage:
  node scripts/bootstrap-real-super-admin.js --project=<firebase-project-id> --email=<email> [--display-name="Full Name"]

This bootstraps the FIRST Super Admin account on a REAL Firebase project.
It never accepts a password argument — a temporary password is generated
and printed once; the account must change it at first sign-in.

Required:
  --project=<id>   Explicit real Firebase project id. Refused if it starts
                    with "demo-" — use scripts/seed-super-admin.js against
                    the Emulator Suite for local development instead.
  --email=<email>   Email address for the account.

Optional:
  --display-name="..."   Defaults to "Super Admin".
  --i-understand-this-adds-another-super-admin
                    Required if the project already has one or more active
                    Super Admins. This script is for the FIRST bootstrap
                    only — add further admins via the app's own user
                    management screen afterward.

Authentication: run once beforehand, as yourself:
  gcloud auth application-default login
No service-account JSON key is used or required.
`);
}

function promptLine(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project || !args.email) {
    printUsage();
    process.exitCode = 1;
    return;
  }

  if (args.project.startsWith('demo-')) {
    console.error(`Refusing: "${args.project}" looks like an Emulator Suite demo project id.`);
    console.error('Use scripts/seed-super-admin.js against the Emulator Suite for local development instead.');
    process.exitCode = 1;
    return;
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(args.email)) {
    console.error(`Refusing: "${args.email}" does not look like a valid email address.`);
    process.exitCode = 1;
    return;
  }

  console.log('');
  console.log('=============================================================');
  console.log('  REAL FIREBASE PROJECT — SUPER ADMIN BOOTSTRAP');
  console.log('=============================================================');
  console.log(`  Project:      ${args.project}`);
  console.log(`  Email:        ${args.email}`);
  console.log(`  Display name: ${args.displayName}`);
  console.log('=============================================================');
  console.log('');
  console.log('This writes directly to Firebase Authentication and Firestore');
  console.log('on the project above using your local Application Default');
  console.log('Credentials. Nothing has been written yet.');
  console.log('');

  const typedProject = await promptLine(`Type the project id ("${args.project}") to confirm you are targeting the right project: `);
  if (typedProject.trim() !== args.project) {
    console.error('Project id did not match what you typed. Aborting — nothing was created.');
    process.exitCode = 1;
    return;
  }

  const proceed = await promptLine(`Type "yes" to proceed with creating/verifying a Super Admin on "${args.project}": `);
  if (proceed.trim().toLowerCase() !== 'yes') {
    console.error('Aborted. Nothing was created.');
    process.exitCode = 1;
    return;
  }

  admin.initializeApp({ projectId: args.project });
  const auth = admin.auth();
  const db = admin.firestore();

  const existingActiveSuperAdmins = await db.collection('users').where('role', '==', 'superAdmin').where('status', '==', 'active').get();
  if (!existingActiveSuperAdmins.empty && !args.force) {
    console.error('');
    console.error(`Project "${args.project}" already has ${existingActiveSuperAdmins.size} active Super Admin(s):`);
    for (const doc of existingActiveSuperAdmins.docs) {
      console.error(`  - ${doc.data().email} (uid=${doc.id})`);
    }
    console.error('');
    console.error("This script is meant for the FIRST bootstrap only. To add another");
    console.error("Super Admin, sign in as an existing one and use the app's own User");
    console.error('Management screen (which calls the createUser Cloud Function and');
    console.error('produces a proper audit trail attributed to that admin, not this script).');
    console.error('');
    console.error('If you are certain you want to proceed anyway, rerun with:');
    console.error('  --i-understand-this-adds-another-super-admin');
    process.exitCode = 1;
    return;
  }

  // Idempotent + resumable: reuse the existing Auth user if this email
  // already exists (e.g. a prior run of this script got partway through),
  // rather than failing outright or generating a second password.
  let userRecord;
  let createdNewAuthUser = false;
  try {
    userRecord = await auth.getUserByEmail(args.email);
    console.log(`An Auth user for ${args.email} already exists (uid=${userRecord.uid}) — leaving their password untouched.`);
  } catch (error) {
    if (!error || error.code !== 'auth/user-not-found') throw error;
    const temporaryPassword = generateTemporaryPassword();
    userRecord = await auth.createUser({ email: args.email, password: temporaryPassword, displayName: args.displayName, disabled: false });
    createdNewAuthUser = true;
    console.log('');
    console.log('=============================================================');
    console.log(`  Temporary password (shown once — copy it now):`);
    console.log(`  ${temporaryPassword}`);
    console.log('=============================================================');
    console.log('');
  }

  await auth.setCustomUserClaims(userRecord.uid, { role: 'superAdmin', status: 'active' });

  const now = admin.firestore.FieldValue.serverTimestamp();
  const userDocRef = db.collection('users').doc(userRecord.uid);
  const existingDoc = await userDocRef.get();
  await userDocRef.set(
    {
      email: args.email,
      displayName: args.displayName,
      photoUrl: null,
      role: 'superAdmin',
      status: 'active',
      mustChangePassword: createdNewAuthUser ? true : (existingDoc.data() && existingDoc.data().mustChangePassword) !== false,
      createdAt: existingDoc.exists ? existingDoc.data().createdAt : now,
      createdBy: 'bootstrap-real-super-admin-script',
      updatedAt: now,
      updatedBy: 'bootstrap-real-super-admin-script',
    },
    { merge: true },
  );

  // Same shape functions/src/lib/audit.ts's writeAuditEvent produces —
  // written directly here since this plain script runs outside the
  // compiled functions bundle.
  await db.collection('auditLogs').add({
    eventType: 'create',
    entityType: 'user',
    entityId: userRecord.uid,
    actorId: 'bootstrap-real-super-admin-script',
    actorRole: 'system',
    changeSummary: `Bootstrapped Super Admin ${args.email} on ${args.project}`,
    requestId: `bootstrap-${args.project}-${Date.now()}`,
    source: 'migration',
    timestamp: now,
  });

  console.log(`Done. ${args.email} (uid=${userRecord.uid}) is now an active Super Admin on "${args.project}".`);
  if (createdNewAuthUser) {
    console.log('They must sign in with the temporary password above and will be forced to change it immediately.');
  } else {
    console.log('Their custom claims and Firestore profile have been (re)confirmed as an active Super Admin.');
  }
}

main().catch((error) => {
  console.error('Bootstrap failed:', error);
  process.exitCode = 1;
});
