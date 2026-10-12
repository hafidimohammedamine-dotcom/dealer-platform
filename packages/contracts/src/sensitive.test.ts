import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { sensitive } from './common.js';
import * as api from './index.js';
import {
  CREDIT_APP_SENSITIVE_FIELDS,
  CentsNonNegativeSchema,
  CreditAppSchema,
  CustomerSchema,
  IsoDateSchema,
  LENDER_DECISION_SENSITIVE_FIELDS,
  isSensitive,
  sensitiveFields,
} from './index.js';
import { ok, samples } from './samples.test.js';

const mark = sensitive(z.string());
const fields = (schema: z.core.$ZodType) => sensitiveFields(z.object({ a: schema }));

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
  it('rejects malformed SSN and uses the fake 900 range in the sample', () => {
    expect(ok('creditApp', { ssn: '123456789' })).toBe(false);
    expect(ok('creditApp', { ssn: '900-1-23456' })).toBe(false);
    expect(samples.creditApp.value.ssn.startsWith('900-')).toBe(true);
  });
});

describe('lender decision sensitive fields (consumer-report data)', () => {
  it('pins the frozen list', () => {
    expect(LENDER_DECISION_SENSITIVE_FIELDS).toEqual([
      'adverse_action_reasons',
      'credit_bureau',
      'credit_score',
      'key_factors',
      'score_date',
      'score_range_max',
      'score_range_min',
    ]);
    expect(Object.isFrozen(LENDER_DECISION_SENSITIVE_FIELDS)).toBe(true);
  });
});

describe('every exported object schema', () => {
  const NAME = /ssn|social|birth|dob|income|account_number|routing/i;
  const names = (shape: z.ZodRawShape, prefix: string): string[] =>
    Object.entries(shape).flatMap(([name, field]) => {
      let inner: z.core.$ZodType = field;
      while (inner instanceof z.ZodOptional || inner instanceof z.ZodNullable) {
        inner = inner.def.innerType;
      }
      const path = `${prefix}${name}`;
      const own = NAME.test(name) ? [path] : [];
      if (inner instanceof z.ZodObject) {
        return [...own, ...names(inner.shape, `${path}.`)];
      }
      if (inner instanceof z.ZodArray && inner.element instanceof z.ZodObject) {
        return [...own, ...names(inner.element.shape, `${path}[].`)];
      }
      return own;
    });
  const schemas: [string, z.ZodObject<z.ZodRawShape>][] = [];
  for (const [exportName, value] of Object.entries(api)) {
    if (value instanceof z.ZodObject) {
      schemas.push([exportName, value]);
    }
  }

  it('finds the object schemas', () => {
    expect(schemas.length).toBeGreaterThanOrEqual(10);
  });
  it('marks every ssn, dob, income, account or routing field as sensitive', () => {
    for (const [schemaName, schema] of schemas) {
      const marked = sensitiveFields(schema);
      for (const path of names(schema.shape, '')) {
        expect(marked, `${schemaName}.${path} looks sensitive but is not sensitive()`).toContain(
          path,
        );
      }
    }
  });
  it('would catch an unmarked field of that kind', () => {
    const bad = z.object({ ssn: z.string(), inner: z.object({ dob: z.string() }).optional() });
    expect(names(bad.shape, '')).toEqual(['ssn', 'inner.dob']);
    expect(sensitiveFields(bad)).toEqual([]);
  });
});

