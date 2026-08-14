# Release checklist (Staging / Production)

Gate items that must be true before promoting this codebase beyond Dev.
Not a deployment how-to (see `docs/architecture/environments.md` for
that) — this is a go/no-go list.

## Blocking

- [ ] **Scheduled publishing** — see
      `docs/architecture/known-issues.md`. Scheduled pages must reliably
      transition to `Published` at or after `scheduledAt`, verified by a
      real, executed reproduction (not just code review) in an
      environment with a live Cloud Scheduler job, before this box may
      be checked. Currently **open** — release is blocked on this.
- [ ] Every milestone's CI reference in `docs/architecture/decisions.md`
      is green, including the emulator-backed job.
- [ ] No entry in `docs/architecture/known-issues.md` is unresolved and
      marked blocking.

## Verification

- [ ] Full CI green on the branch being promoted (Flutter workspace,
      Cloud Functions, Firestore/Storage rules + emulator-backed
      callables).
- [ ] `npm run verify:deploy-package` passes against a clean build
      (confirms the Functions deploy bundle actually contains the
      compiled entry point — see `decisions.md`'s Functions deployment
      packaging fix for why this check exists at all).
- [ ] Manual UAT checklist for each shipped CMS Core module completed
      against the target environment, not assumed from Dev behavior.

## Process

- [ ] Every real deployment follows the staged sequence in
      `environments.md` (rules/indexes → Storage rules → Functions →
      verify → Hosting), never everything at once.
- [ ] Super Admin bootstrap for the target environment completed via
      `functions/scripts/bootstrap-real-super-admin.js`, not manually.
