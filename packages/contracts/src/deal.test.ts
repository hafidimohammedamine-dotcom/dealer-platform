import { describe, expect, it } from 'vitest';
import { DealSchema, DealStatusSchema } from './index.js';
import { T, ok, samples, without } from './samples.test.js';

const contracted = {
  status: 'contracted',
  identity_verification: { method: 'drivers_license', verified_at: T, verified_by_user_id: 'u1' },
  ofac_screening: { result: 'clear', screened_at: T },
};
const REG_Z = [
  'term_months',
  'apr_basis_points',
  'finance_charge_cents',
  'total_of_payments_cents',
  'total_sale_price_cents',
  'monthly_payment_cents',
  'first_payment_date',
];
const TAX = ['tax_rate_basis_points', 'tax_jurisdiction', 'taxable_amount_cents'];

/** The sample as a contracted deal with `keys` removed. */
function contractedWithout(...keys: string[]): Record<string, unknown> {
  const rest: Record<string, unknown> = { ...samples.deal.value, ...contracted };
  for (const key of keys) {
    delete rest[key];
  }
  return rest;
}

describe('deal fees and rates', () => {
  it('has no lump-sum fees_cents or stored trade equity', () => {
    expect(ok('deal', { fees_cents: 50000 })).toBe(false);
    expect(ok('deal', { trade_equity_cents: 1 })).toBe(false);
  });
  it('splits fees into doc, title, registration and other', () => {
    for (const key of ['doc_fee_cents', 'title_fee_cents', 'registration_fee_cents']) {
      expect(DealSchema.safeParse(without('deal', key)).success, key).toBe(false);
    }
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: 9900 }] })).toBe(true);
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: 99.5 }] })).toBe(false);
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: -1 }] })).toBe(false);
    expect(ok('deal', { other_fees: [{ description: '', amount_cents: 1 }] })).toBe(false);
  });
  it('records tax rate, jurisdiction and base (Butler County at 650)', () => {
    expect(ok('deal', { tax_rate_basis_points: 650, tax_jurisdiction: 'Butler County, OH' })).toBe(
      true,
    );
    expect(ok('deal', { tax_rate_basis_points: 650.5 })).toBe(false);
    expect(ok('deal', { tax_rate_basis_points: 10001 })).toBe(false);
    expect(ok('deal', { tax_jurisdiction: '' })).toBe(false);
    expect(ok('deal', { tax_jurisdiction: 'x'.repeat(101) })).toBe(false);
  });
  it('limits term_months to 1-120 and apr to 0-10000 basis points', () => {
    for (const [term, good] of [
      [0, false],
      [1, true],
      [120, true],
      [121, false],
    ] as const) {
      expect(ok('deal', { term_months: term }), String(term)).toBe(good);
    }
    for (const [apr, good] of [
      [-1, false],
      [0, true],
      [10000, true],
      [10001, false],
    ] as const) {
      expect(ok('deal', { apr_basis_points: apr }), String(apr)).toBe(good);
    }
  });
  it('pins the status names and rejects an unknown one', () => {
    expect(DealStatusSchema.options).toContain('contracted');
    expect(ok('deal', { status: 'sold' })).toBe(false);
  });
});

describe('deal type', () => {
  it('is required and one of cash, retail_installment or lease', () => {
    expect(DealSchema.safeParse(without('deal', 'deal_type')).success).toBe(false);
    expect(ok('deal', { deal_type: 'barter' })).toBe(false);
    for (const deal_type of ['cash', 'retail_installment', 'lease']) {
      expect(ok('deal', { deal_type }), deal_type).toBe(true);
    }
  });
  it('requires the Reg Z fields for a contracted retail installment deal', () => {
    expect(ok('deal', contracted)).toBe(true);
    expect(ok('deal', { ...contracted, status: 'funded' })).toBe(true);
    for (const key of REG_Z) {
      const rest = contractedWithout(key);
      expect(DealSchema.safeParse(rest).success, key).toBe(false);
      expect(DealSchema.safeParse({ ...rest, status: 'quote' }).success, `quote ${key}`).toBe(true);
    }
  });
  it('does not require Reg Z fields on a contracted cash deal, but still the tax fields', () => {
    const cash = { deal_type: 'cash' };
    expect(DealSchema.safeParse({ ...contractedWithout(...REG_Z), ...cash }).success).toBe(true);
    for (const key of TAX) {
      expect(DealSchema.safeParse({ ...contractedWithout(...REG_Z, key), ...cash }).success).toBe(
        false,
      );
    }
  });
  it('rejects a contracted or funded lease (no Reg M fields yet) but allows a lease quote', () => {
    expect(ok('deal', { ...contracted, deal_type: 'lease' })).toBe(false);
    expect(ok('deal', { ...contracted, status: 'funded', deal_type: 'lease' })).toBe(false);
    expect(ok('deal', { deal_type: 'lease', status: 'desking' })).toBe(true);
  });
  it('requires the tax fields once contracted', () => {
    for (const key of TAX) {
      const rest = contractedWithout(key);
      expect(DealSchema.safeParse(rest).success, key).toBe(false);
      expect(DealSchema.safeParse({ ...rest, status: 'quote' }).success, `quote ${key}`).toBe(true);
    }
  });
});

