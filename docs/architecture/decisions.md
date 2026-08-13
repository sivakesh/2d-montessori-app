# Architecture decisions and requirements conflict log

Precedence, per project instruction: **the Phase 1 SRS (`2D_Montessori_Phase_1_SRS.pdf`) is authoritative
for scope, roles, workflow and acceptance criteria.** The PRD/Architecture
Spec v1.1 (`2D_Montessori_Product_Requirements_and_Architecture_Specification_v1.1.pdf`)
governs technical/architecture detail where it does not conflict. Any
future scope addition must go through the SRS §17 change-control process.

## Confirmed Phase 1 modules (approved, not optional)

The SRS mandates these; the PRD v1.1 omits or under-specifies some of them.
Where they conflict, the SRS wins:

- **Events and Announcements** (SRS WEB-06) — entirely absent from the PRD's
  routes/content models. New `feature_events` package + `events` /
  `publishedEvents` collections.
- **Staff and Team Profiles** (SRS WEB-11) — absent from the PRD. New
  `feature_team` package + `team` / `publishedTeam` collections.
- **Downloadable Documents Library** (SRS WEB-12) — the PRD only models
  generic `kind: document` media, with no classification/versioning
  domain. New `feature_documents` package + `documents` /
  `publishedDocuments` collections, extending the media library rather
  than replacing it.
- **Admissions information** (SRS WEB-05) — informational page only (process,
  eligibility, documents needed, FAQs, brochure, CTAs); no `/admissions`
  route exists in the PRD's Information Architecture table. Added as a
  Managed page.
- **Enquiry management** (SRS ENQ-01..ENQ-07) — full capture, assignment,
  follow-up, reminders, export and Super-Admin deletion pipeline. The PRD
  §13 suggests avoiding an "open enquiry database" in favor of mailto/tel/
  WhatsApp links "unless a protected form is separately approved" — the
  SRS's explicit ENQ module **is** that approval. New `feature_enquiries`
  package + private `enquiries`/`followUps` collections (no public read
  model), enquiry creation goes through a callable Cloud Function only,
  never a direct client write, to satisfy the PRD's underlying security
  concern about an unprotected open form.

## Other SRS vs. PRD conflicts and how Phase 0 resolves them

| Conflict | Resolution |
|---|---|
| Shared categories/tags & automatic related-content: SRS §2.2 excludes them; PRD's Experience/Article models assume a shared taxonomy. | **Locked decision (user, 2026-08-12): drop shared taxonomy.** `feature_experiences`/`feature_news` use local free-text labels only, not a shared `categories`/`tags` collection; related content is manually curated per SRS CMS-12. |
| Testimonial `rating` field: SRS §2.2/WEB-10 explicitly exclude ratings; PRD §6.5 schema includes an optional 1–5 rating. | **Locked decision (user, 2026-08-12): omit entirely.** No rating field anywhere in `feature_testimonials`' Phase 1 data model. |
| MFA for Publisher/Super Admin: SRS AUTH-02 specifies email/password only; PRD recommends MFA for privileged roles. | **Locked decision (user, 2026-08-12): defer to Phase 2.** Phase 1 auth is email/password only, per SRS. |
| Role naming: SRS has 3 roles (Editor, Publisher, Super Admin) with an exact capability matrix (SRS §3); PRD has 5 (adds Public visitor, System service). | Use SRS's 3 human roles and capability matrix as canonical. "Public visitor" isn't an account. "System service" is implemented as a non-interactive Cloud Functions identity, not a selectable role. |
| Flutter Web SEO/Core Web Vitals risk: SRS NFR-03/04 require Lighthouse ≥90 and strict CWV budgets; PRD's own SEO NFR admits "Flutter implementation must prove crawlability in staging." | Real technical risk, not a document conflict. Mitigation: HTML renderer (not CanvasKit) for the public shell, prerendered/static snapshots for `publishedPages/*` routes for crawlers and first paint. Must be proven in Staging per PRD's own acceptance line before Phase 3 is considered done. |

## Locked Phase 0 decisions (asked via clarifying questions, 2026-08-12)

1. **Firebase projects:** fresh **dev / staging / prod** trio, not the
   existing `2dmontessori.com` production project. See
   `docs/architecture/environments.md`.
2. **Testimonial ratings:** omitted entirely (see table above).
3. **Shared taxonomy:** dropped entirely (see table above).
4. **MFA:** deferred to Phase 2 (see table above).

## Phase 1 Foundation (identity & security) — decisions and status

### Identity data model

Role and status live in **both** Firebase Auth custom claims and the
`users/{uid}` Firestore doc, deliberately:

- **Custom claims** (`role`, `status`) are the source Firestore/Storage
  rules and Cloud Functions trust for authorization. Only
  `functions/src/auth` (Admin SDK) ever sets them.
