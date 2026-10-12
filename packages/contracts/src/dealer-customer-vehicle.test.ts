import { describe, expect, it } from 'vitest';
import { VehicleSchema } from './index.js';
import { ok, without } from './samples.test.js';

describe('dealer', () => {
  it('has dealer_id equal to its own id', () => {
    expect(ok('dealer', { dealer_id: 'other' })).toBe(false);
  });
  it('checks name, phone and email', () => {
    expect(ok('dealer', { name: '' })).toBe(false);
    expect(ok('dealer', { name: 'x'.repeat(200) })).toBe(true);
    expect(ok('dealer', { name: 'x'.repeat(201) })).toBe(false);
    expect(ok('dealer', { name: 'Müller Автo 車'.repeat(10) })).toBe(true);
    expect(ok('dealer', { phone: '555-0100' })).toBe(false);
    expect(ok('dealer', { email: `${'a'.repeat(250)}@example.com` })).toBe(false);
  });
});

describe('customer', () => {
  it('requires E.164 phone numbers and valid email', () => {
    expect(ok('customer', { phone: '555-0101' })).toBe(false);
    expect(ok('customer', { email: 'not-an-email' })).toBe(false);
  });
  it('limits names to 1-100 characters and accepts Unicode', () => {
    expect(ok('customer', { first_name: '' })).toBe(false);
    expect(ok('customer', { first_name: 'x'.repeat(100) })).toBe(true);
    expect(ok('customer', { first_name: 'x'.repeat(101) })).toBe(false);
    expect(ok('customer', { last_name: 'x'.repeat(101) })).toBe(false);
    expect(ok('customer', { first_name: '李小龍' })).toBe(true);
  });
  it('limits address fields and rejects unknown address keys', () => {
    const full = { street: 'x'.repeat(200), city: 'x'.repeat(100), region: 'x'.repeat(50) };
    expect(ok('customer', { address: { ...full, postal_code: 'x'.repeat(20) } })).toBe(true);
    expect(ok('customer', { address: { street: 'x'.repeat(201) } })).toBe(false);
    expect(ok('customer', { address: { city: 'x'.repeat(101) } })).toBe(false);
    expect(ok('customer', { address: { region: 'x'.repeat(51) } })).toBe(false);
    expect(ok('customer', { address: { postal_code: 'x'.repeat(21) } })).toBe(false);
    expect(ok('customer', { address: { city: 'Austin', country: 'US' } })).toBe(false);
    expect(ok('customer', { address: { city: 'Zürich 東京' } })).toBe(true);
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
  it('limits text fields and accepts Unicode', () => {
    expect(ok('vehicle', { make: '' })).toBe(false);
    expect(ok('vehicle', { make: 'x'.repeat(50) })).toBe(true);
    expect(ok('vehicle', { make: 'x'.repeat(51) })).toBe(false);
    expect(ok('vehicle', { model: 'x'.repeat(101) })).toBe(false);
    expect(ok('vehicle', { trim: 'x'.repeat(101) })).toBe(false);
    expect(ok('vehicle', { stock_number: 'x'.repeat(51) })).toBe(false);
    expect(ok('vehicle', { make: 'Citroën', model: 'Ë-C4 電動', trim: 'Édition' })).toBe(true);
  });
  it('limits condition and status to the known values', () => {
    expect(ok('vehicle', { condition: 'certified' })).toBe(true);
    expect(ok('vehicle', { condition: 'broken' })).toBe(false);
    expect(ok('vehicle', { status: 'stolen' })).toBe(false);
    expect(ok('vehicle', { odometer_miles: -1 })).toBe(false);
    expect(ok('vehicle', { odometer_miles: 10.5 })).toBe(false);
  });
  it('names the advertised price, which must be above zero', () => {
    expect(ok('vehicle', { price_cents: 100 })).toBe(false);
    expect(VehicleSchema.safeParse(without('vehicle', 'advertised_price_cents')).success).toBe(
      false,
    );
    expect(ok('vehicle', { advertised_price_cents: 0 })).toBe(false);
    expect(ok('vehicle', { advertised_price_cents: 1 })).toBe(true);
    expect(ok('vehicle', { advertised_price_cents: -1 })).toBe(false);
  });
});