describe('deal identity, OFAC and co-buyer', () => {
  const coBuyer = {
    co_buyer_customer_id: 'c2',
    co_buyer_identity_verification: {
      method: 'state_id',
      verified_at: T,
      verified_by_user_id: 'u1',
    },
    co_buyer_ofac_screening: { result: 'clear', screened_at: T },
  };
  it('requires the identity check and a clear OFAC screening once contracted', () => {
    expect(ok('deal', { ...contracted, identity_verification: undefined })).toBe(false);
    expect(ok('deal', { ...contracted, ofac_screening: undefined })).toBe(false);
    for (const result of ['potential_match', 'confirmed_match']) {
      expect(
        ok('deal', { ...contracted, ofac_screening: { result, screened_at: T } }),
        result,
      ).toBe(false);
    }
    expect(ok('deal', { ofac_screening: { result: 'potential_match', screened_at: T } })).toBe(
      true,
    );
  });
  it('accepts a co-buyer with both checks and a clear result when contracted', () => {
    expect(ok('deal', { ...contracted, ...coBuyer })).toBe(true);
    expect(ok('deal', { ...contracted, status: 'funded', ...coBuyer })).toBe(true);
    expect(ok('deal', { deal_type: 'cash', ...coBuyer })).toBe(true);
  });
  it('requires the co-buyer identity check and OFAC screening once contracted', () => {
    const noId = { ...coBuyer, co_buyer_identity_verification: undefined };
    const noOfac = { ...coBuyer, co_buyer_ofac_screening: undefined };
    expect(ok('deal', { ...contracted, ...noId })).toBe(false);
    expect(ok('deal', { ...contracted, ...noOfac })).toBe(false);
    expect(ok('deal', { ...contracted, ...noId, status: 'quote' })).toBe(true);
    expect(ok('deal', { ...contracted, ...noOfac, status: 'quote' })).toBe(true);
  });
  it('requires the co-buyer OFAC result to be clear', () => {
    for (const result of ['potential_match', 'confirmed_match']) {
      const hit = { ...coBuyer, co_buyer_ofac_screening: { result, screened_at: T } };
      expect(ok('deal', { ...contracted, ...hit }), result).toBe(false);
      expect(ok('deal', { ...hit, status: 'quote' }), `quote ${result}`).toBe(true);
    }
  });
  it('rejects co-buyer checks without a co-buyer id', () => {
    expect(ok('deal', { ...coBuyer, co_buyer_customer_id: undefined })).toBe(false);
    expect(ok('deal', { co_buyer_ofac_screening: coBuyer.co_buyer_ofac_screening })).toBe(false);
    expect(ok('deal', { co_buyer_customer_id: '../c2' })).toBe(false);
  });
});

describe('deal cash and Form 8300', () => {
  const form = { required: true, filed_at: T };
  it('does not require form_8300 at 1,000,000 cents but requires it at 1,000,001', () => {
    expect(ok('deal', { cash_received_cents: 1000000 })).toBe(true);
    expect(ok('deal', { cash_received_cents: 1000001 })).toBe(false);
    expect(ok('deal', { cash_received_cents: 1000001, form_8300: form })).toBe(true);
    expect(ok('deal', { cash_received_cents: 1000001, form_8300: { required: true } })).toBe(true);
  });
  it('checks the form_8300 shape and rejects fractional cash', () => {
    expect(ok('deal', { form_8300: { required: false } })).toBe(false);
    expect(ok('deal', { form_8300: { required: true, surprise: 1 } })).toBe(false);
    expect(ok('deal', { form_8300: { required: true, filed_at: 'x' } })).toBe(false);
    expect(ok('deal', { cash_received_cents: 1500000.5, form_8300: form })).toBe(false);
  });
});
