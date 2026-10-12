import { describe, expect, it } from 'vitest';
import { ConsentSchema } from './index.js';
import { ok, samples, without } from './test-samples.js';

const RETAIN = '2031-10-12T14:30:00Z';
const revoked = { status: 'revoked', evidence_text: undefined, retain_until: RETAIN };

describe('consent', () => {
  it('requires evidence_text when granted', () => {
    expect(ConsentSchema.safeParse(without('consent', 'evidence_text')).success).toBe(false);
    expect(ok('consent', { evidence_text: '' })).toBe(false);
    expect(ok('consent', revoked)).toBe(true);
  });
  it('limits evidence_text to 2000 characters', () => {
    expect(ok('consent', { evidence_text: 'x'.repeat(2000) })).toBe(true);
    expect(ok('consent', { evidence_text: 'x'.repeat(2001) })).toBe(false);
  });
  it('needs a customer or a lead', () => {
    expect(ConsentSchema.safeParse(without('consent', 'customer_id')).success).toBe(false);
    expect(
      ConsentSchema.safeParse({ ...without('consent', 'customer_id'), lead_id: 'bad' }).success,
    ).toBe(false);
    expect(ok('consent', { lead_id: '00000000-0000-4000-8000-0000000000a1' })).toBe(true);
    expect(ConsentSchema.safeParse(without('consent', 'address')).success).toBe(false);
    expect(ok('consent', { address: '' })).toBe(false);
  });
  it('allows a revoke-all record only when revoked', () => {
    const all = { channel: 'all', address: '+15555550101' };
    expect(ok('consent', { ...revoked, ...all })).toBe(true);
    expect(ok('consent', all)).toBe(false);
    expect(ok('consent', { channel: 'fax' })).toBe(false);
    expect(
      ConsentSchema.safeParse({ ...without('consent', 'customer_id'), ...revoked, ...all }).success,
    ).toBe(false);
  });
  it('accepts purpose all only on a revocation', () => {
    expect(ok('consent', { ...revoked, purpose: 'all' })).toBe(true);
    expect(ok('consent', { purpose: 'all' })).toBe(false);
    expect(ok('consent', { purpose: 'informational' })).toBe(true);
    expect(ok('consent', { purpose: 'spam' })).toBe(false);
  });
  it('requires capture context and accepts a rep id', () => {
    expect(ConsentSchema.safeParse(without('consent', 'purpose')).success).toBe(false);
    expect(ConsentSchema.safeParse(without('consent', 'capture_context')).success).toBe(false);
    expect(ok('consent', { capture_context: {} })).toBe(false);
    expect(ok('consent', { capture_context: { method: 'paper', ip_address: 'nope' } })).toBe(false);
    expect(
      ok('consent', { capture_context: { method: 'web_form', page_url: 'javascript:1' } }),
    ).toBe(false);
    expect(
      ok('consent', {
        capture_context: {
          method: 'web_form',
          ip_address: '2001:db8::1',
          page_url: 'https://example.com/x',
        },
        captured_by_user_id: '00000000-0000-4000-8000-0000000000b1',
      }),
    ).toBe(true);
  });
  it('limits user_agent, source and address, and rejects unknown capture keys', () => {
    const ctx = (extra: Record<string, unknown>) => ({
      capture_context: { method: 'paper', ...extra },
    });
    expect(ok('consent', ctx({ user_agent: 'x'.repeat(500) }))).toBe(true);
    expect(ok('consent', ctx({ user_agent: 'x'.repeat(501) }))).toBe(false);
    expect(ok('consent', ctx({ extra: 1 }))).toBe(false);
    expect(ok('consent', { source: 'x'.repeat(100) })).toBe(true);
    expect(ok('consent', { source: 'x'.repeat(101) })).toBe(false);
    expect(ok('consent', { source: '' })).toBe(false);
    expect(ok('consent', { address: '+1'.padEnd(255, '5') })).toBe(false);
  });
});

describe('consent address per channel', () => {
  const cases: Record<string, { good: string[]; bad: string[] }> = {
    sms: {
      good: ['+15555550101'],
      bad: ['(555) 555-0101', '5555550101', 'a@example.com', '12345'],
    },
    voice_ai: { good: ['+15555550101'], bad: ['555-555-0101', 'a@example.com'] },
    email: { good: ['ann@example.com'], bad: ['Ann@Example.com', '+15555550101', 'not-an-email'] },
    messenger: { good: ['1234567890123456'], bad: ['abc123', '+15555550101', '', 'a@example.com'] },
  };
  for (const [channel, { good, bad }] of Object.entries(cases)) {
    it(`${channel}: accepts its canonical address and rejects the rest`, () => {
      for (const address of good) {
        expect(ok('consent', { channel, address }), address).toBe(true);
      }
      for (const address of bad) {
        expect(ok('consent', { channel, address }), address).toBe(false);
      }
    });
  }
  it('all: accepts a phone, a lowercase email or a PSID, and nothing else', () => {
    for (const address of ['+15555550101', 'ann@example.com', '1234567890']) {
      expect(ok('consent', { ...revoked, channel: 'all', address }), address).toBe(true);
    }
    for (const address of ['(555) 555-0101', 'Ann@Example.com', 'hello']) {
      expect(ok('consent', { ...revoked, channel: 'all', address }), address).toBe(false);
    }
  });
  it('rejects a non-E.164 phone on an sms revocation', () => {
    expect(ok('consent', { ...revoked, address: '(555) 555-0101' })).toBe(false);
    expect(ok('consent', { ...revoked, address: '+15555550101' })).toBe(true);
  });
});

describe('consent retention', () => {
  const at = (recorded_at: string, retain_until: string) =>
    ok('consent', { ...revoked, recorded_at, retain_until });
  it('a granted record has no retain_until (kept while the consent is in use)', () => {
    expect(ok('consent', {})).toBe(true);
    expect(samples.consent.value).not.toHaveProperty('retain_until');
    expect(ok('consent', { retain_until: '2040-01-01T00:00:00Z' })).toBe(false);
  });
  it('a revoked record needs retain_until at least 5 years after recorded_at', () => {
    expect(ok('consent', { ...revoked, retain_until: undefined })).toBe(false);
    expect(ok('consent', { ...revoked, retain_until: '2031-10-12T14:29:59Z' })).toBe(false);
    expect(ok('consent', { ...revoked, retain_until: '2020-01-01T00:00:00Z' })).toBe(false);
    expect(ok('consent', revoked)).toBe(true);
    expect(ok('consent', { ...revoked, retain_until: '2040-01-01T00:00:00Z' })).toBe(true);
  });
  it('counts a Feb 29 record from Mar 1 (the longer reading)', () => {
    const leap = '2028-02-29T00:00:00Z';
    expect(at(leap, '2033-02-28T23:59:59Z')).toBe(false);
    expect(at(leap, '2033-03-01T00:00:00Z')).toBe(true);
    expect(at('2028-02-28T00:00:00Z', '2033-02-28T00:00:00Z')).toBe(true);
    expect(at('2028-02-28T00:00:00Z', '2033-02-27T23:59:59Z')).toBe(false);
  });
});
