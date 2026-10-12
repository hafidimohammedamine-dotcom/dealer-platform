import { z } from 'zod';

/**
 * Record id: a UUID string, so an id can never climb out of a storage path or URL.
 * Decision (manager, issue #3): Payload is configured with `idType: 'uuid'` (Payload's Postgres adapter uses numeric
 * ids by default). The `apps/admin/payload.config.ts` change is routed to the devops PR #55 / issue #5; until it lands,
 * CRM records read through `packages/data` would carry numeric ids and fail this contract.
 */
export const IdSchema = z.uuid();

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

/**
 * Characters never allowed in free text: C0/C1 control characters (log forging), line and paragraph separators and
 * bidirectional controls (misleading display). `\n` and `\t` are allowed only when `allowLayout` is true.
 */
function hasForbiddenChar(value: string, allowLayout: boolean): boolean {
  for (const ch of value) {
    const cp = ch.codePointAt(0) ?? 0;
    if (allowLayout && (cp === 0x0a || cp === 0x09)) {
      continue;
    }
    const control = cp < 0x20 || (cp >= 0x7f && cp <= 0x9f);
    const bidi =
      cp === 0x061c ||
      cp === 0x200e ||
      cp === 0x200f ||
      (cp >= 0x2028 && cp <= 0x202e) ||
      (cp >= 0x2066 && cp <= 0x2069);
    if (control || bidi) {
      return true;
    }
  }
  return false;
}

/**
 * Single-line free text (names, labels): trimmed, no control characters, no bidi controls. Add `.min()` / `.max()` at
 * the use site. Leading `= + - @` is NOT rejected (real names and notes start that way): any CSV export must escape
 * formula prefixes itself.
 */
export const SafeTextSchema = z
  .string()
  .trim()
  .refine((v) => !hasForbiddenChar(v, false), {
    message: 'text must not contain control or bidirectional characters',
  });

/**
 * Multi-line free text (comments, consent wording): like `SafeTextSchema` but keeps `\n` and `\t` and does not trim,
 * so quoted consent wording is stored exactly. CSV export must escape formula prefixes.
 */
export const SafeLongTextSchema = z.string().refine((v) => !hasForbiddenChar(v, true), {
  message: 'text must not contain control or bidirectional characters',
});

/** Exact wording shown to or received from a customer (consent, credit pull authorization, joint intent). */
export const EvidenceTextSchema = SafeLongTextSchema.min(1).max(2000);

/**
 * An https URL on a domain name (no IP literal, no `localhost`). The value is untrusted and display-only. This is NOT
 * an SSRF control: names such as `metadata.google.internal` or `127.0.0.1.nip.io` pass. Never fetch it server-side
 * without an SSRF guard (resolve, then block private, loopback and link-local addresses).
 */
export const HttpsUrlSchema = z.url({ protocol: /^https$/, hostname: z.regexes.domain }).max(2048);

/** The contact fields every person-like record shares (customer, lead contact). Frozen: no importer can edit it. */
export const contactFields = Object.freeze({
  first_name: SafeTextSchema.min(1).max(100).optional(),
  last_name: SafeTextSchema.min(1).max(100).optional(),
  email: EmailSchema.optional(),
  phone: PhoneE164Schema.optional(),
});

/** Fields every record carries. Frozen: no importer can drop `dealer_id`. */
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

/** Fail closed: if zod ever changes where it keeps a child schema, throw instead of skipping it. */
function schemaOf(value: unknown, where: string): z.core.$ZodType {
  if (!isSchema(value)) {
    throw new Error(`sensitive-field check cannot read ${where}`);
  }
  return value;
}

/** Types with nothing inside them to look at. */
const LEAF_TYPES = new Set([
  'string',
  'number',
  'boolean',
  'bigint',
  'date',
  'null',
  'undefined',
  'void',
  'any',
  'unknown',
  'never',
  'nan',
  'symbol',
  'literal',
  'enum',
  'file',
  'template_literal',
  'custom',
  'transform',
]);

/** Wrapper types that hold one schema in `innerType`. */
const WRAPPER_TYPES = new Set([
  'optional',
  'nullable',
  'default',
  'prefault',
  'nonoptional',
  'readonly',
  'catch',
  'promise',
  'success',
]);

