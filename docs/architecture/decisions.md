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

## Traceability

Every implementation story must reference an SRS requirement ID (e.g.
`WEB-06`, `ENQ-03`, `CMS-11`) or a named PRD model/section. Any scope
addition — forms collecting personal data, admissions applications,
payments, portals, multilingual authoring, arbitrary layouts, custom
embeds — requires a documented change request per SRS §17, not an
ad hoc code change.
