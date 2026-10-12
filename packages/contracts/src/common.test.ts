import { describe, expect, it } from 'vitest';
import {
  BasisPointsSchema,
  EvidenceTextSchema,
  HttpsUrlSchema,
  IdSchema,
  SafeLongTextSchema,
  SafeTextSchema,
  TimeZoneSchema,
} from './index.js';
import { contactFields, recordBase } from './common.js';
import { ID, ok } from './test-samples.js';

describe('ids', () => {
  it('accepts only UUIDs (Payload idType uuid)', () => {
    expect(IdSchema.safeParse(ID.record).success).toBe(true);
    for (const bad of [
      '../x',
      'a/b',
      '%2e%2e',
      'a b',
      '',
      'a\0b',
      'x'.repeat(65),
      'd1',
      '123',
      5,
    ]) {
      expect(IdSchema.safeParse(bad).success, String(bad)).toBe(false);
    }
  });
});

describe('shared base objects', () => {
  it('are frozen so no importer can drop dealer_id or edit a contact field', () => {
    expect(Object.isFrozen(recordBase)).toBe(true);
    expect(Object.isFrozen(contactFields)).toBe(true);
    expect(Reflect.deleteProperty(recordBase, 'dealer_id')).toBe(false);
    expect(recordBase.dealer_id).toBeDefined();
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
});

describe('safe text', () => {
  const bad = ['a\u0000b', 'a\nb', 'a\tb', 'a\rb', 'a\u007fb', 'a\u0085b', 'a\u202eb', 'a\u2066b'];
  it('rejects control characters and bidi controls in single-line text', () => {
    for (const text of [...bad, 'a\u2028b', 'a\u200fb', 'a\u061cb']) {
      expect(SafeTextSchema.safeParse(text).success, JSON.stringify(text)).toBe(false);
    }
  });
  it('accepts Unicode, emoji joiners and leading formula characters (export must escape them)', () => {
    for (const text of [
      '李小龍',
      'Zoë',
      '👨\u200d👩\u200d👧',
      'می\u200cخواهم',
      '=SUM(A1)',
      '-x',
      '@home',
      '+1',
    ]) {
      expect(SafeTextSchema.safeParse(text).success, text).toBe(true);
    }
  });
  it('trims, so a blank value is empty', () => {
    expect(SafeTextSchema.parse('  Ann  ')).toBe('Ann');
    expect(SafeTextSchema.min(1).safeParse('   ').success).toBe(false);
  });
  it('long text keeps newline and tab but still rejects other controls and bidi', () => {
    expect(SafeLongTextSchema.safeParse('line 1\nline 2\tx').success).toBe(true);
    expect(SafeLongTextSchema.parse(' kept ')).toBe(' kept ');
    for (const text of ['a\u0000b', 'a\rb', 'a\u202eb', 'a\u2029b', 'a\u0085b']) {
      expect(SafeLongTextSchema.safeParse(text).success, JSON.stringify(text)).toBe(false);
    }
  });
  it('is used by names, wording and notes', () => {
    expect(ok('customer', { first_name: 'a\nb' })).toBe(false);
    expect(ok('lead', { comments: 'x\u202ey' })).toBe(false);
    expect(ok('vehicle', { make: 'Ho\u0000nda' })).toBe(false);
    expect(ok('dealer', { name: 'Fake\u202e Motors' })).toBe(false);
  });
});

describe('evidence text', () => {
  it('is 1-2000 characters of long text', () => {
    expect(EvidenceTextSchema.safeParse('').success).toBe(false);
    expect(EvidenceTextSchema.safeParse('x'.repeat(2000)).success).toBe(true);
    expect(EvidenceTextSchema.safeParse('x'.repeat(2001)).success).toBe(false);
    expect(EvidenceTextSchema.safeParse('a\u202eb').success).toBe(false);
  });
});

describe('https url', () => {
  const url = (u: string) => HttpsUrlSchema.safeParse(u).success;
  it('accepts only https URLs on a domain name', () => {
    expect(url('https://www.cargurus.com/lead')).toBe(true);
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
      expect(url(bad), bad).toBe(false);
    }
  });
  it('is NOT an SSRF control: internal-looking domain names pass, so never fetch it unguarded', () => {
    expect(url('https://metadata.google.internal/computeMetadata')).toBe(true);
    expect(url('https://127.0.0.1.nip.io')).toBe(true);
  });
});

describe('basis points', () => {
  it('are integers from 0 to 10000', () => {
    for (const [bp, good] of [
      [-1, false],
      [0, true],
      [650, true],
      [10000, true],
      [10001, false],
      [650.5, false],
    ] as const) {
      expect(BasisPointsSchema.safeParse(bp).success, String(bp)).toBe(good);
    }
  });
});