type Child = readonly [suffix: string, schema: z.core.$ZodType];

function childrenOf(schema: z.core.$ZodType): Child[] {
  const def = schema._zod.def;
  const at = (key: string) => schemaOf(Reflect.get(def, key), `${def.type}.${key}`);
  const each = (key: string) => {
    const list: unknown = Reflect.get(def, key);
    if (!Array.isArray(list)) {
      throw new Error(`sensitive-field check cannot read ${def.type}.${key}`);
    }
    return list.map((item) => schemaOf(item, `${def.type}.${key}`));
  };
  if (WRAPPER_TYPES.has(def.type)) {
    return [['', at('innerType')]];
  }
  switch (def.type) {
    case 'pipe':
      return [
        ['', at('in')],
        ['', at('out')],
      ];
    case 'union':
      return each('options').map((o) => ['', o] as const);
    case 'intersection':
      return [
        ['', at('left')],
        ['', at('right')],
      ];
    case 'record':
    case 'map':
      return [
        ['{}', at('keyType')],
        ['{}', at('valueType')],
      ];
    case 'set':
      return [['[]', at('valueType')]];
    case 'tuple': {
      const items = each('items').map((o, i) => [`[${i}]`, o] as const);
      return Reflect.get(def, 'rest') ? [...items, ['[]', at('rest')] as const] : items;
    }
    case 'array':
      return [['[]', at('element')]];
    case 'object': {
      const shape: unknown = Reflect.get(def, 'shape');
      if (!isRecord(shape)) {
        throw new Error('sensitive-field check cannot read object.shape');
      }
      return Object.entries(shape).map(
        ([name, field]) => [`.${name}`, schemaOf(field, `object.${name}`)] as const,
      );
    }
    case 'lazy': {
      const getter: unknown = Reflect.get(def, 'getter');
      if (typeof getter !== 'function') {
        throw new Error('sensitive-field check cannot read lazy.getter');
      }
      return [['', schemaOf(getter(), 'lazy.getter()')]];
    }
    default:
      if (LEAF_TYPES.has(def.type)) {
        return [];
      }
      // Fail closed: an unknown wrapper could hide a sensitive field, so refuse to guess.
      throw new Error(`sensitive-field check does not know schema type "${def.type}"`);
  }
}

function visit(
  schema: z.core.$ZodType,
  path: string,
  found: Set<string>,
  ancestors: Set<z.core.$ZodType>,
): void {
  if (z.globalRegistry.get(schema)?.[SENSITIVE_META_KEY] === true) {
    found.add(path);
    return;
  }
  if (ancestors.has(schema)) {
    return;
  }
  ancestors.add(schema);
  for (const [suffix, child] of childrenOf(schema)) {
    visit(child, `${path}${suffix}`, found, ancestors);
  }
  ancestors.delete(schema);
}

/** Every path under the schema that is marked sensitive. A path is reported at most once, and sorted. */
function sensitivePaths(schema: z.core.$ZodType): string[] {
  const found = new Set<string>();
  visit(schema, '', found, new Set());
  return [...found].map((p) => (p.startsWith('.') ? p.slice(1) : p)).sort();
}

/**
 * True when the schema, or anything inside it, was marked with `sensitive()`. Follows every wrapper (optional,
 * nullable, default, prefault, nonoptional, readonly, catch, promise, success), both sides of a pipe (so `preprocess`
 * works), union options, intersection sides, record and map keys and values, set values, tuple items, array
 * elements, object fields and the lazy getter. Throws on a schema type it does not know.
 */
export function isSensitive(schema: z.core.$ZodType): boolean {
  return sensitivePaths(schema).length > 0;
}

/**
 * Paths of the fields of an object schema that are marked sensitive, sorted. Walks everything `isSensitive` walks:
 * nested objects (`a.b`), arrays of objects (`a[].b`), tuples (`a[0]`), records and maps (`a{}`) and sets (`a[]`).
 * A mark found inside a union is reported at the union's own path.
 */
export function sensitiveFields(schema: z.ZodObject<z.ZodRawShape>): string[] {
  return sensitivePaths(schema);
}
