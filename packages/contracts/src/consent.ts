import { z } from 'zod';
import { IdSchema, IsoDateTimeSchema, recordBase } from './common.js';

/** `all` is a revoke-all opt-out (47 CFR 64.1200(a)(10)) and is valid only on a revoked record. */
export const ConsentChannelSchema = z.enum(['sms', 'voice_ai', 'email', 'messenger', 'all']);
export const ConsentStatusSchema = z.enum(['granted', 'revoked']);
export const ConsentPurposeSchema = z.enum(['marketing', 'informational']);

/** How and where the consent was captured. */
export const ConsentCaptureContextSchema = z.strictObject({
  method: z.enum([
    'web_form',
    'text_reply',
    'voice_recording',
    'email_reply',
    'paper',
    'in_person',
    'api',
  ]),
  ip_address: z.union([z.ipv4(), z.ipv6()]).optional(),
  user_agent: z.string().max(500).optional(),
  /** Page where the consent box was shown. */
  page_url: z
    .url({ protocol: /^https$/, hostname: z.regexes.domain })
    .max(2048)
    .optional(),
});

const RETENTION_YEARS = 5;

/**
 * Written consent (or its withdrawal) for one channel. Revoked records are kept (do-not-call: 5 years).
 * `address` is the exact phone number, email or Messenger PSID consented, so the Reassigned Numbers Database can be
 * checked. A consent that arrives before the lead is matched to a customer carries only `lead_id`.
 */
export const ConsentSchema = z
  .strictObject({
    ...recordBase,
    customer_id: IdSchema.optional(),
    lead_id: IdSchema.optional(),
    channel: ConsentChannelSchema,
    status: ConsentStatusSchema,
    purpose: ConsentPurposeSchema,
    /** Phone (E.164), email or Messenger PSID this record covers. */
    address: z.string().min(1).max(254),
    /** Where and how it was given or revoked, for example `web_form`, `stop_keyword`. */
    source: z.string().min(1).max(100),
    capture_context: ConsentCaptureContextSchema,
    /** Rep who captured it. Absent when the customer did it themselves (web form, STOP keyword). */
    captured_by_user_id: IdSchema.optional(),
    /** Exact wording shown or received. Required when consent is granted. */
    evidence_text: z.string().max(2000).optional(),
    recorded_at: IsoDateTimeSchema,
    /** Keep the record at least until this time (at least 5 years after `recorded_at`). */
    retain_until: IsoDateTimeSchema,
  })
  .superRefine((c, ctx) => {
    if (c.customer_id === undefined && c.lead_id === undefined) {
      ctx.addIssue({
        code: 'custom',
        message: 'customer_id or lead_id is required',
        path: ['customer_id'],
      });
    }
    if (c.status === 'granted' && (c.evidence_text === undefined || c.evidence_text.length === 0)) {
      ctx.addIssue({
        code: 'custom',
        message: 'evidence_text is required when granted',
        path: ['evidence_text'],
      });
    }
    if (c.channel === 'all' && c.status !== 'revoked') {
      ctx.addIssue({
        code: 'custom',
        message: 'channel all is only for revoked records',
        path: ['channel'],
      });
    }
    const earliest = new Date(c.recorded_at);
    earliest.setUTCFullYear(earliest.getUTCFullYear() + RETENTION_YEARS);
    if (new Date(c.retain_until).getTime() < earliest.getTime()) {
      ctx.addIssue({
        code: 'custom',
        message: 'retain_until must be at least 5 years after recorded_at',
        path: ['retain_until'],
      });
    }
  });
export type Consent = z.infer<typeof ConsentSchema>;
