import { z } from 'zod';

/** Record id (opaque string). Letters, digits, `_` and `-` only, so an id can never climb out of a storage path or URL. */
export const IdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, 'id: 1-64 of A-Z a-z 0-9 _ -');

/** Every record belongs to exactly one dealer (tenant). */
export const DealerIdSchema = IdSchema;

/** Money is always integer cents, never floating point. Can be negative (e.g. negative equity). */
export const CentsSchema = z.number().int().safe();
export const CentsNonNegativeSchema = CentsSchema.nonnegative();

/** Annual percentage rate in basis points (650 = 6.50%), an integer so no floating point. */
export const AprBasisPointsSchema = z.number().int().min(0).max(10000);

/** Loan or lease term in months. */
export const TermMonthsSchema = z.number().int().positive().max(120);

/** Vehicle model year. */
export const ModelYearSchema = z.number().int().min(1900).max(2100);

/** ISO 8601 UTC timestamp, for example `2026-10-12T14:30:00Z` (offsets other than Z are rejected). */
export const IsoDateTimeSchema = z.iso.datetime();
/** ISO 8601 calendar date, for example `1980-02-29`. */
export const IsoDateSchema = z.iso.date();

export const EmailSchema = z.email().max(254);
/** E.164 phone number. */
export const PhoneE164Schema = z.string().regex(/^\+[1-9]\d{6,14}$/);

function isRealTimeZone(name: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name });
    return true;
  } catch {
    return false;
  }
}

/** IANA time zone name such as `America/Chicago` or `America/Indiana/Indianapolis`. Texting hours depend on it. */
export const TimeZoneSchema = z
  .string()
  .max(64)
  .regex(/^[A-Za-z]+(?:\/[A-Za-z0-9_+-]+)+$/, 'time zone: IANA name such as America/Chicago')
  .refine(isRealTimeZone, { message: 'unknown IANA time zone' });

/** The contact fields every person-like record shares (customer, lead contact). */
export const contactFields = {
  first_name: z.string().max(100).optional(),
  last_name: z.string().max(100).optional(),
  email: EmailSchema.optional(),
  phone: PhoneE164Schema.optional(),
};

/** Fields every record carries. */
export const recordBase = {
  id: IdSchema,
  dealer_id: DealerIdSchema,
  created_at: IsoDateTimeSchema,
  updated_at: IsoDateTimeSchema,
};

/** Marker key stored in a schema's metadata so code can find fields to encrypt and mask. */
export const SENSITIVE_META_KEY = 'sensitive';

/** Mark a schema as sensitive (encrypt at rest, mask on screen, never log). Returns a new schema; the input is untouched. */
export function sensitive<T extends z.ZodType>(schema: T): T {
  return schema.meta({ [SENSITIVE_META_KEY]: true });
}

/** The schema one wrapper layer down (optional, nullable, default, readonly, catch, pipe), or undefined. */
function inner(schema: z.core.$ZodType): z.core.$ZodType | undefined {
  if (
    schema instanceof z.ZodOptional ||
    schema instanceof z.ZodNullable ||
    schema instanceof z.ZodDefault ||
    schema instanceof z.ZodNonOptional ||
    schema instanceof z.ZodReadonly ||
    schema instanceof z.ZodCatch
  ) {
    return schema.def.innerType;
  }
  if (schema instanceof z.ZodPipe) {
    return schema.def.in;
  }
  return undefined;
}

/** True when the schema, or any wrapper layer around it, was marked with `sensitive()`. */
export function isSensitive(schema: z.core.$ZodType): boolean {
  for (let s: z.core.$ZodType | undefined = schema; s; s = inner(s)) {
    if (z.globalRegistry.get(s)?.[SENSITIVE_META_KEY] === true) {
      return true;
    }
  }
  return false;
}

/** The schema with every wrapper layer removed. */
function core(schema: z.core.$ZodType): z.core.$ZodType {
  let s = schema;
  for (let next = inner(s); next; next = inner(s)) {
    s = next;
  }
  return s;
}

function collect(shape: z.ZodRawShape, prefix: string, out: string[]): void {
  for (const [name, field] of Object.entries(shape)) {
    const path = `${prefix}${name}`;
    if (isSensitive(field)) {
      out.push(path);
      continue;
    }
    const bare = core(field);
    if (bare instanceof z.ZodObject) {
      collect(bare.shape, `${path}.`, out);
    } else if (bare instanceof z.ZodArray) {
      const item = core(bare.element);
      if (item instanceof z.ZodObject) {
        collect(item.shape, `${path}[].`, out);
      }
    }
  }
}

/**
 * Paths of the fields of an object schema that are marked sensitive, sorted. Sees through optional, nullable and
 * default wrappers and walks nested objects (`a.b`) and arrays of objects (`a[].b`).
 */
export function sensitiveFields(schema: z.ZodObject<z.ZodRawShape>): string[] {
  const out: string[] = [];
  collect(schema.shape, '', out);
  return out.sort();
}
