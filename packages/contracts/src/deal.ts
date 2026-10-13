import { z } from 'zod';
import {
  BasisPointsSchema,
  CentsNonNegativeSchema,
  IdSchema,
  IsoDateSchema,
  IsoDateTimeSchema,
  SafeTextSchema,
  TermMonthsSchema,
  recordBase,
} from './common.js';

export const DealStatusSchema = z.enum([
  'quote',
  'desking',
  'submitted',
  'approved',
  'contracted',
  'funded',
  'dead',
]);

/** How the deal is paid. Reg Z fields apply to `retail_installment` only; a contracted `lease` is not yet supported. */
export const DealTypeSchema = z.enum(['cash', 'retail_installment', 'lease']);

/** Cash above this many cents (more than $10,000) needs IRS Form 8300. */
const FORM_8300_THRESHOLD_CENTS = 1_000_000;

/** Form 8300 flag: the cash report is required, and when it was filed. */
export const Form8300Schema = z.strictObject({
  required: z.literal(true),
  filed_at: IsoDateTimeSchema.optional(),
});

export const OtherFeeSchema = z.strictObject({
  description: SafeTextSchema.min(1).max(200),
  amount_cents: CentsNonNegativeSchema,
});

/** Customer identity check (ID type and who checked it), needed before a deal is contracted. */
export const IdentityVerificationSchema = z.strictObject({
  method: z.enum(['drivers_license', 'state_id', 'passport', 'other']),
  verified_at: IsoDateTimeSchema,
  verified_by_user_id: IdSchema,
});

/** OFAC screening result. Only `clear` allows a contracted deal. */
export const OfacScreeningSchema = z.strictObject({
  result: z.enum(['clear', 'potential_match', 'confirmed_match']),
  screened_at: IsoDateTimeSchema,
});

/** Reg Z (TILA) disclosure fields that must be present once a retail installment deal is contracted. */
const REG_Z_FIELDS = [
  'term_months',
  'apr_basis_points',
  'finance_charge_cents',
  'total_of_payments_cents',
  'total_sale_price_cents',
  'monthly_payment_cents',
  'first_payment_date',
] as const;

/** Tax fields that must be present once a deal is contracted. */
const TAX_FIELDS = ['tax_rate_basis_points', 'tax_jurisdiction', 'taxable_amount_cents'] as const;

export const DealSchema = z
  .strictObject({
    ...recordBase,
    customer_id: IdSchema,
    vehicle_id: IdSchema,
    lead_id: IdSchema.optional(),
    salesperson_user_id: IdSchema.optional(),
    deal_type: DealTypeSchema,
    status: DealStatusSchema,
    selling_price_cents: CentsNonNegativeSchema,
    trade_allowance_cents: CentsNonNegativeSchema.optional(),
    trade_payoff_cents: CentsNonNegativeSchema.optional(),
    down_payment_cents: CentsNonNegativeSchema,
    /** Dealer documentation fee. Any legal cap is checked by the desking service, not stored here. */
    doc_fee_cents: CentsNonNegativeSchema,
    title_fee_cents: CentsNonNegativeSchema,
    registration_fee_cents: CentsNonNegativeSchema,
    other_fees: z.array(OtherFeeSchema).max(50).optional(),
    taxes_cents: CentsNonNegativeSchema,
    /** Tax rate in basis points (650 = 6.50%), set by the buyer's jurisdiction. */
    tax_rate_basis_points: BasisPointsSchema.optional(),
    /** For example `Butler County, OH`. */
    tax_jurisdiction: SafeTextSchema.min(1).max(100).optional(),
    taxable_amount_cents: CentsNonNegativeSchema.optional(),
    /** Amount to finance. May not be negative. */
    amount_financed_cents: CentsNonNegativeSchema,
    term_months: TermMonthsSchema.optional(),
    apr_basis_points: BasisPointsSchema.optional(),
    finance_charge_cents: CentsNonNegativeSchema.optional(),
    total_of_payments_cents: CentsNonNegativeSchema.optional(),
    total_sale_price_cents: CentsNonNegativeSchema.optional(),
    monthly_payment_cents: CentsNonNegativeSchema.optional(),
    first_payment_date: IsoDateSchema.optional(),
    identity_verification: IdentityVerificationSchema.optional(),
    ofac_screening: OfacScreeningSchema.optional(),
    /** Second buyer (a Customer). Identity check and OFAC screen are required for them too once contracted. */
    co_buyer_customer_id: IdSchema.optional(),
    co_buyer_identity_verification: IdentityVerificationSchema.optional(),
    co_buyer_ofac_screening: OfacScreeningSchema.optional(),
    /** Cash received, for Form 8300 reporting. */
    cash_received_cents: CentsNonNegativeSchema.optional(),
    /** Required when `cash_received_cents` is above 1,000,000. */
    form_8300: Form8300Schema.optional(),
  })
  .superRefine((deal, ctx) => {
    const fail = (message: string, field: string): void => {
      ctx.addIssue({ code: 'custom', message, path: [field] });
    };
    if ((deal.cash_received_cents ?? 0) > FORM_8300_THRESHOLD_CENTS && !deal.form_8300) {
      fail('form_8300 is required when cash received is above 1,000,000 cents', 'form_8300');
    }
    const hasCoBuyer = deal.co_buyer_customer_id !== undefined;
    if (
      !hasCoBuyer &&
      (deal.co_buyer_identity_verification !== undefined ||
        deal.co_buyer_ofac_screening !== undefined)
    ) {
      fail('co-buyer checks need co_buyer_customer_id', 'co_buyer_customer_id');
    }
    if (deal.status !== 'contracted' && deal.status !== 'funded') {
      return;
    }
    if (deal.deal_type === 'lease') {
      fail('a lease cannot be contracted yet (Reg M fields are not in the contract)', 'deal_type');
    }
    const required: (keyof typeof deal)[] = [...TAX_FIELDS, 'identity_verification'];
    if (deal.deal_type === 'retail_installment') {
      required.push(...REG_Z_FIELDS);
    }
    if (hasCoBuyer) {
      required.push('co_buyer_identity_verification');
    }
    for (const field of required) {
      if (deal[field] === undefined) {
        fail(`${field} is required once contracted`, field);
      }
    }
    if (deal.ofac_screening?.result !== 'clear') {
      fail('ofac_screening must be clear once contracted', 'ofac_screening');
    }
    if (hasCoBuyer && deal.co_buyer_ofac_screening?.result !== 'clear') {
      fail('co_buyer_ofac_screening must be clear once contracted', 'co_buyer_ofac_screening');
    }
  });
export type Deal = z.infer<typeof DealSchema>;
