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

**Status: Phase 0 (local scaffolding).** No real Firebase project is
connected yet — everything below runs against the local Emulator Suite.
See [`docs/architecture/environments.md`](docs/architecture/environments.md)
for how the real dev/staging/prod projects get wired in later.

## Prerequisites

| Tool | Version used to build this scaffold |
|---|---|
| Flutter | 3.41.6 (stable channel, Dart 3.11.4) |
| Node.js | 20.x |
| Firebase CLI | 15.x (`npm install -g firebase-tools`) |
| JDK | **21 or newer** — required by the Firestore/Database emulators. Recent `firebase-tools` checks the Java version at startup for *any* `emulators:start`/`emulators:exec` invocation, even runs that only request Auth/Storage/Functions, so this is required to run the emulators at all, not only when using Firestore. `brew install openjdk@21` on macOS. |

## Repository layout

```
apps/public_web/     Public website (Flutter web)
apps/admin_web/      Admin/CMS portal (Flutter web)
packages/            core_contracts, design_system, firebase_adapters,
                      and 16 feature_* packages — see repository-structure.md
functions/            Cloud Functions (TypeScript)
firebase/             Firestore/Storage rules, indexes, emulator fixtures
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

**Terminal 2 — run an app:**

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
in Phase 0 there is nothing to configure here yet, since only the local
emulator tier exists.

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

### Security rules

`firebase/firestore.rules` and `firebase/storage.rules` currently
implement a deny-by-default baseline (public read only on `published*`/
`public*` collections). Validate them with the emulator:

```bash
firebase emulators:start --project demo-montessori-2d --only firestore,storage
```

A real positive/negative rules test suite (`@firebase/rules-unit-testing`)
is added once role-based rules exist in Phase 1/2 — see the TODO in
`.github/workflows/ci.yml`'s `security-rules` job.

## Implementation milestones

| Phase | Scope | Acceptance check |
|---|---|---|
| 0 — Scaffolding (this commit) | Workspace, packages, emulator config, CI, docs | This README's commands succeed; no real Firebase project needed |
| 1 — Foundation | Real dev/staging/prod Firebase projects, `feature_identity` (auth + custom claims + role matrix), design tokens finalized | Emulator-based auth/role tests pass; preview channel deploys |
| 2 — CMS Core | `feature_pages` page builder + approved section templates, `feature_media`, `feature_settings`, `feature_publishing`, `feature_audit`, recycle bin | SRS CMS-01–CMS-15 pass end-to-end with role matrix enforced |
| 3 — Public Website | All SRS WEB-01–WEB-15 routes incl. Events, Team, Documents, Admissions, FAQs; global search; SEO/sitemap/redirects | WEB acceptance criteria met; first real Lighthouse/CWV baseline |
| 4 — Enquiry Management | `feature_enquiries` full ENQ-01–07 pipeline | ENQ criteria pass with audit entries; App Check + rate-limit verified |
| 5 — Trust & Hardening | Legal/policy pages + cookie consent (LEG-01–05), accessibility/performance tuning, backup/restore drill | SRS NFR-01–12 targets met; SRS §14 checklist closed |
| 6 — Launch & Handover | Production cutover, DNS/SSL/Search Console, editor training, runbooks | SRS §13 acceptance-by-capability table passes; sign-off recorded |

## Contributing

See [`analysis_options.yaml`](analysis_options.yaml) for the shared lint
baseline and `docs/architecture/repository-structure.md` for package
boundary rules (no feature-to-feature imports; only barrel-file imports
across package boundaries).
