import { z } from 'zod';
import {
  AprBasisPointsSchema,
  CentsNonNegativeSchema,
  IdSchema,
  IsoDateSchema,
  IsoDateTimeSchema,
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

export const OtherFeeSchema = z.strictObject({
  description: z.string().min(1).max(200),
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

/** Reg Z (TILA) disclosure fields that must be present once a deal is contracted. */
const REG_Z_FIELDS = [
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
    tax_rate_basis_points: AprBasisPointsSchema.optional(),
    /** For example `Butler County, OH`. */
    tax_jurisdiction: z.string().min(1).max(100).optional(),
    taxable_amount_cents: CentsNonNegativeSchema.optional(),
    /** Amount to finance. May not be negative. */
    amount_financed_cents: CentsNonNegativeSchema,
    term_months: TermMonthsSchema.optional(),
    apr_basis_points: AprBasisPointsSchema.optional(),
    finance_charge_cents: CentsNonNegativeSchema.optional(),
    total_of_payments_cents: CentsNonNegativeSchema.optional(),
    total_sale_price_cents: CentsNonNegativeSchema.optional(),
    monthly_payment_cents: CentsNonNegativeSchema.optional(),
    first_payment_date: IsoDateSchema.optional(),
    identity_verification: IdentityVerificationSchema.optional(),
    ofac_screening: OfacScreeningSchema.optional(),
    /** Cash received, for Form 8300 reporting. */
    cash_received_cents: CentsNonNegativeSchema.optional(),
  })
  .superRefine((deal, ctx) => {
    if (deal.status !== 'contracted' && deal.status !== 'funded') {
      return;
    }
    for (const field of [...REG_Z_FIELDS, ...TAX_FIELDS, 'identity_verification'] as const) {
      if (deal[field] === undefined) {
        ctx.addIssue({
          code: 'custom',
          message: `${field} is required once contracted`,
          path: [field],
        });
      }
    }
    if (deal.ofac_screening?.result !== 'clear') {
      ctx.addIssue({
        code: 'custom',
        message: 'ofac_screening must be clear once contracted',
        path: ['ofac_screening'],
      });
    }
  });
export type Deal = z.infer<typeof DealSchema>;
