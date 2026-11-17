# Parent data access — security foundation (Phases 0, 0.1 and 0.2)

Status: implemented in the app; **security rules are a tested proposal, not
deployed**. Phase 0.2 is application-level only: it did not change any rules
proposal, so the protections it adds hold in the app but are **not yet
enforced on the server** against someone calling the Firebase APIs directly
(see §9). Nothing here changes the login, sign-up, roles or session
handling, the Fees/Finance calculations, or Fee Bill Issuance's numbering,
allocation, amounts, cancellation or documents (it only gained a refresh
hook that runs after a committed issue or cancellation, §3a).

## 1. Where the rules live (and don't)

- The root `firebase.json` declares hosting only — no Firestore or Storage
  rules, no indexes. The deployed rules for `montessori-app-95988` (DEV/UAT)
  and production are **not in this repository**.
- `test/firebase_rules/` holds emulator-only *proposals* (website, forms, fee
  bills, parent access). None of them is a deployment source.
- The deployed rules can be read without changing them (Firebase console →
  Firestore/Storage → Rules, or the read-only Firebase Rules API;
  `docs/website_dev_validation.md` §2). That needs the owner's approval and
  has not been done.

**Merge warning.** Firestore and Storage grant access when *any* matching
rule allows it. A broad match left in the deployed rules (for example
`match /{document=**} { allow read, write: if request.auth != null; }`)
cancels every restriction below. See §9 for the integration plan.

## 2. Who is who (as the app already establishes it)

- The OTP login keys every account at `users/{last 10 digits of the phone}`
  and the app reads `role` and `isActive` there. No custom claim is set
  anywhere in the app.
- The parent rules find the same record from the token's `phone_number`.
  Missing `role` = `parent`, missing `isActive` = active (as `AppUser`).
- `admin` and `staff` are the privileged roles. A disabled account reads no
  protected data, even with an open session.
- Account shapes the rules can't use are reported by Settings → Parent
  access → Check (§8).

## 3. Parent access mapping

`parent_access/{userId}` — one per parent, written only by administrators
(`ParentAccessService`), derived from `user_student_links`:

| Field | Meaning |
|---|---|
| `studentIds` | every linked child |
| `financeStudentIds` | children whose **Father or Mother** this parent is |
| `relations` | studentId → Father / Mother / Guardian / Other / Unresolved |
| `classIds` | the linked children's classes (class-targeted notices) |

- Many children per parent, many parents per child.
- Nothing is guessed: a missing, unrecognised or contradictory relationship
  links the child but withholds fees; a parent listed only on a student
  record, or a link to a missing student, grants nothing. All reported.
- `classIds` is refreshed whenever an admin changes a student (class
  changes included).

### Keeping links consistent (Phase 0.1 fix)

All three admin link editors now go through `ParentLinkService`, which
writes the `user_student_links` records **and** the students'
`parentLinks` in one atomic batch:

| Editor | Before | Now |
|---|---|---|
| Students → Parents (student form) | batch (Phase 0) | `saveLinksForStudent` |
| Parent profile → Linked students | un-ticked child kept the parent on its `parentLinks` and on the parent's profile list | `saveLinksForParent`: removed from both; the child's other parents kept |
| Student view dialog → Parents | wrote `parentLinks` only (no link records, so no access) | `saveLinksForStudent` |

After each save the affected parents' access records and students'
parent-safe profiles are rebuilt. A rebuild that fails never fails the save;
the admin is told to use Settings → Parent access.

## 3a. Parent-safe projections

Parents don't read the original student, fee, payment, bill, notice or
document records. Administrators' writes maintain parent-safe copies built
from an **allowlist** of fields (`parent_projections.dart`), so a field added
to an original later is never exposed by accident. No copy carries a
download URL.

