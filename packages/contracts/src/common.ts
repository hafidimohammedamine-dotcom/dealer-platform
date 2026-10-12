import { z } from 'zod';

/**
 * Record id (opaque string). Letters, digits, `_` and `-` only, so an id can never climb out of a storage path or URL.
 * Decision: Payload is configured with `idType: 'uuid'` (apps/admin/payload.config.ts), so CRM records coming through
 * `packages/data` carry string ids that pass this check. Payload's default is a numeric id, which would fail here. If
 * the founders prefer numeric ids, change this schema and every id field, not the call sites.
 */
export const IdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, 'id: 1-64 of A-Z a-z 0-9 _ -');

/** Every record belongs to exactly one dealer (tenant). */
export const DealerIdSchema = IdSchema;

/** Money is always integer cents, never floating point. Can be negative (e.g. negative equity). */
export const CentsSchema = z.number().int().safe();
export const CentsNonNegativeSchema = CentsSchema.nonnegative();

/** A rate in basis points (650 = 6.50%), an integer so no floating point. Used for APR and tax rate. */
export const BasisPointsSchema = z.number().int().min(0).max(10000);

/** Loan or lease term in months. */
export const TermMonthsSchema = z.number().int().positive().max(120);

/** Vehicle model year. */
export const ModelYearSchema = z.number().int().min(1900).max(2100);

/** ISO 8601 UTC timestamp, for example `2026-10-12T14:30:00Z` (offsets other than Z are rejected). */
export const IsoDateTimeSchema = z.iso.datetime();
/** ISO 8601 calendar date, for example `1980-02-29`. */
export const IsoDateSchema = z.iso.date();

const BIDI_CONTROLS = new Set([
  0x061c, 0x200e, 0x200f, 0x2028, 0x2029, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067,
  0x2068, 0x2069,
]);

function isSafeText(text: string, allowLayout: boolean): boolean {
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i);
    if (code < 0x20) {
      if (allowLayout && (code === 0x0a || code === 0x09)) {
        continue;
      }
      return false;
    }
    if ((code >= 0x7f && code <= 0x9f) || BIDI_CONTROLS.has(code)) {
      return false;
    }
  }
  return true;
}

/**
 * Single-line free text: no control characters (so no newline, tab or NUL) and no bidi or line-separator controls. That
 * stops log forging and misleading display. It does NOT stop a leading `=`, `+`, `-` or `@`: any CSV export must escape
 * formula prefixes itself.
 */
export const SafeTextSchema = z
  .string()
  .refine((s) => isSafeText(s, false), { message: 'text has control or bidi characters' });

/** Multi-line free text: like `SafeTextSchema` but `\n` and `\t` are allowed. Same CSV warning applies. */
export const SafeLongTextSchema = z
  .string()
  .refine((s) => isSafeText(s, true), { message: 'text has control or bidi characters' });

/**
 * An https URL with a domain-name host, at most 2048 characters. UNTRUSTED, display-only input: this is not an SSRF
 * control (`metadata.google.internal` and `127.0.0.1.nip.io` pass it). Never fetch it server-side without an SSRF guard.
 */
export const HttpsUrlSchema = z.url({ protocol: /^https$/, hostname: z.regexes.domain }).max(2048);

/** Exact wording a customer saw or agreed to (consent, credit pull, joint intent). Never empty. */
export const EvidenceTextSchema = SafeLongTextSchema.min(1).max(2000);

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

/** The contact fields every person-like record shares (customer, lead contact). Internal and frozen. */
export const contactFields = Object.freeze({
  first_name: SafeTextSchema.min(1).max(100).optional(),
  last_name: SafeTextSchema.min(1).max(100).optional(),
  email: EmailSchema.optional(),
  phone: PhoneE164Schema.optional(),
});

/** Fields every record carries. Internal and frozen, so no importer can drop `dealer_id`. */
export const recordBase = Object.freeze({
  id: IdSchema,
  dealer_id: DealerIdSchema,
  created_at: IsoDateTimeSchema,
  updated_at: IsoDateTimeSchema,
});

/** Marker key stored in a schema's metadata so code can find fields to encrypt and mask. */
export const SENSITIVE_META_KEY = 'sensitive';

