import { pageCompletenessViolations } from '../src/pages/completeness';

function validContent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: 'About us',
    slug: 'about-us',
    summary: 'A short summary.',
    sections: [{ id: 's1', type: 'richText', body: 'Body text.' }],
    seo: { title: 'About us', metaDescription: 'A page about us.' },
    featuredImage: null,
    ...overrides,
  };
}

describe('pageCompletenessViolations', () => {
  it('returns no violations for a fully-filled page', () => {
    expect(pageCompletenessViolations(validContent())).toEqual([]);
  });

  it('flags missing title, slug, summary, sections and SEO fields', () => {
    const violations = pageCompletenessViolations({ sections: [], seo: {} });
    expect(violations).toContain('Title is required.');
    expect(violations).toContain('A URL slug is required.');
    expect(violations).toContain('A short summary is required.');
    expect(violations).toContain('At least one section is required.');
    expect(violations).toContain('An SEO title is required.');
    expect(violations).toContain('A meta description is required.');
  });

  it('flags a featured image with no alt text', () => {
    const violations = pageCompletenessViolations(validContent({ featuredImage: { url: 'https://x.test/a.png', altText: '' } }));
    expect(violations).toContain('The featured image needs alternative text.');
  });

  it('flags an image section missing alt text', () => {
    const violations = pageCompletenessViolations(
      validContent({ sections: [{ id: 's1', type: 'image', image: { url: 'https://x.test/a.png', altText: '' } }] }),
    );
    expect(violations).toContain('An image section is missing alternative text.');
  });

  it('flags a cta section with no label/target', () => {
    const violations = pageCompletenessViolations(validContent({ sections: [{ id: 's1', type: 'cta', primaryCta: {} }] }));
    expect(violations).toContain('A call-to-action section needs a label and a destination.');
  });

  it('flags empty highlights/faq/gallery/testimonial/relatedContent sections', () => {
    const violations = pageCompletenessViolations(
      validContent({
        sections: [
          { id: 's1', type: 'highlights', cards: [] },
          { id: 's2', type: 'faq', items: [] },
          { id: 's3', type: 'gallery', items: [] },
          { id: 's4', type: 'testimonial', items: [] },
          { id: 's5', type: 'relatedContent', relatedPageIds: [] },
        ],
      }),
    );
    expect(violations).toContain('A highlights section needs at least one card.');
    expect(violations).toContain('An FAQ section needs at least one question.');
    expect(violations).toContain('A gallery section needs at least one image.');
    expect(violations).toContain('A testimonial section needs at least one entry.');
    expect(violations).toContain('A related-content section needs at least one selection.');
  });

  it('flags a gallery item missing alt text even when the section is non-empty', () => {
    const violations = pageCompletenessViolations(
      validContent({ sections: [{ id: 's1', type: 'gallery', items: [{ url: 'https://x.test/a.png', altText: '' }] }] }),
    );
    expect(violations).toContain('Every gallery image needs alternative text.');
  });
});
