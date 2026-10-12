import { z } from 'zod';
import { cents, centsNonNegative, id, recordBase } from './common.js';

export const DealStatusSchema = z.enum([
  'quote',
  'desking',
  'submitted',
  'approved',
  'contracted',
  'funded',
  'dead',
]);

export const DealSchema = z.strictObject({
  ...recordBase,
  customer_id: id,
  vehicle_id: id,
  lead_id: id.optional(),
  salesperson_user_id: id.optional(),
  status: DealStatusSchema,
  selling_price_cents: centsNonNegative,
  trade_allowance_cents: centsNonNegative.optional(),
  trade_payoff_cents: centsNonNegative.optional(),
  down_payment_cents: centsNonNegative,
  fees_cents: centsNonNegative,
  taxes_cents: centsNonNegative,
  /** Amount to finance. May not be negative. */
  amount_financed_cents: centsNonNegative,
  /** Positive or negative equity on the trade. */
  trade_equity_cents: cents.optional(),
  term_months: z.number().int().positive().max(120).optional(),
});
export type Deal = z.infer<typeof DealSchema>;
