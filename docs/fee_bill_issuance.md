# Fee Bill Issuance

**A bill is a document. A payment is a financial transaction.**

Fee Bill Issuance issues supplementary, month-wise bills against a payment
that has already been collected and receipted in Fees. It is used when a
parent asks for separate monthly bills for one payment.

It has its own records, bill numbers, adjustment history and PDFs. It reads
the original payment, but it never creates, changes, reverses or deletes:

- payments, fee transactions or receipts (`fee_transactions`, `fee_receipts`);
- fee assignments, payable amounts, collected amounts or balances
  (`student_fee_assignments`);
- Finance income, ledger entries or account balances (`finance_income`,
  `finance_ledger`, `finance_accounts`).

It calls no `FeeService` or `FinanceService` method. Fee reports,
outstanding figures, receipts, the Finance dashboard, the ledger,
reconciliation, month-end balances and Expense Efficiency do not read its
records, so they are unaffected.

## Where it is

**Fees → Fee Bill Issuance**: the button beside the Fees heading. The page
shows:

- the issued bills, with search (bill number, student, admission number,
  receipt number, month or item) and an All / Issued / Cancelled filter;
- the bill issuance report: active bills, gross billed, bill-only
  adjustments, net billed and cancelled bills. These are bill totals only.
  They are never added to fee collections or to Finance.

Only administrators can issue, reprint or cancel bills. Other users who can
open the page can view bills and download their PDFs.

## Issuing bills

1. Click **Issue Bills**.
2. Search for and choose the student.
3. Choose one of the student's payments. Each payment shows how much of it
   active bills already represent ("Already billed") and how much is left
   ("Not yet billed"). Voided payments can't be chosen.
4. Check the original payment's details: student, receipt number, payment
   date, amount received, payment mode and payment reference.
5. Add the bill lines. **Each line becomes a separate bill** with its own
   number and PDF. A line has:
   - Billing month and year;
   - **Class shown on this bill**: defaults to the class on the original
     receipt; any class can be chosen, for this bill only. The student's and
     the receipt's classes are never changed;
   - Description or fee particulars;
   - Gross bill amount;
   - an optional **bill-only adjustment**: Discount adjustment or Other
     adjustment, its amount and its reason (required);
   - Net bill amount = gross − adjustment, shown as you type.
6. Optionally tick the GST options, both off by default and applying to
   every bill in this issue, exactly as on the regenerated receipt:
   - **Show GSTIN on bill** prints the school's GSTIN, from School
     Settings, in the header. It needs a valid saved GSTIN.
   - **Amount includes GST** shows "(GST Included)" beside the net bill
     amount.

   Neither calculates, adds or changes any amount.
7. The allocation summary shows the original payment, the amount already
   billed, these bills' net total and what will still be unbilled.
8. Click **Preview**. Each bill is listed with its issue date, class and
   parent or guardian, and **Preview PDF** downloads a draft marked
   "PREVIEW - NOT ISSUED", with no number. A preview writes nothing.
9. Click **Issue Bills** and confirm. The bills are numbered and saved, and
   each can be downloaded.

### Example

A parent paid ₹12,500 in one payment and asks for three monthly bills of
₹4,200:

| Month | Gross bill | Adjustment | Net bill |
|---|---:|---:|---:|
| September 2026 | ₹4,200 | ₹0 | ₹4,200 |
| October 2026 | ₹4,200 | ₹0 | ₹4,200 |
| November 2026 | ₹4,200 | ₹100 (Discount adjustment) | ₹4,100 |
| **Total** | **₹12,600** | **₹100** | **₹12,500** |

Without the ₹100 adjustment the bills would total ₹12,600, more than the
payment, so they are refused. With it, the net bills equal the payment
exactly and the payment is fully billed. The receipt, the fee assignment
and Finance are unchanged.

## Rules

- Every bill is linked to an existing, active payment (`fee_receipts`) of
  the selected student and of this school.
- The net bills of one payment never total more than the payment. A payment
  may be partly billed: the unbilled amount is always shown.
