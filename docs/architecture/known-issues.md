# Known issues

Defects that are real, reproduced or reported against a real environment,
and deliberately **not** fixed yet — tracked here so they are never
silently forgotten or accepted as "working as intended." Each entry must
be removed (moved to `decisions.md`'s fix history) only once it has a
verified fix with regression coverage, the same bar every other fix in
this repository has met.

## Scheduled publishing does not reliably transition to Published (Dev UAT)

**Status:** Open. Not accepted, not production-ready. Must be fixed and
retested before Staging or Production release.

**Symptom:** scheduled pages do not reliably transition from `Scheduled`
to `Published` at or after their `scheduledAt` time.

**What this is not:** a separate, earlier defect — early/stale public
materialization of `Scheduled` content (a page becoming publicly
readable *before* its scheduled time) — was root-caused and fixed in
commit `896111b` (see `decisions.md`'s "Post-deployment fix: stale
`publishedPages` materialization"), with regression coverage that
passed in CI. That fix is unrelated to, and does not resolve, this
issue. `Scheduled` content correctly remains non-public as of that fix
— this remaining issue is about the *executor's* transition to
`Published` not reliably happening, not about premature public exposure.

**Suspected areas** (not yet root-caused; each must be checked before
this is marked fixed):
- Cloud Scheduler job execution itself (does `schedulingfns-
  publishscheduledcontent`'s Cloud Scheduler job exist, and is it
  actually firing on its `every 5 minutes` / `Asia/Kolkata` schedule, in
  the real Dev project?).
- `runScheduledPublish`'s query eligibility (`status == 'scheduled' &&
  scheduledAt <= now`) — composite index availability, `scheduledAt`
  field type/consistency.
- Timestamp handling — `scheduledAt` is parsed server-side from a
  client-supplied ISO 8601 string with no explicit timezone handling
  audit performed yet; a timezone mismatch between the Admin app's local
  time and the server's parsing could produce a `scheduledAt` that never
  satisfies `<= now` at the intended real-world time, or satisfies it at
  the wrong time.
- Cloud Scheduler's invoker permissions for the `onSchedule` function's
  underlying Cloud Run service (see `environments.md`'s "Cloud Functions
  callable invoker policy" for the *unrelated* callable-invoker incident
  found on the same project — this function is not a callable and was
  not affected by that specific defect, but its own invoker
  configuration has not been independently re-verified since).
- Transaction execution / silent per-document failure inside
  `runScheduledPublish` (each document's publish is wrapped in a
  try/catch that deliberately does not stop the batch — a per-document
  failure here would currently only surface via
  `console.error`/`failedContentIds`, easy to miss without dedicated
  monitoring).

**Mitigation in place until fixed** (Admin UI, `packages/feature_pages`'s
`PageEditorScreen`): the "schedule" action button is disabled with an
explanatory tooltip ("Scheduled publishing is temporarily unavailable
while a known issue is being fixed... Use Publish for an immediate
release instead") so administrators cannot rely on it without knowing
it's broken. Ordinary immediate publishing (`publish`/`unpublish`) is
unaffected and remains fully available. Nothing in the scheduling
implementation, its Cloud Function, or its tests has been deleted or
altered as a workaround — the underlying `schedule`/`unschedule`
actions, `runScheduledPublish`, and all existing regression coverage
remain exactly as implemented, so re-enabling the button is the only
step needed once the real root cause is found and fixed.

**Explicitly not done as a workaround, per standing instruction:**
scheduled pages are not being force-published immediately, the
scheduling code/tests are not being removed, and this is not being
marked accepted or production-ready.

**Next steps to root-cause:** inspect the real Dev project (read-only):
Cloud Scheduler job existence/last-run status
(`gcloud scheduler jobs describe firebase-schedule-publishScheduledContent-us-central1 --project=twod-montessori-dev --location=us-central1`),
Cloud Functions logs for `schedulingFns-publishScheduledContent`
(`gcloud functions logs read schedulingfns-publishscheduledcontent --project=twod-montessori-dev --region=us-central1`),
and a manual comparison of a real scheduled page's stored `scheduledAt`
Firestore Timestamp against the Admin app's intended local time.