| Copy | Who (app) | Contents | Withheld |
|---|---|---|---|
| `parent_student_profiles/{studentId}` | every linked parent | name, admission no./date, class, section, roll no., date of birth, age, gender, nationality, mother tongue, photo (**Storage path**), parents & guardians (**name and relationship**) | blood group, address, documents (next row); approval status; fee discount; parents' phone/email/user id; URLs; created/updated fields |
| `parent_student_details/{studentId}` | **Father/Mother** | blood group, home address, documents (name, type, file name, **Storage path**, date) from the student record and the `documents` collection | document URL, uploaded-by |
| `parent_fee_assignments/{assignmentId}` | **Father/Mother** | fee name, academic year, fee month, due date, gross (`totalFee`), **discount applied** (`discountAmount`), net (`payableAmount`), collected, outstanding, status, components | revision history (reasons, reviser names), `feeRevision`, `lastRevisedAt`, `assignedBy`, `deletedBy`, student-discount configuration (type, value, reason, dates, config/operation ids, applied-by), structure/year ids |
| `parent_payments/{receiptId}` | **Father/Mother** | date, amount, mode, reference, receipt no., fee name, fee month, assignment | remarks, collector, created-by, PDF URL/path, transaction id; voided payments removed |
| `parent_fee_bills/{billId}` | **Father/Mother** | the bill snapshot: Bill Reference, student, class, billing month, particulars, gross, bill-only adjustment and reason, net, GST flag, issue date, parent name, school identity, **Receipt Reference**, and for each supporting payment its receipt number, payment date and amount used (`allocations`) — **active (issued) bills only**: a cancelled bill has no copy (removed by the next refresh or rebuild) | `issuedBy`, `issueRequestId`, cancelled bills entirely, cancellation details, replacement links (`replacesBillId`/`replacedByBillId`), `adjustment.createdBy`, internal receipt id, receipt and allocation ids of the supporting payments, the allocation ledger and reversal records, audit history, school logo URL (kept as `logoPath`) |
| `parent_notices/{noticeId}` | targeted parents | Published Parents/Public notices; attachment by **Storage path** | author, other students'/classes' names, staff targeting, attachment URL |

- **Fees are not recalculated.** A fee copy is built from the existing
  `StudentFeeAssignmentModel` and keeps the stored amounts; the parent screens
  read it back through the same model. Components are the applied
  student-discount allocation (name, gross, discount), or else the fee
  structure's particulars when they add up to the fee's gross amount.
- **Fee bills stay identical.** `FeeIssuedBill.fromMap` reads the bill copy,
  and the unchanged `FeeBillPdf` produces the same rows and amounts as from
  the original (tested). Fee Bill Issuance was not modified.
- **Attendance** has no copy (staff mark it every day). Parent screens pass
  each record through `parentAttendanceRecord`: status, date and times kept,
  the photo by **Storage path** (`attendance_photos/students/{date}/{id}.jpg`
  — the path `AttendanceService` writes), and no URL, marker or environment
  field. The records themselves are unchanged.

### Refresh paths

| Source change | Refreshed by | Copies |
|---|---|---|
| student create/update/delete, photo, documents (student record), class assignment | `AdminStudentService`, `StudentService`, `StudentEnrollmentService`, student view dialog | profile, details, parents' class ids |
| document upload to the `documents` collection | `AdminDocumentsService.uploadDocument` | details |
| parent links (all three editors) | `ParentLinkService.refresh` | access, profile |
| assign, edit, revise, delete an assignment | `FeeService.assignFee`, `updateAssignment`, `reviseAssignmentFee`, `deleteAssignment` | fees, payments, bills of that student |
| bulk assignment, structure sync, monthly fees, due-date backfill, apply student discounts | `bulkAssignClassFees`, `syncAssignmentsForFeeStructure`, `assignMonthlyFees`, `applyMissingDueDates`, `applyStudentDiscounts` | every affected student |
| fee structure name/components | `updateFeeStructure` (also deactivate) | students with that structure |
| collect, edit, void a collection (also the Finance-side void) | `collectFee`, `updateCollection`, `voidReceipt` | fees, payments, bills |
| issue a fee bill, cancel one (with or without a replacement) | `FeeBillService.issueBills`, `cancelBill` → after-change hook `refreshParentFeeBills` (`ParentProjectionService.syncFeeBillsQuietly`) | bills of that student |
| an administrator opens Fee Bill Issuance | `FeeBillService.backfillDerivedCopies` → `backfillParentFeeBills` (`ParentProjectionService.syncAllFeeBillsQuietly`) | every bill copy that is missing or outdated (bills issued before the automatic refresh existed, or whose refresh failed); nothing is written when all are current |
| notification create/update/publish/archive/delete/seed | `AdminNotificationService` | notice |
| Settings → Parent access → Apply / Rebuild | `ParentProjectionService.syncAll` | everything |

All hooks run **after** the original write has committed and never throw, so
they can't change or fail the admin's operation (no Fees/Finance calculation
or transaction changed).

**Fee Bill Issuance hook.** `FeeBillService` takes a `FeeBillsChanged`
callback (`afterChange`, or the app-wide `FeeBillService.defaultAfterChange`)
and calls it only after its issue or cancel transaction has returned — never
for a refused request or a failed commit — and contains anything it throws.
The Parent module registers it at startup (`registerParentFeeBillRefresh()`
in `main.dart`), so the Fees module does not import the Parent module for
bills; tests and other callers that don't register it are unaffected. The
refresh re-derives the student's bill copies from the original bills, so it
is idempotent (a repeated request rewrites nothing) and writes no original
record (tested). A failed refresh is recorded (per bill, scope `feeBills`; or
`bills` for the student) and repaired by the next bill or fees refresh of
that student, or by Rebuild.