- An adjustment is never negative and never more than its line's gross
  amount, so a net bill is never negative. An adjustment needs a type and a
  reason. It is a bill-only adjustment: it never changes a fee structure,
  student discount, assignment, payable, collected or outstanding amount,
  and is not a payment, refund or credit.
- **Duplicates.** One payment can't have two active bills for the same
  billing month and description (case and spacing ignored), until the first
  is cancelled. Each Issue press has a request id: repeating it, after a
  double click or a lost response, returns the bills it already issued.
- **Concurrency.** Issuing and cancelling run in a Firestore transaction
  that reads the payment's allocation first. Two people issuing against the
  same payment at once can never both use the same unbilled amount: one is
  retried and refused.
- All amounts are whole paise (integers). Typed amounts are converted
  exactly, with no floating point.

## Bill numbers and PDFs

- **Bill Reference** = the original receipt number + a six-digit sequence
  for that payment. For example, receipt `REC-2026-1792729533955` gets
  `REC-2026-1792729533955-000001`, `-000002` and so on. It is stored on the
  bill as `billNo` and never changes.
- Each payment has its own sequence, kept on its allocation
  (`fee_bill_allocations/{receiptId}.nextSequence`). It is advanced in the
  same transaction that writes the allocation and the bills:
  - concurrent issues against one payment get distinct, consecutive
    references;
  - the sequence never goes back, so a cancelled bill's reference is never
    reused, and a replacement always gets the next one;
  - at most 999,999 bills per payment.
- The bill's document id contains its reference, which makes a duplicate
  reference impossible.
- **Unusable receipt numbers.** A receipt number is used only if it is made
  of letters, digits and single hyphens and is at most 33 characters long.
  A receipt whose number is missing, contains spaces, slashes or other
  characters, or is shared with another receipt is refused, with the
  reason. The Issue dialog shows such payments but they can't be chosen.
  No ambiguous reference is ever made.
- The receipt numbers themselves, and invoice numbering, are never used
  for anything else or changed.
- `system_counters` is not used. A per-receipt counter there would also
  work, but it would add a second document to keep in step with the
  allocation in every transaction.
- Each bill's PDF is built only from the bill's stored snapshot, so it is
  always the same document.
- The PDF, the issued-bills list and the bill details show the **Bill
  Reference**, and the original receipt number as **Receipt Reference**.
  Search finds bills by either.
- The PDF follows the regenerated fee receipt's layout and shows:
  - the school header as it was at issue, with the GSTIN only when "Show
    GSTIN on bill" was ticked;
  - **FEE BILL**, the **Bill Reference** and the **Issue Date**;
  - **Student details**: Father's Name (else Mother's, else Guardian's),
    student name, admission number and the selected class;
  - **Bill details**: billing month, fee particulars, gross amount, the
    bill-only adjustment and its reason (when there is one), and the
    **Receipt Reference** (the original receipt number);
  - the net bill amount, with "(GST Included)" only when ticked, and the
    amount in words;
  - "System-generated fee bill. No signature required."
- The original payment's date and reference are not printed. They stay
  in the bill record (`payment`) for traceability.
- It never shows a payment amount or "receipt" as its title.

### Issue date

The Issue Date is the **first working day of the billing month**, not the
day the bill is issued. It is stored on the bill (`issueDate`), so a
reprint shows the same date. The day the bill was actually issued is kept
separately (`issuedAt`).

The working day comes from the school calendar (`school_calendar_events`,
Published events only; drafts and archived events are ignored):

- a day marked **School Holiday** is skipped;
- a day marked **Working Day** counts, even on a weekend;
- otherwise Monday to Friday counts and Saturday and Sunday don't, the
  same weekday rule as Leave;
- a date marked both a holiday and a working day is treated as a holiday.

If the calendar can't be read, the issue is refused rather than guessing a
date.

### Parent or guardian

The bill names the student's linked father, else the mother, else a
guardian (any other relationship counts as a guardian). These come from
`students.parentLinks`, as on the regenerated receipt. When none is linked,
the row is left out. The name is stored on the bill when it is issued, so
later changes to the student don't alter it.
- Amounts print as "Rs." because the PDF font has no ₹ symbol.

