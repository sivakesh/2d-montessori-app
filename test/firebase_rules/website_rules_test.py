"""Emulator tests for the proposed website-content security rules.

Runs against the Firestore and Storage emulators only (a demo- project id,
so nothing can reach a real Firebase project), using their REST APIs and
unsigned test ID tokens, which the emulators accept. Standard library only.

    firebase emulators:exec --config test/firebase_rules/firebase.json \
      --project demo-montessori-website --only firestore,storage \
      "python3 -I test/firebase_rules/website_rules_test.py"

Exits non-zero if any check fails.
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROJECT = os.environ.get("GCLOUD_PROJECT", "demo-montessori-website")
if not PROJECT.startswith("demo-"):
    sys.exit(f"Refusing to run against non-demo project {PROJECT!r}")
FIRESTORE = "http://" + os.environ.get("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8085")
STORAGE = "http://" + os.environ.get("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9195")
BUCKET = f"{PROJECT}.appspot.com"
DOCS = f"{FIRESTORE}/v1/projects/{PROJECT}/databases/(default)/documents"


# ---------------------------------------------------------------- helpers

def token(uid, **claims):
    """An unsigned Firebase ID token, as the emulators accept."""
    def b64(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")
    now = int(time.time())
    payload = {
        "iss": f"https://securetoken.google.com/{PROJECT}", "aud": PROJECT,
        "sub": uid, "user_id": uid, "auth_time": now, "iat": now, "exp": now + 3600,
        "firebase": {"sign_in_provider": "phone", "identities": {}}, **claims,
    }
    return b64({"alg": "none", "typ": "JWT"}) + "." + b64(payload) + "."


ADMIN = token("admin-uid", role="admin")
STAFF = token("staff-uid", role="staff")
PARENT = token("parent-uid", role="parent")
SIGNED_IN = token("plain-uid")          # signed in, no role claim
PUBLIC = None                           # not signed in
OWNER = "owner"                         # emulator admin bypass, for seeding only


def request(method, url, auth=None, body=None, content_type="application/json"):
    data = None
    headers = {}
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        headers["Content-Type"] = content_type
    if auth:
        headers["Authorization"] = f"Bearer {auth}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw and resp.headers.get("Content-Type", "").startswith("application/json") else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def value(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: value(x) for k, x in v.items()}}}
    raise TypeError(v)


def doc_body(data):
    return {"fields": {k: value(v) for k, v in data.items()}}


def fs_set(path, data, auth):
    """Create or overwrite a document (rules: create if absent, else update)."""
    return request("PATCH", f"{DOCS}/{path}", auth, doc_body(data))[0]


def fs_update(path, fields, auth):
    """Update named fields of an existing document (rules: update)."""
    mask = "&".join("updateMask.fieldPaths=" + urllib.parse.quote(k) for k in fields)
    return request("PATCH", f"{DOCS}/{path}?currentDocument.exists=true&{mask}", auth, doc_body(fields))[0]


def fs_get(path, auth):
    return request("GET", f"{DOCS}/{path}", auth)[0]


def fs_delete(path, auth):
    return request("DELETE", f"{DOCS}/{path}", auth)[0]


def fs_query(collection, auth, where=None):
    query = {"from": [{"collectionId": collection}]}
    if where:
        field, val = where
        query["where"] = {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL", "value": value(val)}}
    parent, _, _ = f"{DOCS}/{collection}".rpartition("/")
    return request("POST", f"{parent}:runQuery", auth, {"structuredQuery": query})[0]


def reset_firestore():
    request("DELETE", f"{FIRESTORE}/emulator/v1/projects/{PROJECT}/databases/(default)/documents")


def object_url(path):
    return f"{STORAGE}/v0/b/{BUCKET}/o/{urllib.parse.quote(path, safe='')}"


def st_upload(path, data, content_type, auth):
    status, body = request("POST", f"{STORAGE}/v0/b/{BUCKET}/o?name={urllib.parse.quote(path, safe='')}", auth, data, content_type)
    return status, body


def st_download(path, auth, token_param=None):
    url = object_url(path) + "?alt=media" + (f"&token={token_param}" if token_param else "")
    return request("GET", url, auth)[0]


def st_delete(path, auth):
    return request("DELETE", object_url(path), auth)[0]


# ---------------------------------------------------------------- checks

results = []


def check(name, actual, allowed):
    ok = (200 <= actual < 300) if allowed else actual in (401, 403)
    results.append((ok, name, actual, "allow" if allowed else "deny"))


def media(status="draft", consent=False, alt="Children reading", **extra):
    return {"url": "https://example.test/d.jpg", "storagePath": "website_media/x/d.jpg", "status": status,
            "consentConfirmed": consent, "alt": {"en": alt, "ta": ""}, "caption": {"en": "", "ta": ""},
            "inGallery": True, "galleryOrder": 0, **extra}


def live_slot(**extra):
    return {"slot": "home", "imageMediaId": "", "mediaIds": [], "headline": {"en": "Hi", "ta": ""}, "intro": {"en": "", "ta": ""}, **extra}


def live_custom(slug="open-day", **extra):
    page = {"kind": "custom", "slug": slug, "title": {"en": "Open Day", "ta": ""}, "intro": {"en": "", "ta": ""},
            "heroMediaId": "", "sections": [], "showInNavigation": False, "navOrder": 0, "mediaIds": []}
    page.update(extra)
    return page


def live_layout(**extra):
    link = {"id": "m1", "label": {"en": "", "ta": ""}, "target": {"kind": "builtin", "id": "home"}, "visible": True}
    layout = {"kind": "layout", "schemaVersion": 1, "siteName": {"en": "2D Montessori", "ta": ""},
              "tagline": {"en": "", "ta": ""}, "mainNav": [link], "footerNav": [link],
              "footerText": {"en": "", "ta": ""}, "copyright": {"en": "", "ta": ""}}
    layout.update(extra)
    return layout


def live_languages(**extra):
    def lang(code, name, on):
        return {"code": code, "nativeName": name, "englishName": name, "enabled": on, "public": on}
    registry = {"kind": "languages", "schemaVersion": 1, "source": "en", "fallback": "en",
                "languages": [lang("en", "English", True), lang("ta", "Tamil", True), lang("hi", "Hindi", False)]}
    registry.update(extra)
    return registry


def firestore_tests():
    reset_firestore()
    # Seed (bypassing rules).
    fs_set("website_media/pub", media("published", consent=True), OWNER)
    fs_set("website_media/draft", media("draft"), OWNER)
    fs_set("website_media/hidden", media("hidden"), OWNER)
    fs_set("website_media/pub/audit/a1", {"action": "uploaded", "byId": "9000000000", "byName": "Admin"}, OWNER)
    fs_set("website_pages/home", live_slot(), OWNER)
    fs_set("website_pages/p1", live_custom(), OWNER)
    fs_set("website_page_drafts/home", {**live_slot(), "updatedById": "9000000000", "updatedByName": "Admin"}, OWNER)
    fs_set("website_page_drafts/p1", {**live_custom(), "archived": False, "updatedByName": "Admin"}, OWNER)
    fs_set("website_pages/site_layout", live_layout(), OWNER)
    fs_set("website_pages/site_languages", live_languages(), OWNER)
    fs_set("website_page_drafts/site_languages", {**live_languages(), "updatedByName": "Admin"}, OWNER)
    fs_set("website_page_drafts/site_layout", {**live_layout(), "updatedById": "9000000000", "updatedByName": "Admin"}, OWNER)

    visitors = [("public", PUBLIC), ("signed-in, no role", SIGNED_IN), ("staff", STAFF), ("parent", PARENT)]

    # --- public reads
    for who, auth in visitors:
        check(f"{who}: get published media", fs_get("website_media/pub", auth), True)
        check(f"{who}: get draft media", fs_get("website_media/draft", auth), False)
        check(f"{who}: get hidden media", fs_get("website_media/hidden", auth), False)
        check(f"{who}: list media where status == published", fs_query("website_media", auth, ("status", "published")), True)
        check(f"{who}: list all media (no status filter)", fs_query("website_media", auth), False)
        check(f"{who}: list media where status == draft", fs_query("website_media", auth, ("status", "draft")), False)
        check(f"{who}: get live page", fs_get("website_pages/home", auth), True)
        check(f"{who}: list live pages", fs_query("website_pages", auth), True)
        check(f"{who}: get draft page", fs_get("website_page_drafts/home", auth), False)
        check(f"{who}: list draft pages", fs_query("website_page_drafts", auth), False)
        check(f"{who}: read audit", fs_get("website_media/pub/audit/a1", auth), False)
        check(f"{who}: get live site layout", fs_get("website_pages/site_layout", auth), True)
        check(f"{who}: get draft site layout", fs_get("website_page_drafts/site_layout", auth), False)
        check(f"{who}: get live languages", fs_get("website_pages/site_languages", auth), True)
        check(f"{who}: get draft languages", fs_get("website_page_drafts/site_languages", auth), False)

    # --- non-admin writes (all denied)
    for who, auth in visitors:
        check(f"{who}: create media", fs_set(f"website_media/new-{who[:3]}", media(), auth), False)
        check(f"{who}: publish media", fs_update("website_media/draft", {"status": "published", "consentConfirmed": True}, auth), False)
        check(f"{who}: delete media", fs_delete("website_media/pub", auth), False)
        check(f"{who}: delete audit entry", fs_delete("website_media/pub/audit/a1", auth), False)
        check(f"{who}: publish (write) live page", fs_set("website_pages/admissions", live_slot(slot="admissions"), auth), False)
        check(f"{who}: update live page", fs_update("website_pages/home", {"headline": {"en": "Hacked", "ta": ""}}, auth), False)
        check(f"{who}: unpublish (delete) live page", fs_delete("website_pages/home", auth), False)
        check(f"{who}: delete live custom page", fs_delete("website_pages/p1", auth), False)
        check(f"{who}: write draft page", fs_set("website_page_drafts/home", live_slot(), auth), False)
        check(f"{who}: delete draft page", fs_delete("website_page_drafts/p1", auth), False)
        check(f"{who}: publish site layout", fs_set("website_pages/site_layout", live_layout(siteName={"en": "Hacked", "ta": ""}), auth), False)
        check(f"{who}: unpublish site layout", fs_delete("website_pages/site_layout", auth), False)
        check(f"{who}: publish contact page blocks", fs_set("website_pages/contact", {"schemaVersion": 2, "blocks": []}, auth), False)
        check(f"{who}: write draft site layout", fs_set("website_page_drafts/site_layout", live_layout(), auth), False)
        check(f"{who}: publish languages", fs_set("website_pages/site_languages", live_languages(fallback="ta"), auth), False)
        check(f"{who}: unpublish languages", fs_delete("website_pages/site_languages", auth), False)
        check(f"{who}: write draft languages", fs_set("website_page_drafts/site_languages", live_languages(), auth), False)

    # --- admin: media
    check("admin: list all media", fs_query("website_media", ADMIN), True)
    check("admin: get draft media", fs_get("website_media/draft", ADMIN), True)
    check("admin: create draft media", fs_set("website_media/m1", media(), ADMIN), True)
    check("admin: create published media with consent + alt", fs_set("website_media/m2", media("published", consent=True), ADMIN), True)
    check("admin: create published media without consent", fs_set("website_media/m3", media("published", consent=False), ADMIN), False)
    check("admin: create published media with empty alt", fs_set("website_media/m4", media("published", consent=True, alt=""), ADMIN), False)
    check("admin: create media with unknown status", fs_set("website_media/m5", media("live"), ADMIN), False)
    check("admin: create media holding fileName", fs_set("website_media/m6", media(fileName="Asha.jpg"), ADMIN), False)
    check("admin: create media holding updatedByName", fs_set("website_media/m7", media(updatedByName="Admin"), ADMIN), False)
    check("admin: publish draft without consent", fs_update("website_media/draft", {"status": "published"}, ADMIN), False)
    check("admin: publish draft with consent", fs_update("website_media/draft", {"status": "published", "consentConfirmed": True}, ADMIN), True)
    check("admin: withdraw consent + hide", fs_update("website_media/draft", {"status": "hidden", "consentConfirmed": False}, ADMIN), True)
    check("admin: withdraw consent but keep published", fs_update("website_media/pub", {"consentConfirmed": False}, ADMIN), False)
    check("admin: reorder (update galleryOrder only)", fs_update("website_media/pub", {"galleryOrder": 5}, ADMIN), True)
    check("admin: read audit", fs_get("website_media/pub/audit/a1", ADMIN), True)
    check("admin: create audit entry", fs_set("website_media/pub/audit/a2", {"action": "published"}, ADMIN), True)
    check("admin: edit audit entry", fs_update("website_media/pub/audit/a1", {"action": "changed"}, ADMIN), False)
    check("admin: delete audit entry", fs_delete("website_media/pub/audit/a2", ADMIN), True)
    check("admin: delete media", fs_delete("website_media/m1", ADMIN), True)

    # --- admin: live pages (publication)
    check("admin: publish built-in slot", fs_set("website_pages/admissions", live_slot(slot="admissions"), ADMIN), True)
    check("admin: publish built-in slot with editor name", fs_set("website_pages/programs", live_slot(slot="programs", updatedByName="Admin"), ADMIN), False)
    check("admin: publish built-in slot doc marked custom", fs_set("website_pages/gallery", live_custom(), ADMIN), False)
    check("admin: publish unknown non-custom page id", fs_set("website_pages/about", live_slot(), ADMIN), False)
    check("admin: publish valid custom page", fs_set("website_pages/p2", live_custom("sports-day"), ADMIN), True)
    check("admin: publish custom page with bad slug", fs_set("website_pages/p3", live_custom("Bad Slug"), ADMIN), False)
    check("admin: publish custom page with path slug", fs_set("website_pages/p4", live_custom("../app"), ADMIN), False)
    check("admin: publish custom page without title", fs_set("website_pages/p5", live_custom(title={"en": "", "ta": ""}), ADMIN), False)
    check("admin: publish archived custom page", fs_set("website_pages/p6", live_custom("old-page", archived=True), ADMIN), False)
    check("admin: publish custom page with editor id", fs_set("website_pages/p7", live_custom("p-seven", updatedById="9000000000"), ADMIN), False)
    check("admin: publish custom page with 21 sections", fs_set("website_pages/p8", live_custom("too-many", sections=[{"id": str(i)} for i in range(21)]), ADMIN), False)
    check("admin: reorder live custom page (navOrder)", fs_update("website_pages/p1", {"navOrder": 3}, ADMIN), True)
    check("admin: unpublish (delete) built-in slot", fs_delete("website_pages/admissions", ADMIN), True)
    check("admin: unpublish (delete) custom page", fs_delete("website_pages/p2", ADMIN), True)
    check("admin: delete a live page that doesn't exist", fs_delete("website_pages/never-existed", ADMIN), True)

    # --- admin: site layout
    many = [{"id": str(i)} for i in range(11)]
    check("admin: publish valid site layout", fs_set("website_pages/site_layout", live_layout(publishedAt="2026-10-25"), ADMIN), True)
    check("admin: publish site layout with editor name", fs_set("website_pages/site_layout", live_layout(updatedByName="Admin"), ADMIN), False)
    check("admin: publish site layout with an unknown field", fs_set("website_pages/site_layout", live_layout(script="x"), ADMIN), False)
    check("admin: publish site layout, schema version 2", fs_set("website_pages/site_layout", live_layout(schemaVersion=2), ADMIN), False)
    check("admin: publish custom page as site_layout", fs_set("website_pages/site_layout", live_custom("site-layout"), ADMIN), False)
    check("admin: publish site layout, mainNav not a list", fs_set("website_pages/site_layout", live_layout(mainNav="home"), ADMIN), False)
    check("admin: publish site layout, 11 main links", fs_set("website_pages/site_layout", live_layout(mainNav=many), ADMIN), False)
    check("admin: publish site layout, 17 footer links", fs_set("website_pages/site_layout", live_layout(footerNav=[{"id": str(i)} for i in range(17)]), ADMIN), False)
    check("admin: publish site layout, 61-character name", fs_set("website_pages/site_layout", live_layout(siteName={"en": "x" * 61, "ta": ""}), ADMIN), False)
    check("admin: publish site layout, footer text not a map", fs_set("website_pages/site_layout", live_layout(footerText="x"), ADMIN), False)
    design = {"palette": [{"id": "forest", "name": "Forest", "hex": "#1F4D3A"}], "bodySize": 16, "headingSize": 26, "lineHeight": 1.6}
    check("admin: publish site layout with design, header and footer", fs_set("website_pages/site_layout", live_layout(design=design, header={"background": "#FFFFFF"}, footer={"phone": "+91 44 1234 5678"}), ADMIN), True)
    check("admin: publish site layout, design not a map", fs_set("website_pages/site_layout", live_layout(design="dark"), ADMIN), False)
    check("admin: publish site layout, header not a map", fs_set("website_pages/site_layout", live_layout(header=["x"]), ADMIN), False)
    check("admin: save contact page blocks (draft)", fs_set("website_page_drafts/contact", {"schemaVersion": 2, "blocks": [], "mediaIds": []}, ADMIN), True)
    check("admin: publish contact page blocks", fs_set("website_pages/contact", {"schemaVersion": 2, "blocks": [], "mediaIds": []}, ADMIN), True)
    check("admin: publish contact page with editor name", fs_set("website_pages/contact", {"schemaVersion": 2, "blocks": [], "updatedByName": "Admin"}, ADMIN), False)
    check("admin: publish layout under another id", fs_set("website_pages/layout2", live_layout(), ADMIN), False)
    check("admin: save site layout draft (editor name)", fs_set("website_page_drafts/site_layout", {**live_layout(), "updatedByName": "Admin", "lastPublishedByName": "Admin"}, ADMIN), True)
    check("admin: save site layout draft, wrong kind", fs_set("website_page_drafts/site_layout", live_layout(kind="custom", slug="site-layout"), ADMIN), False)
    check("admin: save site layout draft, 11 main links", fs_set("website_page_drafts/site_layout", live_layout(mainNav=many), ADMIN), False)
    check("admin: unpublish site layout", fs_delete("website_pages/site_layout", ADMIN), True)

    # --- admin: language registry
    check("admin: publish valid languages", fs_set("website_pages/site_languages", live_languages(publishedAt="2026-10-25"), ADMIN), True)
    check("admin: publish languages with editor name", fs_set("website_pages/site_languages", live_languages(updatedByName="Admin"), ADMIN), False)
    check("admin: publish languages with an unknown field", fs_set("website_pages/site_languages", live_languages(apiKey="sk-x"), ADMIN), False)
    check("admin: publish languages, schema version 2", fs_set("website_pages/site_languages", live_languages(schemaVersion=2), ADMIN), False)
    check("admin: publish languages, source not English", fs_set("website_pages/site_languages", live_languages(source="ta"), ADMIN), False)
    check("admin: publish languages, fallback not a string", fs_set("website_pages/site_languages", live_languages(fallback=1), ADMIN), False)
    check("admin: publish languages, empty list", fs_set("website_pages/site_languages", live_languages(languages=[]), ADMIN), False)
    check("admin: publish languages, 21 entries", fs_set("website_pages/site_languages", live_languages(languages=[{"code": f"l{i}"} for i in range(21)]), ADMIN), False)
    check("admin: publish layout doc as site_languages", fs_set("website_pages/site_languages", live_layout(), ADMIN), False)
    check("admin: save languages draft (editor name)", fs_set("website_page_drafts/site_languages", {**live_languages(), "updatedByName": "Admin", "lastPublishedByName": "Admin"}, ADMIN), True)
    check("admin: save languages draft, wrong kind", fs_set("website_page_drafts/site_languages", live_languages(kind="layout"), ADMIN), False)
    check("admin: unpublish languages", fs_delete("website_pages/site_languages", ADMIN), True)

    # --- admin: drafts
    check("admin: get draft", fs_get("website_page_drafts/home", ADMIN), True)
    check("admin: list drafts", fs_query("website_page_drafts", ADMIN), True)
    check("admin: save built-in draft", fs_set("website_page_drafts/programs", {**live_slot(slot="programs"), "updatedByName": "Admin"}, ADMIN), True)
    check("admin: save custom draft (archived, editor name)", fs_set("website_page_drafts/p9", {**live_custom("draft-page"), "archived": True, "updatedByName": "Admin"}, ADMIN), True)
    check("admin: save custom draft with bad slug", fs_set("website_page_drafts/p10", live_custom("BAD"), ADMIN), False)
    check("admin: save unknown non-custom draft", fs_set("website_page_drafts/about", live_slot(), ADMIN), False)
    check("admin: delete draft", fs_delete("website_page_drafts/p9", ADMIN), True)


def storage_tests():
    jpeg = b"\xff\xd8\xff\xe0" + b"0" * 64
    path = "website_media/m1/1_display.jpg"
    status, body = st_upload(path, jpeg, "image/jpeg", ADMIN)
    check("admin: upload JPEG", status, True)
    download_token = body.get("downloadTokens") if isinstance(body, dict) else None
    check("admin: upload PNG", st_upload("website_media/m1/1_thumb.png", b"\x89PNG" + b"0" * 32, "image/png", ADMIN)[0], True)
    check("admin: upload WebP", st_upload("website_media/m1/1_x.webp", b"RIFF" + b"0" * 32, "image/webp", ADMIN)[0], True)
    check("admin: upload PDF", st_upload("website_media/m1/doc.pdf", b"%PDF" + b"0" * 32, "application/pdf", ADMIN)[0], False)
    check("admin: upload SVG", st_upload("website_media/m1/x.svg", b"<svg/>", "image/svg+xml", ADMIN)[0], False)
    check("admin: upload 15 MB image", st_upload("website_media/m1/big.jpg", b"0" * (15 * 1024 * 1024), "image/jpeg", ADMIN)[0], False)
    check("admin: upload outside website_media", st_upload("other/x.jpg", jpeg, "image/jpeg", ADMIN)[0], False)
    for who, auth in [("public", PUBLIC), ("signed-in, no role", SIGNED_IN), ("staff", STAFF), ("parent", PARENT)]:
        check(f"{who}: upload image", st_upload(f"website_media/m2/{who[:3]}.jpg", jpeg, "image/jpeg", auth)[0], False)
        check(f"{who}: download without the URL token", st_download(path, auth), False)
        check(f"{who}: delete image", st_delete(path, auth), False)
    check("admin: download", st_download(path, ADMIN), True)
    if download_token:
        check("public: download with the stored URL token", st_download(path, PUBLIC, download_token), True)
    else:
        results.append((False, "public: download with the stored URL token (no token returned by emulator)", 0, "allow"))
    check("admin: delete image", st_delete(path, ADMIN), True)


def main():
    firestore_tests()
    storage_tests()
    failed = [r for r in results if not r[0]]
    for ok, name, actual, expected in results:
        print(f"{'PASS' if ok else 'FAIL'}  expect {expected:<5} got {actual}  {name}")
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} checks")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
