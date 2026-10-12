import { z } from 'zod';
import {
  centsNonNegative,
  id,
  isoDate,
  isoDateTime,
  recordBase,
  sensitive,
  sensitiveFields,
} from './common.js';

/**
 * Credit application. Fields wrapped in `sensitive()` must be encrypted at rest, masked on screen, never logged and
 * never sent by text or email. Fake data only: SSNs in the 900-xx-xxxx range.
 */
export const CreditAppSchema = z.strictObject({
  ...recordBase,
  deal_id: id,
  customer_id: id,
  applicant_name: z.string().min(1).max(200),
  /** Social Security number, `NNN-NN-NNNN`. */
  ssn: sensitive(z.string().regex(/^\d{3}-\d{2}-\d{4}$/)),
  date_of_birth: sensitive(isoDate),
  monthly_income_cents: sensitive(centsNonNegative),
  bank_account_number: sensitive(z.string().regex(/^\d{4,17}$/)),
  bank_routing_number: sensitive(z.string().regex(/^\d{9}$/)),
  employer_name: z.string().max(200).optional(),
  has_coapplicant: z.boolean(),
  submitted_at: isoDateTime.optional(),
});
export type CreditApp = z.infer<typeof CreditAppSchema>;

/** Names of the sensitive CreditApp fields, derived from the schema. */
export const CREDIT_APP_SENSITIVE_FIELDS = sensitiveFields(CreditAppSchema);

const MASK = '********';

/** Copy of a credit app that is safe to show: sensitive fields replaced, SSN keeps its last 4 digits. */
export function maskCreditApp(app: CreditApp): Record<string, unknown> {
  const out: Record<string, unknown> = { ...app };
  for (const name of CREDIT_APP_SENSITIVE_FIELDS) {
    out[name] = MASK;
  }
  out.ssn = `***-**-${app.ssn.slice(-4)}`;
  return out;
}