## Viewing, reprinting and cancelling

Click a bill to open its details. From there you can:

- **Download PDF.**
- **Reprint**: the same bill number and contents, with a small "Reprint
  generated on …" line. The reprint is recorded in the bill's history.
- **Original payment**: the receipt as it is now in Fees, read only. This
  includes whether it has since been voided, and how much of it is billed.
- **History**: issued (with the adjustment), cancelled (reason, amount
  released, replacement) and reprinted, each with who and when.
- **Cancel bill** (administrators):
  - A reason is required. The bill is kept, marked cancelled with the
    reason, who and when, and its PDF is marked CANCELLED.
  - Its net amount is released, so that much of the payment can be billed
    again.
  - With **Issue a replacement bill**, a corrected bill for the same month
    is issued in the same transaction. It gets a **new** number and is
    linked to the cancelled one. It is checked against the payment like any
    new bill.

Issued bills are never edited. A cancellation is refused, and nothing is
written, if the payment's allocation doesn't record the bill exactly, since
that would leave it inconsistent.

## Several payments, several bills and partial allocations

A bill can be supported by more than one payment, a payment can support
more than one bill, and a payment never has to be billed in full at once.
Issuing a bill only records which part of which payment it represents: no
payment, receipt, fee balance or Finance record is created or changed.

- **Choosing payments.** Issue Bills lists the student's payments with
  their collected amount, what active bills already use, and what is still
  available. A payment can be chosen only when it is:
  - an active (not voided) receipt of this school and student, with an
    amount above ₹0 and a usable receipt number;
  - linked (`transactionId`) to its Fees transaction record, which exists,
    is not voided, and has the same student, school and amount.
  Any other payment is listed with the reason it can't be used. There is no
  fallback that skips this check. Every receipt the app has written
  (`collectFee`, since the Fees module's first version) has its transaction
  record, written in the same batch; a receipt created outside the app
  without one can't support new bills, though its existing bills stay
  readable, downloadable and cancellable.
- **One payment chosen.** Each bill line uses its net amount of that
  payment, exactly as before.
- **Several payments chosen.** Each bill line gets one amount per chosen
  payment (the allocation matrix). The payments' remaining amounts, the
  total allocated and the amount left unallocated update as amounts are
  typed. "Allocate automatically" fills the bills in order from the
  earliest payment. Before issuing, each bill's allocations must equal its
  net amount, no payment may be used beyond what is available, and no
  amount may be negative or invalid. Issuing asks for confirmation.
- **Limits.** At most 12 bills per issue and 6 payments per bill, checked
  before any transaction with a message saying what to change. Nothing is
  truncated.
- **Net amount above ₹0.** A bill must be supported by an amount actually
  paid, so a bill whose adjustment equals its gross (net ₹0) can no longer
  be issued. Existing bills like that stay readable and cancellable.
- **Bill-only adjustments** are never allocations: a payment supports the
  bill's net amount only (gross ₹4,200, adjustment ₹100, allocation
  ₹4,100).
- **Bill Reference.** A bill supported by several payments is numbered from
  its primary payment, the earliest by payment date (then the lowest receipt
  number), using that payment's own sequence:
  `{primary receipt number}-{six digits}`. Existing references and the
  per-payment sequences are unchanged; a reference is still never reused.
- **PDF.** A bill supported by one payment prints exactly as before. A bill
  supported by several lists every receipt number under Receipt Reference
  and adds a PAYMENT ALLOCATION table (payment reference, payment date,
  allocated amount, total allocated) between BILL DETAILS and the net
  amount, in the same layout. Administrators and parents download the same
  PDF.
- **Cancelling** a bill gives back to each of its payments exactly what it
  used: its ledger entries are marked released and a reversal record is
  written for each. No other bill's allocation is touched. A replacement
  gets a new reference and new allocations; for a bill supported by several
  payments, its allocations are prefilled from the cancelled bill's and can
  be changed (they must total its net amount).
