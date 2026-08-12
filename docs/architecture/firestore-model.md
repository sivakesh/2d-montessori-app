# Firestore logical model (Phase 0 snapshot)

This is the collection map agreed during architecture review, extended
from PRD §12 to close the gaps in `decisions.md`. It is the target shape
for Phase 1 (Foundation: `users`, auth-adjacent) and Phase 2 (CMS Core:
everything else) — no collections are created by Phase 0 scaffolding
itself; `firebase/firestore.rules` only reserves the public-read
namespace so Phase 1/2 rules changes are additive, not restructuring.

| Collection | Purpose | Public read |
|---|---|---|
| `users/{uid}` | CMS profile, role display, audit fields | No |
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
| `auditLogs/{eventId}` | Append-only event history | No |
| `publishJobs/{jobId}` | Idempotent schedule/processing job state | No |

`(new)` marks collections required by the SRS that the PRD v1.1 did not
model — see `decisions.md` for why.

## Rules posture

`firebase/firestore.rules` currently allows public **read** on every
`published*`/`public*` collection listed above and denies everything else
(reads and writes) by default. Role-based write rules (Editor/Publisher/
Super Admin per SRS §3, backed by custom claims) are added in Phase 1/2 as
each collection's editing UI is built — see the rules file's own header
comment for what's intentionally not implemented yet.