describe('sensitive field walker', () => {
  it('is false for unmarked fields', () => {
    expect(isSensitive(z.string())).toBe(false);
    expect(isSensitive(CreditAppSchema.shape.applicant_name)).toBe(false);
    expect(sensitiveFields(CustomerSchema)).toEqual([]);
    expect(fields(z.string().optional())).toEqual([]);
  });
  it('leaves the shared base schemas unmarked', () => {
    expect(isSensitive(IsoDateSchema)).toBe(false);
    expect(isSensitive(CentsNonNegativeSchema)).toBe(false);
    expect(isSensitive(sensitive(IsoDateSchema))).toBe(true);
  });
  it('keeps the mark through every wrapper', () => {
    expect(fields(mark.optional())).toEqual(['a']);
    expect(fields(mark.nullable().optional())).toEqual(['a']);
    expect(fields(mark.default('x'))).toEqual(['a']);
    expect(fields(mark.prefault('x'))).toEqual(['a']);
    expect(fields(mark.readonly())).toEqual(['a']);
    expect(fields(mark.optional().nonoptional())).toEqual(['a']);
    expect(fields(mark.catch('x'))).toEqual(['a']);
    expect(fields(sensitive(z.string().optional()))).toEqual(['a']);
  });
  it('follows both sides of a pipe, preprocess and transform', () => {
    expect(fields(mark.pipe(z.string()))).toEqual(['a']);
    expect(fields(z.string().pipe(mark))).toEqual(['a']);
    expect(fields(z.preprocess((v) => String(v), mark))).toEqual(['a']);
    expect(fields(z.preprocess((v) => String(v), z.string()))).toEqual([]);
    expect(fields(mark.transform((v) => v.length))).toEqual(['a']);
  });
  it('follows unions, discriminated unions and intersections', () => {
    expect(fields(z.union([mark, z.literal('')]))).toEqual(['a']);
    expect(fields(z.union([z.string(), z.number()]))).toEqual([]);
    const dis = z.discriminatedUnion('k', [
      z.object({ k: z.literal('x'), v: mark }),
      z.object({ k: z.literal('y') }),
    ]);
    expect(fields(dis)).toEqual(['a.v']);
    expect(fields(z.intersection(z.object({ p: mark }), z.object({ q: z.string() })))).toEqual([
      'a.p',
    ]);
    expect(fields(z.intersection(z.object({ q: z.string() }), z.object({ p: mark })))).toEqual([
      'a.p',
    ]);
  });
  it('follows records, maps, sets, tuples and arrays', () => {
    expect(fields(z.record(z.string(), mark))).toEqual(['a.*']);
    expect(fields(z.map(z.string(), mark))).toEqual(['a.*']);
    expect(fields(z.set(mark))).toEqual(['a[]']);
    expect(fields(z.tuple([z.string(), mark]))).toEqual(['a[1]']);
    expect(fields(z.tuple([z.string()], mark))).toEqual(['a[]']);
    expect(fields(z.tuple([z.string()]))).toEqual([]);
    expect(fields(z.array(mark))).toEqual(['a[]']);
    expect(fields(z.promise(mark))).toEqual(['a']);
    expect(fields(mark.pipe(z.string()).optional().nullable())).toEqual(['a']);
  });
  it('walks nested objects and arrays of objects', () => {
    const nested = z.object({
      a: z.object({ b: sensitive(z.string()), c: z.string() }).optional(),
      list: z.array(z.object({ d: sensitive(z.string()) })),
      plain: z.array(z.string()),
    });
    expect(sensitiveFields(nested)).toEqual(['a.b', 'list[].d']);
  });
  it('follows a lazy getter, and survives a recursive schema', () => {
    expect(fields(z.lazy(() => mark))).toEqual(['a']);
    const tree: z.ZodType = z.object({
      secret: mark,
      child: z.lazy(() => tree).optional(),
    });
    expect(fields(tree)).toEqual(['a.secret']);
  });
  it('throws on a schema type it does not know instead of skipping it', () => {
    // Object.create returns `any`, so this builds a fake schema without a type assertion.
    const fake = (def: object): z.ZodType =>
      Object.create(z.string(), { _zod: { value: { def } } });
    expect(() => fields(fake({ type: 'bogus' }))).toThrow(/unhandled schema type "bogus"/);
    expect(() => fields(fake({}))).toThrow(/no type/);
    expect(() => fields(fake({ type: 'optional' }))).toThrow(/not a schema/);
    expect(() => fields(fake({ type: 'object' }))).toThrow(/no shape/);
  });
});