(The Fees service's own hooks still import `ParentProjectionService`
directly — a module dependency from Phase 0.1/0.2. It could move to the same
callback pattern later; it was left as it is to avoid a broad refactor.)

**Not covered automatically** (repaired by Rebuild, and reported by Check):
- Student documents deleted through `DocumentService.deleteDocument`
  (`documents` collection, not used for students in the admin UI today).
- Seeding sample students/fee structures (developer tools).
- Any write made outside the app (console, scripts, a future backend).

### Reliability (Phase 0.2)

- A refresh that fails is **recorded**, not treated as success:
  `parent_projection_failures/{scope}_{id}` holds the scope (`profile`,
  `details`, `feeAssignments`, `payments`, `feeBills`, `notices`, `student`,
  `fees`, `bills`, `notice`, `rebuild`), the record id, the error (first 300
  characters), the time and the attempt count. The admin's own change is
  unaffected. The next successful refresh of that record removes it.
- **Check** (Settings → Parent access) now also shows, per kind, how many
  copies are missing, out of date or no longer needed — by rebuilding each
  copy in memory and comparing it with the stored one — and lists the
  recorded failures. Check writes nothing.
- **Per-student refreshes** (after an admin write) write each changed copy as
  its own document write, up to 10 at a time: one copy that fails is recorded
  on its own and the others are still written, where one batch would have
  failed them all. Only copies that differ are written, so the number of
  writes equals what a batch would bill; a refresh with nothing to change
  writes nothing. Within one refresh operation (for example all the students
  of a bulk Fees operation) the recorded failures and the fee structures are
  read once, and a failure record is deleted only if one exists.
- **Rebuild** (and Apply) writes only copies that differ, removes orphans,
  and works batch by batch: a record whose data can't be turned into a copy,
  or a batch that fails, is recorded and skipped while everything else
  continues; the last good copy of that record is kept rather than deleted.
  Running it again changes nothing. It never writes an original record.
- **Diagnostics.** Check also compares the access records with the links
  and lists linked parents with **no access record** or an out-of-date one
  (until Apply writes it, such a parent reads fees directly but cannot read
  issued bills), shows the fee bills found / copies current / missing /
  outdated, and reports any kind it could not read with the Firestore error
  code (e.g. `permission-denied`) instead of failing. "Check one parent
  account" shows, for a phone number: user record, access record, link
  records and, per child, relationship, fee access, profile copy, bills
  issued and parent bill copies (counts only). Opening Fee Bill Issuance shows
  the bill backfill's result, including failed writes and their code. On the
  parent side a bill problem never hides the fees: the dialog distinguishes
  no bills, access not configured, not permitted, and a read error (code,
  Retry).
- Failure records are for administrators only; parents never read them (the
  rules for that collection are part of the later review).

## 4. What each role may do (proposed rules)

| Collection | Parent (active) | Staff | Admin |
|---|---|---|---|
| `users` | read own; OTP login create/update only | read | all |
| `user_student_links` | read own | — | all |
| `parent_access` | read own | — | all (validated) |
| `students` | — | read | all |
| `parent_student_profiles` | get a linked child's | read | all |
| `documents` | — | read | all |
| `attendance` | get a linked child's day by id | read, write | all |
| `staff_leave_requests` | read/create a linked child's student leave (Pending) | read, create | all |
| `school_notifications` | — | read | all |
| `parent_notices` | Public, all-classes, all-students, own child's class, own child | read | all |
| `student_fee_assignments` | **Father/Mother** read | — | all |
| `fee_transactions`, `fee_receipts` | — | — | all |
| `parent_payments` | **Father/Mother** read | — | all |
| `fee_issued_bills` | **Father/Mother** read | — | read (writes: fee-bill proposal) |
| bill `audit`, `fee_bill_allocations` | — | — | read |

**Class enforcement.** A notice naming students goes only to those
students' parents (the class list the form keeps as its student filter is
dropped from the copy — the app used to show such notices to the whole
class); otherwise its classes are checked against the parent's `classIds`.
Changing a query or guessing an id is refused (emulator-tested).

**OTP login compatibility** (unchanged code): a first login may create its
own `users/{phone}` as an active parent; later logins may record the uid and
times. Role and `isActive` can't change (missing role → `parent`, missing
`isActive` → `true` only); disabled accounts can't write.

