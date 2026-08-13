# Repository structure

Modular monolith at the client/Firebase boundary (PRD §11.1). "No
dependencies" means no *direct feature-to-feature* dependency — features
communicate only through `core_contracts`, never by importing each other.

```
apps/public_web/     Public site composition root (routing, bootstrap, shell)
apps/admin_web/      Admin/CMS composition root (routing, auth gate, shell)

packages/core_contracts/     Shared kernel — Dart only, no Flutter, no Firebase
packages/design_system/      Tokens + accessible responsive primitives — Flutter only, no feature imports
packages/firebase_adapters/  Firebase SDK adapters + environment/emulator bootstrap

packages/feature_identity/       Auth session, profile, claims, authorization gates
packages/feature_pages/          Managed pages, approved section-type registry, editor,
                                  preview, public rendering (Phase 1 CMS Core — live)
packages/feature_publishing/     Shared workflow engine (domain/data; no presentation layer
                                  of its own — driven through feature_pages' screens via the
                                  adapter documented below): states, transitions, role
                                  enforcement, scheduling foundation
packages/feature_media/          Media library, uploads, derivatives, consent
packages/feature_programs/       Program collection/detail
packages/feature_experiences/    Experience collection/detail
packages/feature_events/         Events & Announcements (SRS WEB-06)
packages/feature_team/           Staff/Team profiles (SRS WEB-11)
packages/feature_documents/      Downloadable Documents library (SRS WEB-12)
packages/feature_gallery/        Gallery albums/media placements
packages/feature_testimonials/   Testimonials (no rating field — see decisions.md)
packages/feature_news/           Blog/News
packages/feature_faqs/           Centrally managed FAQs (own collection — see decisions.md)
packages/feature_enquiries/      Enquiry capture/assignment/follow-up/export/deletion (SRS ENQ-01..07)
packages/feature_settings/       Brand, nav, footer, SEO defaults, legal pages, cookie config
packages/feature_audit/          Append-only activity log

functions/            Trusted Cloud Functions (TypeScript), organized by capability —
                      auth, publishing, media, enquiries, scheduling, redirects, seo, maintenance

firebase/             firestore.rules, storage.rules, firestore.indexes.json, emulator-fixtures/
config/env/           Non-secret per-environment app config (dart-define-from-file)
docs/architecture/    This document, environments.md, decisions.md
```

## Each feature package's internal layout

```
packages/feature_x/
  lib/
    feature_x.dart        # public API barrel — the ONLY import surface other code may use
    src/
      domain/              # entities, value objects, use cases, repository interfaces (no Flutter/Firebase)
      data/                 # DTOs, mappers, Firestore/Storage/Functions repository implementations
      presentation/         # Flutter screens/widgets/state
  test/
```

`domain/` depends on nothing but `core_contracts`. `data/` depends on its
own `domain/` interfaces plus `firebase_adapters`. `presentation/` depends
on its own `domain/` use cases plus `design_system`. No file outside
`feature_x` may import anything under `feature_x/lib/src/` — only the
barrel file.

## Dependency-wiring decision

Each feature package is added to an app's `dependencies:` only in the
milestone that actually implements its screens, so every dependency
addition is traceable to real work rather than speculative wiring:

- `apps/admin_web` depends on `core_contracts`, `design_system`,
  `firebase_adapters`, `feature_identity` (Phase 1 Foundation: auth,
  custom claims, role matrix, user management) **and, as of Phase 1 CMS
  Core, `feature_publishing` and `feature_pages`**. `feature_publishing`
  is a direct dependency even though `feature_pages` re-exposes its
  workflow use cases through `PageEditorController`, because
  `admin_web/lib/main.dart` also needs `feature_publishing`'s
  `PublishingStatus`/`PublishingAction` types directly when composing
  that controller. The remaining feature packages land here as later
  milestones build their admin screens.
- `apps/public_web` depends on `core_contracts`, `design_system`,
  `firebase_adapters` **and, as of Phase 1 CMS Core, `feature_pages`**
  (slug resolution, section rendering) plus the SDK-provided
  `flutter_web_plugins` and `web` packages (real `/slug` URLs and SEO
  `<head>` updates — see `decisions.md`'s SEO-limitation section).
  `feature_identity` is still deliberately never a dependency of the
  public site, since public visitors never authenticate (see
  `apps/public_web/lib/main.dart`'s doc comment).

## Cross-cutting UI infrastructure: `AdminNavEntry`

`feature_identity`'s `AdminShell` (the authenticated admin app's Home-
plus-drawer shell) does not hardcode which non-Home sections exist. It
accepts a `List<AdminNavEntry>` from whichever caller builds it —
`AuthGate`'s optional `adminSections` callback threads them through from
`apps/admin_web/lib/main.dart`, the one place allowed to depend on every
feature package. This is what lets `feature_pages`' "Pages" nav entry
exist without `feature_identity` ever importing `feature_pages` (which
the "no feature-to-feature imports" rule above would otherwise forbid) —
see `AdminNavEntry`'s own doc comment for the full reasoning. Any future
feature adding an admin screen follows the same pattern: build an
`AdminNavEntry` in `admin_web/lib/main.dart`, not inside
`feature_identity`.

See the root README's "Implementation milestones" section.

## Why Dart pub workspaces instead of Melos

Flutter 3.41.6 / Dart 3.11 support native [pub
workspaces](https://dart.dev/tools/pub/workspaces): a `workspace:` list in
the root `pubspec.yaml` plus `resolution: workspace` in each member
resolves every app/package in one `flutter pub get`, with one shared
`pubspec.lock`. This removes the need for Melos as an extra dependency —
if cross-package scripted commands (bootstrap, versioned publishing,
selective test runs) become painful later, revisit that decision, but it
is not needed for Phase 0/1.
