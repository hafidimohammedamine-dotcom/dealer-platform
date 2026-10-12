import { describe, expect, it } from 'vitest';
import { ConsentCaptureContextSchema, ConsentSchema } from './index.js';
import { ok, without } from './samples.test.js';

const revoked = {
  status: 'revoked',
  evidence_text: undefined,
  recorded_at: '2026-10-12T14:30:00Z',
  retain_until: '2031-10-12T14:30:00Z',
};

describe('consent evidence and ownership', () => {
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
      ConsentSchema.safeParse({ ...without('consent', 'customer_id'), lead_id: 'l1' }).success,
    ).toBe(true);
    expect(ok('consent', { lead_id: 'l1' })).toBe(true);
  });
  it('limits source (1-100)', () => {
    expect(ok('consent', { source: '' })).toBe(false);
    expect(ok('consent', { source: 'x'.repeat(100) })).toBe(true);
    expect(ok('consent', { source: 'x'.repeat(101) })).toBe(false);
  });
});

describe('consent purpose and channel', () => {
  it('allows a revoke-all channel only when revoked', () => {
    expect(ok('consent', { ...revoked, channel: 'all' })).toBe(true);
    expect(ok('consent', { channel: 'all' })).toBe(false);
    expect(ok('consent', { channel: 'fax' })).toBe(false);
  });
  it('allows purpose all only when revoked', () => {
    expect(ok('consent', { ...revoked, purpose: 'all' })).toBe(true);
    expect(ok('consent', { purpose: 'all' })).toBe(false);
    expect(ok('consent', { purpose: 'informational' })).toBe(true);
    expect(ok('consent', { purpose: 'spam' })).toBe(false);
  });
  it('requires purpose and capture context', () => {
    expect(ConsentSchema.safeParse(without('consent', 'purpose')).success).toBe(false);
    expect(ConsentSchema.safeParse(without('consent', 'capture_context')).success).toBe(false);
    expect(ok('consent', { capture_context: {} })).toBe(false);
  });
});

describe('consent address matches its channel', () => {
  const cases = [
    ['sms', '+15555550101', '(555) 555-0101'],
    ['voice_ai', '+15555550101', '555-555-0101'],
    ['email', 'ann@example.com', 'Ann@Example.com'],
    ['messenger', '1234567890', 'psid-123'],
    ['all', '+15555550101', 'not an address'],
  ] as const;
  for (const [channel, good, bad] of cases) {
    it(`${channel}: accepts ${good} and rejects ${bad}`, () => {
      const patch = channel === 'all' ? revoked : {};
      expect(ok('consent', { ...patch, channel, address: good })).toBe(true);
      expect(ok('consent', { ...patch, channel, address: bad })).toBe(false);
    });
  }
  it('lets an all record carry a phone, an email or a PSID', () => {
    for (const address of ['+15555550101', 'ann@example.com', '1234567890']) {
      expect(ok('consent', { ...revoked, channel: 'all', address })).toBe(true);
    }
  });
  it('rejects a non-E.164 phone on an sms consent and on an sms revocation', () => {
    expect(ok('consent', { address: '(555) 555-0101' })).toBe(false);
    expect(ok('consent', { ...revoked, address: '(555) 555-0101' })).toBe(false);
    expect(ok('consent', { ...revoked, address: '+15555550101' })).toBe(true);
  });
  it('requires an address and limits it to 254 characters', () => {
    expect(ConsentSchema.safeParse(without('consent', 'address')).success).toBe(false);
    expect(ok('consent', { address: '' })).toBe(false);
    expect(ok('consent', { channel: 'email', address: `${'a'.repeat(250)}@example.com` })).toBe(
      false,
    );
  });
});

describe('consent capture context', () => {
  const ctx = (patch: Record<string, unknown>) =>
    ConsentCaptureContextSchema.safeParse({ method: 'web_form', ...patch }).success;
  it('checks IP address and page URL', () => {
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
        captured_by_user_id: 'u1',
      }),
    ).toBe(true);
  });
  it('limits user_agent to 500 characters and rejects control characters', () => {
    expect(ctx({ user_agent: 'x'.repeat(500) })).toBe(true);
    expect(ctx({ user_agent: 'x'.repeat(501) })).toBe(false);
    expect(ctx({ user_agent: 'Mozilla\nInjected: line' })).toBe(false);
  });
  it('rejects an unknown method and unknown keys', () => {
    expect(ctx({ method: 'carrier_pigeon' })).toBe(false);
    expect(ctx({ surprise: 1 })).toBe(false);
    expect(ok('consent', { capture_context: { method: 'web_form', surprise: 1 } })).toBe(false);
  });
});

describe('consent retention', () => {
  it('forbids retain_until on a granted record (kept while in use)', () => {
    expect(ok('consent', {})).toBe(true);
    expect(ok('consent', { retain_until: '2040-01-01T00:00:00Z' })).toBe(false);
  });
  it('requires retain_until on a revoked record, at least 5 years after recorded_at', () => {
    expect(ok('consent', { ...revoked, retain_until: undefined })).toBe(false);
    expect(ok('consent', { ...revoked, retain_until: '2031-10-12T14:29:59Z' })).toBe(false);
    expect(ok('consent', { ...revoked, retain_until: '2020-01-01T00:00:00Z' })).toBe(false);
    expect(ok('consent', { ...revoked, retain_until: '2031-10-12T14:30:00Z' })).toBe(true);
    expect(ok('consent', { ...revoked, retain_until: '2040-01-01T00:00:00Z' })).toBe(true);
  });
  it('rolls a leap day forward: 2028-02-29 plus 5 years is 2033-03-01', () => {
    const leap = { ...revoked, recorded_at: '2028-02-29T12:00:00Z' };
    expect(ok('consent', { ...leap, retain_until: '2033-02-28T12:00:00Z' })).toBe(false);
    expect(ok('consent', { ...leap, retain_until: '2033-03-01T11:59:59Z' })).toBe(false);
    expect(ok('consent', { ...leap, retain_until: '2033-03-01T12:00:00Z' })).toBe(true);
  });
  it('counts 5 calendar years across an ordinary leap year', () => {
    const early = { ...revoked, recorded_at: '2027-03-01T00:00:00Z' };
    expect(ok('consent', { ...early, retain_until: '2032-02-29T23:59:59Z' })).toBe(false);
    expect(ok('consent', { ...early, retain_until: '2032-03-01T00:00:00Z' })).toBe(true);
  });
});
