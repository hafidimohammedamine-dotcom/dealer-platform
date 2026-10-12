import { z } from 'zod';
import {
  CentsNonNegativeSchema,
  IdSchema,
  IsoDateSchema,
  IsoDateTimeSchema,
  recordBase,
  sensitive,
  sensitiveFields,
} from './common.js';

/** Customer's permission to pull credit (FCRA permissible purpose). */
export const CreditPullAuthorizationSchema = z.strictObject({
  /** Exact wording the customer agreed to. */
  evidence_text: z.string().min(1).max(2000),
  authorized_at: IsoDateTimeSchema,
  method: z.enum(['written', 'electronic', 'verbal_recorded']),
});

/** Evidence that both applicants intended to apply for joint credit (Reg B, 12 CFR 1002.7(d)(1)). */
export const JointIntentEvidenceSchema = z.strictObject({
  evidence_text: z.string().min(1).max(2000),
  recorded_at: IsoDateTimeSchema,
});

/**
 * Credit application. Fields wrapped in `sensitive()` must be encrypted at rest, masked on screen, never logged and
 * never sent by text or email. Fake data only: SSNs in the 900-xx-xxxx range.
 * When `has_coapplicant` is true the co-applicant is a Customer (`coapplicant_customer_id`) and
 * `joint_intent_evidence` is required; when false both must be absent.
 */
export const CreditAppSchema = z
  .strictObject({
    ...recordBase,
    deal_id: IdSchema,
    customer_id: IdSchema,
    applicant_name: z.string().min(1).max(200),
    /** Social Security number, `NNN-NN-NNNN`. */
    ssn: sensitive(z.string().regex(/^\d{3}-\d{2}-\d{4}$/)),
    date_of_birth: sensitive(IsoDateSchema),
    monthly_income_cents: sensitive(CentsNonNegativeSchema),
    bank_account_number: sensitive(z.string().regex(/^\d{4,17}$/)),
    bank_routing_number: sensitive(z.string().regex(/^\d{9}$/)),
    employer_name: z.string().max(200).optional(),
    credit_pull_authorization: CreditPullAuthorizationSchema,
    has_coapplicant: z.boolean(),
    coapplicant_customer_id: IdSchema.optional(),
    joint_intent_evidence: JointIntentEvidenceSchema.optional(),
    submitted_at: IsoDateTimeSchema.optional(),
  })
  .superRefine((app, ctx) => {
    const present = app.coapplicant_customer_id !== undefined;
    const evidence = app.joint_intent_evidence !== undefined;
    if (app.has_coapplicant) {
      if (!present) {
        ctx.addIssue({
          code: 'custom',
          message: 'coapplicant_customer_id is required',
          path: ['coapplicant_customer_id'],
        });
      }
      if (!evidence) {
        ctx.addIssue({
          code: 'custom',
          message: 'joint_intent_evidence is required',
          path: ['joint_intent_evidence'],
        });
      }
    } else if (present || evidence) {
      ctx.addIssue({
        code: 'custom',
        message: 'co-applicant fields need has_coapplicant',
        path: ['has_coapplicant'],
      });
    }
  });
export type CreditApp = z.infer<typeof CreditAppSchema>;

/** Names of the sensitive CreditApp fields, derived from the schema once and frozen. */
export const CREDIT_APP_SENSITIVE_FIELDS: readonly string[] = Object.freeze(
  sensitiveFields(CreditAppSchema),
);
