import { describe, expect, it } from 'vitest';
import { samples } from './test-samples.js';

describe('every shape', () => {
  for (const [name, { schema, value }] of Object.entries(samples)) {
    describe(name, () => {
      it('accepts a valid record', () => {
        expect(schema.safeParse(value).success).toBe(true);
      });
      it('requires dealer_id', () => {
        const rest: Record<string, unknown> = { ...value };
        delete rest.dealer_id;
        expect(schema.safeParse(rest).success).toBe(false);
      });
      it('rejects an empty, over-long, null, numeric or non-UUID dealer_id', () => {
        for (const bad of ['', 'x'.repeat(65), null, 5, 'd1', '../x']) {
          expect(schema.safeParse({ ...value, dealer_id: bad }).success, String(bad)).toBe(false);
        }
      });
      it('rejects unknown fields', () => {
        expect(schema.safeParse({ ...value, surprise: 1 }).success).toBe(false);
      });
      it('rejects non-UTC and non-ISO timestamps', () => {
        expect(
          schema.safeParse({ ...value, created_at: '2026-10-12T14:30:00-05:00' }).success,
        ).toBe(false);
        expect(schema.safeParse({ ...value, created_at: '10/12/2026' }).success).toBe(false);
      });
      it('keeps every money field as a non-negative integer number of cents', () => {
        const moneyKeys = Object.keys(value).filter((k) => k.endsWith('_cents'));
        const bad = [10.5, Number.NaN, Infinity, -Infinity, Number.MAX_SAFE_INTEGER + 1, '100', -1];
        for (const key of moneyKeys) {
          for (const v of bad) {
            expect(schema.safeParse({ ...value, [key]: v }).success, `${key}=${String(v)}`).toBe(
              false,
            );
          }
        }
      });
    });
  }
});