/** Mark a schema as sensitive (encrypt at rest, mask on screen, never log). Returns a new schema; the input is untouched. */
export function sensitive<T extends z.ZodType>(schema: T): T {
  return schema.meta({ [SENSITIVE_META_KEY]: true });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isSchema(value: unknown): value is z.core.$ZodType {
  return isRecord(value) && '_zod' in value;
}

function need(value: unknown, what: string): z.core.$ZodType {
  if (!isSchema(value)) {
    throw new Error(`sensitive-field walker: ${what} is not a schema`);
  }
  return value;
}

/** Wrappers with one inner schema (`def.innerType`). */
const WRAPPERS = new Set([
  'optional',
  'nullable',
  'default',
  'prefault',
  'nonoptional',
  'readonly',
  'catch',
  'success',
  'promise',
]);

/** Schemas with nothing inside that could hold a sensitive field. */
const LEAVES = new Set([
  'string',
  'number',
  'boolean',
  'bigint',
  'symbol',
  'null',
  'undefined',
  'void',
  'never',
  'any',
  'unknown',
  'date',
  'file',
  'enum',
  'literal',
  'nan',
  'template_literal',
  'transform',
  'custom',
]);

function join(path: string, name: string): string {
  return path === '' ? name : `${path}.${name}`;
}

function walk(
  schema: z.core.$ZodType,
  path: string,
  out: Set<string>,
  stack: Set<z.core.$ZodType>,
): void {
  if (stack.has(schema)) {
    return;
  }
  if (z.globalRegistry.get(schema)?.[SENSITIVE_META_KEY] === true) {
    out.add(path);
    return;
  }
  const def: unknown = schema._zod.def;
  if (!isRecord(def) || typeof def.type !== 'string') {
    throw new Error('sensitive-field walker: schema has no type');
  }
  stack.add(schema);
  try {
    const sub = (child: unknown, childPath: string = path): void =>
      walk(need(child, `${def.type} child`), childPath, out, stack);
    if (WRAPPERS.has(def.type)) {
      sub(def.innerType);
    } else if (LEAVES.has(def.type)) {
      return;
    } else if (def.type === 'pipe') {
      sub(def.in);
      sub(def.out);
    } else if (def.type === 'union') {
      for (const option of Array.isArray(def.options) ? def.options : []) {
        sub(option);
      }
    } else if (def.type === 'intersection') {
      sub(def.left);
      sub(def.right);
    } else if (def.type === 'object') {
      if (!isRecord(def.shape)) {
        throw new Error('sensitive-field walker: object has no shape');
      }
      for (const [name, field] of Object.entries(def.shape)) {
        sub(field, join(path, name));
      }
    } else if (def.type === 'array') {
      sub(def.element, `${path}[]`);
    } else if (def.type === 'set') {
      sub(def.valueType, `${path}[]`);
    } else if (def.type === 'map' || def.type === 'record') {
      sub(def.keyType, `${path}.*`);
      sub(def.valueType, `${path}.*`);
    } else if (def.type === 'tuple') {
      (Array.isArray(def.items) ? def.items : []).forEach((item: unknown, i: number) => {
        sub(item, `${path}[${i}]`);
      });
      if (isSchema(def.rest)) {
        sub(def.rest, `${path}[]`);
      }
    } else if (def.type === 'lazy' && typeof def.getter === 'function') {
      sub(def.getter());
    } else {
      throw new Error(`sensitive-field walker: unhandled schema type "${def.type}"`);
    }
  } finally {
    stack.delete(schema);
  }
}

function findSensitive(schema: z.core.$ZodType): Set<string> {
  const out = new Set<string>();
  walk(schema, '', out, new Set());
  return out;
}

/**
 * True when the schema, or anything inside it, was marked with `sensitive()`. Fails closed: see `sensitiveFields`.
 */
export function isSensitive(schema: z.core.$ZodType): boolean {
  return findSensitive(schema).size > 0;
}

/**
 * Paths of the fields of an object schema that are marked sensitive, sorted. The walker fails closed. It follows
 * optional, nullable, default, prefault, nonoptional, readonly, catch, success and promise wrappers; BOTH sides of a
 * pipe (so `z.preprocess` and a mark on the output are seen); every union option (and discriminated union option);
 * both sides of an intersection; record and map keys and values; set elements; tuple items and rest; the lazy getter;
 * nested objects (`a.b`); and arrays (`a[]`, `a[].b`). A schema type it does not know throws, so a mark can never be
 * silently skipped.
 */
export function sensitiveFields(schema: z.ZodObject<z.ZodRawShape>): string[] {
  return [...findSensitive(schema)].sort();
}
