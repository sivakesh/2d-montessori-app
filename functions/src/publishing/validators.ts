import { HttpsError } from 'firebase-functions/v2/https';

import { isPublishingAction, type PublishingAction } from './stateMachine';

export function validateContentId(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'A content id is required.');
  }
  return value;
}

export function validateContentType(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0 || trimmed.length > 40) {
    throw new HttpsError('invalid-argument', 'A content type (1-40 characters) is required.');
  }
  return trimmed;
}

export function validateTitle(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0 || trimmed.length > 200) {
    throw new HttpsError('invalid-argument', 'A title (1-200 characters) is required.');
  }
  return trimmed;
}

export function validateAction(value: unknown): PublishingAction {
  if (!isPublishingAction(value)) {
    throw new HttpsError('invalid-argument', 'A valid publishing action is required.');
  }
  return value;
}

/** Optional field — returns undefined if absent, throws if present but blank. */
export function validateOptionalComment(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'comment must be a non-empty string when provided.');
  }
  return value.trim();
}

/** Optional field — returns undefined if absent, throws if present but not a valid ISO date string. */
export function validateOptionalScheduledAt(value: unknown): Date | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'scheduledAt must be an ISO 8601 date string.');
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError('invalid-argument', 'scheduledAt must be a valid ISO 8601 date string.');
  }
  return parsed;
}
