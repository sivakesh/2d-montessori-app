/**
 * Recursively removes keys whose value is `undefined` from objects
 * (including inside arrays). The Admin SDK's `Transaction.update()`
 * rejects `undefined` anywhere in the payload — including nested inside
 * an array of objects — even though `optionalStr()`-style helpers
 * throughout `validators.ts`/`sections.ts` legitimately produce
 * `undefined` for an omitted optional field (e.g. a `RichTextSection`
 * with no `heading`). `set()`/plain top-level `update()` calls elsewhere
 * in this codebase never hit this because their optional fields are
 * written as explicit `null`, not `undefined` — this validated-content
 * pipeline is the one place that returns raw `undefined`, so it is
 * cleaned up once here rather than forcing every section-type builder in
 * `sections.ts` to hand-write conditional-spread `null`/omit logic. Found
 * by CI, not by review or `tsc --noEmit` — see decisions.md.
 */
export function stripUndefinedDeep<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map((item) => stripUndefinedDeep(item)) as unknown as T;
  }
  if (value !== null && typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      if (entry === undefined) continue;
      result[key] = stripUndefinedDeep(entry);
    }
    return result as T;
  }
  return value;
}
