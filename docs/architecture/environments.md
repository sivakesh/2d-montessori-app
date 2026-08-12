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
| dev | Yes (to be created) | Shared preview/dev deployments |
| staging | Yes (to be created) | Production-equivalent rehearsal (PRD §17) |
| prod | Yes (to be created) | Production |

## Current Phase 0 status

`apps/*/lib/main.dart` always boots the **local** tier — it calls
`bootstrapFirebase(options: demoEmulatorFirebaseOptions, environment: AppEnvironment.dev)`.
This is intentionally simplified: today, `AppEnvironment.dev` and "use
emulators" are the same thing because no real `dev` project exists yet.
Once it does, this mapping needs revisiting — likely by decoupling
`usesEmulators` from the enum value entirely (e.g. a separate
`--dart-define=USE_EMULATORS=` flag, per `config/env/README.md`) so a
developer can point a `dev`-flavored build at either the emulators or the
real dev project. Flagged here so it isn't mistaken for a finished design.

## Bringing up a real project (dev/staging/prod), once created

1. Create the Firebase project in the console (or `firebase projects:create`).
2. Enable Authentication (email/password), Firestore, Storage, Functions,
   Hosting and App Check for it.
3. Copy `.firebaserc.template` to `.firebaserc` and replace the
   `REPLACE_WITH_*` placeholders with the real project ID(s) and Hosting
   site IDs.
4. Generate its Flutter options:
   ```bash
   flutterfire configure --project=<project-id> \
     --out=apps/public_web/lib/firebase_options_<env>.dart --platforms=web
   flutterfire configure --project=<project-id> \
     --out=apps/admin_web/lib/firebase_options_<env>.dart --platforms=web
   ```
   Both generated files are gitignored (see `/.gitignore`) — they hold
   project-specific, non-secret web config, not credentials.
5. Add a `main_<env>.dart` entrypoint that imports the generated options
   file and calls `bootstrapFirebase(options: ..., environment:
   AppEnvironment.<env>)` with `usesEmulators` returning `false`.
6. Deploy: `firebase deploy --project <env> --only firestore:rules,storage:rules,functions,hosting`.

## Secrets

No application secret currently exists (Phase 0 has no third-party API
keys). When one is needed (e.g. an analytics or maps key used server-side),
it must be set via `firebase functions:secrets:set <NAME> --project <env>`
(Secret Manager), never committed to `functions/.env` or source control —
see `functions/.env.example` and SRS NFR-05.
