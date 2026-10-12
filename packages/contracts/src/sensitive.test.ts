import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import * as api from './index.js';
import {
  CREDIT_APP_SENSITIVE_FIELDS,
  CentsNonNegativeSchema,
  CreditAppSchema,
  CustomerSchema,
  IsoDateSchema,
  isSensitive,
  sensitive,
  sensitiveFields,
} from './index.js';
import { ok } from './test-samples.js';

const mark = sensitive(z.string());

function isZod(value: unknown): value is z.core.$ZodType {
  return typeof value === 'object' && value !== null && '_zod' in value;
}
const fieldsOf = (field: z.ZodType) => sensitiveFields(z.object({ a: field }));

describe('credit app sensitive fields', () => {
  it('marks exactly SSN, DOB, income and bank fields, in a frozen list', () => {
    expect(CREDIT_APP_SENSITIVE_FIELDS).toEqual([
      'bank_account_number',
      'bank_routing_number',
      'date_of_birth',
      'monthly_income_cents',
      'ssn',
    ]);
    expect(Object.isFrozen(CREDIT_APP_SENSITIVE_FIELDS)).toBe(true);
  });
  it('isSensitive is false for unmarked fields', () => {
    expect(isSensitive(z.string())).toBe(false);
    expect(isSensitive(CreditAppSchema.shape.applicant_name)).toBe(false);
    expect(sensitiveFields(CustomerSchema)).toEqual([]);
  });
  it('marking a field leaves the shared base schemas unmarked', () => {
    expect(isSensitive(IsoDateSchema)).toBe(false);
    expect(isSensitive(CentsNonNegativeSchema)).toBe(false);
    expect(isSensitive(sensitive(IsoDateSchema))).toBe(true);
  });
  it('reports the same set on derived credit app schemas', () => {
    const shape = CreditAppSchema.shape;
    expect(sensitiveFields(z.object(shape))).toEqual(CREDIT_APP_SENSITIVE_FIELDS);
    expect(sensitiveFields(z.object(shape).partial())).toEqual(CREDIT_APP_SENSITIVE_FIELDS);
    expect(sensitiveFields(z.object(shape).extend({ extra: z.string() }))).toEqual(
      CREDIT_APP_SENSITIVE_FIELDS,
    );
    expect(sensitiveFields(z.object(shape).pick({ ssn: true, applicant_name: true }))).toEqual([
      'ssn',
    ]);
    expect(sensitiveFields(z.object({ nested: z.object(shape).optional() }))).toEqual(
      CREDIT_APP_SENSITIVE_FIELDS.map((n) => `nested.${n}`),
    );
  });
  it('rejects malformed SSN', () => {
    expect(ok('creditApp', { ssn: '123456789' })).toBe(false);
    expect(ok('creditApp', { ssn: '900-1-23456' })).toBe(false);
  });
});

