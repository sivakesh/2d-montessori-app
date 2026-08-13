import { slugify } from '../src/pages/slugify';

describe('slugify', () => {
  it('lowercases and hyphenates', () => {
    expect(slugify('About Us')).toBe('about-us');
  });

  it('strips punctuation and collapses runs of non-alphanumerics', () => {
    expect(slugify("The Montessori Way: Our Philosophy!")).toBe('the-montessori-way-our-philosophy');
  });

  it('trims leading/trailing hyphens', () => {
    expect(slugify('  -About-  ')).toBe('about');
  });

  it('falls back to "page" for an empty/non-alphanumeric title', () => {
    expect(slugify('!!!')).toBe('page');
    expect(slugify('')).toBe('page');
  });

  it('truncates to 100 characters', () => {
    expect(slugify('a'.repeat(150)).length).toBeLessThanOrEqual(100);
  });
});
