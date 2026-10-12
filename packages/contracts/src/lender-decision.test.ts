import { describe, expect, it } from 'vitest';
import {
  LENDER_DECISION_SENSITIVE_FIELDS,
  LenderDecisionSchema,
  LenderDecisionStatusSchema,
} from './index.js';
import { T, ok, without } from './test-samples.js';

const declined = { status: 'declined', adverse_action_reasons: ['Insufficient income'] };
const decision = (patch: Record<string, unknown>) => ok('decision', patch);

describe('lender decision', () => {
  it('pins the status names', () => {
    expect(LenderDecisionStatusSchema.options).toEqual([
      'pending',
      'approved',
      'conditional',
      'countered',
      'declined',
      'expired',
    ]);
    expect(decision({ status: 'maybe' })).toBe(false);
  });
  it('requires request_id and ties a callback to it', () => {
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_id')).success).toBe(false);
    expect(decision({ request_id: '../q' })).toBe(false);
  });
  it('limits and cleans the lender code', () => {
    expect(decision({ lender: 'x'.repeat(100) })).toBe(true);
    expect(decision({ lender: 'x'.repeat(101) })).toBe(false);
    expect(decision({ lender: '' })).toBe(false);
    expect(decision({ lender: 'Bänk 銀行' })).toBe(true);
    expect(decision({ lender: 'a\nb' })).toBe(false);
  });
});

describe('provider_message_id (dedupe key with request_id)', () => {
  const without_id = (patch: Record<string, unknown>) => ({
    ...without('decision', 'provider_message_id'),
    ...patch,
  });
  const parses = (record: Record<string, unknown>) =>
    LenderDecisionSchema.safeParse(record).success;
  it('is required on every status except pending', () => {
    expect(parses(without_id({}))).toBe(false);
    expect(parses(without_id({ status: 'pending' }))).toBe(true);
    expect(parses(without_id({ ...declined }))).toBe(false);
  });
  it('is 1-200 visible ASCII characters', () => {
    for (const good of ['msg-1', 'a:b/c=d', 'x'.repeat(200), '~!']) {
      expect(decision({ provider_message_id: good }), good).toBe(true);
    }
    for (const bad of ['', 'x'.repeat(201), 'a b', 'a\nb', 'é', '日本', 'a\u0000b']) {
      expect(decision({ provider_message_id: bad }), JSON.stringify(bad)).toBe(false);
    }
  });
});

describe('lender decision timing and adverse action', () => {
  it('rejects decided_at before request_date and allows either one alone', () => {
    expect(decision({ decided_at: '2026-10-12T14:29:59Z' })).toBe(false);
    expect(decision({ decided_at: '2026-10-12T14:30:01Z' })).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_date')).success).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'decided_at')).success).toBe(true);
  });
  it('requires adverse action reasons when declined', () => {
    expect(decision({ status: 'declined' })).toBe(false);
    expect(decision({ status: 'declined', adverse_action_reasons: [] })).toBe(false);
    expect(decision(declined)).toBe(true);
    expect(decision({ status: 'countered' })).toBe(true);
    expect(decision({ ...declined, adverse_action_reasons: ['x'.repeat(501)] })).toBe(false);
    expect(decision({ ...declined, adverse_action_reasons: Array(11).fill('x') })).toBe(false);
  });
  it('limits conditions to 50, term_months and apr to their ranges', () => {
    expect(decision({ conditions: Array.from({ length: 50 }, () => 'x') })).toBe(true);
    expect(decision({ conditions: Array.from({ length: 51 }, () => 'x') })).toBe(false);
    expect(decision({ conditions: ['x'.repeat(501)] })).toBe(false);
    expect(decision({ term_months: 0 })).toBe(false);
    expect(decision({ term_months: 120 })).toBe(true);
    expect(decision({ term_months: 121 })).toBe(false);
    expect(decision({ apr_basis_points: -1 })).toBe(false);
    expect(decision({ apr_basis_points: 10000 })).toBe(true);
    expect(decision({ apr_basis_points: 10001 })).toBe(false);
  });
});

describe('credit score (FCRA 615 notice data)', () => {
  const extra = { ...declined, credit_score: 580, credit_bureau: 'experian' };
  it('carries score, bureau and notice date', () => {
    expect(decision({ ...extra, adverse_action_notice_sent_at: T })).toBe(true);
    expect(decision({ ...extra, credit_bureau: 'acme' })).toBe(false);
    expect(decision({ ...extra, adverse_action_notice_sent_at: 'yesterday' })).toBe(false);
  });
  it('accepts scores from 250 to 900 and no others', () => {
    for (const [score, good] of [
      [249, false],
      [250, true],
      [850, true],
      [900, true],
      [901, false],
      [580.5, false],
    ] as const) {
      expect(decision({ ...extra, credit_score: score }), String(score)).toBe(good);
    }
  });
  it('checks the score against its range, which comes as a pair', () => {
    const range = (min: number, max: number) => ({ score_range_min: min, score_range_max: max });
    expect(decision({ ...extra, ...range(300, 850) })).toBe(true);
    expect(decision({ ...extra, ...range(250, 900), credit_score: 250 })).toBe(true);
    expect(decision({ ...extra, ...range(300, 850), credit_score: 250 })).toBe(false);
    expect(decision({ ...extra, ...range(300, 850), credit_score: 900 })).toBe(false);
    expect(decision({ ...extra, ...range(850, 300) })).toBe(false);
    expect(decision({ ...extra, score_range_min: 300 })).toBe(false);
    expect(decision({ ...extra, score_range_max: 850 })).toBe(false);
    expect(decision({ ...range(300, 850), ...declined })).toBe(false);
    expect(decision({ ...extra, ...range(100, 850) })).toBe(false);
  });
  it('carries the score date and at most 5 key factors', () => {
    expect(decision({ ...extra, score_date: '2026-10-12' })).toBe(true);
    expect(decision({ ...extra, score_date: '10/12/2026' })).toBe(false);
    expect(decision({ ...extra, key_factors: Array(5).fill('Too many inquiries') })).toBe(true);
    expect(decision({ ...extra, key_factors: Array(6).fill('Too many inquiries') })).toBe(false);
    expect(decision({ ...extra, key_factors: [''] })).toBe(false);
  });
});

describe('lender decision sensitive fields', () => {
  it('marks the consumer-report data, in a frozen list', () => {
    expect(LENDER_DECISION_SENSITIVE_FIELDS).toEqual([
      'adverse_action_reasons',
      'credit_bureau',
      'credit_score',
      'key_factors',
      'score_date',
      'score_range_max',
      'score_range_min',
    ]);
    expect(Object.isFrozen(LENDER_DECISION_SENSITIVE_FIELDS)).toBe(true);
  });
});