## 5. Parent queries

| Data | Query |
|---|---|
| children | `parent_access/{me}` → `parent_student_profiles/{id}` gets |
| child details | `parent_student_details/{id}` get (Father/Mother only) |
| fees | `parent_fee_assignments where studentId ==` (Father/Mother) |
| payments | `parent_payments where studentId ==` (Father/Mother) |
| leave | `staff_leave_requests where subjectType == 'student' and studentId in [children]` |
| attendance | one get per day by id |
| notices | `parent_notices`: Public; all-classes; all-students; `applicableClassIds array-contains-any [classes]`; `applicableStudentIds array-contains-any [children]` |
| fee bills | `parent_fee_bills where studentId ==` (`ParentFileService.feeBillsForStudent`, Father/Mother) |

Before the reconciliation has created a parent's access record (and before
the rules are deployed) the app uses the previous, narrowed reads of the
original records, so parents keep working during the rollout.

**Indexes.** Equality, `in` and `array-contains-any` filters without
ordering — normally served by automatic single-field indexes. The emulator
does not check indexes; open each parent screen once on DEV after deploying.

## 6. Protected downloads

`ParentFileService(parentUserId: …)` is the only download path for parents.
Each method first checks, in the app, the parent's own access record and the
copy that lists the file, then downloads by **Storage path** through the
signed-in Storage SDK (`Reference.getData`) — never by a stored URL:

| File | Who | Check |
|---|---|---|
| child photo | any linked parent | child linked; path from the child's profile copy |
| attendance photo | any linked parent | child linked; deterministic path |
| student documents | **Father/Mother** | child in `financeStudentIds`; path listed on the child's details copy |
| notice attachment | targeted parents | the notice copy is targeted at the parent (classes/children) and lists that path |
| fee bill PDF | **Father/Mother** | child in `financeStudentIds`; built from the bill copy with the unchanged `FeeBillPdf` |
| receipt PDF | nobody | not offered |

Document sources:
- the student record's `documents` list (Students → view dialog uploads);
- the `documents` collection with `entityType: 'student'` (Documents
  uploads);
- `school_documents` (school-wide: circulars, policies) — **not** exposed to
  parents at all; nothing reads it for them;
- `documents` with `entityType: 'user'` — not exposed.

Not changed: existing download URLs keep working for administrators; the
tokens stored in original records remain valid for anyone who already has
them (rotating them is a URL migration — re-upload or revoke each token —
not done). Attendance photo URLs stay in attendance records; parent screens
never pass them on, but an attendance copy (or no parent read of
`attendance`) is needed for the server to stop a direct read. Web downloads
need the bucket's CORS configuration (`cors.json`).

## 7. Owner policy (approved, Phase 0.2)

- Father and Mother: the full approved profile, blood group, home address,
  all student documents, the complete fee breakdown with the discount
  applied, payments and fee bills.
- Guardian (and Other / unresolved relationships): the approved profile
  without blood group or home address; no documents; no financial
  information at all.
- Every linked parent sees the other parents' names and relationships; no
  phone numbers or emails.
- Admission approval status is internal (not copied).
- Discount configuration, eligibility rules and administrative settings are
  never copied; only the amount applied.

## 8. Administrator and staff identity (structural review)

Supported formats in the code:
- `users/{10-digit phone}`: written by the OTP login, the dev login,
  `UserService.createAdminUser` and the admin user form.
- A record keyed otherwise is still found by the app through
  `firebaseAuthUid` (`userLoaderProvider` fallback), but **not by the
  rules**, so such an admin or staff account would lose access.
- Editing a user's phone in the admin user form writes a new
  `users/{new phone}` record and leaves the old one (two records, roles may
  differ).
- `prod_users` (legacy) is written by unused methods only.
- `getStaffUsers` treats `teacher` and `admin_staff` as staff, but routing
  and the rules recognise only `staff`.

Production data was not read. **Check (no changes)** now reports, with each
account's role: ids that aren't phone numbers, stored phone ≠ id, and phone
numbers shared by several accounts. Recommended before any rules
deployment: run it on each project; for each flagged admin/staff account,
create the phone-keyed record with the same role (admin form) and retire
the old one; never change roles in bulk.

## 9. Rules integration assessment

