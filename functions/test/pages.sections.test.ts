import { HttpsError } from 'firebase-functions/v2/https';

import { isPageSectionType, validatePageSection, validatePageSections } from '../src/pages/sections';

describe('isPageSectionType', () => {
  it('accepts every declared type', () => {
    for (const type of ['richText', 'image', 'imageText', 'cta', 'highlights', 'faq', 'gallery', 'testimonial', 'relatedContent']) {
      expect(isPageSectionType(type)).toBe(true);
    }
  });

  it('rejects unknown values', () => {
    expect(isPageSectionType('notAType')).toBe(false);
    expect(isPageSectionType(42)).toBe(false);
  });
});

describe('validatePageSection', () => {
  it('rejects a non-object', () => {
    expect(() => validatePageSection('not-an-object', 0)).toThrow(HttpsError);
  });

  it('rejects a missing id', () => {
    expect(() => validatePageSection({ type: 'richText', body: 'x' }, 0)).toThrow(HttpsError);
  });

  it('rejects an unrecognized type', () => {
    expect(() => validatePageSection({ id: 's1', type: 'notAType' }, 0)).toThrow(HttpsError);
  });

  it('validates richText', () => {
    const result = validatePageSection({ id: 's1', type: 'richText', heading: 'H', body: 'Body' }, 0);
    expect(result).toMatchObject({ id: 's1', type: 'richText', heading: 'H', body: 'Body' });
  });

  it('requires alt text on image', () => {
    expect(() => validatePageSection({ id: 's1', type: 'image', image: { url: 'https://x.test/a.png' } }, 0)).toThrow(HttpsError);
  });

  it('validates image with alt text', () => {
    const result = validatePageSection({ id: 's1', type: 'image', image: { url: 'https://x.test/a.png', altText: 'Alt' } }, 0);
    expect(result.image).toMatchObject({ altText: 'Alt' });
  });

  it('requires alt text and body on imageText', () => {
    expect(() =>
      validatePageSection({ id: 's1', type: 'imageText', body: 'Body', image: { url: 'https://x.test/a.png' } }, 0),
    ).toThrow(HttpsError);
  });

  it('validates imageText and normalizes imageSide', () => {
    const result = validatePageSection(
      { id: 's1', type: 'imageText', body: 'Body', image: { url: 'https://x.test/a.png', altText: 'Alt' }, imageSide: 'right' },
      0,
    );
    expect(result.imageSide).toBe('right');
  });

  it('requires a label and target on cta', () => {
    expect(() => validatePageSection({ id: 's1', type: 'cta', primaryCta: { label: '' } }, 0)).toThrow(HttpsError);
  });

  it('validates cta', () => {
    const result = validatePageSection({ id: 's1', type: 'cta', primaryCta: { label: 'Enquire', target: '/contact' } }, 0);
    expect(result.primaryCta).toMatchObject({ label: 'Enquire', target: '/contact' });
  });

  it('requires at least one card on highlights', () => {
    expect(() => validatePageSection({ id: 's1', type: 'highlights', cards: [] }, 0)).toThrow(HttpsError);
  });

  it('validates highlights', () => {
    const result = validatePageSection({ id: 's1', type: 'highlights', cards: [{ title: 'A', body: 'B' }] }, 0);
    expect(result.cards).toHaveLength(1);
  });

  it('requires at least one item and complete question/answer on faq', () => {
    expect(() => validatePageSection({ id: 's1', type: 'faq', items: [] }, 0)).toThrow(HttpsError);
    expect(() => validatePageSection({ id: 's1', type: 'faq', items: [{ question: 'Q?', answer: '' }] }, 0)).toThrow(HttpsError);
  });

  it('validates faq', () => {
    const result = validatePageSection({ id: 's1', type: 'faq', items: [{ question: 'Q?', answer: 'A.' }] }, 0);
    expect(result.items).toHaveLength(1);
  });

  it('requires at least one item on gallery', () => {
    expect(() => validatePageSection({ id: 's1', type: 'gallery', items: [] }, 0)).toThrow(HttpsError);
  });

  it('validates gallery', () => {
    const result = validatePageSection({ id: 's1', type: 'gallery', items: [{ url: 'https://x.test/a.png', altText: 'Alt' }] }, 0);
    expect(result.items).toHaveLength(1);
  });

  it('requires a quote on every testimonial entry', () => {
    expect(() => validatePageSection({ id: 's1', type: 'testimonial', items: [{ quote: '' }] }, 0)).toThrow(HttpsError);
  });

  it('validates testimonial', () => {
    const result = validatePageSection({ id: 's1', type: 'testimonial', items: [{ quote: 'Great!' }] }, 0);
    expect(result.items).toHaveLength(1);
  });

  it('requires at least one selection on relatedContent', () => {
    expect(() => validatePageSection({ id: 's1', type: 'relatedContent', relatedPageIds: [] }, 0)).toThrow(HttpsError);
  });

  it('validates relatedContent', () => {
    const result = validatePageSection({ id: 's1', type: 'relatedContent', relatedPageIds: ['p2', 'p3'] }, 0);
    expect(result.relatedPageIds).toEqual(['p2', 'p3']);
  });
});

describe('validatePageSections', () => {
  it('returns an empty array for non-array input', () => {
    expect(validatePageSections(undefined)).toEqual([]);
  });

  it('validates every section and preserves order', () => {
    const sections = validatePageSections([
      { id: 's1', type: 'richText', body: 'First' },
      { id: 's2', type: 'richText', body: 'Second' },
    ]);
    expect(sections.map((s) => s.body)).toEqual(['First', 'Second']);
  });
});
