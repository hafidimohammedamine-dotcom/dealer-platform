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

export const LenderDecisionStatusSchema = z.enum([
  'pending',
  'approved',
  'conditional',
  'countered',
  'declined',
  'expired',
]);

/** Visible ASCII only, 1-200 characters: no spaces, control characters or Unicode in a lender message id. */
const ProviderMessageIdSchema = z.string().regex(/^[\x21-\x7E]{1,200}$/);

/**
 * One lender's answer to one credit request. `request_id` ties the callback to the request we sent;
 * `provider_message_id` is the lender's own message id. The dedupe key for a callback is `request_id` plus
 * `provider_message_id`, so `provider_message_id` is required on every status except `pending` (our own record,
 * made before any callback). Duplicate and out-of-order callback handling lives in `services/callbacks`, not here.
 *
 * Consumer-report data (score, range, date, key factors, bureau, adverse-action reasons: GLBA/FCRA) is marked
 * `sensitive()`. Amount, APR, term and payment are not marked: they are deal terms the dealer shows on screen.
 */
export const LenderDecisionSchema = z
  .strictObject({
    ...recordBase,
    deal_id: IdSchema,
    credit_app_id: IdSchema,
    request_id: IdSchema,
    provider_message_id: ProviderMessageIdSchema.optional(),
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
    credit_score: sensitive(z.number().int().min(250).max(900)).optional(),
    /** Lowest and highest score the model can give (FCRA 615 notice). Both or neither. */
    score_range_min: sensitive(z.number().int().min(250).max(900)).optional(),
    score_range_max: sensitive(z.number().int().min(250).max(900)).optional(),
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
    const fail = (message: string, path: string) => {
      ctx.addIssue({ code: 'custom', message, path: [path] });
    };
    if (d.status !== 'pending' && d.provider_message_id === undefined) {
      fail('provider_message_id is required unless pending', 'provider_message_id');
    }
    if (d.status === 'declined' && (d.adverse_action_reasons ?? []).length === 0) {
      fail('adverse_action_reasons is required when declined', 'adverse_action_reasons');
    }
    const { score_range_min: min, score_range_max: max, credit_score: score } = d;
    if ((min === undefined) !== (max === undefined)) {
      fail('score_range_min and score_range_max go together', 'score_range_min');
    } else if (min !== undefined && max !== undefined) {
      if (min > max) {
        fail('score_range_min must not be above score_range_max', 'score_range_min');
      }
      if (score === undefined) {
        fail('a score range needs credit_score', 'credit_score');
      } else if (score < min || score > max) {
        fail('credit_score must be inside its score range', 'credit_score');
      }
    }
    if (
      d.request_date !== undefined &&
      d.decided_at !== undefined &&
      new Date(d.decided_at).getTime() < new Date(d.request_date).getTime()
    ) {
      fail('decided_at must not be before request_date', 'decided_at');
    }
  });
export type LenderDecision = z.infer<typeof LenderDecisionSchema>;

/** Names of the sensitive LenderDecision fields, derived from the schema once and frozen. */
export const LENDER_DECISION_SENSITIVE_FIELDS: readonly string[] = Object.freeze(
  sensitiveFields(LenderDecisionSchema),
);
