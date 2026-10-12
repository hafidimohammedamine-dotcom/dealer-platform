import { z } from 'zod';
import { centsNonNegative, id, isoDateTime, recordBase } from './common.js';

export const LenderDecisionStatusSchema = z.enum([
  'pending',
  'approved',
  'conditional',
  'countered',
  'declined',
]);

export const LenderDecisionSchema = z.strictObject({
  ...recordBase,
  deal_id: id,
  credit_app_id: id,
  /** Lender identifier, for example a RouteOne or Dealertrack lender code. */
  lender: z.string().min(1).max(100),
  status: LenderDecisionStatusSchema,
  approved_amount_cents: centsNonNegative.optional(),
  /** Annual percentage rate in basis points (650 = 6.50%), an integer so no floating point. */
  apr_basis_points: z.number().int().min(0).max(10000).optional(),
  term_months: z.number().int().positive().max(120).optional(),
  monthly_payment_cents: centsNonNegative.optional(),
  conditions: z.array(z.string().max(500)).max(50).optional(),
  decided_at: isoDateTime.optional(),
});
export type LenderDecision = z.infer<typeof LenderDecisionSchema>;
