# Website forms (Forms Manager)

Enquiry and registration forms for the public website. This file covers the Forms Library, the builder, the Form block, submissions and the private Submissions Inbox.

> **Visitors' browsers write submissions directly to Firestore**, in the Firebase project the build uses (the local emulator, DEV or production). Whether a school accepts them is decided only by its own setting, **Settings → Public form submissions**, never by the environment. The app's checks are not a security boundary: anyone can write to Firestore directly, so **the rules must enforce them, and rules hardening is deferred to the final security module.** See [Direct submissions and environments](#direct-submissions-and-environments).

Code lives in `lib/modules/forms/`. Tests are in `test/website_forms_test.dart`, `test/public_submission_settings_test.dart` and `test/form_answer_parity_test.dart` (VM), and `test/emulator/` (Firestore and Auth emulators). `functions/` holds an **inactive** submission endpoint ([below](#inactive-submission-endpoint-functions)): not used and not deployed.

## Where it is

Open **Settings → Website forms**. It has two tabs:
- **Forms library**
- **Submissions**

Only admins can open it. Anyone else sees the locked view, and every service call checks the role again.

Whether visitors can send forms at all is set in **Settings → Public form submissions** ([below](#public-form-submissions-setting)). The Forms library shows its current state, with a **Change** link.

Forms appear on the website through the visual editor's **Form** block. It is added with Add block → Form. There is no ready-made section, because a ready-made section must be valid as created and a Form block needs a form chosen first.

## Data

Form definitions and submissions are kept in separate collections:

| Collection | Holds | Who reads it |
|---|---|---|
| `website_forms` | Each form as admins edit it: title, public `description`, `coverMediaId`, internal description, `items` (questions and content, in order), `fields` (the questions alone), `mediaIds`, success message, status, version, the last activated schema, timestamps, who changed it, `schoolId` | Admins |
| `website_public_forms` | The **active version** of each form, at the form's ID. It holds only `formId`, `schoolId`, `title`, `description`, `coverMediaId`, `items`, `fields`, `mediaIds`, `successMessage`, `version` and `activatedAt` (`PublicWebsiteForm.storedFields`). Only **Activate** writes it; **Deactivate** and **Delete** remove it. | The public website |
| `website_form_versions` | One record per activated version (`<formId>_v<n>`): its full visitor schema, when, and by whom. Written once, never changed. | Admins |
| `website_deleted_forms` | What remains of a deleted form, at its ID: title, template, last version, last active schema, questions and content, who deleted it and when. Written once, never changed. | Admins |
| `website_form_submissions` | One document per submission, at its submission key: `reference`, `formId`, `formVersion`, `formTitle`, `schoolId`, a `fields` snapshot, `answers`, `status`, `createdAt`, `updatedAt` | Admins |
| `website_form_submissions/{id}/notes` | Internal notes: `text`, `authorId`, `authorName`, `createdAt` | Admins |
| `school_settings/{schoolId}` → `publicFormSubmissions` | The school's public-submissions setting: `enabled`, `closedMessage`, `revision`, `updatedAt`, `updatedById`, `updatedByName` (one map in the existing School Settings record) | Admins (signed-in users read the record for the school's name and logo) |
| `school_settings/{schoolId}/audit` | One entry per change of that setting: `action`, `enabled`, `previousEnabled`, `closedMessageChanged`, `revision`, `byId`, `byName`, `at`. Never changed. | Admins |
| `website_public_settings/{schoolId}` | The visitor copy of that setting: `schoolId`, `submissionsOpen`, `closedMessage`, `revision`, `updatedAt` (no administrator details) | The public website: the form's open or closed state, and the check before each write |

- **Page blocks** store only the form's ID, heading and introduction. One form can sit on many pages without its definition being copied.
- **Items and fields.** A form's content is `items`: questions (`f_…`) and content blocks (`c_…`, marked `kind: content`). `fields` repeats just the questions, so older readers, the submission snapshot and the proposed rules' `fields` check keep working. On read, `items` is used when present (a form saved before content blocks has only `fields`). A visitor copy whose `items` and `fields` disagree is refused.
- **Images are stored by media ID only**, never as a URL or storage path. Visitors see an image only while it is published, consent-confirmed and has a file; otherwise the form is shown without it.
- **School scope:** everything carries `schoolId` (`default_school`, from `kDefaultSchoolId`). Every admin query filters on it, and every single-document operation checks it.
- **`website_public_items`** is unchanged.

## Forms library

Admins can:
- create a form from a template;
- search forms by title and filter them by status (Draft, Active, Inactive);
- edit, duplicate, preview, activate and deactivate a form.

There are four starter templates: **Admission Enquiry**, **General Enquiry**, **Event Registration** and **Custom Form**. A template only provides starting fields (each with fresh field IDs) and a success message. Every form is then edited the same way.

### Activation and versions

- **Saving never changes what visitors see.**
  - Saving writes only the editable content.
  - It never writes status or version: those are never taken from the browser.
  - It refuses malformed schemas: unknown field types, options that can't be read, or anything over the limits.
- **Activate:**
  1. Checks the complete schema as stored. It needs a title, labels, at least two distinct options per dropdown or radio field, a success message and at least one field.
  2. Writes the visitor copy.
  3. Marks the form Active.
  
  The visitor copy and the status are written in one batch.
- **Version numbers:**
  - A changed schema gets the next version number.
  - Activating an unchanged schema keeps its number, including after deactivating and reactivating.
- **Editing an active form:**
  - The card shows "Changes not active".
  - Visitors keep the old version until **Activate changes** is used.
- **Deactivate:**
  - Deletes the visitor copy and marks the form Inactive.
  - The form's submissions are kept, and it can be activated again.
- **Duplicate** creates a new Draft at version 0, titled "Copy of …", with **fresh IDs** for the form, every question, option and content block. It keeps the cover image and description.
- **Version history:** each activation of a changed form writes a record in `website_form_versions`. The builder's Form settings list them (version, title, number of questions, when and by whom).
- **Delete** (see [Deleting a form](#deleting-a-form)).

### Required title, description and cover image

- **Drafts may be incomplete.** Saving refuses only malformed data: unknown types, unreadable settings, IDs that aren't IDs, and anything over the limits.
- **Activation needs all three**, in English: a title, a description (shown under the title), and a cover image.
- **Every image the form uses must be eligible:** the cover and every image block. It must exist in the media library, be published with consent confirmed and a file, and have English alt text (`WebsiteFormsService.imageProblem`). Otherwise activation is refused, with the reason.
- **A previously eligible image later hidden, deleted or with consent withdrawn:**
  - Visitors see the form without that image; the public site only resolves published, consented images.
  - The library card warns "Cover image not shown to visitors", and the builder names the problem.
  - The active version stays as it is until an admin activates changes.
- **Media protection:**
  - An image used by any form (draft or active) can't be deleted from the media library.
  - An image shown by an active form can't be hidden.
  - Withdrawing consent always works, and removes the image from the website at once.

### Visual builder

It is laid out like the website's page builder (`WebsiteVisualEditor`), with the same breakpoint (`narrowEditorWidth`) and the same shared pieces (`websiteField`, `showWebsiteImagePicker`, `WebsiteMediaThumb`, `WebsiteStatusChip`). The page builder itself is unchanged: its canvas and panels are tied to page blocks, so they are mirrored rather than shared.

- **Structure (left):**
  - Form settings, then every question and content block in order.
  - **Select** an item by clicking it.
  - **Reorder** by dragging the handle, or with Move up and Move down.
  - **Duplicate** an item (it gets a new ID) or **remove** it.
  - **+ Add** inserts a question or content after the selected item.
  - Items with problems are marked.
- **Canvas (centre):**
  - The form as visitors see it, drawn by the public renderer (`PublicWebsiteFormView`).
  - It is laid out at desktop (960 px), tablet (768 px) or phone (390 px) width, and scaled down to fit, as the page builder does.
  - Click any item, or the cover and title, to select it.
  - Images visitors couldn't see are shown as a warning on the canvas only.
- **Properties (right):**
  - **Nothing selected:** Form settings: title, description, cover image, success message, internal description, version history.
  - **A question selected:** its settings.
  - **Content selected:** its text or image.
- **Narrower than 840 px:** one panel at a time (Form, Structure, Edit), with an Edit button for the selection.
- **Status:** chips show Draft or Active, the visitor version, "Changes not active", "Unsaved edits" and "N to fix". A "To fix before activating" list is above the canvas.
- **Save draft** is enabled only with unsaved edits. **Activate** saves first, then asks for confirmation.
- **Leaving** with unsaved edits asks first ("Leave without saving?").
- **Preview** opens the draft at desktop, tablet or phone width. Nothing can be sent from it.

**Content blocks**, insertable anywhere among the questions:
- Section heading, with an optional description.
- Text or instructions.
- Image: from the media library, with an optional caption; alt text comes from the library.
- Divider.

Every item keeps its ID when it is moved or edited. Submissions snapshot only the questions, so content changes never affect earlier responses.

**Field types:**
- Short text
- Email
- Phone
- Number
- Dropdown
- Radio buttons
- Checkbox (its label is the consent statement)
- Long text
- Date
- Document upload (see [Document attachment fields](#document-attachment-fields))

**Each field has:**
- a stable ID (`f_xxxxxxxx`), a type and a label (English; see [Languages](#languages));
- a required flag ("Must be ticked" for a checkbox; marked `*` for visitors, and "(optional)" otherwise);
- a placeholder (typed fields);
- help text (shown under it);
- a custom error message (shown instead of the standard one);
- options (dropdown and radio; each option has a stable ID, `o_…`);
- **constraints:** fewest and most characters (short and long text), smallest and largest value (number), and earliest and latest date (date).

Contradictory settings are refused (a minimum above the maximum, a date not written `YYYY-MM-DD`, a constraint on a type that has none). Errors are shown with each field and announced to screen readers.

### Builder upgrade (long text, layout, steps)

**Stored data is kept.** Questions, their options and content items keep every stored key this version doesn't read (`extra`), and write it back unchanged: in the draft, the visitor copy and submission snapshots. A placeholder stored on a dropdown or radio question (which shows none, say after a type change) is kept as stored too. The form itself keeps top-level keys it doesn't read (`WebsiteForm.extra`): saving updates only the keys it writes, and a duplicate carries them, with the form's step and completion settings. They stay on the draft and never reach the visitor copy or its version records, which hold only what visitors see. Ids, Tamil text and forms stored before content items (questions only) are unchanged by editing and saving (`test/website_forms_compat_test.dart`).

**New settings** (each stored only when set, so earlier questions are written back exactly as they were):

| Setting | On | Stored as | Default |
|---|---|---|---|
| Visible rows (2–12) | Long text | `rows` | 4 |
| Height: grows with the answer, or fixed at its rows (scrolls) | Long text | `resize` (`fixed`) | grows, up to 10 rows (as before), or to its rows if more |
| Character counter: automatic, show, hide | Short and long text | `counter` | shown for long text and with a most-characters limit |
| Width on wider screens: full, half, one third | Every question | `width` | automatic: two short questions to a row, as before |
| Default answer (typed, or an option) | All but checkbox and attachment | `defaultValue` | none; never for a checkbox, so consent is never given in advance |
| Show to visitors | Questions and content | `hidden: true` | shown |
| Show the form in steps; review before sending | Form | `multiStep`, `reviewStep` | one page |
| Completion heading | Form | `completionTitle` | none |

A new content item, **Page break** (`page_break`, with an optional step title), starts a step of a multi-step form; on a single-page form it shows nothing.

**Answer validation is unchanged.** Every new setting is about display. A hidden question or content item is left out of the version visitors see (`toPublic`), so it is never asked and never required, and the browser's checks and the submission service's (and the inactive endpoint's) see the same questions. A default answer must be one the question accepts (checked when saving). Each step is checked with the same `validateFormAnswers` before Next, and the whole form again before sending. The visitor copy gains `multiStep`, `reviewStep` and `completionTitle` only when set (`PublicWebsiteForm.optionalStoredFields`); a single-page form's copy has exactly the keys it had. Builds from before this change don't know `page_break`: they treat a form with one as unusable and show nothing, so deploy this build before activating such a form.

**Builder.** Settings are in collapsible groups (Basic information, Placeholder and help text, Validation, open at first; Display and layout, Advanced), showing only what applies to the question's type. The structure lists each item with its type icon, `*` for required and an eye for hidden; removing asks first. The add menu has icons, **Long text (multiline)** and a **Consent checkbox (required)** preset. Hidden items show dimmed on the canvas, marked "Hidden from visitors"; page breaks show where each step starts. Form settings has **Steps** and the completion heading.

**Visitors.**
- A note says "Fields marked * are required".
- When answers aren't accepted (on Send or Next), a summary lists each one, as a link to the question, and the first is focused.
- Long text shows its counter ("120 / 500", read as "120 of 500 characters"), which stays beside an error message; what was typed is kept.
- Multi-step forms show "Step 2 of 4 · About your child" with a progress bar, Previous and Next (Next checks only that step), keep every answer when moving between steps, and, with review on, list every answer with **Change** before Send.
- After sending: the completion heading, the success message and the reference.

**Not built yet (needs approval):** URL and Yes/No questions and conditional logic (they change answer validation, so `functions/` must change with them); document uploads (secure upload path and Storage rules); per-field CSS (widths and the design system instead).

### Document attachment fields

An admin can configure:
- the label and help text;
- the allowed file types: PDF, JPG, PNG, DOC, DOCX (their MIME types are listed);
- the largest file (1–10 MB);
- the most files (1–5).

**Visitors can't upload yet** (`FormAttachments.publicUploadsEnabled = false`):
- The field is shown disabled, with its limits and "Document uploads aren't available yet. Please send documents to the school directly."
- It is never required meanwhile, and any answer to it is refused by the app (the service rejects it too).
- The builder says so.
- No upload code or Storage path exists.

When uploads are built, they must:
- go through the trusted backend, which checks each file's type and size;
- be stored in a private path, never world-readable and never served by public URLs;
- be readable by admins only.

A submission keeps its snapshot, so removing an attachment field later leaves earlier responses readable.

Limits (`FormLimits`):

| What | Limit |
|---|---|
| Fields per form | 30 |
| Options per field | 20 |
| Title | 120 characters |
| Label | 200 characters (600 for a checkbox's consent text) |
| Placeholder | 120 characters |
| Option label | 100 characters |
| Success message | 500 characters |
| Internal description | 1,000 characters |
| Short text answer | 200 characters |
| Long text answer | 3,000 characters |
| Email answer | 254 characters |
| Phone answer | 25 characters |
| Number answer | 30 characters |
| Help text | 300 characters |
| Custom error message | 200 characters |
| Headings, texts, images and dividers per form | 30 |
| Content text | 2,000 characters |

Out of scope: public file uploads, payments, conditional logic, multi-step forms, page breaks and marketing automation (see [Designs for later](#designs-for-later)).

### Deleting a form

**Delete** is in the Forms library.
- **Before deleting**, the dialog lists every page (draft or published) with a Form block showing the form (`WebsiteFormsService.formReferences`). Those blocks then show visitors nothing; the editor flags them.
- **Confirmation:** the admin must type the form's title exactly. The service checks it too.
- **The steps:**
  1. **Off the website first:** the visitor copy is removed and the form marked Inactive. If that fails, nothing is deleted, and the error says so.
  2. **Then together:** an immutable record in `website_deleted_forms` is written, and the definition is deleted.
- **Never touched:** submissions, their notes and snapshots, version records and images.
- **In the inbox,** deleted forms' submissions stay readable and searchable, marked "Form deleted". The form filter shows "(deleted)".
- **Retrying** is safe: a form already deleted is reported as done.
- **Access:** admin only, and school-scoped.

## Form block

The block's settings are:
- **Form:** chosen from the active forms.
- **Heading:** English.
- **Introduction:** optional.
- **Styles:** the usual background, spacing, colours and width.

Rendering:
- **Visitors** see the form's active version, read from `website_public_forms` only. An inactive, deleted, malformed or other-school form shows nothing, not even the heading.
- **In the editor:**
  - If the chosen form is no longer active, the dropdown and the canvas both say so.
  - The canvas preview never sends anything.
- **Previewing drafts:** an admin previews a draft form in the builder, never through the public read.

Layout:
- From 640 px wide, consecutive short fields (short text, email, phone, date) sit two to a row.
- Narrower than that, it is one column. It is tested at 1200, 700, 360 and 320 px with no overflow.

The form's own wording (Send, error messages) has English and Tamil versions (`FormStrings`), used if a visitor switches the public site to Tamil. **The Tamil should be reviewed by a native speaker.**

## Submissions

Every answer is checked by `validateFormAnswers`, in the form (for messages) and again by `FormSubmissionService` before the write. It enforces:
- required fields, and that a required checkbox is ticked;
- email format;
- phone format: 7 to 15 digits, with `+`, spaces, brackets, dots or dashes;
- dates as real `YYYY-MM-DD` dates;
- dropdown and radio answers that are the saved option IDs;
- the length limits above;
- the right value types;
- no answers for fields the form doesn't have.

`FormSubmissionService.submit` (from the browser: `DirectFirestoreSubmissionGateway`, source `visitorCopy`) builds the submission from stored data, not from the request. In order:
1. **The school's setting must be on.** From the browser it reads the setting's visitor copy (`website_public_settings/{schoolId}.submissionsOpen`, written in the same transaction as `school_settings/{schoolId}.publicFormSubmissions`). Missing, malformed, another school's, unreadable or off is refused as closed.
2. The form's visitor copy (`website_public_forms/{formId}`) must exist, be usable and be this school's. It exists only while the form is active.
3. A request carrying an old version is refused as `formChanged`.
4. The answers are validated against that version's fields.
5. In one transaction:
   - the setting is read **again, right before the write**: switched off meanwhile, refused;
   - the submission key is checked: if it's already stored, nothing new is written;
   - the submission is written to `website_form_submissions/{submissionKey}`.
6. The submission stores the school, version, title and field snapshot from the form's visitor copy, the validated answers, a status (Spam when the honeypot is filled) and server times. The request has no school, status or time field.
7. Success is shown only after Firestore confirms the commit. Answers are never logged.

**Refusals by Firestore are never shown as success.** A permission error, on the write or on the duplicate check, is reported as "The website couldn't save your response". If the rules hide stored submissions from visitors, a resend of a key that was already stored is refused rather than confirmed. It is still stored only once.

The `storedDefinition` source also checks the admins' definition and reads the school's settings record. It's for a trusted caller (tests, a future backend), not the browser.

In the browser, each filled-in form gets one random key:
- **Send** is disabled while sending.
- A retry after a network failure reuses the key, so it can't be stored twice.
- After a refusal for invalid answers, the corrected form gets a new key.

Error states:

| State | What the visitor is told |
|---|---|
| Field errors | Per field, plus "Please check the highlighted answers." |
| Submissions switched off (or the setting can't be read) | The school's closed message, or: online submissions aren't open yet; contact the school. Shown up front, with Send disabled. |
| Form no longer accepting responses | The form is no longer accepting responses. |
| Form changed | The form has been updated; reload the page. |
| Firestore refused the write (`permission-denied`) | The website couldn't save your response; contact the school. Never shown as "closed" or as sent. |
| Storing failed (connection, timeout) | The response couldn't be sent; try again. |

On success, the visitor sees the success message and their reference, `WF-XXXXXXXX`.

## Submissions inbox

- **Finding submissions:**
  - Search by reference or by answers.
  - Filter by form, by status, and by period: today, the last 7 days or the last 30 days.
  - The list shows 20 per page.
- **Detail view:**
  - It shows the answers labelled from the submission's own snapshot, so they stay readable after the form is edited or deactivated.
  - It shows the reference, version and timestamps.
  - Status can be set to New, Contacted, In Progress, Closed or Spam.
  - Internal notes (up to 2,000 characters) are stored in the `notes` subcollection, never on the submission or anything public.
- **CSV export** (web only) downloads the filtered submissions:
  - Columns: reference, time in UTC, form, version, status, then one column per question.
  - **Not included:** internal notes.
  - **Formula safety:** cells starting with `= + - @` are prefixed with `'` so spreadsheets can't run them.
  - It is written in the browser through `dart:js_interop`, with no new dependency.

## Public form submissions setting

**Settings → Public form submissions** (also linked from the Forms library) switches public submissions on or off for the school, and sets the message visitors see while they're off. It is the only switch: no environment opens or closes submissions.

- **Off by default.** A school that has never saved the setting, or whose setting can't be read, is closed.
- **Screen:**
  - an ON/OFF switch with a confirmation;
  - the current status;
  - the closed message (up to 300 characters; blank uses the website's own wording, in English or Tamil);
  - who changed it last and when.
  - The switch always shows what is saved. A change shows only after it is saved; a failed change says so and reloads the saved state.
  - **Concurrent changes:** each save carries the revision it was read at. If another admin saved first, the change is refused, nothing is written, and the screen shows what is saved now.
  - A failed submission never changes the setting.
- **Where it's stored** (`PublicSubmissionSettingsService`, one transaction, or nothing):
  - the school's own record, `school_settings/{schoolId}.publicFormSubmissions` (the existing School Settings document; its name, contact details and logo are kept);
  - the visitor copy, `website_public_settings/{schoolId}`, which the public form reads to show itself open or closed, and checks before each write (visitors can't read `school_settings` under the proposed rules);
  - an audit entry, `school_settings/{schoolId}/audit`.
- **Who can change it:** admins of that school only. The service refuses any other role, and an admin whose school isn't the setting's. The app serves one school (`kDefaultSchoolId`), and `AppUser` has no school, so an admin's school is that one. The proposed rules identify it by a `schoolId` claim (absent: `default_school`).
- **The public form** (`publicSubmissionStatusProvider`, a live read of the visitor copy):
  - **Off:** the form is still shown, with the school's closed message (or the website's wording), and Send is disabled.
  - **On:** Send is enabled. After a successful submission the form is replaced by the confirmation and reference, so it can't be sent twice; a retry reuses the same key.
  - **Loading:** Send is disabled, with no message yet. **Unreadable:** closed.
  - **Switched off while a visitor has the form open:** the form closes as soon as the change arrives, keeping what they typed. If they send before it arrives, the check right before the write refuses it as closed and the form shows the closed message.
- **Enforcement:** the app checks the setting before writing, and the proposed rules refuse a new submission unless the visitor copy says `submissionsOpen: true`. The deployed rules don't (see below); that is for the final security module.
- **Existing data:** switching it never changes forms, versions, submissions or notes.

## Direct submissions and environments

### Which project each build writes to

The browser writes with `FirebaseFirestore.instance`, initialised from `DEPLOY_TARGET` (`firebaseOptionsFor`), and connected to the emulator when `FIRESTORE_EMULATOR_HOST` is set (`main.dart`). No environment name opens or closes submissions.

| Environment | Build | Writes to |
|---|---|---|
| **Local** | `--dart-define=FIRESTORE_EMULATOR_HOST=127.0.0.1:8086` (DEV target) | The local Firestore emulator only. The setting is loopback-only and refused with `DEPLOY_TARGET=prod`. |
| **DEV** | `DEPLOY_TARGET=dev` | `montessori-app-95988` |
| **Staging** | **Not configured** (no project, alias or `DeployTarget`) | — |
| **Production** | `DEPLOY_TARGET=prod` | `twod-montessori-prod`. Not used or deployed without approval. |

A DEV build can't write to production, or the reverse: each build has only its own project's options (`test/prod01_deploy_target_test.dart`).

### DEV results (2026-10-28)

All read-only and unauthenticated, except one synthetic submission, which was written through the app's own `DirectFirestoreSubmissionGateway` from a local web build with the DEV options. No settings or rules were changed.

| Check | Result |
|---|---|
| Read `website_public_settings/default_school` | Allowed. `submissionsOpen: true`, revision 3 (saved 2026-10-27 20:13 UTC, through the admin screen). |
| Read `website_public_forms` | Allowed. One active form (`3s70Y7L3aIBPhAlmuRpb`, v2). |
| Get a submission key that doesn't exist | Allowed (404). |
| **Write a synthetic submission** | **Allowed.** `website_form_submissions/bbg88vry7ff7w3ocvp092z001yl6xnja` (`WF-BBG88VRY`): status `new`, version 2, `default_school`, the full field set. No permission error. |
| Read `school_settings/default_school` unauthenticated | **Allowed** (the proposal allows signed-in users only). |
| **List `website_form_submissions` unauthenticated** | **Allowed: anyone can read every submission's answers in DEV.** |

So the current DEV rules permit the direct write, and are broadly open. The last two rows are exposures for the final security module; nothing here changed them. The synthetic submission can be marked Spam or Closed in the inbox.

**The deployed DEV website** is still the build deployed for UAT on 2026-10-28, from before the setting existed. Its forms stay closed whatever the setting says, until the current build is deployed to Hosting (needs approval).

### Security (deferred to the final module)

The app's checks run in the visitor's browser, so they are **not a security boundary**. With the current DEV rules anyone can:
- write any document to `website_form_submissions` (any shape, any school, while the setting is off);
- read every submission;
- read `school_settings`.

The proposed rules (`test/firebase_rules/forms.firestore.rules`, emulator only, **never deployed**) narrow this:
- **A new submission only:**
  - while the school's `website_public_settings` copy says `submissionsOpen: true`;
  - for a form whose visitor copy exists;
  - with that copy's school, version, title and fields, status New or Spam, the derived reference and server timestamps, and no other keys.
- **Reads:** visitors may only learn that a key is still free. Admins read and change status; `notes` are admins only.
- **Settings:** `website_public_settings` is public read, school-admin write; `school_settings` and its `audit` are school-admin.

Even those rules can't check each answer's type or options, rate-limit, or stop automated submissions. A protected endpoint ([below](#inactive-submission-endpoint-functions)) or App Check would be needed for that. The final module decides.

### Emulator checks

`test/emulator/forms_emulator_checks.dart` runs the real services through the real Firestore and Auth web plugins, against the Firestore and Auth emulators, under the proposed rules, writing submissions directly as the website does. The admin signs in through the Auth emulator with an unsigned custom token carrying the `role: admin` claim.

The checks cover:
- the build's gateway writing directly to Firestore;
- the public submissions setting:
  - off for a school that never saved it, by the app and by the rules;
  - off refused by the app, and direct writes refused by the rules;
  - visitors and another school's admin can't change it; changes are audited; on again is accepted;
- a valid submission stored and read back by the inbox, with status and notes;
- visitors unable to read submissions, notes or form definitions;
- invalid answers refused by the app, and crafted direct writes refused by the rules;
- inactive and draft forms;
- duplicates: a resend stores nothing new and isn't reported as sent;
- version mismatch and per-version snapshots;
- school isolation;
- the honeypot;
- deleting a form: submissions and notes kept, and version and deleted-form records immutable and admin-only;
- the Submissions Inbox screen showing a saved submission;
- local development mode: the seeded `/pages/privacy` form open and submitting through the app's own gateway.

`flutter test --platform chrome` crashes in this Flutter SDK before loading any test (`currentPackageConfig`). So the checks are a small web app that `test/emulator/run_forms_emulator_checks.sh` builds into a temporary folder, opens in headless Chrome, and reads results from the console. Run:

```
PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:exec \
  --config test/firebase_rules/forms.firebase.json \
  --project demo-montessori-forms --only firestore,auth \
  "bash \"$PWD/test/emulator/run_forms_emulator_checks.sh\" \"$PWD\""
```

It needs JDK 21, Chrome and network access (the Firebase web SDK is loaded from gstatic). It refuses non-demo projects.

### Inactive submission endpoint (`functions/`)

`functions/` holds an HTTPS callable function (`submitWebsiteForm`) that runs the same checks with the Admin SDK, plus rate limits, request validation and optional App Check. It is **not used by the app, has no deploy configuration and is deployed nowhere** (the Cloud Functions API isn't enabled in DEV). It is kept, with its tests, as one option for the final security module.
- `functions/test/` covers it against the Firestore emulator: `npm --prefix functions install`, then `firebase emulators:exec --config test/firebase_rules/forms.firebase.json --project demo-montessori-forms --only firestore "npm --prefix functions test"`.
- `test/fixtures/form_answer_cases.json` holds the validation cases both it and the app must agree on (`test/form_answer_parity_test.dart`).

## Languages

Editing is **English only** for now: `multilingualEditing = false`, in `website_content_editors.dart`. No form or website editor shows a Tamil field or a preview-language switch, and the Languages tab is hidden. The language module will turn this back on: enable a language, translate the English with AI, store the translations, and let admins review them.

- **Stored Tamil is kept.** Existing Tamil text in forms, pages, the layout and media isn't deleted or migrated. Editors carry it when saving English changes, and the public website still shows it.
- **Tamil is never required.** No validation asks for it; new forms are saved with empty Tamil.
- **The data model is unchanged.** Every text is still `{en, ta, …}` (`LocalizedText`), so the language module can fill in other languages without a migration.

## Designs for later

These aren't implemented. Each fits the current model without a migration.

- **Conditional show/hide.**
  - Add an optional `showWhen` to any item: `{fieldId, operator: equals|notEquals|isAnswered, value}`, referring only to an earlier question.
  - Validation would skip hidden questions on both sides (browser and backend). Hidden questions' answers would be refused.
  - Snapshots stay as they are.
- **Multi-page forms.**
  - A `page_break` content block splits items into pages, with a progress indicator ("Step 2 of 4").
  - Each page is validated before Next; the whole form is validated again on submit.
  - The canvas would show page separators.
- **Reusable field groups.**
  - A `website_form_groups` collection of saved item lists (for example, "Parent details").
  - Inserting a group copies its items with fresh IDs, so editing the group never changes existing forms.
- **Email and WhatsApp notifications.**
  - Sent by the trusted backend after a submission is stored (never from the browser), to staff addresses configured per form.
  - Visitor confirmations only with consent.
  - The message names the form and reference, not the answers.
- **Custom date ranges and analytics.**
  - Replace the inbox's period filter with from/to dates (`SubmissionsQuery` already supports them).
  - Add per-form counts by status and by week, computed in the admin app from the submissions list (no new collection).

## Browser UAT

1. As a teacher, check that Settings → Website forms is locked.
2. As an admin:
   - Create a form from each template.
   - Edit fields, reorder them, add options and remove options.
   - Check the problems list, then Preview.
3. Save and check that nothing appears on the website. Activate and confirm.
4. Duplicate a form, and check the copy is a Draft.
5. Add a Form block to a page (Add block → Form), choose the form and publish the page. Check the form at desktop, tablet, 360 px and 320 px.
6. Click Send with required fields empty. Then enter an invalid email, phone and date. Check each message.
7. Fill in the form correctly and click Send:
   - with **Settings → Public form submissions** off: the closed message is shown up front and Send is disabled;
   - on: the confirmation and a `WF-…` reference (locally, in the emulator; in DEV, in the DEV project);
   - on, where the rules refuse the write: "The website couldn't save your response".
8. Edit the form and save it: the page still shows the old version. Activate the changes and check the version increments.
9. Deactivate the form: the block disappears from the page, and the editor flags the inactive choice.
10. Inbox (use synthetic submissions created in the emulator):
    - Check search, filters and pagination.
    - Open a submission, change its status and add a note.
    - Export CSV, and check the notes are absent and formula cells are neutralised.

### Visual builder, metadata, attachments and deletion

11. Open a form in the builder at desktop width, then below 840 px. Check the three panels, and the Form / Structure / Edit tabs.
12. Clear the description and cover image, and check that activation is blocked with the reasons.
13. Choose a cover image. Try a draft, hidden or consent-withdrawn image: each is named as not visible. Activate with a published one.
14. Add a section heading, a text, an image and a divider between questions. Drag them, and use Move up, Move down, Duplicate and Remove. Check the canvas updates live.
15. Set help text, a custom error message, a minimum length, a number range and a date range. Preview, and check each message.
16. Add a document upload field. Choose file types, the size and the count. On the website it is disabled, with the "not available yet" note.
17. Switch the canvas and the preview between desktop, tablet and phone. Check that nothing overflows at 320 px on the website.
18. Make an edit, then press Back: "Leave without saving?" appears.
19. Duplicate a form, and check the copy's questions are the same but new.
20. In the media library, try to delete the cover image (refused, naming the form) and to hide it while the form is active (refused).
21. Delete a form that a page shows:
    - the dialog lists the page;
    - Delete stays disabled until the title is typed;
    - afterwards the page shows nothing there;
    - the inbox still lists its submissions, marked "Form deleted", with notes intact.

