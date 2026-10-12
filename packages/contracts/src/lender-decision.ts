import { z } from 'zod';
import {
  AprBasisPointsSchema,
  CentsNonNegativeSchema,
  IdSchema,
  IsoDateTimeSchema,
  TermMonthsSchema,
  recordBase,
} from './common.js';

export const LenderDecisionStatusSchema = z.enum([
  'pending',
  'approved',
  'conditional',
  'countered',
  'declined',
  'expired',
]);

/**
 * One lender's answer to one credit request. `request_id` ties the callback to the request we sent;
 * `provider_message_id` is the lender's own message id so a repeated callback is handled once. Duplicate and
 * out-of-order callback handling lives in `services/callbacks`, not here.
 */
export const LenderDecisionSchema = z
  .strictObject({
    ...recordBase,
    deal_id: IdSchema,
    credit_app_id: IdSchema,
    request_id: IdSchema,
    provider_message_id: z.string().min(1).max(200).optional(),
    /** Lender identifier, for example a RouteOne or Dealertrack lender code. */
    lender: z.string().min(1).max(100),
    status: LenderDecisionStatusSchema,
    approved_amount_cents: CentsNonNegativeSchema.optional(),
    apr_basis_points: AprBasisPointsSchema.optional(),
    term_months: TermMonthsSchema.optional(),
    monthly_payment_cents: CentsNonNegativeSchema.optional(),
    conditions: z.array(z.string().max(500)).max(50).optional(),
    /** Reasons for a decline (Reg B adverse action). Required when declined. */
    adverse_action_reasons: z.array(z.string().min(1).max(500)).max(10).optional(),
    /** Credit score used (FCRA risk-based pricing and adverse-action disclosure). */
    credit_score: z.number().int().min(300).max(850).optional(),
    credit_bureau: z.enum(['equifax', 'experian', 'transunion', 'other']).optional(),
    adverse_action_notice_sent_at: IsoDateTimeSchema.optional(),
    request_date: IsoDateTimeSchema.optional(),
    decided_at: IsoDateTimeSchema.optional(),
  })
  .superRefine((d, ctx) => {
    if (d.status === 'declined' && (d.adverse_action_reasons ?? []).length === 0) {
      ctx.addIssue({
        code: 'custom',
        message: 'adverse_action_reasons is required when declined',
        path: ['adverse_action_reasons'],
      });
    }
    if (
      d.request_date !== undefined &&
      d.decided_at !== undefined &&
      new Date(d.decided_at).getTime() < new Date(d.request_date).getTime()
    ) {
      ctx.addIssue({
        code: 'custom',
        message: 'decided_at must not be before request_date',
        path: ['decided_at'],
      });
    }
  });
export type LenderDecision = z.infer<typeof LenderDecisionSchema>;
