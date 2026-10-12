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
 * `all` covers every purpose and is valid only on a revoked record. A revocation counts as `all` unless the customer
 * limited it to one purpose.
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
  /** Page where the consent box was shown. */
  page_url: HttpsUrlSchema.optional(),
});

const RETENTION_YEARS = 5;

const isPhone = (a: string): boolean => PhoneE164Schema.safeParse(a).success;
const isEmail = (a: string): boolean => a === a.toLowerCase() && EmailSchema.safeParse(a).success;
const isPsid = (a: string): boolean => /^\d{1,64}$/.test(a);

/** True when `address` has the canonical form for the channel, so a lookup by address always finds the record. */
function addressMatchesChannel(channel: z.infer<typeof ConsentChannelSchema>, address: string) {
  switch (channel) {
    case 'sms':
    case 'voice_ai':
      return isPhone(address);
    case 'email':
      return isEmail(address);
    case 'messenger':
      return isPsid(address);
    case 'all':
      return isPhone(address) || isEmail(address) || isPsid(address);
  }
}

/**
 * Written consent (or its withdrawal) for one channel.
 * - `address` is the exact phone number (E.164 for `sms` and `voice_ai`), lowercased email (`email`) or digits-only
 *   Messenger PSID (`messenger`) consented, so opt-out lookups and the Reassigned Numbers Database check always match.
 *   A consent that arrives before the lead is matched to a customer carries only `lead_id`.
 * - `channel: 'all'` and `purpose: 'all'` are revoked-only (47 CFR 64.1200(a)(10)). An `all` record covers every
 *   address of that person (it needs `customer_id` or `lead_id`, like every record); the address shown is the one the
 *   STOP came from.
 * - Retention: a granted record has no `retain_until` (it is kept while the consent is in use). It must be kept until
 *   at least 5 years after the consent is revoked or last used. A revoked record needs `retain_until`, at least 5 years
 *   after `recorded_at` (do-not-call is kept 5 years). A leap day rolls forward: 2028-02-29 + 5 years = 2033-03-01.
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
    const fail = (message: string, field: string): void => {
      ctx.addIssue({ code: 'custom', message, path: [field] });
    };
    if (c.customer_id === undefined && c.lead_id === undefined) {
      fail('customer_id or lead_id is required', 'customer_id');
    }
    if (c.status === 'granted' && c.evidence_text === undefined) {
      fail('evidence_text is required when granted', 'evidence_text');
    }
    if (c.channel === 'all' && c.status !== 'revoked') {
      fail('channel all is only for revoked records', 'channel');
    }
    if (c.purpose === 'all' && c.status !== 'revoked') {
      fail('purpose all is only for revoked records', 'purpose');
    }
    if (!addressMatchesChannel(c.channel, c.address)) {
      fail(
        `address is not a valid ${c.channel} address (E.164 phone, lowercase email or digit PSID)`,
        'address',
      );
    }
    if (c.status === 'granted') {
      if (c.retain_until !== undefined) {
        fail('retain_until is not allowed on a granted record (kept while in use)', 'retain_until');
      }
    } else if (c.retain_until === undefined) {
      fail('retain_until is required when revoked', 'retain_until');
    } else {
      const earliest = new Date(c.recorded_at);
      earliest.setUTCFullYear(earliest.getUTCFullYear() + RETENTION_YEARS);
      if (new Date(c.retain_until).getTime() < earliest.getTime()) {
        fail('retain_until must be at least 5 years after recorded_at', 'retain_until');
      }
    }
  });
export type Consent = z.infer<typeof ConsentSchema>;
