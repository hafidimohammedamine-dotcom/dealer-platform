import { describe, expect, it } from 'vitest';
import { DealerSchema, VehicleSchema } from './index.js';
import { ok, without } from './test-samples.js';

describe('dealer', () => {
  it('has dealer_id equal to its own id', () => {
    expect(ok('dealer', { dealer_id: '00000000-0000-4000-8000-0000000000d2' })).toBe(false);
  });
  it('requires a time zone', () => {
    expect(DealerSchema.safeParse(without('dealer', 'time_zone')).success).toBe(false);
  });
  it('checks name, phone and email', () => {
    expect(ok('dealer', { name: '' })).toBe(false);
    expect(ok('dealer', { name: 'Müller Автo 車'.repeat(10) })).toBe(true);
    expect(ok('dealer', { name: 'x'.repeat(200) })).toBe(true);
    expect(ok('dealer', { name: 'x'.repeat(201) })).toBe(false);
    expect(ok('dealer', { phone: '555-0100' })).toBe(false);
    expect(ok('dealer', { email: `${'a'.repeat(250)}@example.com` })).toBe(false);
  });
});

describe('customer', () => {
  it('requires E.164 phone numbers and valid email', () => {
    expect(ok('customer', { phone: '555-0101' })).toBe(false);
    expect(ok('customer', { email: 'not-an-email' })).toBe(false);
    expect(ok('customer', { first_name: 'x'.repeat(101) })).toBe(false);
    expect(ok('customer', { first_name: '李小龍' })).toBe(true);
    expect(ok('customer', { first_name: '' })).toBe(false);
    expect(ok('customer', { last_name: '  ' })).toBe(false);
  });
  it('time zone is optional on a customer (it is required on a dealer)', () => {
    expect(ok('customer', {})).toBe(true);
  });
  it('limits the address fields', () => {
    const limits = { street: 200, city: 100, region: 50, postal_code: 20 };
    for (const [key, max] of Object.entries(limits)) {
      expect(ok('customer', { address: { [key]: 'x'.repeat(max) } }), key).toBe(true);
      expect(ok('customer', { address: { [key]: 'x'.repeat(max + 1) } }), key).toBe(false);
    }
    expect(ok('customer', { address: { city: 'Zürich 東京' } })).toBe(true);
    expect(ok('customer', { address: { city: 'a\u0000b' } })).toBe(false);
  });
  it('rejects unknown keys in the address', () => {
    expect(ok('customer', { address: { city: 'Austin', country: 'US' } })).toBe(false);
  });
});

describe('vehicle', () => {
  it('accepts only 17 character VINs without I, O or Q', () => {
    const bad = [
      '1HGCM82633A00435I',
      '1HGCM82633A00435O',
      '1HGCM82633A00435Q',
      '1hgcm82633a004352',
      '1HGCM82633A00435',
      '1HGCM82633A0043522',
      '1HGCM82633A00435 ',
      'SHORT',
      '',
    ];
    for (const vin of bad) {
      expect(ok('vehicle', { vin }), vin).toBe(false);
    }
  });
  it('limits the model year to 1900-2100', () => {
    expect(ok('vehicle', { year: 1899 })).toBe(false);
    expect(ok('vehicle', { year: 1900 })).toBe(true);
    expect(ok('vehicle', { year: 2100 })).toBe(true);
    expect(ok('vehicle', { year: 2101 })).toBe(false);
  });
  it('names the advertised price and no longer has price_cents', () => {
    expect(ok('vehicle', { price_cents: 100 })).toBe(false);
    expect(VehicleSchema.safeParse(without('vehicle', 'advertised_price_cents')).success).toBe(
      false,
    );
  });
  it('rejects a zero advertised price (bait pricing) and accepts one cent', () => {
    expect(ok('vehicle', { advertised_price_cents: 0 })).toBe(false);
    expect(ok('vehicle', { advertised_price_cents: -1 })).toBe(false);
    expect(ok('vehicle', { advertised_price_cents: 1 })).toBe(true);
  });
  it('limits and cleans the text fields', () => {
    expect(ok('vehicle', { make: 'Citroën 東' })).toBe(true);
    expect(ok('vehicle', { make: 'x'.repeat(51) })).toBe(false);
    expect(ok('vehicle', { model: 'x'.repeat(101) })).toBe(false);
    expect(ok('vehicle', { trim: 'x'.repeat(101) })).toBe(false);
    expect(ok('vehicle', { stock_number: 'x'.repeat(51) })).toBe(false);
    expect(ok('vehicle', { make: '' })).toBe(false);
    expect(ok('vehicle', { condition: 'mint' })).toBe(false);
    expect(ok('vehicle', { status: 'lost' })).toBe(false);
  });
});
