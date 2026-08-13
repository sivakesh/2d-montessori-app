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
| `content/{contentId}` **(live)** (+ `transitions/`, `revisions/`) | Shared publishing-workflow envelope (`feature_publishing`) — Draft/InReview/Approved/Scheduled/Published/Archived status, owner, timestamps/actors per state, all mutations via `functions/src/publishing`. `transitions/{transitionId}` is the per-content history/audit trail of every transition; `revisions/{revisionId}` (Phase 1 CMS Core / feature_pages) is the per-content-edit history (SRS CMS-06), full field snapshots, append-only. **Pages live here** (`contentType == 'page'`) alongside the generic reference type this milestone's own tests still use — see `decisions.md` "Pages storage: `content` collection, not a separate `pages` collection" for why there is no separate `pages/{pageId}` collection; later content features (Programs, Experiences, ...) compose with this same envelope rather than reimplementing workflow state — see `decisions.md` "Publishing workflow: reusable contracts" | No (owner or active Publisher/Super Admin only) |
| `publishedPages/{slug}` **(live)** | Denormalized published-page snapshot, keyed by slug — synced from `content/{contentId}` by `functions/src/pages/syncPublishedPage.ts` (a Firestore trigger) whenever a page's status changes to/from `published`. Contains only public-safe fields (title, sections, SEO, `resolvedRelatedPages`) — no `ownerId`, `status`, actor identities, or revision history; see `decisions.md` "Public rendering: `publishedPages` is a materialized view, not a filtered `content` read" | Yes |
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

`publishJobs/{jobId}` (planned in earlier drafts of this model as separate
scheduled-job bookkeeping) was not built — the scheduled-publishing
executor (`functions/src/scheduling/publishScheduledContent.ts`, Phase 1
CMS Core / feature_pages) achieves idempotency and retry directly from
each `content` document's own `status`/`scheduledAt` fields inside a
transaction, with no separate job-record collection needed; see
`decisions.md`'s scheduled-publishing section for why.

`(new)` marks collections required by the SRS that the PRD v1.1 did not
model — see `decisions.md` for why.

## Rules posture

`firebase/firestore.rules` allows public **read** on every
`published*`/`public*` collection listed above, a narrow self-or-Super-
Admin **read** on `users/{uid}` (no client writes at all — every mutation
goes through `functions/src/auth`), an owner-or-active-Publisher/Super-
Admin **read** on `content/{contentId}` and its `transitions/`/
`revisions/` subcollections (no client writes at all — every mutation
goes through `functions/src/publishing`/`functions/src/pages`), and
denies everything else (reads and writes) by default, including
`auditLogs`. Role-based write rules for the
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
