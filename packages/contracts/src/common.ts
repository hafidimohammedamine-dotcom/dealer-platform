import { z } from 'zod';

/** Record id (opaque string). */
export const id = z.string().min(1).max(64);

/** Every record belongs to exactly one dealer (tenant). */
export const dealerId = id;

/** Money is always integer cents, never floating point. Can be negative (e.g. negative equity). */
export const cents = z.number().int().safe();
export const centsNonNegative = cents.nonnegative();

/** ISO 8601 UTC timestamp, for example `2026-10-12T14:30:00Z` (offsets other than Z are rejected). */
export const isoDateTime = z.iso.datetime();
/** ISO 8601 calendar date, for example `1980-02-29`. */
export const isoDate = z.iso.date();

export const email = z.email().max(254);
/** E.164 phone number. */
export const phoneE164 = z.string().regex(/^\+[1-9]\d{6,14}$/);

/** Fields every record carries. */
export const recordBase = {
  id,
  dealer_id: dealerId,
  created_at: isoDateTime,
  updated_at: isoDateTime,
};

/** Marker key stored in a schema's metadata so code can find fields to encrypt and mask. */
export const SENSITIVE_META_KEY = 'sensitive';

/** Mark a schema as sensitive (encrypt at rest, mask on screen, never log). */
export function sensitive<T extends z.ZodType>(schema: T): T {
  return schema.meta({ [SENSITIVE_META_KEY]: true });
}

/** True when the schema was marked with `sensitive()`. */
export function isSensitive(schema: z.core.$ZodType): boolean {
  return z.globalRegistry.get(schema)?.[SENSITIVE_META_KEY] === true;
}

/** Names of the top level fields of an object schema that are marked sensitive. */
export function sensitiveFields(schema: z.ZodObject<z.ZodRawShape>): string[] {
  return Object.entries(schema.shape)
    .filter(([, field]) => isSensitive(field))
    .map(([name]) => name)
    .sort();
}
