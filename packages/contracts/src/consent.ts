import { z } from 'zod';
import {
  EmailSchema,
  EvidenceTextSchema,
  HttpsUrlSchema,
  IdSchema,
  IsoDateTimeSchema,
  PhoneE164Schema,
  SafeTextSchema,
  recordBase,
} from './common.js';

/** `all` is a revoke-all opt-out (47 CFR 64.1200(a)(10)) and is valid only on a revoked record. */
export const ConsentChannelSchema = z.enum(['sms', 'voice_ai', 'email', 'messenger', 'all']);
export const ConsentStatusSchema = z.enum(['granted', 'revoked']);
/**
 * `all` is valid only on a revoked record. A revocation counts as `all` unless the customer limited it to one purpose,
 * so a "stop texting me" never leaves one purpose still texting.
 */
export const ConsentPurposeSchema = z.enum(['marketing', 'informational', 'all']);

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
  user_agent: SafeTextSchema.max(500).optional(),
  /** Page where the consent box was shown. Untrusted, display-only. */
  page_url: HttpsUrlSchema.optional(),
});

const RETENTION_YEARS = 5;

/** Messenger page-scoped id: digits only. */
const PSID = /^\d{1,64}$/;

/**
 * True when `address` has the canonical form for `channel`, so an opt-out saved here is found by a lookup made with
 * the same canonical value: E.164 phone for `sms` and `voice_ai`, lowercased email for `email`, digits-only PSID for
 * `messenger`, and any one of those for `all`.
 */
function addressFitsChannel(
  channel: z.infer<typeof ConsentChannelSchema>,
  address: string,
): boolean {
  const phone = PhoneE164Schema.safeParse(address).success;
  const email = EmailSchema.safeParse(address).success && address === address.toLowerCase();
  const psid = PSID.test(address);
  switch (channel) {
    case 'sms':
    case 'voice_ai':
      return phone;
    case 'email':
      return email;
    case 'messenger':
      return psid;
    case 'all':
      return phone || email || psid;
  }
}

/**
 * Written consent (or its withdrawal) for one channel and purpose.
 *
 * `address` is the canonical phone number, email or Messenger PSID consented (see `addressFitsChannel`), so opt-out
 * lookups and the Reassigned Numbers Database check match. A consent that arrives before the lead is matched to a
 * customer carries only `lead_id`. Channel `all` is a revoke-all and covers every address of that person
 * (`customer_id` or `lead_id`), whatever its own `address` says.
 *
 * Retention: a granted record has no `retain_until` and must be kept while the consent is in use and until 5 years
 * after it is revoked or last used. A revoked record carries `retain_until`, at least 5 years after `recorded_at`
 * (do-not-call: 5 years). On Feb 29 the 5 years end on Mar 1 (the longer reading).
 */
export const ConsentSchema = z
  .strictObject({
    ...recordBase,
    customer_id: IdSchema.optional(),
    lead_id: IdSchema.optional(),
    channel: ConsentChannelSchema,
    status: ConsentStatusSchema,
    purpose: ConsentPurposeSchema,
    /** Phone (E.164), lowercased email or Messenger PSID this record covers. */
    address: z.string().min(1).max(254),
    /** Where and how it was given or revoked, for example `web_form`, `stop_keyword`. */
    source: SafeTextSchema.min(1).max(100),
    capture_context: ConsentCaptureContextSchema,
    /** Rep who captured it. Absent when the customer did it themselves (web form, STOP keyword). */
    captured_by_user_id: IdSchema.optional(),
    /** Exact wording shown or received. Required when consent is granted. */
    evidence_text: EvidenceTextSchema.optional(),
    recorded_at: IsoDateTimeSchema,
    /** Revoked records only: keep at least until this time (at least 5 years after `recorded_at`). */
    retain_until: IsoDateTimeSchema.optional(),
  })
  .superRefine((c, ctx) => {
    if (c.customer_id === undefined && c.lead_id === undefined) {
      ctx.addIssue({
        code: 'custom',
        message: 'customer_id or lead_id is required',
        path: ['customer_id'],
      });
    }
    if (c.status === 'granted' && c.evidence_text === undefined) {
      ctx.addIssue({
        code: 'custom',
        message: 'evidence_text is required when granted',
        path: ['evidence_text'],
      });
    }
    if (c.status !== 'revoked' && (c.channel === 'all' || c.purpose === 'all')) {
      ctx.addIssue({
        code: 'custom',
        message: 'channel all and purpose all are only for revoked records',
        path: [c.channel === 'all' ? 'channel' : 'purpose'],
      });
    }
    if (!addressFitsChannel(c.channel, c.address)) {
      ctx.addIssue({
        code: 'custom',
        message: `address does not fit channel ${c.channel} (E.164 phone, lowercased email or digits-only PSID)`,
        path: ['address'],
      });
    }
    if (c.status === 'granted') {
      if (c.retain_until !== undefined) {
        ctx.addIssue({
          code: 'custom',
          message:
            'retain_until is not allowed on a granted record (keep while the consent is in use)',
          path: ['retain_until'],
        });
      }
      return;
    }
    if (c.retain_until === undefined) {
      ctx.addIssue({
        code: 'custom',
        message: 'retain_until is required on a revoked record',
        path: ['retain_until'],
      });
      return;
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
