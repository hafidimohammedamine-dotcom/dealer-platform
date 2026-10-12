import { describe, expect, it } from 'vitest';
import { DealSchema, DealStatusSchema } from './index.js';
import { ID, T, ok, samples, without } from './test-samples.js';

const contracted = {
  status: 'contracted',
  identity_verification: {
    method: 'drivers_license',
    verified_at: T,
    verified_by_user_id: ID.user,
  },
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

/** The sample deal with some keys removed and some fields set. */
function deal(remove: string[], patch: Record<string, unknown>) {
  const rest = without('deal', ...remove);
  return DealSchema.safeParse({ ...rest, ...patch }).success;
}

describe('deal fees and tax', () => {
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
    expect(ok('deal', { tax_jurisdiction: 'x'.repeat(100) })).toBe(true);
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
  it('knows the deal statuses', () => {
    expect(DealStatusSchema.options).toContain('contracted');
    expect(ok('deal', { status: 'maybe' })).toBe(false);
    expect(ok('deal', { status: 'dead' })).toBe(true);
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
  it('requires the Reg Z and tax fields once a retail installment deal is contracted', () => {
    for (const key of [...REG_Z, ...TAX]) {
      const patch = { ...contracted };
      expect(deal([key], patch), key).toBe(false);
      expect(deal([key], { ...patch, status: 'quote' }), `quote ${key}`).toBe(true);
      expect(deal([key], { ...patch, status: 'funded' }), `funded ${key}`).toBe(false);
    }
    expect(deal([], contracted)).toBe(true);
    expect(deal([], { ...contracted, status: 'funded' })).toBe(true);
  });
  it('lets a cash deal be contracted without Reg Z fields, but still needs tax and checks', () => {
    const cash = { ...contracted, deal_type: 'cash', amount_financed_cents: 0 };
    expect(deal(REG_Z, cash)).toBe(true);
    expect(deal([...REG_Z, ...TAX], cash)).toBe(false);
    expect(deal(REG_Z, { ...cash, identity_verification: undefined })).toBe(false);
    expect(
      deal(REG_Z, { ...cash, ofac_screening: { result: 'potential_match', screened_at: T } }),
    ).toBe(false);
  });
  it('lets a lease be quoted but not contracted until the Reg M fields exist', () => {
    expect(deal([], { deal_type: 'lease', status: 'desking' })).toBe(true);
    expect(deal([], { ...contracted, deal_type: 'lease' })).toBe(false);
    expect(deal([], { ...contracted, deal_type: 'lease', status: 'funded' })).toBe(false);
  });
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
});

describe('co-buyer', () => {
  const coBuyer = {
    co_buyer_customer_id: ID.customer2,
    co_buyer_identity_verification: { ...contracted.identity_verification },
    co_buyer_ofac_screening: { result: 'clear', screened_at: T },
  };
  it('needs identity and a clear OFAC result once contracted or funded', () => {
    expect(ok('deal', { ...contracted, ...coBuyer })).toBe(true);
    expect(ok('deal', { ...contracted, ...coBuyer, status: 'funded' })).toBe(true);
    for (const missing of ['co_buyer_identity_verification', 'co_buyer_ofac_screening']) {
      expect(ok('deal', { ...contracted, ...coBuyer, [missing]: undefined }), missing).toBe(false);
    }
    for (const result of ['potential_match', 'confirmed_match']) {
      const co_buyer_ofac_screening = { result, screened_at: T };
      expect(ok('deal', { ...contracted, ...coBuyer, co_buyer_ofac_screening }), result).toBe(
        false,
      );
    }
    expect(ok('deal', { ...contracted, co_buyer_customer_id: ID.customer2 })).toBe(false);
  });
  it('can be recorded on a quote without checks, and on a cash deal', () => {
    expect(ok('deal', { co_buyer_customer_id: ID.customer2 })).toBe(true);
    expect(deal(REG_Z, { ...contracted, ...coBuyer, deal_type: 'cash' })).toBe(true);
  });
  it('rejects co-buyer checks without a co-buyer', () => {
    expect(ok('deal', { co_buyer_ofac_screening: { result: 'clear', screened_at: T } })).toBe(
      false,
    );
    expect(
      ok('deal', { co_buyer_identity_verification: coBuyer.co_buyer_identity_verification }),
    ).toBe(false);
    expect(ok('deal', { co_buyer_customer_id: '../c2' })).toBe(false);
  });
});

describe('cash and Form 8300', () => {
  it('needs the form_8300 flag only above 1,000,000 cents', () => {
    expect(ok('deal', { cash_received_cents: 1000000 })).toBe(true);
    expect(ok('deal', { cash_received_cents: 1000001 })).toBe(false);
    expect(ok('deal', { cash_received_cents: 1000001, form_8300: { required: true } })).toBe(true);
    expect(
      ok('deal', { cash_received_cents: 1500000, form_8300: { required: true, filed_at: T } }),
    ).toBe(true);
    expect(ok('deal', { cash_received_cents: 1500000.5, form_8300: { required: true } })).toBe(
      false,
    );
  });
  it('accepts only a true required flag and a valid filed time', () => {
    expect(ok('deal', { form_8300: { required: false } })).toBe(false);
    expect(ok('deal', { form_8300: { required: true, filed_at: 'soon' } })).toBe(false);
    expect(ok('deal', { form_8300: { required: true, extra: 1 } })).toBe(false);
    expect(samples.deal.value.cash_received_cents).toBeLessThanOrEqual(1000000);
  });
});