| Topic | Finding | Plan |
|---|---|---|
| Admin identity | website, forms and fee-bill proposals use custom claims `role`/`schoolId` that nothing sets; parent rules use `users/{phone}.role` | pick one. Recommended: the `users` record (no backend; protected by the role rule here). Replace each proposal's `isAdmin`/`isSchoolAdmin` with shared functions; `schoolId` defaults to `default_school` |
| Duplicate matches | forms proposal contains "EMULATOR ONLY" simplified copies of `website_media`, `website_pages`, `website_page_drafts`, `website_public_items` | drop them; keep the website proposal's |
| Fee bills | parent read added here, writes in the fee-bill proposal | merge into one `fee_issued_bills` match; drop the obsolete `system_counters` rule (bill numbers now use the allocation counter) and add the bill fields listed in `docs/fee_bill_issuance.md` |
| Public reads | intended `if true` reads on website pages/items, public forms and settings | keep |
| Wildcards | none in the proposals; the deployed rules are unknown and, since the dev login has no Auth session, DEV's are probably open | read the deployed rules first; remove any wildcard |
| Not covered by any proposal | `classes`, `academic_years`, `school_calendar_events`, `mood_checkins`, `profiles`, `user_session_logs`, `student_enrollments`, `school_documents`, `school_settings` (Storage), `finance_*`, `vendors`, `staff_salary_payments`, `audit` subcollections, `prod_users` | write rules for each before deploying (parents need read of classes, academic years and Parents/Public calendar events, and create/read of their own mood check-ins and session logs) |
| Cross-service | Storage rules read `users`, `parent_access`, `parent_notices` from Firestore | grant the Rules service agent Firestore access (console prompt on first deploy); each such download costs Firestore reads; verify the per-request document-access limit on DEV |
| Dev login | debug builds have no Firebase Auth session | DEV checks use real OTP (test phone numbers) |

**Phase 0.2 dependencies for the review** (the proposals were not edited in
this phase):
- `parent_student_details`, `parent_fee_assignments`, `parent_fee_bills`:
  need rules — get/list only for a Father/Mother of `studentId` (details:
  `isFamily(studentId)`, i.e. the access record's `financeStudentIds`);
  writes administrators only. Without them, deployed proposal rules would
  refuse these reads (parents would see no details, fees or bills).
- `parent_student_profiles`: unchanged rule (any linked parent); its
  contents no longer include blood group, address or documents.
- `student_fee_assignments` and `fee_issued_bills`: remove the parent read
  from the proposal once the copies are in use (it was the Phase 0 path).
- `parent_projection_failures`: administrators only.
- `attendance`: either an attendance copy without `photoUrl`, or keep the
  parent read but accept the URL exposure.
- Storage: student `documents/students/{id}/…` and `students/{id}/…`
  documents should be Father/Mother only (the proposal allows any linked
  parent); student photos stay any linked parent.

Deployment order: (1) read deployed rules; (2) deploy the app; (3) admin
runs Check, fixes problems, Apply (also builds the parent copies); (4) merge
one consolidated ruleset, test on DEV with real OTP accounts; (5) deploy.

## 10. Remaining risks

- **Server enforcement**: until the consolidated rules are deployed, every
  parent restriction is enforced by the app only. A user calling the Firebase
  APIs directly is limited only by the (unknown) deployed rules.
- **Copies lag** when a refresh fails; this is now recorded and visible, and
  Rebuild repairs it, but nothing repairs it automatically.
- **Attendance** records still carry the photo URL (not shown to parents).
- **Existing token URLs** remain valid (no URL migration).
- Unused `AdminStudentService.linkParentToStudent`/`removeParentLink` still
  write `parentLinks` alone (no caller today).

## 11. Tests

- `test/parent_access_test.dart`, `test/parent_projection_test.dart`,
  `test/parent_data_readiness_test.dart` — mapping, reconciliation,
  projections and policy, fee and bill copies, hooks, class targeting,
  unlinking, account checks, downloads, attendance photos, refresh
  reliability.
- `test/parent_fee_bill_refresh_test.dart` — the Fee Bill Issuance hook:
  successful issue and cancellation, refused and failed issue/cancellation
  (no refresh, no copy), failed refresh (recorded, repaired by retry and by
  Rebuild), a throwing hook, the production registration, per-student
  partial failures and a repeated bulk refresh writing nothing.
- `test/parent_dashboard_layout_test.dart` — the Parent Dashboard at 320–1440
  px with one or two children and long names (no overflow), and the AppBar
  in windows as narrow as 40 px.
- `test/firebase_rules/parent_access_rules_test.py` — emulator checks:

```
PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:exec \
  --config test/firebase_rules/parent_access.firebase.json \
  --project demo-montessori-parents --only firestore,storage \
  "python3 -I test/firebase_rules/parent_access_rules_test.py"
```
