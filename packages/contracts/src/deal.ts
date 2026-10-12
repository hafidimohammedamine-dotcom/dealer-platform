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

/**
 * `cash`: no financing, so no Reg Z fields. `retail_installment`: Reg Z disclosures required once contracted.
 * `lease`: Reg M (12 CFR 1013.4) fields do not exist yet, so a lease can be quoted and desked but not contracted.
 */
export const DealTypeSchema = z.enum(['cash', 'retail_installment', 'lease']);

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

/** Form 8300: cash over this many cents needs the report flag. */
const FORM_8300_THRESHOLD_CENTS = 1_000_000;

/** Form 8300 (cash over $10,000) report flag: `required` is always true when present. */
export const Form8300Schema = z.strictObject({
  required: z.literal(true),
  filed_at: IsoDateTimeSchema.optional(),
});

/** Reg Z (TILA) disclosure fields that must be present on a retail installment deal once it is contracted. */
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
    /** Second buyer (a Customer). Needs identity and OFAC checks once contracted. */
    co_buyer_customer_id: IdSchema.optional(),
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
    co_buyer_identity_verification: IdentityVerificationSchema.optional(),
    co_buyer_ofac_screening: OfacScreeningSchema.optional(),
    /** Cash received. Over 1,000,000 cents (Form 8300) `form_8300` is required. */
    cash_received_cents: CentsNonNegativeSchema.optional(),
    form_8300: Form8300Schema.optional(),
  })
  .superRefine((deal, ctx) => {
    const need = (field: keyof typeof deal, message: string) => {
      ctx.addIssue({ code: 'custom', message, path: [field] });
    };
    if (
      (deal.cash_received_cents ?? 0) > FORM_8300_THRESHOLD_CENTS &&
      deal.form_8300 === undefined
    ) {
      need('form_8300', 'form_8300 is required when cash received is over 1,000,000 cents');
    }
    const hasCoBuyer = deal.co_buyer_customer_id !== undefined;
    if (
      !hasCoBuyer &&
      (deal.co_buyer_identity_verification !== undefined ||
        deal.co_buyer_ofac_screening !== undefined)
    ) {
      need('co_buyer_customer_id', 'co-buyer checks need co_buyer_customer_id');
    }
    if (deal.status !== 'contracted' && deal.status !== 'funded') {
      return;
    }
    if (deal.deal_type === 'lease') {
      need('deal_type', 'a lease cannot be contracted until the Reg M fields exist');
    }
    const required =
      deal.deal_type === 'retail_installment'
        ? ([...REG_Z_FIELDS, ...TAX_FIELDS, 'identity_verification'] as const)
        : ([...TAX_FIELDS, 'identity_verification'] as const);
    for (const field of required) {
      if (deal[field] === undefined) {
        need(field, `${field} is required once contracted`);
      }
    }
    if (deal.ofac_screening?.result !== 'clear') {
      need('ofac_screening', 'ofac_screening must be clear once contracted');
    }
    if (hasCoBuyer) {
      if (deal.co_buyer_identity_verification === undefined) {
        need(
          'co_buyer_identity_verification',
          'co_buyer_identity_verification is required once contracted',
        );
      }
      if (deal.co_buyer_ofac_screening?.result !== 'clear') {
        need('co_buyer_ofac_screening', 'co_buyer_ofac_screening must be clear once contracted');
      }
    }
  });
export type Deal = z.infer<typeof DealSchema>;
