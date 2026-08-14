import { collectPageMediaUsage } from '../src/media/usageTracking';

function mediaRef(mediaId: string, extra: Record<string, unknown> = {}) {
  return { url: `https://storage.googleapis.com/bucket/public/media/${mediaId}/w640.webp`, altText: 'alt', storagePath: `private/media/${mediaId}/original.png`, ...extra };
}

describe('collectPageMediaUsage', () => {
  it('finds a featuredImage reference', () => {
    const usage = collectPageMediaUsage({ featuredImage: mediaRef('m1') });
    expect(usage.get('m1')).toEqual(['featuredImage']);
  });

  it('finds an SEO social-share image reference', () => {
    const usage = collectPageMediaUsage({ seo: { social: { image: mediaRef('m1') } } });
    expect(usage.get('m1')).toEqual(['seo.social.image']);
  });

  it('finds image/imageText section references', () => {
    const usage = collectPageMediaUsage({
      sections: [
        { id: 's1', type: 'image', image: mediaRef('m1') },
        { id: 's2', type: 'imageText', image: mediaRef('m2') },
      ],
    });
    expect(usage.get('m1')).toEqual(['sections[0].image']);
    expect(usage.get('m2')).toEqual(['sections[1].image']);
  });

  it('finds every gallery item reference', () => {
    const usage = collectPageMediaUsage({
      sections: [{ id: 's1', type: 'gallery', items: [mediaRef('m1'), mediaRef('m2')] }],
    });
    expect(usage.get('m1')).toEqual(['sections[0].items[0]']);
    expect(usage.get('m2')).toEqual(['sections[0].items[1]']);
  });

  it('finds a highlight card image reference', () => {
    const usage = collectPageMediaUsage({
      sections: [{ id: 's1', type: 'highlights', cards: [{ title: 'A', body: 'B', image: mediaRef('m1') }] }],
    });
    expect(usage.get('m1')).toEqual(['sections[0].cards[0].image']);
  });

  it('groups multiple occurrences of the same asset under one mediaId', () => {
    const usage = collectPageMediaUsage({
      featuredImage: mediaRef('m1'),
      sections: [{ id: 's1', type: 'image', image: mediaRef('m1') }],
    });
    expect(usage.get('m1')?.sort()).toEqual(['featuredImage', 'sections[0].image'].sort());
  });

  it('ignores a MediaReference with no storagePath (an external URL, not a library asset)', () => {
    const usage = collectPageMediaUsage({ featuredImage: { url: 'https://example.com/photo.jpg', altText: 'alt' } });
    expect(usage.size).toBe(0);
  });

  it('ignores a null featuredImage, absent seo, and empty sections without throwing', () => {
    expect(() => collectPageMediaUsage({})).not.toThrow();
    expect(collectPageMediaUsage({ featuredImage: null, seo: null, sections: [] }).size).toBe(0);
  });

  it('returns an empty map when nothing references any media asset', () => {
    const usage = collectPageMediaUsage({
      featuredImage: null,
      sections: [{ id: 's1', type: 'richText', body: 'Hello' }],
    });
    expect(usage.size).toBe(0);
  });
});
