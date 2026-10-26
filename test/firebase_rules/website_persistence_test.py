"""Emulator checks of real Firestore behaviour for the visual site editor's
write paths: what the rules allow, and what the stored document looks like
afterwards. fake_cloud_firestore differs from Firestore here (it ignores
`mergeFields` and deep-merges maps on `update`), so these checks are the
proof the Dart tests can't give.

Each step sends exactly the write the Flutter SDK sends for the service's
call (WebsiteContentAdminService):
  - set(data)                  -> a full write (no mask, no precondition);
  - set(data, mergeFields: k)  -> a write with update mask k, no precondition;
  - update(data)               -> a write with update mask = data's keys and
                                  "document exists"; a masked field with no
                                  value (FieldValue.delete()) is removed;
  - a WriteBatch               -> one atomic commit.

Same setup as website_rules_test.py (demo- project only, standard library):

    firebase emulators:exec --config test/firebase_rules/firebase.json \
      --project demo-montessori-website --only firestore \
      "python3 -I test/firebase_rules/website_persistence_test.py"

RULES_UNDER_TEST=previous runs against the rules before the visual editor
(Contact and the layout's design, header and footer then refused), to list
exactly which operations need the rules change.
Exits non-zero if any check fails.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from website_rules_test import (  # noqa: E402  (shared emulator helpers)
    ADMIN, DOCS, OWNER, PROJECT, PUBLIC, STAFF, live_layout, request, reset_firestore, value,
)

PREVIOUS = os.environ.get("RULES_UNDER_TEST") == "previous"
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
DELETE = object()  # FieldValue.delete()

results = []


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))


def decode(v):
    kind, raw = next(iter(v.items()))
    if kind == "mapValue":
        return {k: decode(x) for k, x in raw.get("fields", {}).items()}
    if kind == "arrayValue":
        return [decode(x) for x in raw.get("values", [])]
    if kind == "integerValue":
        return int(raw)
    return raw


def read(path):
    status, body = request("GET", f"{DOCS}/{path}", OWNER)
    return {k: decode(v) for k, v in body.get("fields", {}).items()} if status == 200 else None


def write_op(path, data, mask=None, exists=False):
    """One write as the SDK sends it (see the module docstring)."""
    fields = {k: value(v) for k, v in data.items() if v is not DELETE}
    op = {"update": {"name": f"{ROOT}/{path}", "fields": fields}}
    if mask is not None:
        op["updateMask"] = {"fieldPaths": [f"`{k}`" if not k.replace("_", "").isalnum() else k for k in mask]}
    if exists:
        op["currentDocument"] = {"exists": True}
    return op


def delete_op(path):
    return {"delete": f"{ROOT}/{path}"}


def commit(ops, auth):
    status, _ = request("POST", f"{DOCS}:commit", auth, {"writes": ops})
    return status


def set_(path, data, auth=ADMIN):
    return commit([write_op(path, data)], auth)


def set_merge_fields(path, data, auth=ADMIN):
    return commit([write_op(path, data, mask=list(data))], auth)


def update(path, data, auth=ADMIN):
    return commit([write_op(path, data, mask=list(data), exists=True)], auth)


def delete(path, auth=ADMIN):
    return commit([delete_op(path)], auth)


def expect_status(name, status, allowed):
    ok = (200 <= status < 300) if allowed else status in (401, 403)
    check(f"{'allow' if allowed else 'deny '} {name}", ok, f"HTTP {status}")
    return 200 <= status < 300


EDITOR = {"updatedAt": "2026-10-26T10:00:00Z", "updatedById": "9000000000", "updatedByName": "Admin"}
SECTION = {"id": "b1", "type": "section", "v": 1, "columns": [{"id": "c1", "blocks": [{"id": "b2", "type": "text", "v": 1, "heading": {"en": "Hello", "ta": "வணக்கம்"}}]}]}
DESIGN = {"palette": [{"id": "forest", "name": "Forest", "hex": "#123456"}], "bodySize": 17, "headingSize": 26, "lineHeight": 1.6}


def layout_checks():
    # A layout draft as the app leaves it after publishing, plus a field a
    # newer version wrote and a third language in the site name.
    reset_firestore()
    seeded = {**live_layout(siteName={"en": "2D Montessori", "ta": "டூடி", "hi": "टूडी"}), **EDITOR,
              "lastPublishedAt": "2026-10-20T09:00:00Z", "lastPublishedById": "9000000001", "lastPublishedByName": "Earlier admin",
              "design": DESIGN, "header": {"background": "token:forest"}, "futureLayoutField": {"keep": True}}
    set_("website_page_drafts/site_layout", seeded, OWNER)

    # saveSiteLayoutDraft: set(toDraftMap + editor fields, mergeFields).
    # Back to the default design (so `design` isn't sent); the header
    # changes; the Hindi site name is removed; the unknown key is sent back
    # (the app keeps it in `preserved`).
    draft = {**live_layout(siteName={"en": "2D Montessori", "ta": "டூடி"}), "header": {"background": "#FFFFFF"},
             "futureLayoutField": {"keep": True}, **EDITOR}
    if expect_status("save layout draft (set, mergeFields)", set_merge_fields("website_page_drafts/site_layout", draft), True):
        # _clearDefaultStyles: update({design: delete}).
        expect_status("clear the default design from the draft (update, delete)", update("website_page_drafts/site_layout", {"design": DELETE}), True)
        saved = read("website_page_drafts/site_layout")
        check("layout draft keeps lastPublished* (not in the mask)", saved.get("lastPublishedByName") == "Earlier admin" and saved.get("lastPublishedById") == "9000000001", saved.get("lastPublishedByName"))
        check("layout draft keeps the unknown top-level field", saved.get("futureLayoutField") == {"keep": True})
        check("a language removed from a text map is gone (the field is replaced whole)", saved.get("siteName") == {"en": "2D Montessori", "ta": "டூடி"}, json.dumps(saved.get("siteName"), ensure_ascii=False))
        check("a nested map is replaced whole, not merged", saved.get("header") == {"background": "#FFFFFF"}, json.dumps(saved.get("header")))
        check("a design back to the default is removed from the draft", "design" not in saved)

    # publishSiteLayout: one batch: the draft (mergeFields) and the live copy
    # (full set) with the design, header and footer.
    live = {**live_layout(), "design": DESIGN, "header": {"background": "#FFFFFF"}, "footer": {"phone": "+91 44 1234 5678"}, "publishedAt": "2026-10-26T10:00:00Z"}
    published = {**live_layout(), "design": DESIGN, "header": {"background": "#FFFFFF"}, "footer": {"phone": "+91 44 1234 5678"}, **EDITOR,
                 "lastPublishedAt": "2026-10-26T10:00:00Z", "lastPublishedById": "9000000000", "lastPublishedByName": "Admin"}
    status = commit([write_op("website_page_drafts/site_layout", published, mask=list(published)), write_op("website_pages/site_layout", live)], ADMIN)
    if expect_status("publish a layout with design, header and footer (batch)", status, not PREVIOUS):
        check("the live layout holds the design, header and footer", read("website_pages/site_layout").get("footer") == {"phone": "+91 44 1234 5678"})
    else:
        check("the refused batch changed neither document (atomic)", read("website_pages/site_layout") is None and "footer" not in read("website_page_drafts/site_layout"))
    plain = {**live_layout(), "publishedAt": "2026-10-26T10:00:00Z"}
    expect_status("publish a layout with the site's own look (no design/header/footer)", commit([write_op("website_page_drafts/site_layout", published, mask=list(published)), write_op("website_pages/site_layout", plain)], ADMIN), True)


def built_in_checks():
    reset_firestore()
    managed = {"slot": "admissions", "imageMediaId": "", "headline": {"en": "Join us", "ta": "சேருங்கள்", "hi": "जुड़ें"}, "intro": {"en": "", "ta": ""}}
    set_("website_page_drafts/admissions", {**managed, "mediaIds": [], **EDITOR, "futureDraftField": 1}, OWNER)
    set_("website_pages/admissions", {**managed, "mediaIds": [], "publishedAt": "2026-10-20T09:00:00Z"}, OWNER)

    # saveBuiltInPageDraft on an existing draft: update(blocks fields).
    blocks = {"schemaVersion": 2, "blocks": [SECTION], "mediaIds": [], **EDITOR}
    if expect_status("save built-in blocks draft (update)", update("website_page_drafts/admissions", blocks), True):
        saved = read("website_page_drafts/admissions")
        check("blocks draft keeps the managed heading in every language", saved.get("headline") == managed["headline"])
        check("blocks draft keeps an unknown field", saved.get("futureDraftField") == 1)
        check("blocks are stored as sent (nested section and columns)", saved.get("blocks") == [SECTION])

    # The old form editor's saveDraft: update(its fields); Hindi removed.
    form = {**managed, "headline": {"en": "Join us", "ta": "சேருங்கள்"}, "mediaIds": [], **EDITOR}
    if expect_status("old form save on a converted draft (update)", update("website_page_drafts/admissions", form), True):
        saved = read("website_page_drafts/admissions")
        check("the form keeps the blocks", saved.get("blocks") == [SECTION])
        check("a language removed by the form is gone", saved.get("headline") == {"en": "Join us", "ta": "சேருங்கள்"})

    # publishBuiltInPage's live write: update(blocks fields, publishedAt).
    if expect_status("publish built-in blocks (update live)", update("website_pages/admissions", {"schemaVersion": 2, "blocks": [SECTION], "mediaIds": [], "publishedAt": "2026-10-26T10:00:00Z"}), True):
        check("live keeps its managed heading (older app versions)", read("website_pages/admissions").get("headline") == managed["headline"])
    expect_status("publish built-in blocks carrying an editor field", update("website_pages/admissions", {"updatedByName": "Admin"}), False)

    # unpublishBuiltInPage: update({schemaVersion: delete, blocks: delete, mediaIds}).
    if expect_status("unpublish built-in blocks (update, delete fields)", update("website_pages/admissions", {"schemaVersion": DELETE, "blocks": DELETE, "mediaIds": []}), True):
        live = read("website_pages/admissions")
        check("unpublished: no blocks, managed content kept", "blocks" not in live and "schemaVersion" not in live and live.get("headline") == managed["headline"])

    # revertBuiltInPage on the draft: the same, with editor fields.
    if expect_status("revert built-in draft (update, delete fields)", update("website_page_drafts/admissions", {"schemaVersion": DELETE, "blocks": DELETE, "mediaIds": [], **EDITOR}), True):
        saved = read("website_page_drafts/admissions")
        check("reverted draft: no blocks; managed content and unknown field kept", "blocks" not in saved and saved.get("headline") == {"en": "Join us", "ta": "சேருங்கள்"} and saved.get("futureDraftField") == 1)

    # The old form's unpublish deletes the live document (refused by the
    # service while blocks are live; the rules allow any admin delete).
    expect_status("old form unpublish (delete live)", delete("website_pages/admissions"), True)


def contact_checks():
    reset_firestore()
    blocks = [SECTION]
    # saveBuiltInPageDraft: no document yet, so set().
    draft_ok = expect_status("create the Contact draft (set)", set_("website_page_drafts/contact", {"schemaVersion": 2, "blocks": blocks, "mediaIds": [], **EDITOR}), not PREVIOUS)
    if draft_ok:
        expect_status("update the Contact draft (update)", update("website_page_drafts/contact", {"schemaVersion": 2, "blocks": blocks, "mediaIds": [], **EDITOR}), True)
    live_ok = expect_status("publish Contact (set live)", set_("website_pages/contact", {"schemaVersion": 2, "blocks": blocks, "mediaIds": [], "publishedAt": "2026-10-26T10:00:00Z"}), not PREVIOUS)
    if live_ok:
        expect_status("republish Contact (update live)", update("website_pages/contact", {"schemaVersion": 2, "blocks": blocks, "mediaIds": [], "publishedAt": "2026-10-26T11:00:00Z"}), True)
        expect_status("publish Contact carrying an editor field", update("website_pages/contact", {"updatedById": "9000000000"}), False)
        check("visitors can read the live Contact page", request("GET", f"{DOCS}/website_pages/contact", PUBLIC)[0] == 200)
    if draft_ok:
        check("visitors can't read the Contact draft", request("GET", f"{DOCS}/website_page_drafts/contact", PUBLIC)[0] in (401, 403))
        check("staff can't read the Contact draft", request("GET", f"{DOCS}/website_page_drafts/contact", STAFF)[0] in (401, 403))
    expect_status("staff create the Contact draft", set_("website_page_drafts/contact", {"schemaVersion": 2, "blocks": []}, STAFF), False)
    expect_status("staff publish Contact", set_("website_pages/contact", {"schemaVersion": 2, "blocks": []}, STAFF), False)
    # Before the proposal `contact` wasn't a built-in id, so it fell under
    # the additional-page draft rule.
    expect_status("Contact draft marked as an additional page", set_("website_page_drafts/contact", {"kind": "custom", "slug": "contact"}), PREVIOUS)
    if PREVIOUS:
        delete("website_page_drafts/contact")
    # Unpublish and revert: Contact's documents hold only blocks, so the
    # service deletes them (admin deletes are allowed under both rule sets).
    expect_status("unpublish or revert Contact (delete live)", delete("website_pages/contact"), True)
    expect_status("revert Contact (delete draft)", delete("website_page_drafts/contact"), True)
    check("after revert, no Contact documents remain", read("website_pages/contact") is None and read("website_page_drafts/contact") is None)


def main():
    layout_checks()
    built_in_checks()
    contact_checks()
    failed = [r for r in results if not r[0]]
    print(f"Rules under test: {'previous (before the visual editor)' if PREVIOUS else 'proposal'}")
    for ok, name, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name}{'  (' + detail + ')' if detail else ''}")
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} checks")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
