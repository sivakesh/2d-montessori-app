/**
 * Server-side field validation for Pages — the authoritative half of
 * SRS CMS-08 ("Publishing checks required fields...") for everything
 * that must hold on *every* save, not just before publish (see
 * `completeness.ts` for the additional checks gated on submit/publish/
 * schedule specifically).
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { validatePageSections } from './sections';

const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const PAGE_TYPES = ['standard', 'collectionLanding'] as const;
const INDEXING_VALUES = ['indexFollow', 'noIndexFollow', 'noIndexNoFollow'] as const;

export function validatePageId(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'A page id is required.');
  }
  return value;
}

export function validatePageTitle(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0 || trimmed.length > 200) {
    throw new HttpsError('invalid-argument', 'A title (1-200 characters) is required.');
  }
  return trimmed;
}

/** Format only — see `slug.ts` for the separate uniqueness check. */
export function validateSlugFormat(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (!SLUG_PATTERN.test(trimmed) || trimmed.length > 120) {
    throw new HttpsError('invalid-argument', 'The URL slug must be lowercase letters, numbers and hyphens only.', {
      reason: 'invalid-slug',
    });
  }
  return trimmed;
}

export function validateSummary(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length > 300) {
    throw new HttpsError('invalid-argument', 'Summary must be 300 characters or fewer.');
  }
  return trimmed;
}

export function validatePageType(value: unknown): (typeof PAGE_TYPES)[number] {
  if (typeof value === 'string' && (PAGE_TYPES as readonly string[]).includes(value)) {
    return value as (typeof PAGE_TYPES)[number];
  }
  return 'standard';
}

function optionalStr(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

interface ValidatedSeo {
  title?: string | undefined;
  metaDescription?: string | undefined;
  canonicalUrl?: string | undefined;
  indexing: (typeof INDEXING_VALUES)[number];
  social: { title?: string | undefined; description?: string | undefined; image: unknown };
}

export function validateSeo(raw: unknown): ValidatedSeo {
  const map = typeof raw === 'object' && raw !== null ? (raw as Record<string, unknown>) : {};
  const indexing = typeof map.indexing === 'string' && (INDEXING_VALUES as readonly string[]).includes(map.indexing) ? map.indexing : 'indexFollow';
  const socialRaw = typeof map.social === 'object' && map.social !== null ? (map.social as Record<string, unknown>) : {};
  return {
    title: optionalStr(map.title),
    metaDescription: optionalStr(map.metaDescription),
    canonicalUrl: optionalStr(map.canonicalUrl),
    indexing: indexing as (typeof INDEXING_VALUES)[number],
    social: { title: optionalStr(socialRaw.title), description: optionalStr(socialRaw.description), image: socialRaw.image ?? null },
  };
}

export function validateFeaturedImage(raw: unknown): unknown {
  if (raw === undefined || raw === null) return null;
  const map = typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const altText = optionalStr(map.altText);
  if (!altText) {
    throw new HttpsError('invalid-argument', 'The featured image needs alternative text.');
  }
  return { url: optionalStr(map.url) ?? '', altText, storagePath: optionalStr(map.storagePath) ?? null, caption: optionalStr(map.caption) ?? null };
}

export interface ValidatedPageContent {
  title: string;
  slug: string;
  summary: string;
  pageType: string;
  sections: Record<string, unknown>[];
  featuredImage: unknown;
  seo: ValidatedSeo;
  navigationLabel: string | null;
  showInNavigation: boolean;
}

/** Validates the full editable-content payload `pagesFns-updatePageContent` accepts. */
export function validatePageContent(data: Record<string, unknown>): ValidatedPageContent {
  return {
    title: validatePageTitle(data.title),
    slug: validateSlugFormat(data.slug),
    summary: validateSummary(data.summary),
    pageType: validatePageType(data.pageType),
    sections: validatePageSections(data.sections),
    featuredImage: validateFeaturedImage(data.featuredImage),
    seo: validateSeo(data.seo),
    navigationLabel: optionalStr(data.navigationLabel) ?? null,
    showInNavigation: data.showInNavigation === true,
  };
}