- **Bills issued before the ledger** have no stored allocations. They are
  read as one allocation of their net amount from their one payment, and
  print as before. Nothing was migrated; when one is cancelled, its ledger
  entry is recorded then (`legacy: true`, already released) with its
  reversal record.
- **Report.** Fee Bill Issuance also shows what payments active bills use,
  what was collected on payments usable for bills, what is not yet
  allocated, any payment billed for more than its current amount (edited
  in Fees afterwards), and each payment's allocation. These are documents
  only, never income.
- **Parents** see, in an active bill's details, the payments supporting it
  (receipt number, date, amount used). A payment that supports several bills
  appears on each; it was still paid once, and Payment History is
  unchanged.

## Data model

### `fee_issued_bills/{schoolId}_{billNo}`

One immutable bill.

| Field | |
|---|---|
| `schoolId`, `billNo`, `status` | `issued` or `cancelled` |
| `receiptId`, `studentId` | the original payment and student (references) |
| `studentName`, `admissionNo` | snapshots from the receipt |
| `className` | the class selected for this bill (default: the receipt's) |
| `parentRelation`, `parentName` | the parent or guardian named, at issue (`''` when none) |
| `issueDate` | the first working day of the billing month |
| `amountIncludesGst` | "Amount includes GST" was ticked |
| `payment` | snapshot: `receiptId`, `receiptNo`, `amountPaise`, `paymentMode`, `referenceNo`, `paymentDate` |
| `billingMonth`, `description` | `YYYY-MM` and the item |
| `grossPaise`, `adjustmentType`, `adjustmentPaise`, `adjustmentReason`, `netPaise` | the line, in paise |
| `adjustment` | when there is one: `type`, `amountPaise`, `reason`, `createdBy`, `createdAt` |
| `school` | the header at issue: `name`, `addressLines`, `contactLines`, `logoUrl`, and `gstin` when shown |
| `issuedAt`, `issuedBy`, `issueRequestId`, `createdAt` | |
| `replacesBillId`, `replacedByBillId` | cancellation and reissue links |
| `cancellation` | `reason`, `by`, `at` (only once cancelled) |

Its `audit` subcollection holds the history entries (`issued`, `cancelled`,
`reprinted`), added to and never changed.

### `fee_bill_allocations/{receiptId}`

One per payment that has bills.

| Field | |
|---|---|
| `schoolId`, `receiptId`, `studentId` | |
| `paymentPaise` | the receipt's amount when last written |
| `allocatedPaise` | what active bills use of this payment (the sum of `bills`) |
| `bills` | active bill id → the paise that bill uses of this payment (its whole net for a one-payment bill) |
| `lineKeys` | active bill line (month and description) → bill id |
| `requests` | issue request id → the bill ids it created |
| `nextSequence` | the sequence of this payment's next Bill Reference (only increases) |
| `version`, `createdAt`, `updatedAt`, `updatedBy` | |

**Why it exists.** Firestore transactions can't run queries, so the total
of a payment's bills can't be checked safely by listing them. One document
per payment, read and written by every issue and cancel transaction, makes
the check atomic. Its consistency is kept as follows:

- It is only ever written in the same transaction as the bills it
  describes.
- `allocatedPaise` is recomputed from `bills` on every write.
- A transaction that finds it inconsistent refuses to write.
- The proposed rules require each new bill to be recorded in it at its net
  amount, the total to stay within the payment, and the version to advance
  by one.

**Bills supported by several payments** add these fields to
`fee_issued_bills` (every new bill has them; earlier bills don't):

| Field | |
|---|---|
| `allocations` | `[{allocationId, receiptId, receiptNo, paymentDate, paymentAmountPaise, allocatedPaise}]`, primary first; never changed |
| `receiptIds` | the supporting receipts' ids |
| `allocationSchema` | 2 |

`receiptId` and `payment` hold the primary payment.

### `fee_bill_payment_allocations/{billId}__{receiptId}`

The allocation ledger: one entry per bill and supporting payment. The id
makes a second allocation of the same payment to the same bill impossible.

| Field | |
|---|---|
| `schoolId`, `studentId`, `allocationId`, `billId`, `billNo` | |
| `receiptId`, `receiptNo`, `paymentDate`, `paymentAmountPaise` | the payment, as it was when allocated |
| `allocatedPaise` | |
| `status` | `active`, or `released` when the bill is cancelled |
| `reversalId`, `releasedAt`, `releasedBy` | set on release |
| `requestId`, `allocatedAt`, `allocatedBy` | |
| `legacy`, `recordedAt` | for a bill issued before the ledger, recorded when it is cancelled |

Written only in the issue and cancel transactions; details never change,
only `active` → `released`. Never deleted.

### `fee_bill_allocation_reversals/{allocationId}`

The explicit record of a released allocation: `allocationId`, `billId`,
`billNo`, `receiptId`, `receiptNo`, `releasedPaise`, `reason`,
`replacedByBillId`, `legacy`, `by`, `at`. Created once, never changed or
deleted.

### `fee_bill_issue_requests/{requestId}`

`schoolId`, `studentId`, `billIds`, `receiptIds`, `by`, `at`. A repeated
request returns these bills instead of issuing again. Earlier requests are
still recognised from `fee_bill_allocations.requests`.

**Transactions.** An issue reads the request record, then for every payment
used its receipt, its Fees transaction record and its allocation record,
then the new bill and ledger ids, and checks everything before writing the
bills, audit entries, ledger entries, allocation records and request record
together. A cancellation reads the bill, its payments' records, its ledger
entries and reversal ids (and, with a replacement, the replacement's
payments). Two transactions using the same payment are serialised by its
allocation record, so the second sees the first's allocations and is
refused if they no longer fit.

No student or payment record is copied apart from the snapshots needed for
the document's historical accuracy.

## Firestore rules (proposal, not deployed)

The deployed rules are not in this repository. The proposed rules for
these three paths are in `test/firebase_rules/fee_bills.firestore.rules`,
with emulator tests in `test/firebase_rules/fee_bills_rules_test.py`. Merge
them into the project's real rules after review. **Never deploy that file
on its own**: a deploy replaces all rules.

**Update needed before merging.** The proposal's `isValidNewBill` lists
the allowed bill fields (`hasOnly`), and it predates the issue date, parent
and GST snapshots. Add `issueDate`, `parentRelation`, `parentName` and
`amountIncludesGst` to that list, and re-run its emulator tests. Until then
the proposal would refuse new bills. `school.gstin` sits inside the
existing `school` map, so it needs no change.

With per-payment Bill References, the proposal also needs these changes:

- Drop the `system_counters/fee_bills_*` rule, which is no longer used.
- For `fee_bill_allocations`, require an integer `nextSequence` that never
  decreases.
- Optionally, require each new bill's `billNo` to be
  `{receipt's receiptNo}-{6 digits}`.

The existing check that the id is `{schoolId}_{billNo}` and that `billNo`
is at most 40 characters still holds: a base of up to 33 characters plus
`-000001` is at most 40.

**Who counts as an administrator.** A signed-in user with the custom claims
`role: 'admin'` and `schoolId` (the convention of
`website_content.firestore.rules`). Receipts have no `schoolId` today, so a
receipt without one is treated as `default_school`.

**`fee_issued_bills`**

- **Read:** an administrator of the bill's school.
- **Create:** an administrator of the bill's school, and only when all of
  these hold:
  - only the known fields;
  - id = `{schoolId}_{billNo}`;
  - status `issued`;
  - integer paise, with 0 ≤ adjustment ≤ gross and net = gross −
    adjustment;
  - a type and reason with any adjustment;
  - a valid month and description;
  - `issuedBy` = the signed-in user;
  - the receipt exists, is not voided, and belongs to the bill's school
    and student;
  - the allocation, after the write, records this bill at its net amount.
- **Update:** cancellation only, once.
  - Status goes from `issued` to `cancelled`.
  - Only `status`, `cancellation`, `replacedByBillId`, `updatedAt` and
    `updatedBy` may change.
  - A reason of 1–500 characters is required, with `cancellation.by` = the
    signed-in user.
  - The bill must be released from the allocation in the same write.
- **Delete:** never.

**`fee_issued_bills/{id}/audit`**

- **Read:** an administrator of the school.
- **Create:** an administrator of the school, with action `issued`,
  `cancelled` or `reprinted` and `by` = the signed-in user.
- **Update and delete:** never.

**`fee_bill_allocations`**

- **Read:** an administrator of the school.
- **Create and update:** an administrator of the school, and only when all
  of these hold:
  - the same school as before;
  - `receiptId` = the document id;
  - the receipt exists, is in the same school and is the same student's;
  - `paymentPaise` = the receipt's amount × 100, rounded;
  - integer `allocatedPaise` ≤ `paymentPaise` (a decrease, a release, is
    always allowed);
  - `version` advances by exactly one;
  - `updatedBy` = the signed-in user.
- **Delete:** never.

**`system_counters/fee_bills_{schoolId}`**

- **Read, create and update:** an administrator whose `schoolId` claim
  matches.
- `nextNumber` must be an integer and only increase.
- **Delete:** never.
- Merge this with any existing `system_counters` rules (the invoice
  counters).

No rule allows a write to `fee_receipts`, `fee_transactions`,
`student_fee_assignments`, `finance_income` or `finance_ledger`.

Run the emulator tests (demo project only; firebase-tools needs Java 21):

    PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:exec \
      --config test/firebase_rules/fee_bills.firebase.json \
      --project demo-montessori-bills --only firestore \
      "python3 -I test/firebase_rules/fee_bills_rules_test.py"

### Phase 2 additions for the whole-application rules review

Not implemented: rules work is deferred to the whole-application security
review, and the checks above are app-level only (an administrator role in
the app). The review must cover:

- `fee_issued_bills`: allow the new fields `allocations`, `receiptIds` and
  `allocationSchema` on create (in `hasOnly`), never on update.
- `fee_bill_payment_allocations`: administrators of the school only; create
  only in the same write as its bill (`getAfter`), with `status: active`;
  update only `active` → `released` with `reversalId`, `releasedAt` and
  `releasedBy`, and, for a bill issued before the ledger, create already
  released with `legacy: true`; never delete.
- `fee_bill_allocation_reversals`: administrators only; create once, in
  the same write as the bill's cancellation; never update or delete.
- `fee_bill_issue_requests`: administrators only; create once; never update
  or delete.
- `fee_bill_allocations`: `bills` now holds per-payment amounts. The sum
  checks (a payment's allocations within its amount, a bill's allocations
  equal to its net) can only be partly expressed in rules; the app checks
  them in its transactions.
- Reads of `fee_transactions` by Fee Bill Issuance (administrators).
- `parent_fee_bills`: the copy's new `allocations` (receipt number, payment
  date and amount used only).

No new indexes are needed: the new queries are single-field (`billId`,
`schoolId`). No Functions are added.

## Deployment prerequisites

1. Merge the three rule blocks into the real Firestore rules and deploy
   them, as a separate, approved step.
2. Administrators' Auth accounts need the `role: 'admin'` and `schoolId`
   custom claims for these rules. If the deployed rules identify
   administrators differently, adapt the helper functions before merging.
3. No index is needed: the app queries `fee_issued_bills` by `schoolId`
   only and `fee_receipts` by `studentId` only, both single-field equality
   queries.
4. No Cloud Function or Storage change. PDFs are generated in the browser
   from the stored snapshot and are not uploaded.

## Limitations

- One line is one bill. A bill with several items is not supported.
- The issue date relies on the school calendar being kept up to date. A
  holiday added after a bill is issued doesn't change that bill.
- Bill PDFs aren't stored. They are rebuilt from the immutable snapshot,
  which makes a reprint identical.
- A payment voided in Fees after bills were issued keeps its bills. The
  details show it as voided, and no new bill can be issued against it. Its
  bills can still be cancelled.
- If a collection is later edited in Fees to an amount below what is
  already billed, no new bill can be issued against it until enough bills
  are cancelled. The report lists such payments for review.
- A replacement bill for a multi-payment bill can use only the cancelled
  bill's payments from the bill details; to use other payments, cancel the
  bill and issue a new one.
