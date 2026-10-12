import { z } from 'zod';
import { id, isoDateTime, recordBase } from './common.js';

export const ConsentChannelSchema = z.enum(['sms', 'voice_ai', 'email', 'messenger']);
export const ConsentStatusSchema = z.enum(['granted', 'revoked']);

/** Written consent (or its withdrawal) for one channel. Revoked records are kept (do-not-call: 5 years). */
export const ConsentSchema = z.strictObject({
  ...recordBase,
  customer_id: id,
  channel: ConsentChannelSchema,
  status: ConsentStatusSchema,
  /** Where and how it was given or revoked, for example `web_form`, `stop_keyword`. */
  source: z.string().min(1).max(100),
  /** Exact wording shown or received. */
  evidence_text: z.string().max(2000).optional(),
  recorded_at: isoDateTime,
  /** Keep the record at least until this time. */
  retain_until: isoDateTime,
});
export type Consent = z.infer<typeof ConsentSchema>;
