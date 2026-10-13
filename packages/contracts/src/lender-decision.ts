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
  sensitive,
  sensitiveFields,
} from './common.js';

/** A credit score on any model in use (FICO Auto 250-900, others 300-850). */
const SCORE = z.number().int().min(250).max(900);

export const LenderDecisionStatusSchema = z.enum([
  'pending',
  'approved',
  'conditional',
  'countered',
  'declined',
  'expired',
]);

/**
 * One lender's answer to one credit request. `request_id` ties the callback to the request we sent.
 * `provider_message_id` is the lender's own message id (printable ASCII, 1-200 characters, required). The dedupe key
 * is `dealer_id` + `request_id` + `provider_message_id`; `services/callbacks` uses it to handle a repeated callback
 * once. Duplicate and out-of-order handling lives there, not here.
 *
 * Consumer-report data (GLBA/FCRA) is marked `sensitive()`: credit score, score range, score date, key factors, bureau
 * and adverse-action reasons. Amount, APR and payment are not marked (founders and security may decide to).
 */
export const LenderDecisionSchema = z
  .strictObject({
    ...recordBase,
    deal_id: IdSchema,
    credit_app_id: IdSchema,
    request_id: IdSchema,
    provider_message_id: z
      .string()
      .regex(/^[\x21-\x7E]{1,200}$/, 'printable ASCII, 1-200, no spaces'),
    /** Lender identifier, for example a RouteOne or Dealertrack lender code. */
    lender: SafeTextSchema.min(1).max(100),
    status: LenderDecisionStatusSchema,
    approved_amount_cents: CentsNonNegativeSchema.optional(),
    apr_basis_points: BasisPointsSchema.optional(),
    term_months: TermMonthsSchema.optional(),
    monthly_payment_cents: CentsNonNegativeSchema.optional(),
    conditions: z.array(SafeTextSchema.max(500)).max(50).optional(),
    /** Reasons for a decline (Reg B adverse action). Required when declined. */
    adverse_action_reasons: sensitive(z.array(SafeTextSchema.min(1).max(500)).max(10)).optional(),
    /** Credit score used (FCRA risk-based pricing and adverse-action disclosure). FICO Auto Scores run 250-900. */
    credit_score: sensitive(SCORE).optional(),
    /** Lowest and highest possible score of the model used (FCRA 615 notice). Give both or neither. */
    score_range_min: sensitive(SCORE).optional(),
    score_range_max: sensitive(SCORE).optional(),
    /** Date the score was created (FCRA 615 notice). */
    score_date: sensitive(IsoDateSchema).optional(),
    /** Key factors that hurt the score, at most 5 (FCRA 615 notice). */
    key_factors: sensitive(z.array(SafeTextSchema.min(1).max(500)).max(5)).optional(),
    credit_bureau: sensitive(z.enum(['equifax', 'experian', 'transunion', 'other'])).optional(),
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
    const { credit_score: score, score_range_min: low, score_range_max: high } = d;
    if ((low === undefined) !== (high === undefined)) {
      ctx.addIssue({
        code: 'custom',
        message: 'score_range_min and score_range_max go together',
        path: ['score_range_min'],
      });
    }
    if (low !== undefined && high !== undefined && low > high) {
      ctx.addIssue({
        code: 'custom',
        message: 'score_range_min must not be above score_range_max',
        path: ['score_range_min'],
      });
    }
    if (
      score !== undefined &&
      ((low !== undefined && score < low) || (high !== undefined && score > high))
    ) {
      ctx.addIssue({
        code: 'custom',
        message: 'credit_score is outside its score range',
        path: ['credit_score'],
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

/** Names of the sensitive (consumer-report) LenderDecision fields, derived from the schema once and frozen. */
export const LENDER_DECISION_SENSITIVE_FIELDS: readonly string[] = Object.freeze(
  sensitiveFields(LenderDecisionSchema),
);
