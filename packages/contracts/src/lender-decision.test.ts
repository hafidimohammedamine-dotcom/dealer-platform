import { describe, expect, it } from 'vitest';
import { LenderDecisionSchema, LenderDecisionStatusSchema } from './index.js';
import { T, ok, without } from './samples.test.js';

const declined = { status: 'declined', adverse_action_reasons: ['Insufficient income'] };

describe('lender decision identity and dedupe key', () => {
  it('pins the status names', () => {
    expect(LenderDecisionStatusSchema.options).toEqual([
      'pending',
      'approved',
      'conditional',
      'countered',
      'declined',
      'expired',
    ]);
    expect(ok('decision', { status: 'maybe' })).toBe(false);
  });
  it('requires request_id and provider_message_id', () => {
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_id')).success).toBe(false);
    expect(ok('decision', { request_id: '../q' })).toBe(false);
    expect(LenderDecisionSchema.safeParse(without('decision', 'provider_message_id')).success).toBe(
      false,
    );
  });
  it('limits provider_message_id to printable ASCII without spaces, 1-200 characters', () => {
    const id = (provider_message_id: string) => ok('decision', { provider_message_id });
    expect(id('')).toBe(false);
    expect(id('x'.repeat(200))).toBe(true);
    expect(id('x'.repeat(201))).toBe(false);
    expect(id('<msg-1.2@lender.example>:a/b')).toBe(true);
    for (const bad of ['a b', 'a\nb', 'a\tb', 'é', '李', 'a\u0000b', 'a\u007fb']) {
      expect(id(bad), JSON.stringify(bad)).toBe(false);
    }
  });
  it('limits lender (1-100) and accepts Unicode', () => {
    expect(ok('decision', { lender: '' })).toBe(false);
    expect(ok('decision', { lender: 'x'.repeat(100) })).toBe(true);
    expect(ok('decision', { lender: 'x'.repeat(101) })).toBe(false);
    expect(ok('decision', { lender: 'Banque Générale 銀行' })).toBe(true);
    expect(ok('decision', { lender: 'Fake\nBank' })).toBe(false);
  });
});

describe('lender decision timing and reasons', () => {
  it('rejects decided_at before request_date and allows either one alone', () => {
    expect(ok('decision', { decided_at: '2026-10-12T14:29:59Z' })).toBe(false);
    expect(ok('decision', { decided_at: '2026-10-12T14:30:01Z' })).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_date')).success).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'decided_at')).success).toBe(true);
  });
  it('requires adverse action reasons when declined', () => {
    expect(ok('decision', { status: 'declined' })).toBe(false);
    expect(ok('decision', { status: 'declined', adverse_action_reasons: [] })).toBe(false);
    expect(ok('decision', declined)).toBe(true);
    expect(ok('decision', { status: 'countered' })).toBe(true);
  });
  it('limits reasons (10 of 1-500) and conditions (50 of 500)', () => {
    const reasons = (n: number) => ({ ...declined, adverse_action_reasons: Array(n).fill('r') });
    expect(ok('decision', reasons(10))).toBe(true);
    expect(ok('decision', reasons(11))).toBe(false);
    expect(ok('decision', { ...declined, adverse_action_reasons: [''] })).toBe(false);
    expect(ok('decision', { ...declined, adverse_action_reasons: ['x'.repeat(501)] })).toBe(false);
    expect(ok('decision', { conditions: Array(50).fill('x') })).toBe(true);
    expect(ok('decision', { conditions: Array(51).fill('x') })).toBe(false);
    expect(ok('decision', { conditions: ['x'.repeat(501)] })).toBe(false);
  });
  it('limits term_months and apr to their ranges', () => {
    expect(ok('decision', { term_months: 0 })).toBe(false);
    expect(ok('decision', { term_months: 120 })).toBe(true);
    expect(ok('decision', { term_months: 121 })).toBe(false);
    expect(ok('decision', { apr_basis_points: -1 })).toBe(false);
    expect(ok('decision', { apr_basis_points: 0 })).toBe(true);
    expect(ok('decision', { apr_basis_points: 10000 })).toBe(true);
    expect(ok('decision', { apr_basis_points: 10001 })).toBe(false);
  });
});

describe('lender decision consumer-report fields (FCRA 615)', () => {
  const extra = {
    ...declined,
    credit_score: 580,
    credit_bureau: 'experian',
    adverse_action_notice_sent_at: T,
  };
  it('carries credit score, bureau and notice date', () => {
    expect(ok('decision', extra)).toBe(true);
    expect(ok('decision', { ...extra, credit_bureau: 'acme' })).toBe(false);
    expect(ok('decision', { ...extra, adverse_action_notice_sent_at: 'yesterday' })).toBe(false);
    expect(ok('decision', { ...extra, credit_score: 580.5 })).toBe(false);
  });
  it('accepts scores from 250 to 900', () => {
    for (const [score, good] of [
      [249, false],
      [250, true],
      [900, true],
      [901, false],
    ] as const) {
      expect(ok('decision', { ...extra, credit_score: score }), String(score)).toBe(good);
    }
  });
  it('checks the score against its range', () => {
    const range = { score_range_min: 250, score_range_max: 900 };
    expect(ok('decision', { ...extra, ...range })).toBe(true);
    expect(ok('decision', { ...extra, score_range_min: 300, score_range_max: 850 })).toBe(true);
    expect(
      ok('decision', { ...extra, credit_score: 290, score_range_min: 300, score_range_max: 850 }),
    ).toBe(false);
    expect(
      ok('decision', { ...extra, credit_score: 860, score_range_min: 300, score_range_max: 850 }),
    ).toBe(false);
    expect(
      ok('decision', { ...extra, credit_score: 300, score_range_min: 300, score_range_max: 850 }),
    ).toBe(true);
    expect(
      ok('decision', { ...extra, credit_score: 850, score_range_min: 300, score_range_max: 850 }),
    ).toBe(true);
  });
  it('needs both range ends in order', () => {
    expect(ok('decision', { ...extra, score_range_min: 300 })).toBe(false);
    expect(ok('decision', { ...extra, score_range_max: 850 })).toBe(false);
    expect(ok('decision', { ...extra, score_range_min: 700, score_range_max: 600 })).toBe(false);
    expect(ok('decision', { ...extra, score_range_min: 200, score_range_max: 850 })).toBe(false);
  });
  it('carries score_date and up to 5 key_factors', () => {
    expect(ok('decision', { ...extra, score_date: '2026-10-12' })).toBe(true);
    expect(ok('decision', { ...extra, score_date: '10/12/2026' })).toBe(false);
    expect(ok('decision', { ...extra, key_factors: Array(5).fill('Too many inquiries') })).toBe(
      true,
    );
    expect(ok('decision', { ...extra, key_factors: Array(6).fill('x') })).toBe(false);
    expect(ok('decision', { ...extra, key_factors: [''] })).toBe(false);
    expect(ok('decision', { ...extra, key_factors: ['x'.repeat(501)] })).toBe(false);
  });
});
