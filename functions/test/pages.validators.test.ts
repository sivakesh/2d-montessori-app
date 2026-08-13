import { HttpsError } from 'firebase-functions/v2/https';

import { validateFeaturedImage, validatePageContent, validatePageId, validatePageTitle, validateSeo, validateSlugFormat, validateSummary } from '../src/pages/validators';

describe('validatePageId / validatePageTitle', () => {
  it('accepts valid values', () => {
    expect(validatePageId('abc123')).toBe('abc123');
    expect(validatePageTitle('  About us  ')).toBe('About us');
  });

  it('rejects empty/over-length values', () => {
    expect(() => validatePageId('')).toThrow(HttpsError);
    expect(() => validatePageTitle('')).toThrow(HttpsError);
    expect(() => validatePageTitle('a'.repeat(201))).toThrow(HttpsError);
  });
});

describe('validateSlugFormat', () => {
  it('accepts lowercase letters, numbers and hyphens', () => {
    expect(validateSlugFormat('about-us')).toBe('about-us');
  });

  it('rejects invalid formats with reason invalid-slug', () => {
    expect.assertions(2);
    try {
      validateSlugFormat('Not Valid!');
    } catch (error) {
      expect(error).toBeInstanceOf(HttpsError);
      expect((error as HttpsError).details).toMatchObject({ reason: 'invalid-slug' });
    }
  });

  it('rejects an over-length slug', () => {
    expect(() => validateSlugFormat('a'.repeat(121))).toThrow(HttpsError);
  });
});

describe('validateSummary', () => {
  it('trims and accepts up to 300 characters', () => {
    expect(validateSummary('  hello  ')).toBe('hello');
    expect(validateSummary('a'.repeat(300))).toHaveLength(300);
  });

  it('rejects over 300 characters', () => {
    expect(() => validateSummary('a'.repeat(301))).toThrow(HttpsError);
  });
});

describe('validateFeaturedImage', () => {
  it('returns null when absent', () => {
    expect(validateFeaturedImage(undefined)).toBeNull();
    expect(validateFeaturedImage(null)).toBeNull();
  });

  it('requires alt text', () => {
    expect(() => validateFeaturedImage({ url: 'https://x.test/a.png' })).toThrow(HttpsError);
  });

  it('accepts a valid reference', () => {
    const result = validateFeaturedImage({ url: 'https://x.test/a.png', altText: 'A photo' }) as Record<string, unknown>;
    expect(result.altText).toBe('A photo');
    expect(result.url).toBe('https://x.test/a.png');
  });
});

describe('validateSeo', () => {
  it('defaults indexing to indexFollow and handles missing social', () => {
    const seo = validateSeo({});
    expect(seo.indexing).toBe('indexFollow');
    expect(seo.social.image).toBeNull();
  });

  it('rejects an unrecognized indexing value by falling back to the default', () => {
    const seo = validateSeo({ indexing: 'not-a-real-value' });
    expect(seo.indexing).toBe('indexFollow');
  });

  it('carries through valid values', () => {
    const seo = validateSeo({ title: 'SEO title', metaDescription: 'Desc', indexing: 'noIndexFollow', social: { title: 'Social title' } });
    expect(seo.title).toBe('SEO title');
    expect(seo.indexing).toBe('noIndexFollow');
    expect(seo.social.title).toBe('Social title');
  });
});

describe('validatePageContent', () => {
  it('validates a full content payload', () => {
    const content = validatePageContent({
      title: 'About',
      slug: 'about',
      summary: 'Summary',
      pageType: 'standard',
      sections: [],
      seo: {},
      showInNavigation: true,
    });
    expect(content.title).toBe('About');
    expect(content.slug).toBe('about');
    expect(content.showInNavigation).toBe(true);
  });

  it('propagates a section validation error', () => {
    expect(() =>
      validatePageContent({
        title: 'About',
        slug: 'about',
        summary: 'Summary',
        sections: [{ id: 's1', type: 'image', image: { url: 'https://x.test/a.png' } }],
        seo: {},
      }),
    ).toThrow(HttpsError);
  });
});
