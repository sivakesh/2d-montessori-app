/**
 * Server-side mirror of `feature_pages`'s Dart `PageSection` sealed
 * hierarchy (`packages/feature_pages/lib/src/domain/page_section.dart`)
 * — hand-synced, not code-shared, the same convention
 * `functions/src/publishing/stateMachine.ts` already uses opposite
 * `PublishingStateMachine`. Every section a client submits is validated
 * structurally here before being written to Firestore: unknown fields
 * are dropped (not stored verbatim), unknown `type` values are rejected,
 * and there is no field anywhere that accepts HTML/script content —
 * "no unrestricted drag-and-drop/free-form builder" and "do not store
 * arbitrary executable HTML" hold here the same way they hold in the
 * Dart client, independently.
 */
import { HttpsError } from 'firebase-functions/v2/https';

export const PAGE_SECTION_TYPES = [
  'richText',
  'image',
  'imageText',
  'cta',
  'highlights',
  'faq',
  'gallery',
  'testimonial',
  'relatedContent',
] as const;
export type PageSectionType = (typeof PAGE_SECTION_TYPES)[number];

export function isPageSectionType(value: unknown): value is PageSectionType {
  return typeof value === 'string' && (PAGE_SECTION_TYPES as readonly string[]).includes(value);
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function optionalStr(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function fail(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

interface MediaReference {
  url: string;
  altText: string;
  storagePath?: string | undefined;
  caption?: string | undefined;
}

function validateMediaReference(raw: unknown, context: string): MediaReference {
  if (typeof raw !== 'object' || raw === null) fail(`${context} is missing an image.`);
  const map = raw as Record<string, unknown>;
  const altText = str(map.altText).trim();
  if (altText.length === 0) fail(`${context} is missing alternative text.`);
  return { url: str(map.url).trim(), altText, storagePath: optionalStr(map.storagePath), caption: optionalStr(map.caption) };
}

/**
 * Validates one section's shape and returns a clean, storage-ready
 * object (never the raw client input passed through verbatim) — every
 * field is explicitly read and re-typed, so an unexpected extra field
 * the client sent is silently dropped rather than persisted.
 */
export function validatePageSection(raw: unknown, index: number): Record<string, unknown> {
  if (typeof raw !== 'object' || raw === null) fail(`Section ${index + 1} is not a valid object.`);
  const map = raw as Record<string, unknown>;

  const id = str(map.id).trim();
  if (id.length === 0) fail(`Section ${index + 1} is missing an id.`);
  if (!isPageSectionType(map.type)) fail(`Section ${index + 1} has an unrecognized type.`);
  const sortOrder = typeof map.sortOrder === 'number' ? map.sortOrder : index;
  const isVisible = typeof map.isVisible === 'boolean' ? map.isVisible : true;
  const base = { id, type: map.type, sortOrder, isVisible };
  const context = `Section ${index + 1} (${map.type})`;

  switch (map.type) {
    case 'richText':
      return { ...base, heading: optionalStr(map.heading), body: str(map.body) };
    case 'image':
      return { ...base, image: validateMediaReference(map.image, context) };
    case 'imageText':
      return {
        ...base,
        heading: optionalStr(map.heading),
        body: str(map.body),
        image: validateMediaReference(map.image, context),
        imageSide: map.imageSide === 'right' ? 'right' : 'left',
      };
    case 'cta': {
      if (typeof map.primaryCta !== 'object' || map.primaryCta === null) fail(`${context} is missing its primary action.`);
      const primary = map.primaryCta as Record<string, unknown>;
      if (str(primary.label).trim().length === 0 || str(primary.target).trim().length === 0) {
        fail(`${context}'s primary action needs a label and a destination.`);
      }
      return {
        ...base,
        heading: optionalStr(map.heading),
        body: optionalStr(map.body),
        primaryCta: {
          label: str(primary.label),
          linkType: str(primary.linkType) || 'internal',
          target: str(primary.target),
          openInNewTab: primary.openInNewTab === true,
        },
        secondaryCta: map.secondaryCta ?? null,
      };
    }
    case 'highlights': {
      const cards = Array.isArray(map.cards) ? map.cards : [];
      if (cards.length === 0) fail(`${context} needs at least one card.`);
      return {
        ...base,
        heading: optionalStr(map.heading),
        introduction: optionalStr(map.introduction),
        cards: cards.map((c) => {
          const card = c as Record<string, unknown>;
          return { title: str(card.title), body: str(card.body), image: card.image ?? null };
        }),
      };
    }
    case 'faq': {
      const items = Array.isArray(map.items) ? map.items : [];
      if (items.length === 0) fail(`${context} needs at least one question.`);
      return {
        ...base,
        heading: optionalStr(map.heading),
        items: items.map((i) => {
          const item = i as Record<string, unknown>;
          const question = str(item.question).trim();
          const answer = str(item.answer).trim();
          if (question.length === 0 || answer.length === 0) fail(`${context} has an incomplete question/answer.`);
          return { question, answer };
        }),
      };
    }
    case 'gallery': {
      const items = Array.isArray(map.items) ? map.items : [];
      if (items.length === 0) fail(`${context} needs at least one image.`);
      return { ...base, heading: optionalStr(map.heading), items: items.map((m) => validateMediaReference(m, context)) };
    }
    case 'testimonial': {
      const items = Array.isArray(map.items) ? map.items : [];
      if (items.length === 0) fail(`${context} needs at least one entry.`);
      return {
        ...base,
        heading: optionalStr(map.heading),
        items: items.map((t) => {
          const entry = t as Record<string, unknown>;
          const quote = str(entry.quote).trim();
          if (quote.length === 0) fail(`${context} has an entry with no quote text.`);
          return { quote, attributionName: optionalStr(entry.attributionName), relationship: optionalStr(entry.relationship) };
        }),
      };
    }
    case 'relatedContent': {
      const relatedPageIds = Array.isArray(map.relatedPageIds) ? map.relatedPageIds.filter((v) => typeof v === 'string') : [];
      if (relatedPageIds.length === 0) fail(`${context} needs at least one selection.`);
      return { ...base, heading: optionalStr(map.heading), relatedPageIds };
    }
  }
}

export function validatePageSections(raw: unknown): Record<string, unknown>[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((section, index) => validatePageSection(section, index));
}
