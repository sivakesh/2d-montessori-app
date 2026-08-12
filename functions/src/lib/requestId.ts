/**
 * Extracts a correlation ID for audit events from the callable's raw HTTP
 * request, falling back to [fallback] (typically the affected entity's
 * id) when unavailable.
 *
 * `request.rawRequest?.headers['x-request-id']` (a single optional-chain
 * before the bracket access) looks safe but isn't: if `rawRequest` is
 * undefined OR `rawRequest.headers` itself is undefined/missing the key,
 * indexing `['x-request-id']` on the `?.`-shortcut result still throws
 * "Cannot read properties of undefined" — `?.` only guards the property
 * access immediately after it, not the following bracket index. This was
 * a real, caught-by-actually-running-the-tests bug (see
 * docs/architecture/decisions.md "Foundation Verification checkpoint —
 * bugs found by execution, not review"): every callable using the
 * unguarded form threw on every call under test, where `CallableRequest`
 * objects are hand-constructed and don't have a real Express `.headers`.
 * This helper is the single place that logic lives now.
 */
import type { CallableRequest } from 'firebase-functions/v2/https';

export function resolveRequestId(request: CallableRequest<unknown>, fallback: string): string {
  const headerValue = request.rawRequest?.headers?.['x-request-id'];
  if (typeof headerValue === 'string' && headerValue.length > 0) {
    return headerValue;
  }
  if (Array.isArray(headerValue) && headerValue.length > 0) {
    const first = headerValue[0];
    if (typeof first === 'string' && first.length > 0) return first;
  }
  return fallback;
}
