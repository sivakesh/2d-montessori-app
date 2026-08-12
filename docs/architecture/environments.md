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
   file and calls `bootstrapFirebase(options: ..., useEmulators: false)`.
6. Deploy: `firebase deploy --project <env> --only firestore:rules,storage:rules,functions,hosting`.

## Secrets

No application secret currently exists (Phase 0 has no third-party API
keys). When one is needed (e.g. an analytics or maps key used server-side),
it must be set via `firebase functions:secrets:set <NAME> --project <env>`
(Secret Manager), never committed to `functions/.env` or source control —
see `functions/.env.example` and SRS NFR-05.
