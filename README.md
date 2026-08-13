# 2D Montessori — Website & CMS

Flutter Web + Firebase monorepo for the 2D Montessori public website and
admin/CMS portal. Requirements baseline: `Requirements/2D_Montessori_Phase_1_SRS.pdf`
(authoritative for scope/roles/workflow) and
`Requirements/2D_Montessori_Product_Requirements_and_Architecture_Specification_v1.1.pdf`
(authoritative for technical detail where it doesn't conflict). See
[`docs/architecture/decisions.md`](docs/architecture/decisions.md) for the
full conflict log and locked decisions, and
[`docs/architecture/repository-structure.md`](docs/architecture/repository-structure.md)
for the package layout rationale.

**Status: Phase 1 Foundation (identity & security), Phase 1 — CMS
Core's `feature_publishing` (shared workflow engine) and `feature_pages`
(the first complete CMS content type — creation, review, approval,
publishing, scheduling and public rendering) are all code-complete and
verified green in CI (JDK 21, emulator-backed).** No real Firebase
project is connected yet, and nothing in this repository has been
deployed anywhere — everything below runs against the local Emulator
Suite. See
[`docs/architecture/environments.md`](docs/architecture/environments.md)
for how the real dev/staging/prod projects get wired in later, and
[`docs/architecture/decisions.md`](docs/architecture/decisions.md)'s
"Phase 1 Foundation", "Phase 1 — CMS Core: `feature_publishing`" and
"Phase 1 — CMS Core: `feature_pages`" sections for what each milestone
added and what remains genuinely unverified.

## Prerequisites

| Tool | Version used to build this scaffold |
|---|---|
| Flutter | 3.41.6 (stable channel, Dart 3.11.4) |
| Node.js | 20.x |
| Firebase CLI | 15.x (`npm install -g firebase-tools`) |
| JDK | **21 or newer** — required by the Firestore/Database emulators. Recent `firebase-tools` checks the Java version at startup for *any* `emulators:start`/`emulators:exec` invocation, even runs that only request Auth/Storage/Functions, so this is required to run the emulators at all, not only when using Firestore. `brew install openjdk@21` on macOS. |

## Repository layout

```
apps/public_web/     Public website (Flutter web) — no auth; renders published Pages by
                      slug as of Phase 1 CMS Core (feature_pages)
apps/admin_web/      Admin/CMS portal (Flutter web) — feature_identity-gated (Phase 1
                      Foundation); Pages list/editor/workflow as of Phase 1 CMS Core
packages/            core_contracts, design_system, firebase_adapters,
                      feature_identity (auth/roles/users, Phase 1 Foundation),
                      feature_publishing (workflow engine domain/data, no presentation
                      layer of its own), feature_pages (Pages content type — domain,
                      data, admin + public presentation, Phase 1 CMS Core — live), and
                      13 other feature_* packages — see repository-structure.md
functions/            Cloud Functions (TypeScript) — src/auth, src/publishing, src/pages
                      and src/scheduling (scheduled-publish executor) are implemented;
                      the rest (media, enquiries, ...) are stubs
firebase/             Firestore/Storage rules (users/{uid}; content/{contentId} +
                      transitions/ + revisions/; publishedPages/{slug}; auditLogs — all
                      live), indexes, emulator fixtures, and firebase/test/ (rules +
                      auth-emulator tests)
config/env/            Non-secret per-environment app config
docs/architecture/     Decisions, environments, Firestore model
Requirements/           Source SRS / PRD documents
```

## Setup

```bash
git clone <this-repo>
cd montessori_cms_app

# Resolves every app/package in one go via Dart pub workspaces
# (root pubspec.yaml declares the `workspace:` list; see
# docs/architecture/repository-structure.md).
flutter pub get

# Cloud Functions dependencies
cd functions && npm install && cd ..
```

## Running the apps (against the local Emulator Suite)

Both apps currently boot straight into the Emulator Suite via the safe
`demo-montessori-2d` project — no real Firebase project setup is required
to run them locally today.

**Terminal 1 — start the emulators:**

```bash
firebase emulators:start --project demo-montessori-2d
```

This starts Auth (`:9099`), Firestore (`:8080`), Storage (`:9199`),
Functions (`:5001`) and the Emulator UI (`:4000`). Cloud Functions are
built from `functions/lib` — run `npm --prefix functions run build` first
(or `build:watch` while iterating) so the Functions emulator has something
to load.

**Terminal 2 — seed the first Super Admin (once per fresh emulator run), then run an app:**

A brand-new emulator has no users at all, and account creation
(`createUser`) requires an existing active Super Admin caller — nothing
can bootstrap itself. Run this once after each `firebase emulators:start`
(emulator data isn't persisted between runs unless you pass
`--export-on-exit`/`--import`):

```bash
cd functions
npm run seed:super-admin -- super-admin@example.test "SomePassword1" "Sam Super Admin"
```

Then sign into `admin_web` with that email/password:

```bash
cd apps/public_web && flutter run -d chrome
# or
cd apps/admin_web && flutter run -d chrome
```

## Environment configuration

Non-secret app config (site timezone, feature flags) is supplied via
`--dart-define-from-file`; see
[`config/env/README.md`](config/env/README.md). Firebase *project*
configuration (which project a build targets) is handled separately per
[`docs/architecture/environments.md`](docs/architecture/environments.md) —
there is nothing to configure here yet, since only the local emulator
tier exists (no real dev/staging/prod project has been created).

## Building

```bash
# Public site
cd apps/public_web && flutter build web

# Admin portal
cd apps/admin_web && flutter build web

# Cloud Functions
cd functions && npm run build
```

Production/staging builds require the real Firebase projects and
generated `firebase_options_<env>.dart` files described in
`docs/architecture/environments.md` — not available in Phase 0.

## Testing

```bash
# Every app + package (what CI runs — see .github/workflows/ci.yml)
flutter pub get
for dir in apps/* packages/*; do (cd "$dir" && flutter test); done

# A single package
cd packages/core_contracts && flutter test    # or `dart test` — it's Dart-only

# Static analysis / formatting
flutter analyze
dart format --output=none --set-exit-if-changed .

# Cloud Functions
cd functions
npm run lint
npm run build
npm test
```

### Emulator-dependent tests (Auth, Firestore/Storage rules, Cloud Functions callables)

These need JDK 21+; JDK 21 was not installed in this development
environment (by explicit instruction), so every emulator-dependent
suite is **authored and statically type-checked (`tsc --noEmit`, against
the strict compiler options in `functions/tsconfig.json`) locally, then
run for real in CI** (GitHub Actions installs JDK 21). Phase 1 Foundation
(auth callables, Firestore/Storage rules, disabled-account sign-in) and
Phase 1 CMS Core / `feature_publishing` (`content.rules.test.ts`,
`publishing.functions.test.ts`) are green as of CI run
[`31614601637`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31614601637).
Phase 1 CMS Core / `feature_pages`'s emulator suites
(`content.rules.test.ts`'s new `revisions` coverage,
`pages.functions.test.ts`, `scheduling.functions.test.ts`) are green as
of CI run
[`31674647530`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31674647530)
— see `docs/architecture/decisions.md`'s "Phase 1 — CMS Core:
`feature_pages`" section for the full history, including two real bugs
CI caught and their fixes. Run them yourself once a JDK 21+ is
available:

```bash
# Cloud Functions callables (createUser, setUserRole, setUserStatus,
# resetUserPassword, completeFirstLogin, createDraft, transitionContent,
# createPage, updatePageContent, transitionPage, restorePageRevision)
# and the scheduled-publish executor, against real Auth + Firestore emulators
cd functions && npm run test:emulator

# Firestore/Storage security rules positive/negative cases, plus
# disabled-account sign-in behavior
cd firebase/test && npm install && npm run test:against-emulators
```

`.github/workflows/ci.yml`'s emulator-backed job installs a JDK and runs
both suites above for real, against the Emulator Suite. Check that job's
latest run for the actual pass/fail signal.

## Implementation milestones

| Phase | Scope | Acceptance check |
|---|---|---|
| 0 — Scaffolding | Workspace, packages, emulator config, CI, docs | This README's commands succeed; no real Firebase project needed — **done** |
| 1 — Foundation | `feature_identity` (email/password auth, custom claims, SRS §3 role matrix, forced first-login change, admin user management, role-based Firestore/Storage rules for `users`/`auditLogs`) — **done, verified in CI**. Still open: the real dev/staging/prod Firebase projects (not created — out of this milestone's scope by explicit instruction), design tokens finalization | Dart + Cloud Functions unit tests pass (done, 141/141); emulator-based auth/role/rules tests pass in CI, run [`31610954681`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31610954681) — **all green** |
| 2 — CMS Core | `feature_publishing` shared workflow engine — **code-complete, verified in CI**. `feature_pages` (first complete CMS content type: creation/review/approval/publish/schedule/public rendering, 9 approved section types, revision history, scheduled-publish executor) — **code-complete, verified in CI**. Remaining: `feature_media`, `feature_settings`, `feature_audit` viewer UI, recycle bin | SRS CMS-01–CMS-15 pass end-to-end with role matrix enforced; `feature_publishing` Dart 39/39 + Cloud Functions unit 107/107, emulator suites all green in CI run [`31614601637`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31614601637); `feature_pages` Dart 54/54 + Cloud Functions unit 160/160 (total, incl. publishing) pass locally, emulator suites (Pages callables, scheduling executor, `content`/`revisions` rules) all green in CI run [`31674647530`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31674647530) — **all green** |
| 3 — Public Website | All SRS WEB-01–WEB-15 routes incl. Events, Team, Documents, Admissions, FAQs; global search; SEO/sitemap/redirects | WEB acceptance criteria met; first real Lighthouse/CWV baseline |
| 4 — Enquiry Management | `feature_enquiries` full ENQ-01–07 pipeline | ENQ criteria pass with audit entries; App Check + rate-limit verified |
| 5 — Trust & Hardening | Legal/policy pages + cookie consent (LEG-01–05), accessibility/performance tuning, backup/restore drill | SRS NFR-01–12 targets met; SRS §14 checklist closed |
| 6 — Launch & Handover | Production cutover, DNS/SSL/Search Console, editor training, runbooks | SRS §13 acceptance-by-capability table passes; sign-off recorded |

## Contributing

See [`analysis_options.yaml`](analysis_options.yaml) for the shared lint
baseline and `docs/architecture/repository-structure.md` for package
boundary rules (no feature-to-feature imports; only barrel-file imports
across package boundaries).
