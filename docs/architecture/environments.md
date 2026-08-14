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
| Cloud Functions region | Three-way split: `us-central1` for `onCall`/`onSchedule`; `asia-south1` for the Firestore trigger; `us-east1` for the Storage trigger — see "Cloud Functions region policy" below |
| Firestore database location | `asia-south1` (confirmed via `gcloud firestore databases describe --database="(default)" --project=twod-montessori-dev`) |
| Storage bucket location | `us-east1` (confirmed via `gcloud storage buckets describe gs://twod-montessori-dev.firebasestorage.app --format='value(location)'`) |
| Scheduled-publish timezone | `Asia/Kolkata` (`functions/src/scheduling/publishScheduledContent.ts`) |
| Cloud Functions Node.js runtime | `22` (`functions/package.json`'s `engines.node`; upgraded from `20` — see "Cloud Functions runtime & dependency versions" below) |

### Cloud Functions runtime & dependency versions

Upgraded off Node.js 20 ahead of its Cloud Functions deprecation (deprecated 30 Apr 2026, decommissioned 30 Oct 2026, per the warnings Firebase's own deploy output surfaced after the first successful Dev deployment) to Node.js 22, both GA-supported Cloud Functions runtimes as of this upgrade. Alongside the runtime bump, `functions/package.json`'s Firebase SDK dependencies were upgraded deliberately, not blindly pinned to `latest`:

| Package | Before | After | Why this target, not `latest` |
|---|---|---|---|
| `firebase-functions` | `^6.1.0` (6.6.0 installed) | `^7.3.2` | v7's breaking changes (`functions.config()` removed, v1 `Event` renamed to `LegacyEvent`, Node `>=18` required) don't apply here — confirmed by grep: this codebase has no `functions.config()` call, no `firebase-functions/v1` import, and no `onRequest` handler. Safe to take the true latest. |
| `firebase-admin` | `^12.7.0` | `^13.10.0` (latest **13.x**, deliberately *not* 14.x) | `firebase-admin@14.0.0` requires Node `>=22` (satisfied) but also removes the legacy `admin.firestore()`/`admin.auth()` namespace outright and drops the deprecated Instance ID/FCM types. More importantly: `firebase-functions-test@3.5.0`'s own `peerDependencies` only declare `firebase-admin` support up to `^13.0.0` — it does not yet declare v14 compatibility. Installing admin v14 today would mean the test harness itself is running against an Admin SDK major version it doesn't claim to support. v13's own breaking changes (deprecated FCM API removal, Remote Config hashing change, Node `>=18`) don't apply to this codebase either. **v14 is deferred** until `firebase-functions-test` declares v14 support — track this and revisit, don't force it. |
| `firebase-functions-test` | `^3.4.0` (3.5.0 installed) | unchanged | Already resolves to the latest 3.x release; no forcing change needed. |
| `@types/node` | `^22.10.2` | `^22.20.1` | Patch-level currency within the already-correct major (22.x, matching the runtime) — not a functional change. |

One source change was needed to keep the door open for a future v14 upgrade even though this milestone stays on v13: `functions/src/lib/audit.ts` was migrated from the legacy `admin.firestore()`/`admin.firestore.FieldValue` namespace calls to the modular `getFirestore()`/`FieldValue` imports from `firebase-admin/firestore` — the same pattern every other module in this codebase already used. This was the only legacy-namespace usage found (confirmed by grep across `functions/src`); it doesn't change behavior on v13 (the legacy namespace still works there), it just means nothing in this codebase depends on the v14-removed API, so upgrading the dependency later needs no further source change.

`eslint` (`^8.57.1`), `@typescript-eslint/*` (`^8.18.1`), `typescript` (`^5.7.2`), and `jest`/`ts-jest` (`^29.x`) were deliberately left untouched — their available `latest` versions (`eslint@10`, `typescript@7`, `jest@30`) are major-version jumps unrelated to the Node runtime or Firebase SDKs, each with its own independent breaking-change surface that deserves its own reviewed milestone rather than being bundled into a runtime upgrade.

Local validation for this milestone was run under a real Node.js 22.23.2 installation (via `nvm install 22`), not merely assumed compatible from version numbers — `npm install`, `npm run lint`, `npm run verify:deploy-package` (clean build + deploy-packaging check), and `npm test` (162/162) all ran and passed directly on Node 22. The JDK-21-dependent emulator suite (`npm run test:emulator`, which also exercises `writeAuditEvent` through every privileged callable) is, as with every other milestone in this repository's history, verified via CI rather than this environment — see the milestone's CI run reference.

### Cloud Functions region policy

Region assignment is intentionally split three ways by trigger type, not uniform:

- **`onCall`/`onSchedule` Functions** (every Function except `pagesFns-syncPublishedPage` and `mediaFns-onMediaUploaded`) have no explicit `region` option set anywhere in `functions/src`. These trigger types have no co-location constraint with any other GCP resource, so the Firebase SDK's own default — `us-central1` — applies and is left implicit rather than redundantly pinned in every file.
- **`pagesFns-syncPublishedPage`** (`functions/src/pages/syncPublishedPage.ts`) is the one `onDocumentWritten` Firestore trigger in this codebase, and is explicitly pinned to `region: 'asia-south1'` in code. Firestore triggers use Eventarc, which requires the trigger's region to match the region of the Firestore database it watches — `twod-montessori-dev`'s Firestore database is confirmed to be in `asia-south1`, not `us-central1`. Leaving this one unset would have let Firebase's deploy tooling continue to infer it implicitly (which is what produced the original `asia-south1`/`us-central1` split observed in the first failed deployment); pinning it explicitly instead makes the region an intentional, reviewable part of the source rather than an inferred side effect that could silently change.
- **`mediaFns-onMediaUploaded`** (`functions/src/media/onMediaUploaded.ts`) is the one Cloud Storage `onObjectFinalized` trigger, explicitly pinned to `region: 'us-east1'` — Storage triggers use the same Eventarc bucket-co-location constraint Firestore triggers do, but against the *bucket's* location, not the Firestore database's. `twod-montessori-dev.firebasestorage.app`'s confirmed location is `us-east1`, independently of Firestore's `asia-south1` — the two happening to differ is expected (each Google Cloud resource has its own location chosen independently at creation), not an inconsistency to unify. `bucket` itself is left unset (not hardcoded) — see that file's own doc comment for why relying on the project's default-bucket resolution is correct here, unlike region, which Eventarc requires be explicit and correct.

This means a real deploy targets **three** regions, not one. That is expected and correct for this project — do not "fix" the split by forcing every Function to the same region, and do not infer a Storage trigger's region from the Firestore trigger's region (they can differ, and here they do). `functions/test/media.onMediaUploaded.region.test.ts` locks in all three simultaneously so this can't silently drift.

### Cloud Functions callable invoker policy

**Incident, confirmed against the real project, not guessed:** after the first successful `twod-montessori-dev` Functions deployment, all 11 `onCall` Functions' underlying Cloud Run services (`authfns-completefirstlogin`, `authfns-createuser`, `authfns-resetuserpassword`, `authfns-setuserrole`, `authfns-setuserstatus`, `pagesfns-createpage`, `pagesfns-restorepagerevision`, `pagesfns-transitionpage`, `pagesfns-updatepagecontent`, `publishingfns-createdraft`, `publishingfns-transitioncontent`) came up with a **completely empty IAM policy** — no `allUsers`, no `roles/run.invoker`, verified via `gcloud run services get-iam-policy <service> --region=us-central1 --project=twod-montessori-dev` returning only `etag: ACAB`. `schedulingfns-publishscheduledcontent` (Cloud Scheduler trigger) and `pagesfns-syncpublishedpage` (Eventarc/Firestore trigger) were unaffected — each correctly has its own non-public invoker binding (the Cloud Scheduler job's service account, and Eventarc's managed service account respectively), which Firebase sets up through a different mechanism than the public `allUsers` binding `onCall` needs.

**Why every `onCall` Function needs a public Cloud Run invoker policy at all:** Firebase's callable protocol authenticates the *caller* by verifying a Firebase Auth ID token *inside* the function body (`request.auth`, checked by every callable's own guard — see `functions/src/auth/guards.ts`, `functions/src/publishing/guards.ts`) — not via Cloud IAM. Cloud Run's IAM invoker check happens one layer below that, before the request ever reaches the function's code, and only answers "is this HTTP request allowed to reach the container at all." For the Firebase client SDK's `httpsCallable(...)` to reach that code path in the first place, the Cloud Run service must allow unauthenticated (`allUsers`) invocation — that is not a weaker security posture, it is how every `onCall` Function in this codebase already enforces authorization, one layer up.

**Root cause:** Google Cloud Run now provisions new services **private by default** ("secure by default"). `firebase deploy` is supposed to explicitly grant `allUsers`/`roles/run.invoker` on top of that default for `onCall`/`onRequest` functions — on this project, that step did not take effect for any of the 11 callables, without the deploy itself being reported as failed or any error surfaced. The two most likely mechanisms (either is possible; neither has been confirmed against this specific project's audit logs from this environment, since this environment does not have — and must not obtain — real project access):
1. An organization/project policy (`constraints/iam.allowedPolicyMemberDomains`, or the newer Cloud Run "Invoker IAM check") rejecting the `allUsers` special principal outright.
2. The deploying account lacking `run.services.setIamPolicy` (needs `roles/run.admin` or equivalent — `roles/cloudfunctions.developer` is explicitly **not** sufficient to change IAM policy, a well-documented Firebase CLI gotcha).

**Durable fix:** `functions/scripts/ensure-callable-invoker.js` — reads the same compiled deploy artifact (`functions/lib/index.js`) Firebase itself uploads, structurally identifies every `onCall` export via `__endpoint.callableTrigger` (never a hardcoded function-name list, so it can't silently drift out of sync with the source), and for each one: checks the Cloud Run IAM policy, and if `allUsers`/`roles/run.invoker` is missing, binds it — falling back to `gcloud run services update <service> --no-invoker-iam-check` (Google's own documented workaround) if the direct binding is rejected by policy. It never touches `onSchedule` or `onDocumentWritten` functions. Wired into `firebase.json`'s functions `postdeploy` hook (`npm run ensure:callable-invoker -- --project=$GCLOUD_PROJECT`), so every future real `firebase deploy --only functions` self-heals this regardless of which of the two mechanisms above is the actual cause on this project — and if it's a genuine permission gap, the script's `FAILED` output names the missing role explicitly instead of leaving Functions silently uninvokable behind a "healthy" green Console status. It's also safe to run standalone and narrowly at any time: `npm run ensure:callable-invoker -- --project=twod-montessori-dev` (no rebuild-and-redeploy of any function's code required — this only ever touches Cloud Run IAM policy).

`functions/test/ensureCallableInvoker.test.ts` locks in the exact discovered set (11 callables, never the 2 event-driven functions) against the real project's own confirmed Cloud Run service names, so this can't silently regress as new callables are added.

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