describe('the sensitive check follows every wrapper', () => {
  it('sees through optional, nullable, default, readonly, nonoptional, catch and prefault', () => {
    expect(fieldsOf(mark.optional())).toEqual(['a']);
    expect(fieldsOf(mark.nullable().optional())).toEqual(['a']);
    expect(fieldsOf(mark.default('x'))).toEqual(['a']);
    expect(fieldsOf(mark.readonly())).toEqual(['a']);
    expect(fieldsOf(mark.optional().nonoptional())).toEqual(['a']);
    expect(fieldsOf(mark.catch('x'))).toEqual(['a']);
    expect(fieldsOf(mark.prefault('x'))).toEqual(['a']);
    expect(fieldsOf(sensitive(z.string().optional()))).toEqual(['a']);
    expect(fieldsOf(z.string().optional())).toEqual([]);
  });
  it('sees both sides of a pipe, so preprocess cannot hide a mark', () => {
    expect(fieldsOf(mark.pipe(z.string()))).toEqual(['a']);
    expect(fieldsOf(z.string().pipe(mark))).toEqual(['a']);
    expect(fieldsOf(z.preprocess((v) => v, mark))).toEqual(['a']);
    expect(fieldsOf(z.string().transform((v) => v))).toEqual([]);
  });
  it('sees unions, discriminated unions and intersections', () => {
    expect(fieldsOf(z.union([mark, z.literal('')]))).toEqual(['a']);
    expect(
      fieldsOf(
        z.discriminatedUnion('k', [
          z.object({ k: z.literal('x'), s: mark }),
          z.object({ k: z.literal('y') }),
        ]),
      ),
    ).toEqual(['a.s']);
    expect(fieldsOf(z.intersection(z.object({ s: mark }), z.object({ t: z.string() })))).toEqual([
      'a.s',
    ]);
    expect(fieldsOf(z.union([z.string(), z.number()]))).toEqual([]);
  });
  it('sees records, maps, sets, tuples, arrays and nested objects', () => {
    expect(fieldsOf(z.record(z.string(), mark))).toEqual(['a{}']);
    expect(fieldsOf(z.map(z.string(), mark))).toEqual(['a{}']);
    expect(fieldsOf(z.set(mark))).toEqual(['a[]']);
    expect(fieldsOf(z.tuple([z.string(), mark], mark))).toEqual(['a[1]', 'a[]']);
    expect(fieldsOf(z.tuple([z.string()]))).toEqual([]);
    expect(fieldsOf(z.array(mark))).toEqual(['a[]']);
    const nested = z.object({
      a: z.object({ b: mark, c: z.string() }).optional(),
      list: z.array(z.object({ d: mark })),
      plain: z.array(z.string()),
    });
    expect(sensitiveFields(nested)).toEqual(['a.b', 'list[].d']);
  });
  it('sees through lazy and survives a schema that contains itself', () => {
    expect(fieldsOf(z.lazy(() => mark))).toEqual(['a']);
    const node: z.ZodObject<z.ZodRawShape> = z.object({
      s: mark,
      kid: z.lazy(() => node).optional(),
    });
    expect(sensitiveFields(node)).toEqual(['s']);
  });
  it('knows the plain leaf types', () => {
    const leaves = z.object({
      a: z.literal(1),
      b: z.enum(['x']),
      c: z.custom(),
      d: z.date(),
      e: z.boolean(),
      f: z.bigint(),
      g: z.null(),
      h: z.unknown(),
    });
    expect(sensitiveFields(leaves)).toEqual([]);
  });
  it('throws on a schema type it does not know instead of calling it safe', () => {
    const mystery: unknown = { _zod: { def: { type: 'mystery' } } };
    if (!isZod(mystery)) {
      throw new Error('test setup');
    }
    expect(() => isSensitive(mystery)).toThrow(/mystery/);
  });
});

describe('every exported object schema', () => {
  const objects: [string, z.ZodObject][] = [];
  for (const [name, value] of Object.entries(api)) {
    if (value instanceof z.ZodObject) {
      objects.push([name, value]);
    }
  }
  /** Every field path in the schema, however deeply nested (same path format as `sensitiveFields`). */
  function fieldPaths(schema: z.core.$ZodType, prefix: string): string[] {
    if (schema instanceof z.ZodOptional || schema instanceof z.ZodNullable) {
      return fieldPaths(schema.unwrap(), prefix);
    }
    if (schema instanceof z.ZodArray) {
      return fieldPaths(schema.element, `${prefix}[]`);
    }
    if (schema instanceof z.ZodObject) {
      return Object.entries(schema.shape).flatMap(([name, field]) => {
        const here = prefix === '' ? name : `${prefix}.${name}`;
        return [here, ...fieldPaths(field, here)];
      });
    }
    return [];
  }
  it('finds every record shape', () => {
    expect(objects.length).toBeGreaterThanOrEqual(10);
  });
  it('marks every field that looks like SSN, birth date, income or bank data', () => {
    const risky = /ssn|social|birth|dob|income|account_number|routing/i;
    for (const [name, schema] of objects) {
      const marked = sensitiveFields(schema);
      for (const path of fieldPaths(schema, '').filter((p) => risky.test(p))) {
        expect(marked, `${name}.${path} looks sensitive but is not marked`).toContain(path);
      }
    }
  });
});
