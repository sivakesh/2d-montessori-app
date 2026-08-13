/**
 * SRS CMS-08: "Publishing checks required fields, alt text, ... SEO
 * metadata ... Errors block." The authoritative half — mirrors
 * `packages/feature_pages/lib/src/domain/page_completeness_validator.dart`
 * rule-for-rule (hand-synced, not code-shared, same convention as every
 * other Dart/TypeScript pair in this codebase). Only called for the
 * three actions that move content toward/into public visibility
 * (submitForReview, publish, schedule) — see `transitionPage.ts`.
 */
import type { DocumentData } from 'firebase-admin/firestore';

function violationsForSection(section: Record<string, unknown>): string[] {
  const violations: string[] = [];
  const type = section.type as string;
  switch (type) {
    case 'richText':
      if (!(section.body as string)?.trim()) violations.push('A rich-text section has no content.');
      break;
    case 'image':
      if (!((section.image as Record<string, unknown>)?.altText as string)?.trim()) {
        violations.push('An image section is missing alternative text.');
      }
      break;
    case 'imageText':
      if (!((section.image as Record<string, unknown>)?.altText as string)?.trim()) {
        violations.push('An image-and-text section is missing alternative text.');
      }
      if (!(section.body as string)?.trim()) violations.push('An image-and-text section has no body text.');
      break;
    case 'cta': {
      const primary = section.primaryCta as Record<string, unknown> | undefined;
      if (!(primary?.label as string)?.trim() || !(primary?.target as string)?.trim()) {
        violations.push('A call-to-action section needs a label and a destination.');
      }
      break;
    }
    case 'highlights':
      if (!Array.isArray(section.cards) || section.cards.length === 0) {
        violations.push('A highlights section needs at least one card.');
      }
      break;
    case 'faq':
      if (!Array.isArray(section.items) || section.items.length === 0) {
        violations.push('An FAQ section needs at least one question.');
      }
      break;
    case 'gallery':
      if (!Array.isArray(section.items) || section.items.length === 0) {
        violations.push('A gallery section needs at least one image.');
      } else if ((section.items as Record<string, unknown>[]).some((m) => !(m.altText as string)?.trim())) {
        violations.push('Every gallery image needs alternative text.');
      }
      break;
    case 'testimonial':
      if (!Array.isArray(section.items) || section.items.length === 0) {
        violations.push('A testimonial section needs at least one entry.');
      }
      break;
    case 'relatedContent':
      if (!Array.isArray(section.relatedPageIds) || section.relatedPageIds.length === 0) {
        violations.push('A related-content section needs at least one selection.');
      }
      break;
  }
  return violations;
}

export function pageCompletenessViolations(content: DocumentData): string[] {
  const violations: string[] = [];
  if (!(content.title as string)?.trim()) violations.push('Title is required.');
  if (!(content.slug as string)?.trim()) violations.push('A URL slug is required.');
  if (!(content.summary as string)?.trim()) violations.push('A short summary is required.');
  const sections = Array.isArray(content.sections) ? (content.sections as Record<string, unknown>[]) : [];
  if (sections.length === 0) violations.push('At least one section is required.');
  const seo = (content.seo as Record<string, unknown>) ?? {};
  if (!(seo.title as string)?.trim()) violations.push('An SEO title is required.');
  if (!(seo.metaDescription as string)?.trim()) violations.push('A meta description is required.');
  const featuredImage = content.featuredImage as Record<string, unknown> | null | undefined;
  if (featuredImage && !(featuredImage.altText as string)?.trim()) {
    violations.push('The featured image needs alternative text.');
  }
  for (const section of sections) {
    violations.push(...violationsForSection(section));
  }
  return violations;
}
