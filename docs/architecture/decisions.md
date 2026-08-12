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
| Dart domain/use-case tests (`packages/feature_publishing/test/`) | Yes | 39/39 passing |
| Cloud Functions unit tests (`functions/test/publishing.*.test.ts`) | Yes | included in the 107/107 total below |
| Firestore rules tests (`firebase/test/content.rules.test.ts`) | **No — needs CI** | Authored, type-checked clean; not executed locally |
| Cloud Functions integration test (`functions/test/emulator/publishing.functions.test.ts`) | **No — needs CI** | Authored, type-checked clean (`tsc --noEmit` against the strict compiler options, matching `tsconfig.json`); not executed locally |

The two emulator-dependent rows above have not yet been proven green by
CI the way the Foundation Verification suites have — that CI run has not
been dispatched as of this writing. Do not treat their clean type-check
as equivalent to a passing test; see the milestone report for whether a
CI run against them has since landed.

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
existed. Not yet re-verified by a subsequent CI run as of this writing;
see the milestone report.

## Traceability

Every implementation story must reference an SRS requirement ID (e.g.
`WEB-06`, `ENQ-03`, `CMS-11`) or a named PRD model/section. Any scope
addition — forms collecting personal data, admissions applications,
payments, portals, multilingual authoring, arbitrary layouts, custom
embeds — requires a documented change request per SRS §17, not an
ad hoc code change.
