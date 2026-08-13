# Environments

Three real Firebase projects (approved decision, Phase 0): **dev**,
**staging**, **prod** — a fresh trio, not the existing production
`2dmontessori.com` project. A fourth mode, **local**, needs no real project
at all: it runs entirely against the Firebase Emulator Suite using the
reserved `demo-montessori-2d` project ID (see
`packages/firebase_adapters/lib/src/demo_firebase_options.dart`), which the
Emulator Suite treats as offline-only and which never contacts real
Firebase infrastructure.

| Tier | Real Firebase project? | Used for |
|---|---|---|
| local | No — `demo-montessori-2d` | Everyday development against emulators |
| dev | Yes — `twod-montessori-dev` (project id confirmed; deployment prep complete as of Phase 1 CMS Core — see "Bringing up Dev" below; not yet deployed) | Shared preview/dev deployments |
| staging | Yes (to be created) | Production-equivalent rehearsal (PRD §17) |
| prod | Yes (to be created) | Production |

## Current status

`AppEnvironment` (dev/staging/prod — which Firebase *project* a build
targets) and emulator usage are two independent inputs to
`bootstrapFirebase`:

```dart
Future<void> bootstrapFirebase({required FirebaseOptions options, required bool useEmulators})
```

`useEmulators` is a plain, explicit parameter — not derived from
`AppEnvironment` — precisely so a `dev`-flavored build can point at either
the emulators or the real dev project without an API change. As of Phase
1 Foundation, `apps/*/lib/main.dart` calls
`bootstrapFirebase(options: demoEmulatorFirebaseOptions, useEmulators: true)`
unconditionally: there is still no real `dev` project to point the other
way at, so both apps only ever boot the **local** tier today. Wiring
`AppEnvironment` selection itself (via `--dart-define=APP_ENV=`, per
`config/env/README.md`) into the entrypoint is part of standing up the
first real project, below.

## Bringing up a real project (dev/staging/prod), once created

1. Create the Firebase project in the console (or `firebase projects:create`).
2. Enable Authentication (email/password), Firestore, Storage, Functions,
   Hosting and App Check for it.
3. Create two Firebase Hosting **sites** within the project (Build →
   Hosting → Add another site) — one for the public site, one for the
   admin portal. A single project's default Hosting site is not reused
   for either app deliberately, so the two can have independent domains/
   access patterns later.
4. Copy `.firebaserc.template` to `.firebaserc` and replace any remaining
   `REPLACE_WITH_*` placeholders with the real project ID(s) and Hosting
   site IDs — `dev`'s values are already filled in (see below).
5. Generate each app's Flutter options — **run this twice**, once per
   app, creating a **distinct Firebase Web App registration** each time
   (same project id, different `appId`/`apiKey`):
   ```bash
   flutterfire configure --project=<project-id> \
     --out=apps/public_web/lib/firebase_options_<env>.dart --platforms=web
   flutterfire configure --project=<project-id> \
     --out=apps/admin_web/lib/firebase_options_<env>.dart --platforms=web
   ```
   Both generated files are gitignored (see `/.gitignore`) — they hold
   project-specific, non-secret web config, not credentials. See
   `apps/*/lib/firebase_options_<env>.dart.template` for the exact shape
   each generated file will have.
6. Add a `main_<env>.dart` entrypoint (not committed until the generated
   options file it imports actually exists, so it never breaks
   `flutter analyze`/CI for anyone who hasn't run step 5 yet) that calls
   `bootstrapFirebase(options: ..., useEmulators: false)`.
7. Deploy in the staged sequence documented in the milestone's deployment-
   readiness report (rules/indexes first, then Functions, then Hosting) —
   never everything in one unreviewed command.
8. Bootstrap the first Super Admin with
   `functions/scripts/bootstrap-real-super-admin.js` (see its own doc
   comment) — never `scripts/seed-super-admin.js`, which is hardcoded to
   the emulator-only `demo-montessori-2d` project and refuses (by
   construction — it takes no `--project` flag) to target anything else.

## Bringing up Dev specifically

As of Phase 1 CMS Core deployment prep, the Dev project id and both
Hosting site ids are confirmed and already filled in to
`.firebaserc.template` and `firebase.json`:

| Value | Confirmed as |
|---|---|
| Firebase project id | `twod-montessori-dev` |
| Public Hosting site id | `twod-montessori-dev` |
| Admin Hosting site id | `twod-montessori-admin-dev` |
| Cloud Functions region | `us-central1` (default — explicitly confirmed, not left unconfigured) |
| Scheduled-publish timezone | `Asia/Kolkata` (`functions/src/scheduling/publishScheduledContent.ts`) |

What remains before Dev can actually be deployed to is entirely actions
that require an authenticated Firebase/Google Cloud CLI session on your
machine — `firebase login`, `flutterfire configure` against the real
project, the actual `firebase deploy` commands, and running the Super
Admin bootstrap script — none of which this repository preparation work
performs. See the milestone's deployment-readiness report for the exact,
staged command sequence.

## Secrets

No application secret currently exists (Phase 0 has no third-party API
keys). When one is needed (e.g. an analytics or maps key used server-side),
it must be set via `firebase functions:secrets:set <NAME> --project <env>`
(Secret Manager), never committed to `functions/.env` or source control —
see `functions/.env.example` and SRS NFR-05.
