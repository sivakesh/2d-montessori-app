# Firestore logical model

This is the collection map agreed during architecture review, extended
from PRD §12 to close the gaps in `decisions.md`. It is the target shape
for Phase 1 (Foundation: `users`, auth-adjacent — **live**; CMS Core:
`content` + `transitions`, the shared publishing workflow engine —
**live as of this milestone**) and Phase 2 (everything else, still
target-only). `firebase/firestore.rules` reserves the public-read
namespace for collections not yet built so later rules changes are
additive, not restructuring.

| Collection | Purpose | Public read |
|---|---|---|
| `users/{uid}` **(live)** | CMS profile, role/status mirror, `mustChangePassword`, audit fields — see AUTH-01/AUTH-05 rules in `firebase/firestore.rules` and `docs/architecture/decisions.md` "Identity data model" | No |
| `content/{contentId}` **(live)** (+ `transitions/`) | Shared publishing-workflow envelope (`feature_publishing`) — Draft/InReview/Approved/Scheduled/Published/Archived status, owner, timestamps/actors per state, all mutations via `functions/src/publishing`. `transitions/{transitionId}` is the per-content history/audit trail of every transition. Reference content type only in this milestone (`contentType` + `title`); `feature_pages` and later content features compose with this envelope rather than reimplementing workflow state — see `decisions.md` "Publishing workflow: reusable contracts" | No (owner or active Publisher/Super Admin only) |
| `pages/{pageId}` (+ `sections/`, `versions/`) | Editable pages | No |
| `publishedPages/{routeKey}` | Denormalized published page snapshot | Yes |
| `programs` / `publishedPrograms` | Program collection | No / Yes |
| `experiences` / `publishedExperiences` | Experience collection (local labels only — no shared `categoryIds`, see decisions.md) | No / Yes |
| `events` / `publishedEvents` **(new)** | Events & Announcements (SRS WEB-06) | No / Yes |
| `team` / `publishedTeam` **(new)** | Staff/Team profiles (SRS WEB-11) | No / Yes |
| `documents` / `publishedDocuments` **(new)** | Downloadable documents (SRS WEB-12) | No / Yes |
| `albums` / `publishedAlbums` | Gallery albums + media placements | No / Yes |
| `testimonials` / `publishedTestimonials` | Testimonials — no `rating` field | No / Yes |
| `articles` / `publishedArticles` | Blog/News | No / Yes |
| `faqs` / `publishedFaqs` **(new)** | Centrally managed FAQs (SRS WEB-09), cross-linkable from Programs/Montessori Way | No / Yes |
| `media/{mediaId}` / `publicMedia/{mediaId}` | Media metadata (restricted) / sanitized public delivery metadata | No / Yes |
| `enquiries/{id}` (+ `followUps/`) **(new)** | Enquiry capture/assignment/follow-up (SRS ENQ-01..07) | No (no public mirror) |
| `legalPages/{key}` **(new)** | Privacy/Terms/Cookie/Disclaimer/Child-Image policy, versioned separately from generic pages (SRS LEG-01) | No (published subset rendered via `publicSettings` or a dedicated public read as Phase 2 decides) |
| `settings/{key}` / `publicSettings/{key}` | Brand, contact, navigation, footer, forms config, cookie text, maintenance | No / Yes |
| `redirects/{sourceKey}` | Redirect master | Resolved server-side only |
| `auditLogs/{eventId}` **(live)** | Append-only event history — written by `functions/src/lib/audit.ts`, no client access at all (not even Super Admin; no viewer UI exists yet) | No |
| `publishJobs/{jobId}` | Idempotent schedule/processing job state | No |

`(new)` marks collections required by the SRS that the PRD v1.1 did not
model — see `decisions.md` for why.

## Rules posture

`firebase/firestore.rules` allows public **read** on every
`published*`/`public*` collection listed above, a narrow self-or-Super-
Admin **read** on `users/{uid}` (no client writes at all — every mutation
goes through `functions/src/auth`), an owner-or-active-Publisher/Super-
Admin **read** on `content/{contentId}` and its `transitions/`
subcollection (no client writes at all — every mutation goes through
`functions/src/publishing`), and denies everything else (reads and
writes) by default, including `auditLogs`. Role-based write rules for the
remaining collections (Editor/Publisher/Super Admin per SRS §3, backed by
custom claims) are added in Phase 2 as each collection's editing UI is
built — see the rules file's own header comment for what's intentionally
not implemented yet.

Both `isActiveSuperAdmin()` and `isActivePublisherOrAbove()` (the helpers
gating `users/{uid}` and `content/{contentId}` reads respectively) re-read
the caller's `users/{uid}.status` document live via `get()` rather than
trusting the `status` custom claim alone — see `decisions.md`
"Security-rule inconsistency found and resolved" for why a claims-only
check would let a just-suspended account keep privileged read access
until its cached ID token expires.
