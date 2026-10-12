import { describe, expect, it } from 'vitest';
import {
  BasisPointsSchema,
  EvidenceTextSchema,
  HttpsUrlSchema,
  IdSchema,
  SafeLongTextSchema,
  SafeTextSchema,
  TimeZoneSchema,
  contactFields,
  recordBase,
} from './common.js';
import { ok } from './samples.test.js';

describe('ids', () => {
  it('rejects ids that could climb out of a path or URL', () => {
    for (const bad of ['../x', 'a/b', '%2e%2e', 'a b', '', 'a\0b', 'x'.repeat(65)]) {
      expect(IdSchema.safeParse(bad).success, bad).toBe(false);
    }
    expect(IdSchema.safeParse('Dealer_01-a').success).toBe(true);
    expect(IdSchema.safeParse('x'.repeat(64)).success).toBe(true);
  });
  it('accepts a uuid (Payload idType uuid) and rejects a numeric id', () => {
    expect(IdSchema.safeParse('123e4567-e89b-12d3-a456-426614174000').success).toBe(true);
    expect(IdSchema.safeParse(42).success).toBe(false);
  });
});

describe('time zone', () => {
  it('accepts IANA names and rejects everything else', () => {
    for (const good of ['America/Chicago', 'America/Indiana/Indianapolis']) {
      expect(TimeZoneSchema.safeParse(good).success, good).toBe(true);
    }
    for (const bad of ['Mars/Olympus', 'CST', '', 'America/', '../etc', 'x/'.repeat(40)]) {
      expect(TimeZoneSchema.safeParse(bad).success, bad).toBe(false);
    }
    expect(ok('dealer', { time_zone: 'Mars/Olympus' })).toBe(false);
    expect(ok('customer', { time_zone: 'CST' })).toBe(false);
    expect(ok('customer', { time_zone: 'America/Chicago' })).toBe(true);
  });
  it('is required on Dealer and optional on Customer', () => {
    expect(ok('dealer', { time_zone: undefined })).toBe(false);
    expect(ok('customer', { time_zone: undefined })).toBe(true);
  });
});

describe('basis points', () => {
  it('is an integer from 0 to 10000', () => {
    for (const [value, good] of [
      [-1, false],
      [0, true],
      [650, true],
      [650.5, false],
      [10000, true],
      [10001, false],
    ] as const) {
      expect(BasisPointsSchema.safeParse(value).success, String(value)).toBe(good);
    }
  });
});

describe('evidence text', () => {
  it('is 1-2000 characters and may span lines', () => {
    expect(EvidenceTextSchema.safeParse('').success).toBe(false);
    expect(EvidenceTextSchema.safeParse('x'.repeat(2000)).success).toBe(true);
    expect(EvidenceTextSchema.safeParse('x'.repeat(2001)).success).toBe(false);
    expect(EvidenceTextSchema.safeParse('line one\nline two\tend').success).toBe(true);
    expect(EvidenceTextSchema.safeParse('a\u0000b').success).toBe(false);
  });
});

describe('safe text', () => {
  const bad = [
    'a\u0000b',
    'a\nb',
    'a\tb',
    'a\rb',
    'a\u001bb',
    'a\u007fb',
    'a\u0085b',
    'a\u009fb',
    'a‮b',
    'a⁦b',
    'a⁩b',
    'a‏b',
    'a؜b',
    'a b',
  ];
  it('rejects control, bidi and line-separator characters in single-line text', () => {
    for (const text of bad) {
      expect(SafeTextSchema.safeParse(text).success, JSON.stringify(text)).toBe(false);
    }
  });
  it('allows only newline and tab extra in long text', () => {
    expect(SafeLongTextSchema.safeParse('a\nb\tc').success).toBe(true);
    for (const text of bad.filter((t) => !t.includes('\n') && !t.includes('\t'))) {
      expect(SafeLongTextSchema.safeParse(text).success, JSON.stringify(text)).toBe(false);
    }
  });
  it('accepts ordinary and Unicode text, including a leading formula character (CSV export must escape it)', () => {
    for (const text of ['Zoë 李小龍', 'Müller Автo', '=SUM(A1)', '@home', '-1', '+1 555']) {
      expect(SafeTextSchema.safeParse(text).success, text).toBe(true);
    }
  });
  it('is used by free-text fields in the shapes', () => {
    expect(ok('customer', { first_name: 'A‮B' })).toBe(false);
    expect(ok('customer', { address: { city: 'Au\nstin' } })).toBe(false);
    expect(ok('dealer', { name: 'Fake\u0000Motors' })).toBe(false);
    expect(ok('vehicle', { make: 'Ho‮nda' })).toBe(false);
    expect(ok('lead', { comments: 'Hi‮' })).toBe(false);
    expect(ok('lead', { comments: 'Hi\nthere' })).toBe(true);
    expect(ok('lead', { source: { provider_name: 'Car\nGurus' } })).toBe(false);
    expect(ok('deal', { tax_jurisdiction: 'Butler\nCounty' })).toBe(false);
  });
});

describe('https url (untrusted, display-only; not an SSRF control)', () => {
  it('accepts https URLs with a domain name host', () => {
    expect(HttpsUrlSchema.safeParse('https://www.cargurus.com/lead').success).toBe(true);
  });
  it('rejects other schemes, IP literals, localhost and over-long URLs', () => {
    for (const bad of [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'http://example.com',
      'http://127.0.0.1',
      'https://127.0.0.1',
      'http://169.254.169.254/latest',
      'https://localhost',
      `https://example.com/${'a'.repeat(2048)}`,
    ]) {
      expect(HttpsUrlSchema.safeParse(bad).success, bad).toBe(false);
    }
  });
  it('still lets internal-looking hostnames pass, so callers must never fetch it without an SSRF guard', () => {
    for (const passes of ['https://metadata.google.internal/', 'https://127.0.0.1.nip.io/']) {
      expect(HttpsUrlSchema.safeParse(passes).success, passes).toBe(true);
    }
  });
});

describe('shared field sets', () => {
  it('are frozen, so no importer can drop dealer_id or a contact rule', () => {
    expect(Object.isFrozen(recordBase)).toBe(true);
    expect(Object.isFrozen(contactFields)).toBe(true);
    expect(Reflect.deleteProperty(recordBase, 'dealer_id')).toBe(false);
    expect('dealer_id' in recordBase).toBe(true);
  });
});
