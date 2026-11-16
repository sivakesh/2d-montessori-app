# Fee receipt: Regenerate PDF

When a receipt already has a PDF, **Regenerate PDF** in the receipt view
opens the Regenerate dialog (`FeeReceiptRegenerateDialog`). The dialog
builds a professional copy (`RegeneratedReceipt` in
`lib/modules/fees/services/fee_receipt_regeneration.dart`), which is
downloaded as `<receipt no>-copy.pdf`.

Two things are unchanged and separate from it:

- **Generate PDF**, for a receipt with no PDF yet.
- The PDF made when a fee is collected.

Both still use the default receipt, `FeeService.generateAndUploadReceiptPdf`.
The stored PDF is never replaced by a regenerated copy.

## The regenerated receipt

The page is A4 portrait with print margins. Rows that have no value are
left out, so the receipt never shows a blank placeholder.

1. **Header.** The school logo, then the school name, then the postal
   address. The address is Line 1, then Line 2, then
   "Area, City, State - PIN". After the address come the phone number,
   email and website. The GSTIN appears only when the administrator opts
   in. All of these come from School Settings (`school_settings/{schoolId}`).
2. **FEE PAYMENT RECEIPT.** Shows the existing receipt number. The receipt
   date is the original payment date.
3. **Student Details.**
   - Father's, Mother's or Guardian's Name.
   - Student Name.
   - Admission No.
   - Class.
4. **Payment Details.**
   - Nature of Fee.
   - Service Period.
   - Payment Mode.
   - Transaction Reference.
   - Payment Date.
5. **Amount Paid** in figures, for example "Rs. 52,500.00", and in
   **Amount in Words**, for example "Rupees Fifty-Two Thousand Five Hundred
   Only". Both are calculated from the receipt's exact amount in paise
   (`IndianAmount`), so they always agree. The amount uses Indian lakh and
   crore grouping and includes paise when there are any.
6. **Footer:** "System-generated fee receipt. No signature required." The
   receipt has no signature line or signature image.

It has no Fee Name row and no Generated Date row.

### Where the prefilled values come from

All prefilled values come from saved records, and all of them can be
changed in the dialog. A change applies to the downloaded copy only.

- **Parent / Guardian:** the student's `parentLinks`. The father is
  preferred, then the mother. A relationship other than Father or Mother
  is shown as Guardian. If no parent or guardian is linked, the
  administrator can type a name.
- **Class:** the student's current class. Any existing class can be
  chosen. The receipt's recorded class stays in the list even if that
  class no longer exists.
- **Nature of Fee:** the fee structure's description. If it has none, the
  names of its components are used.
- **Service Period:** the fee month, for example "November 2026". If there
  is no fee month, the assignment's academic year is used, for example
  "Academic Year 2026-2027". The period is never inferred from dates.

### Nothing is written

Regenerating a receipt does not create or change any of the following:

- payments or fee transactions;
- receipts, their receipt numbers or their stored PDFs;
- fee assignments or outstanding balances;
- student records, parent links or class assignments;
- School Settings;
- Finance entries.

## GSTIN

The GSTIN is set in School Settings → Tax Registration.

- Only administrators can change it.
- It is validated by format and by its check character.
- A save that does not change the GSTIN keeps the saved value.
- Each school's GSTIN is stored in that school's own settings document.

## The two GST checkboxes

The Regenerate dialog has two separate checkboxes. Both are unticked by
default, and they are independent: either can be ticked without the other.

| Checkbox | What it does |
|---|---|
| **Show GSTIN on receipt** | Prints the school's GSTIN in the header. Nothing else. |
| **Amount includes GST** | Shows **"(GST Included)"** beside Amount Paid. Nothing else. |

- If **Show GSTIN on receipt** is ticked but no GSTIN is configured, or the
  saved GSTIN is not valid, the dialog shows a message and the copy cannot
  be downloaded.
- **Amount includes GST** does not need a GSTIN. It states what the amount
  paid already contains; showing the GSTIN identifies the school's
  registration. They are different things, so "(GST Included)" can appear
  without the GSTIN.
- Neither checkbox calculates GST, adds GST, changes the amount or the
  amount in words, or changes any payment, receipt or Finance record.
- Neither choice is saved. Both apply only to the downloaded copy, and the
  next time the dialog opens both are unticked again.

In code these are `ReceiptRegenerationOptions.showGstin` and
`ReceiptRegenerationOptions.amountIncludesGst`.

## Future release: a verified GST record

The Fees module has no GST calculation and no saved record of GST
inclusion today, so "(GST Included)" depends only on the administrator
ticking **Amount includes GST** for that copy. If a future release adds GST
to fee structures or payments, the checkbox should be prefilled (or
replaced) from that verified record, and the GSTIN checkbox should still
never set it.