- **Firestore doc** mirrors `role`/`status` (for the User Management list
  and other UI) and additionally holds `displayName`, `photoUrl` and
  `mustChangePassword` — none of which belong in a claim (claims are
  capped at 1000 bytes total and cached in the ID token for up to ~1
  hour, so anything that needs to be immediately fresh, like
  `mustChangePassword`, or is display-only, doesn't belong there).

This means a role/status change made by a Super Admin can take up to ~1
hour to reach the *target* user's cached ID token in the general case.
Three things narrow that window where it matters: (1) Firestore rules
re-check `status` live via Firestore — not the cached claim — for the one
cross-user read they grant (see "Security-rule inconsistency found and
resolved" below), (2) `functions/src/auth/guards.ts`'s
`assertCallerIsActiveSuperAdmin` does the same live re-check before any
Cloud Function mutation, and (3) suspending a user calls
`revokeRefreshTokens` and disables the Auth account outright, which
blocks new sign-ins immediately even though it doesn't retroactively
invalidate an already-issued, unexpired ID token — a documented Firebase
platform limitation, not an oversight here.

### Security-rule inconsistency found and resolved (Foundation Verification checkpoint)

The Phase 1 Foundation report claimed Firestore rules "re-check status
live via Firestore for privileged operations," citing
`firebase/firestore.rules`. That was only true of the Cloud Functions
guard (`assertCallerIsActiveSuperAdmin`) — the **rules file itself**
checked only `request.auth.token.status`, the cached claim, for the one
cross-user read it grants (a Super Admin reading another user's profile
in User Management). Since a suspended Super Admin's already-issued ID
token keeps its old claims for up to ~1 hour, that version of the rule
would have let a just-suspended Super Admin keep reading every other
user's profile for the rest of that window — a real gap, not just
inconsistent documentation, caught by explicit review at this checkpoint.

**Fix:** `firebase/firestore.rules` now defines `isActiveSuperAdmin()`,
which re-checks the caller's status via a live `get()` on their own
`users/{uid}` doc — the same pattern the Cloud Functions guard already
used — rather than trusting the token's cached claim. Self-read of one's
own document is unaffected (still claim-independent, always allowed,
since it grants no privilege beyond seeing your own state). See the
rules file's own header comment for the full reasoning, and
`firebase/test/firestore.rules.test.ts`'s "denies a Super Admin
cross-user read when their cached token is stale" test, which seeds the
caller's Firestore doc as suspended while authenticating them with
claims that still say active — the scenario a claims-only check would
have missed.

### Last-active-Super-Admin guard, including under concurrent requests

`setUserRole` and `setUserStatus` both refuse an operation that would
leave zero active Super Admins (`functions/src/auth/guards.ts`'s
`assertRoleChangeAllowed`/`assertStatusChangeAllowed`), returning a
`failed-precondition` error the client surfaces as `LastSuperAdminFailure`.
The User Management UI also disables the relevant controls proactively
when it can see (from its own already-permitted read of the user list)
that a row is the sole active Super Admin — a UX nicety, not the actual
guard, which is server-side and unconditional.

**Concurrency:** the read (current role/status), the active-Super-Admin
count check, and the eventual write are all performed inside a single
Firestore transaction (`db.runTransaction(...)` in `setUserRole.ts` /
`setUserStatus.ts`), with the count read via `transaction.get(query)`
rather than a standalone query. The original version of this guard read
the count as a plain, non-transactional query before writing — two
concurrent requests demoting/suspending two different Super Admins when
exactly two existed could each have read "2 active" before either write
landed, and both would have proceeded, leaving zero. Firestore tracks a
query read inside a transaction as part of that transaction's read set:
any write that could change the query's result before the transaction
commits forces an automatic retry. Wrapping the whole sequence in one
transaction makes the two concurrent requests serialize correctly —
whichever commits first sees count=2 and succeeds; the other retries,
then sees count=1 and is correctly blocked. Proven by
`functions/test/emulator/auth.functions.test.ts`'s "never suspends/
demotes both of the last two active Super Admins concurrently" tests,
which fire both requests via `Promise.allSettled` and assert exactly one
succeeds.

### Password policy

Minimum 8 characters, at least one letter and one digit
(`feature_identity`'s `PasswordPolicy` and `functions/src/auth/validators.ts`'s
`isPasswordPolicyCompliant`, kept numerically in sync by comment
cross-reference, not shared code — Dart vs. TypeScript). The SRS does not
specify a password complexity policy; this is a reasonable baseline
**pending stakeholder confirmation**, called out explicitly rather than
silently assumed permanent. **Explicitly retained unchanged at the
Foundation Verification checkpoint** — each side has exactly one place
(`PasswordPolicy.minLength`/`validate` in Dart,
`MIN_PASSWORD_LENGTH`/`isPasswordPolicyCompliant` in TypeScript) that
defines the policy, so strengthening it later (e.g. an uppercase or
special-character requirement) means editing those two functions, not
hunting through every screen/callable that collects a password.

### Self-service password reset vs. AUTH-01's "no invitation email"

SRS AUTH-01 excludes invitation/notification emails from account
*creation* in Phase 1. It does not address self-service "forgot password."
This milestone implements standard Firebase Auth password-reset emails
(`sendPasswordResetEmail`/`confirmPasswordReset`) as a distinct,
standard security feature, not an "invitation" — flagged here as an
interpretation call, not a silent scope addition. **Explicitly confirmed
at the Foundation Verification checkpoint**: this does not conflict with
the decision to avoid invitation-based onboarding and is retained.

### Admin routing

`apps/admin_web` does not use a routing package (e.g. go_router) yet.
`AuthGate` (state-based, not URL-based) switches between screens, and
`AdminShell` uses a simple in-memory `_AdminSection` enum for Home vs.
Users. This keeps Phase 1 Foundation dependency-light; introduce real
URL-based routing when Phase 2/3 adds enough CMS routes that
non-bookmarkable admin URLs become a real cost, not before.

### Test execution status

As of the Foundation Verification checkpoint, this development
environment still has JDK 17/11, not the 21+ `firebase-tools` requires to
run any emulator — per explicit instruction, JDK 21 was not installed
locally. Emulator-dependent suites were instead verified via CI (GitHub
Actions, JDK 21 via `actions/setup-java@v4`) — run
[`31610954681`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31610954681),
**all three jobs green**, is the run that reflects every fix documented
above. Do not treat the `tsc --noEmit` clean-compile below as equivalent
to an executed test — the "Result" column states which is which.

| Suite | Run in this environment? | Result |
|---|---|---|
| Dart unit/widget tests (`core_contracts`, `firebase_adapters`, `feature_identity`, both apps) | Yes (local) | 86/86 passing |
| Cloud Functions unit tests (`functions/test/*.test.ts`, excludes `test/emulator/`) | Yes (local) | 54/54 passing |
| Cloud Functions integration tests (`functions/test/emulator/auth.functions.test.ts`) | Yes (CI run `31610954681`, JDK 21) | Passing |
| Firestore rules tests (`firebase/test/firestore.rules.test.ts`) | Yes (CI run `31610954681`, JDK 21) | Passing |
| Storage rules tests (`firebase/test/storage.rules.test.ts`) | Yes (CI run `31610954681`, JDK 21) | Passing |
| Auth account-status (disabled-user) test (`firebase/test/auth.account-status.test.ts`) | Yes (CI run `31610954681`, JDK 21) | Passing |

Nothing in this row set has been reported as passing without actually
running — see the root README for the same caveat stated for the human
reader.

### Bugs found by CI execution, not by review or `tsc --noEmit`

The point of insisting on real execution rather than "compiles cleanly":
the first CI run against `functions/test/emulator/auth.functions.test.ts`
(GitHub Actions, JDK 21) failed all 15 tests, and it found two genuine
bugs neither `tsc --noEmit` nor eslint had any way to catch:

1. **Production bug**: every callable built its audit event's
   `requestId` via `request.rawRequest?.headers['x-request-id']?.toString()
   ?? fallback`. Optional chaining (`?.`) only guards the property access
   immediately after it — `rawRequest?.headers` short-circuits to
   `undefined` safely, but the following `['x-request-id']` is a plain,
   unguarded index into that `undefined`, so it throws
   `TypeError: Cannot read properties of undefined (reading
   'x-request-id')`. In production this likely never surfaced, because a
   real Express `rawRequest.headers` is always an object; the test
   harness's hand-built `CallableRequest` doesn't have one, which is
   exactly what exposed it. Fixed by extracting the logic into
   `functions/src/lib/requestId.ts`'s `resolveRequestId`, with two
   explicit `?.` guards and unit-testable in isolation.
2. **Test bug**: the same test file asserted rejected-promise codes with
   `.rejects.toThrow(/permission-denied/)` etc. Jest's `.toThrow(regex)`
   matches against the thrown error's `.message`, but `HttpsError`'s
   `.message` is the human-readable text ("Super Admin role required."),
   not the `.code` ("permission-denied") — the regex could never match.
   Fixed with an `expectHttpsErrorCode(promise, code)` helper that checks
   `.rejects.toMatchObject({ code })` instead.

The second CI run then found more, in `firebase/test/`'s suite — this one
took three CI iterations to actually root-cause, recorded honestly below
rather than cleaned up into a story where the first fix worked:

3. **`FirebaseError: Firestore has already been started and its settings
   can no longer be changed`**, on `firestore.rules.test.ts`'s last test
   only, both times it recurred. Two contributing fixes were applied
   before finding the real cause:
   - Attempt 1: `firestore.rules.test.ts` and `storage.rules.test.ts`
     both called `initializeTestEnvironment` with the same
     `projectId: 'demo-montessori-2d'`; gave each file its own
     `demo-`-prefixed project ID instead. Reasonable practice, kept, but
     the next CI run hit the identical error.
   - Attempt 2: `firebase/test/package.json`'s `test:sequential` now
     runs each file as its own separate `jest --runTestsByPath <file>`
     process, in case a reused Jest worker process was sharing SDK state
     across files. Also kept as reasonable defensive isolation, but the
     next CI run *still* hit the identical error — proving the cross-file
     theory wrong, not just insufficiently applied.
   - **Actual cause**: the failing test was the only one in the file
     calling `.firestore()` twice on the same `RulesTestContext`
     (once for a `getDoc`, once for a `setDoc`) — every other test in the
     file performs exactly one operation per context. `RulesTestContext
     .firestore()` is evidently not memoized; a second call re-runs
     Firestore initialization for an app that already has one, which is
     exactly what that error message describes. Fixed by calling
     `.firestore()` once per test and reusing the reference for both
     operations — a one-line change once correctly diagnosed.
4. **Test bug, also multi-attempt**: `auth.account-status.test.ts`'s two
   tests shared one hardcoded email; "allows sign-in while enabled"
   created that account, and "rejects sign-in once disabled" assumed it
   still existed via `adminAuth.getUserByEmail(email)`. CI failed that
   lookup with "There is no user record corresponding to the provided
   identifier."
   - Fix attempt bundled two changes at once: unique per-test emails
     (correct — removed the real cross-test dependency), *and* giving
     this file its own distinct project ID like the Firestore files got
     for bug 3 (by analogy, since it looked like the same shape of
     problem). The next CI run showed this made it *worse*: now even the
     *first* test failed the identical lookup, immediately after its own
     `createUserWithEmailAndPassword` had just succeeded — the client SDK
     write and the Admin SDK read were no longer seeing the same data at
     all.
   - **Actual cause**: unlike the Firestore emulator, the Auth emulator
     does not reliably treat an arbitrary `demo-`-prefixed project ID as
     an independent namespace shared consistently between the Client and
     Admin SDKs. Reverted this file to the same project ID
     `firebase emulators:exec --project` was started with; kept the named
     app instances (`auth-status-test-client`/`-admin`), which already
     provide enough isolation from the *Firestore*-side SDK state that
     was bug 3's actual problem — a problem this file, touching only
     Auth, never had in the first place.

All fixes are covered by a subsequent CI run — see the milestone report
for that run's actual result. Recorded in this much detail specifically
because three of these four fix attempts looked plausible, were
individually reasonable engineering by analogy to a nearby bug, and were
still wrong — a reminder that "a plausible-sounding fix" and "an
actually-verified fix" are not the same claim, which is the entire point
of this checkpoint insisting on
real execution over review or `tsc --noEmit`.

### Foundation Verification: final CI result

CI run [`31610954681`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31610954681)
(`workflow_dispatch`, `feature/montessori-cms-monorepo` branch) is the
run that reflects every fix above — all three jobs green: Cloud Functions
lint/build/unit-test, the Flutter workspace (format/analyze/test), and
the emulator-backed job (Firestore/Storage rules, disabled-account
sign-in, and every auth callable, all against a real JDK 21 emulator
instance). The `test:sequential`/`.firestore()`-once fix (bug 3) and the
project-ID revert (bug 4) are both proven correct by this run, not just
argued for. Updated "Test execution status" table below reflects this.

## Phase 1 — CMS Core: `feature_publishing` (shared publishing workflow)

Traceability: SRS CMS-02, CMS-03, CMS-05, CMS-08; PRD Section 9
(Editorial Workflow and Versioning). Per the milestone boundary agreed
before starting this work, this package implements the workflow engine
only — states, transitions, role enforcement, timestamps/actors, audit,
and the scheduled-publishing foundation — against a minimal reference
content envelope (`contentType` + `title`). It does not implement the
page builder, media library, or any other CMS module; those are later
milestones that compose with this engine rather than reimplementing it.

### States and transitions

Six states — Draft, InReview, Approved, Scheduled, Published, Archived —
with 14 server-enforced edges:

| From | Action | To | Capability required | Extra requirement |
|---|---|---|---|---|
| Draft | submitForReview | InReview | `submitForReview` (full for all 3 roles) | — |
| Draft | archive | Archived | `approveRejectPublish` | — |
| InReview | approve | Approved | `approveRejectPublish` | — |
| InReview | reject | Draft | `approveRejectPublish` | comment required |
| InReview | archive | Archived | `approveRejectPublish` | — |
| Approved | publish | Published | `approveRejectPublish` | — |
| Approved | reject | Draft | `approveRejectPublish` | comment required |
| Approved | schedule | Scheduled | `schedulePublishing` (Publisher/Super Admin only) | `scheduledAt` must be in the future |
| Approved | archive | Archived | `approveRejectPublish` | — |
| Scheduled | publish | Published | `approveRejectPublish` | — |
| Scheduled | unschedule | Approved | `schedulePublishing` | — |
| Scheduled | archive | Archived | `approveRejectPublish` | — |
| Published | unpublish | Archived | `approveRejectPublish` | — |
| Archived | restore | Draft | `approveRejectPublish` | — |

No other `(from, action)` pair has an edge; both the Dart
`PublishingStateMachine` and the TypeScript `resolveTransition` return
`null`/`undefined` for anything not in this table, and the shared engine
on each side (`TransitionContentUseCase` client-side,
`applyTransition.ts` server-side) treats that as a rejection, not a
default no-op. Every action writes a `content/{contentId}/transitions/`
history entry (action, from/to status, actor, actor role, comment,
timestamp) in addition to updating the content doc's own
status/timestamp/actor fields — the transitions subcollection is the
authoritative audit trail for "who did what, when" on a specific piece of
content, distinct from the global `auditLogs` collection.

### Role/capability enforcement — client, server, and rules, in that order of trust

1. **Client (Dart, `TransitionContentUseCase`)**: resolves the edge,
   checks `RolePermissionMatrix.hasFull`, checks comment/schedule
   requirements — all before ever calling the repository. This is
   defense-in-depth/UX only (fails fast, avoids a round-trip for an
   obviously-invalid action); it is never the actual authority.
2. **Server (`functions/src/publishing/applyTransition.ts`)**: the real
   authority. Re-resolves the edge from the content doc's status *as read
   inside a Firestore transaction*, re-checks capability
   (`hasFullCapability`), re-checks comment/schedule requirements, and
   only then writes — all inside that one transaction, so a concurrent
   request can never observe or apply a transition against a status that
   a different request has already moved the content out of (see
   "concurrent transitions" below).
3. **Firestore Rules (`content/{contentId}`, `content/{contentId}/
   transitions/{transitionId}`)**: `allow write: if false` unconditionally
   — no client, regardless of role or claim, can write to either
   collection directly. All mutation goes through the callables above.
   Reads are owner-or-active-Publisher/Super-Admin, using the same live
   `get()`-based `isActivePublisherOrAbove()` re-check pattern established
   for `users/{uid}` at the Foundation Verification checkpoint, for the
   same reason: a cached claim must not outlive a Firestore-recorded
   suspension.

### Concurrent transitions

Proven by `functions/test/emulator/publishing.functions.test.ts`'s "never
applies two conflicting concurrent transitions from the same status to
the same content" test: two different valid actions from the same
starting status (`approve` and `archive`, both valid from `InReview`)
fired concurrently via `Promise.allSettled` at the same content doc.
Because both the status read and the write happen inside one
`db.runTransaction(...)`, whichever commits first moves the doc out of
`InReview`; the other is forced to retry, re-reads the new status, finds
its action no longer has an edge from it, and is rejected with
`failed-precondition` — exactly one of the two succeeds, never both, and
never neither.

### Single parameterized callable, not nine distinct ones

Unlike `feature_identity`'s auth module — five *distinct* callables
because each does meaningfully different work — every publishing action
(`submitForReview`, `approve`, `reject`, `publish`, `unpublish`,
`schedule`, `unschedule`, `archive`, `restore`) shares one
implementation, `applyTransition.ts`, invoked through a single
`transitionContent` callable that takes `action` as a parameter. They
differ only in which edge of the transition table applies — exactly what
`action` selects — so nine near-identical callables would have been
duplication, not additional safety: the same transaction, the same
capability check, the same audit-write call, nine times over. The nine
named Dart use cases (`SubmitForReviewUseCase`, `ApproveContentUseCase`,
...) exist purely to keep call sites readable and each action's
required/optional parameters (e.g. `RejectContentUseCase.comment` and
`ScheduleContentUseCase.scheduledAt` are required, non-nullable
parameters, not optional ones with a runtime check) — they all delegate
to the same `TransitionContentUseCase`.

### Reusable contracts for later content modules

`PublishingRecord`, `PublishingStatus`, `PublishingAction`,
`PublishingStateMachine`, and the publishing `Failure` subclasses live in
`feature_publishing`'s own domain layer, not `core_contracts` — they are
publishing-specific, not shared kernel. The intended reuse shape for
`feature_pages` and later content features is composition: a page's own
Firestore document type wraps or references a `content/{contentId}`
envelope (or stores its own status/workflow fields shaped identically)
rather than each feature reimplementing its own state machine, capability
checks, or transitions history. `RolePermissionMatrix` and `UserRole`
(the actual shared kernel pieces this module depends on) already live in
`core_contracts`, unchanged by this milestone.

### Test execution status (feature_publishing)

| Suite | Run in this environment? | Result |
|---|---|---|
| Dart domain/use-case tests (`packages/feature_publishing/test/`) | Yes (local) | 39/39 passing |
| Cloud Functions unit tests (`functions/test/publishing.*.test.ts`) | Yes (local) | included in the 107/107 total below |
| Firestore rules tests (`firebase/test/content.rules.test.ts`) | Yes (CI run [`31614601637`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31614601637), JDK 21) | Passing |
| Cloud Functions integration test (`functions/test/emulator/publishing.functions.test.ts`) | Yes (CI run [`31614601637`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31614601637), JDK 21) | Passing |

All rows now proven green by real execution — CI run `31614601637` (all
three jobs) is the run that reflects the `--runInBand` fix documented
above; the two emulator-dependent rows were red on the prior run
(`31613980326`) for the cross-file-race reason explained there, not
because of anything wrong with the publishing workflow logic itself.

### Bug found by CI execution: a fifth one, same category as before

The first CI run against the `feature_publishing` commit (`31613980326`)
failed both `test/emulator/publishing.functions.test.ts` **and**
`test/emulator/auth.functions.test.ts` — a file that had passed cleanly
in the immediately preceding CI run. Root cause, read directly from the
failure output rather than guessed:

`test/emulator/` previously had exactly one file. `npm run test:emulator`
runs `jest --roots test/emulator ...` with no `--runInBand`, so Jest used
its default parallel workers — harmless with one file, but as soon as
`publishing.functions.test.ts` existed alongside
`auth.functions.test.ts`, both ran **concurrently, in separate
processes, against the same shared Firestore emulator/project**. Both
files' assertions depend on collection-wide state that isn't scoped per
file:

- `auditLogCount()` counts the entire `auditLogs` collection; a
  `before`/`after` delta assertion in one file is invalidated if the
  other file writes an audit entry in between, in a different process.
- `setUserRole`/`setUserStatus`'s active-Super-Admin guard counts *every*
  `users` doc with `role == 'superAdmin' && status == 'active'`,
  globally — not scoped to a test file. `auth.functions.test.ts`'s
  "blocks demoting the only active Super Admin" test assumes it is the
  only active Super Admin in the whole emulator at that moment; with
  `publishing.functions.test.ts` running concurrently and having just
  seeded its own `workflow-super-admin` (active), the guard correctly
  saw *two* active Super Admins and *correctly* allowed the demotion —
  the test's premise was violated by the other file's concurrent
  activity, not a guard bug. (Confirmed from the actual failure:
  `expect(promise).rejects.toMatchObject(...)` — "Received promise
  resolved instead of rejected".)

**Fix:** `functions/package.json`'s `test:emulator` script now passes
`--runInBand` to Jest, forcing every emulator test file to run fully
sequentially in one process — no file's `beforeAll`/tests/`afterAll` can
overlap with another's. This is the same pattern
`firebase/test/package.json`'s `test:sequential` already uses for the
rules tests, and for the identical underlying reason: these are
integration tests against one shared emulator instance, not unit tests
with isolated state, so cross-file concurrency was never actually safe
here — it simply had nothing to collide with until a second file
existed. **Re-verified by CI run
[`31614601637`](https://github.com/sivakesh/2d-montessori-app/actions/runs/31614601637)**
— all three jobs green, including both previously-failing files.

## Phase 1 — CMS Core: `feature_pages` (first CMS content type)

Traceability: SRS WEB-01..WEB-03, CMS-01..CMS-15; PRD §4 (CMS Page
Builder), §5.1/5.2 (Page/SEO models), §9 (Editorial Workflow). Builds
and verifies the first complete CMS content type end to end — creation,
review, approval, publishing, scheduling and public rendering — on top
of the `feature_publishing` engine verified in the previous milestone.
Does not begin `feature_media`, `feature_settings`, or any other CMS Core
component.

### Pages storage: `content` collection, not a separate `pages` collection

`PublishingRecord`'s doc comment (written in the `feature_publishing`
milestone) explicitly allowed two designs: a content type stores its own
fields "alongside these same envelope fields in their own collection, or
compose with this one." This milestone chose the latter: every `CmsPage`
is a `content/{contentId}` document with `contentType == 'page'`,
carrying the full `feature_publishing` envelope (status, owner,
submitted/reviewed/published/archived timestamps and actors) plus
Pages-specific fields (slug, summary, sections, SEO, ...) side by side in
the same document. `docs/architecture/firestore-model.md`'s earlier
`pages/{pageId}` row (drafted before `feature_publishing` existed) is
retired in favor of this.

Rationale: this requires zero changes to `applyTransition.ts`,
`transitionContent.ts`, or `FirestorePublishingRepository` — the
workflow engine already operates on `content/{contentId}` and needs no
awareness that a document happens to be a page. A separate `pages`
collection would have meant either duplicating the transition engine to
target it, or building a cross-collection abstraction the engine doesn't
have today. The downside — different content types commingled in one
collection, distinguished by `contentType` — is a normal, deliberately
accepted tradeoff at this scale, not a compromise made under time
pressure (CMS-10 "Lists and filters" already implies filtering by type
as an ordinary operation).

### Reused unmodified: `PagesAsPublishingRepository`

`feature_pages` does not duplicate the workflow engine. Its own
`PagesRepository` interface (`createPage`, `updateContent`, `get`,
`list`, `listRevisions`, `restoreRevision`, `transition`) is Pages-
specific and richer than `PublishingRepository`, but
`PagesAsPublishingRepository` adapts it to `feature_publishing`'s
`PublishingRepository` interface, mapping `CmsPage` ↔ `PublishingRecord`
via `CmsPage.toPublishingRecord()`. This lets the admin editor construct
`feature_publishing`'s nine named use cases
(`SubmitForReviewUseCase`, `ApproveContentUseCase`, ...) completely
unmodified — see `PageEditorController` — so every transition's
capability checks, comment/schedule requirements, and edge validation
are the exact same code already tested in the `feature_publishing`
milestone, not a re-implementation. Server-side, `functions/src/pages/
transitionPage.ts` follows the identical pattern: it adds the SRS CMS-08
completeness gate (below) as a pre-flight check, then delegates,
unmodified, to `functions/src/publishing/applyTransition.ts`.

### SRS CMS-08 completeness gate

"Publishing checks required fields, alt text, ... SEO metadata, unique
slug, ... Errors block." Implemented in three layers, in order of trust:

1. **Client** (`PageCompletenessValidator`, Dart) — checked before
   Submit for Review/Publish/Schedule buttons are enabled; UX only.
2. **Server** (`pageCompletenessViolations`, TypeScript,
   `functions/src/pages/completeness.ts`) — re-implements the identical
   rules (hand-synced, not code-shared, the established convention for
   every Dart/TypeScript pair in this codebase), called by
   `transitionPage.ts` only for the three actions that move content
   toward or into public visibility (`submitForReview`, `publish`,
   `schedule`) — `reject`/`archive`/`unschedule`/`restore` are ungated,
   since they only ever need the transition engine's own edge/capability
   checks. This is the actual authority; a client bypassing step 1
   cannot bypass step 2.
3. **Slug uniqueness** specifically is server-only (`assertSlugAvailable`
   in `functions/src/pages/slug.ts`) — it requires a live Firestore query
   only the server can authoritatively answer at submission time, so it
   is deliberately not attempted client-side.

### Editing content: Draft-only, no parallel "live draft copy"

The PRD's editorial-workflow model (§9) describes editing published
content as creating a new draft copy while the published snapshot stays
publicly live — a materially more complex model (parallel versions of
one logical page) than the simpler, SRS-aligned single-document lifecycle
`feature_publishing` already implements and this milestone was
instructed to reuse unmodified. This milestone therefore does **not**
build that PRD model. Instead: `updatePageContent`/`restorePageRevision`
both reject with `PageNotEditableFailure` unless the page's status is
exactly `draft`. To edit a page that is currently Published, an
authorised user calls `unpublish` (Published → Archived) then `restore`
(Archived → Draft) — both transitions `feature_publishing` already
provides — edits it, and republishes. This is a deliberate, documented
scope reduction relative to the PRD, not an oversight: it costs an extra
two clicks for the "edit a live page" flow in exchange for zero changes
to the verified workflow engine.

### SRS CMS-06 revision history

Every successful `updatePageContent`/`restorePageRevision` call appends
a full content-field snapshot to `content/{contentId}/revisions/`, in
the same Firestore transaction as the content write itself (so a
revision can never be recorded without the corresponding change landing,
or vice versa). Revisions are never deleted or overwritten — "restore"
copies a prior revision's fields onto the *current* draft and then
itself appends a new revision entry, so restoring is visible in the
history the same way any other edit is, satisfying CMS-06's "without
erasing the audit trail" literally: nothing is ever erased.

### Public rendering: `publishedPages` is a materialized view, not a filtered `content` read

`apps/public_web` never reads `content` — Firestore Rules deny it
unconditionally to unauthenticated callers, and even if they didn't,
`content` carries fields (`ownerId`, workflow timestamps/actors, revision
history) that must never reach a public response. Instead,
`functions/src/pages/syncPublishedPage.ts` (a Firestore
`onDocumentWritten` trigger on `content/{contentId}`) maintains
`publishedPages/{slug}` as a denormalized, public-safe projection:
present with a fixed field set whenever a page's `status == 'published'`,
absent otherwise. `PublicPageView` (the Dart read model
`FirestorePublicPagesRepository` returns) has no field capable of
carrying `ownerId`/`status`/actor identities even if the document
somehow contained them — the type itself is the enforcement mechanism
for "do not expose administrative fields," not a runtime filter that
could be forgotten.

Chosen as a *trigger* (reactive, decoupled from `transitionPage.ts`)
rather than folded into that callable directly, so (a) `applyTransition.ts`
stays generic and untouched, and (b) Cloud Functions triggers get
automatic retry-on-failure semantics for what is fundamentally a
materialized-view sync, not the workflow transition itself (which
already committed and was already audited by the time this runs).
Editing is Draft-only (see above), so a page's `slug` cannot change while
`published` — this sync therefore never has to reconcile "published under
slug A, now published under slug B" in a single write.

**Related-content resolution — a documented staleness limitation.**
`RelatedContentSection.relatedPageIds` are manual selections (SRS 2.2/
CMS-12 both exclude automatic recommendations); at sync time, each
referenced page is resolved to a display summary *only if it is
currently published*, and the result is cached on the referencing page's
`publishedPages` document as `resolvedRelatedPages`. If a related page is
later unpublished, pages that already reference it keep their cached
(now stale) summary until they are themselves next republished — true
real-time reactivity would require a reverse index recomputing every
referencing page whenever any page's status changes, which is out of
scope for this milestone. Not silently accepted: flagged here as a real,
known limitation.

### Section-type catalogue: narrower than the PRD's, on purpose

The PRD §4.2 catalogue lists 14 section templates (`hero`, `rich_text`,
`image_text`, `feature_grid`, `card_collection`, `stats`, `quote`,
`testimonial_carousel`, `media_gallery`, `video`, `cta_banner`, `faq`,
`spacer_divider`, `contact_block`). This milestone's explicit instruction
enumerated exactly nine approved types, which is what
`packages/feature_pages/lib/src/domain/page_section.dart`'s `sealed
PageSection` implements: rich text, image, image+text, CTA, highlights
(cards), FAQ, gallery, testimonial, related-content. The remaining PRD
templates (`hero`, `stats`, `quote`, `video`, `spacer_divider`,
`contact_block`) are deferred, not silently dropped — a future milestone
can add a new `PageSection` subtype the same way each of these nine was
added, with the sealed hierarchy's exhaustiveness checking forcing every
renderer/validator to handle it.

**FAQ and Testimonial sections store entries inline**, not as references
into a central collection — SRS WEB-09's FAQ module and WEB-10's
Testimonials module (`feature_faqs`/`feature_testimonials`) don't exist
yet, so a reference would point at nothing. Migrating to references once
those modules ship is additive (an optional `faqId`/`testimonialId`
alongside the inline fields), not a redesign.

**Related-content selection is Pages-only** for the same reason: Programs,
Experiences, Events, articles and FAQs (the PRD's full related-content
target set) don't exist as buildable content types yet.

**Rich text is plain, paragraph-separated text, not a structured block
model.** The PRD's "validated structured blocks" rich-text model
(inline bold/italic, lists, etc.) is a meaningfully sized sub-feature on
its own; this milestone's `RichTextSection.body` is a plain `String`
with blank-line paragraph breaks and *no markup of any kind* — which
trivially satisfies "do not store arbitrary executable HTML or scripts"
(there is no markup vocabulary to exploit) while keeping scope bounded.
A richer inline-formatting model is a defensible, scoped-out follow-up.

### Media boundary: `MediaReference`, not `feature_media`

Per explicit instruction, `feature_media` (upload pipeline, processing
status, derivatives, consent workflow) is not built this milestone.
`MediaReference` (`url`, `altText`, optional `storagePath`/`caption`) is
the entire surface `feature_pages` needs — editors paste/enter an
already-hosted URL today; there is no upload UI, no processing-status
gating (SRS MED-05's "Ready before publishing" has nothing to gate on
without a pipeline), and no child-image-consent workflow (SRS MED-06) —
another explicit, documented gap, not an oversight. Wiring a real upload
flow into these same fields once `feature_media` exists is additive.

### `AdminShell`/`AdminNavEntry`: fixing a latent architecture violation

Adding a "Pages" admin nav entry the way "Users" already existed would
have required `feature_identity`'s `AdminShell` to import `feature_pages`
directly — a feature-to-feature dependency this codebase's own stated
rule ("features communicate only through `core_contracts`, never by
importing each other") forbids. Rather than accept the violation,
`AdminShell` was generalized to accept `List<AdminNavEntry>` from
whichever caller builds it, and `AuthGate` gained an optional
`adminSections` callback threading them through. `apps/admin_web/lib/
main.dart` — the one place allowed to depend on every feature — now
builds both the "Users" and "Pages" entries; `feature_identity` no longer
hardcodes either. See `docs/architecture/repository-structure.md`'s new
"Cross-cutting UI infrastructure: `AdminNavEntry`" section. A side effect:
`AdminShell`'s app-bar title is now the selected entry's own `label`
rather than a separately hardcoded string per section — a deliberate
simplification, covered by the updated `auth_gate_test.dart`.

### SEO on Flutter Web — the exact limitation, not silently assumed away

Per explicit instruction, this is stated precisely rather than claimed
as full crawler compatibility. `apps/public_web` is client-side rendered
— this milestone does not build server-side rendering or prerendering
(the SRS's Technical Architecture section allows for it; building it is
a separate, sizeable undertaking out of scope here). `SeoHead` (in
`apps/public_web/lib/src/seo_head_web.dart`) updates `document.title`,
`<meta name="description">`, `<link rel="canonical">`, `<meta
name="robots">` and Open Graph tags on every route change, via
`package:web`'s DOM bindings:

- **Works** for user agents that execute JavaScript before reading
  `<head>` — modern Googlebot renders pages before indexing, so per-page
  search-indexing metadata is expected to work correctly.
- **Does not work** for user agents that only read the static HTML from
  the first response and never execute JavaScript — this includes most
  social-preview/link-unfurling crawlers (Facebook, X/Twitter, WhatsApp,
  LinkedIn, Slack). Those only ever see `web/index.html`'s site-wide
  defaults, never a specific page's Open Graph title/description/image,
  until prerendering or SSR is added. This is a real, currently-open gap
  — not fixed in this milestone, tracked here as a named follow-up.

**A real Flutter platform-targeting issue found and fixed along the
way**: `package:web` (and `flutter_web_plugins`, which
`usePathUrlStrategy()` needs) only compile for JS/Wasm targets —
`flutter test` runs on the Dart VM, where `dart:js_interop`'s conversion
extensions and `dart:ui_web` don't exist, so importing either
unconditionally from any file `main.dart` pulls in broke `flutter test`
entirely (not a test failure — a compile error, since Dart resolves
every top-level `import` for a library regardless of whether the
imported symbols are actually called). Fixed with the standard
conditional-export stub pattern: `seo_head.dart`/`url_strategy.dart` each
`export` a no-op stub by default, switching to the real `package:web`/
`flutter_web_plugins` implementation only via `if
(dart.library.js_interop)` — true only under web compilation, never
under the VM. `apps/public_web`'s widget tests now pass without ever
touching real browser DOM APIs.

### Scheduled publishing: the executor now exists — deployment is the remaining gap

`feature_publishing`'s milestone validated and stored a schedule but
nothing made scheduled content actually go live at `scheduledAt` —
flagged there explicitly as a blocker. `functions/src/scheduling/
publishScheduledContent.ts` is that executor: `runScheduledPublish(db,
now)` queries `content` where `status == 'scheduled' && scheduledAt <=
now`, and for each candidate re-checks its status *inside its own
transaction* immediately before writing — idempotent by construction,
since a document already published by a human or a previous/overlapping
run is silently skipped, never double-published or double-audited (see
its own doc comment and the emulator concurrency test proving two
racing runs never both publish the same page). A per-document failure
is logged and the document is left exactly as `'scheduled'`, so the next
run retries it automatically — satisfying NFR-06 ("remains visible and
retryable without silent data loss") with no separate job-record
bookkeeping.

**What this does and does not prove.** The executor's *logic* is
implemented, idempotent, audited, and tested — directly, by calling
`runScheduledPublish` the same way every callable in this codebase is
tested via `.run(request)` rather than through the real trigger
mechanism (Cloud Scheduler cannot be exercised without a real
deployment). The `onSchedule('every 5 minutes', ...)` trigger only
becomes an active cron job once deployed to a real Firebase project.
**As of this commit, nothing has been deployed anywhere** — per this
milestone's explicit deployment boundary (see below) — so no process is
currently publishing scheduled content in any environment. This is
stated plainly so "scheduled publishing" is never reported as fully
working when only the code that would make it work is: it is complete
and verified; it is not yet running.

### Test execution status (feature_pages)

| Suite | Run in this environment? | Result |
|---|---|---|
| Dart domain/use-case/widget tests (`packages/feature_pages/test/`) | Yes (local) | 54/54 passing |
| `apps/admin_web`, `apps/public_web` widget tests | Yes (local) | Passing (admin_web 1/1, public_web 2/2) |
| `feature_identity` (`AdminShell`/`AuthGate` regression from the `AdminNavEntry` refactor) | Yes (local) | 47/47 passing |
| Cloud Functions unit tests (`functions/test/pages.*.test.ts`) | Yes (local) | Included in the 160/160 total (was 107; +53 for Pages) |
| Firestore rules tests — `content`/`revisions` (`firebase/test/content.rules.test.ts`) | **No — needs CI** | Authored, type-checked clean; not executed locally |
| Cloud Functions integration tests — Pages callables (`functions/test/emulator/pages.functions.test.ts`) | **No — needs CI** | Authored, type-checked clean (strict compiler options matching `tsconfig.json`); not executed locally |
| Cloud Functions integration tests — scheduling executor (`functions/test/emulator/scheduling.functions.test.ts`) | **No — needs CI** | Authored, type-checked clean; not executed locally |

Every emulator-dependent row above is authored and statically verified
only, per this environment's JDK constraint (JDK 21 not installed, per
standing instruction) — do not treat that as equivalent to a passing
test; see the milestone report for whether a CI run against them has
since landed.

### Deployment boundary

Per explicit instruction, this milestone does not deploy anywhere —
Dev, Staging, or Production. The full sequence (implement, run local
validation, commit as its own milestone, push, run CI, fix real CI
failures, confirm every job including emulator-backed ones is green,
report) is completed before any deployment is attempted, and deployment
itself requires separate, explicit confirmation.

## Traceability

Every implementation story must reference an SRS requirement ID (e.g.
`WEB-06`, `ENQ-03`, `CMS-11`) or a named PRD model/section. Any scope
addition — forms collecting personal data, admissions applications,
payments, portals, multilingual authoring, arbitrary layouts, custom
embeds — requires a documented change request per SRS §17, not an
ad hoc code change.
