import { describe, expect, it } from 'vitest';
import { LeadSourceSchema, LeadStatusSchema } from './index.js';
import { ok } from './samples.test.js';

const v = (interest: string) => ({ vehicles: [{ interest }] });
const source = (patch: Record<string, unknown>) =>
  LeadSourceSchema.safeParse({ provider_name: 'P', ...patch }).success;

describe('lead', () => {
  it('uses ADF vehicle interest values', () => {
    expect(ok('lead', v('test-drive'))).toBe(true);
    expect(ok('lead', v('window-shop'))).toBe(false);
  });
  it('pins the lead statuses and rejects an unknown one', () => {
    expect(LeadStatusSchema.options).toEqual([
      'new',
      'contacted',
      'appointment',
      'working',
      'won',
      'lost',
    ]);
    expect(ok('lead', { status: 'lost' })).toBe(true);
    expect(ok('lead', { status: 'archived' })).toBe(false);
  });
  it('limits the vehicle year and VIN of interest', () => {
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 1899 }] })).toBe(false);
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 2101 }] })).toBe(false);
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 2020 }] })).toBe(true);
    for (const vin of ['1hgcm82633a004352', '1HGCM82633A00435O', '1HGCM82633A00435']) {
      expect(ok('lead', { vehicles: [{ interest: 'buy', vin }] }), vin).toBe(false);
    }
  });
  it('limits vehicle-of-interest text and accepts Unicode', () => {
    const car = (patch: Record<string, unknown>) => ({ vehicles: [{ interest: 'buy', ...patch }] });
    expect(ok('lead', car({ make: 'x'.repeat(51) }))).toBe(false);
    expect(ok('lead', car({ model: 'x'.repeat(101) }))).toBe(false);
    expect(ok('lead', car({ trim: 'x'.repeat(101) }))).toBe(false);
    expect(ok('lead', car({ stock: 'x'.repeat(51) }))).toBe(false);
    expect(ok('lead', car({ make: 'Citroën', model: '電動', trim: 'Édition', stock: 'Ä1' }))).toBe(
      true,
    );
    expect(ok('lead', car({ status: 'certified' }))).toBe(false);
    expect(ok('lead', car({ surprise: 1 }))).toBe(false);
  });
  it('limits vehicles to 10 and comments to 5000 characters', () => {
    const one = { interest: 'buy' };
    expect(ok('lead', { vehicles: Array.from({ length: 10 }, () => one) })).toBe(true);
    expect(ok('lead', { vehicles: Array.from({ length: 11 }, () => one) })).toBe(false);
    expect(ok('lead', { comments: 'x'.repeat(5000) })).toBe(true);
    expect(ok('lead', { comments: 'x'.repeat(5001) })).toBe(false);
  });
  it('requires a contact with at least one non-empty field', () => {
    expect(ok('lead', { contact: {} })).toBe(false);
    expect(ok('lead', { contact: { last_name: 'Smith' } })).toBe(true);
    expect(ok('lead', { contact: { first_name: '' } })).toBe(false);
    expect(ok('lead', { contact: { first_name: '', last_name: 'Smith' } })).toBe(false);
    expect(ok('lead', { contact: { surprise: 'x' } })).toBe(false);
  });
  it('checks contact phone, email and names', () => {
    expect(ok('lead', { contact: { phone: '555-0101' } })).toBe(false);
    expect(ok('lead', { contact: { email: `${'a'.repeat(250)}@example.com` } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'x'.repeat(101) } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'Zoë 李' } })).toBe(true);
  });
});

describe('lead source', () => {
  it('limits provider name (1-200), service (200) and accepts Unicode', () => {
    expect(source({ provider_name: '' })).toBe(false);
    expect(source({ provider_name: 'x'.repeat(200) })).toBe(true);
    expect(source({ provider_name: 'x'.repeat(201) })).toBe(false);
    expect(source({ service: 'x'.repeat(201) })).toBe(false);
    expect(source({ provider_name: 'Autohaus Zürich 車', service: 'Ünïcode' })).toBe(true);
  });
  it('rejects unknown keys', () => {
    expect(source({ surprise: 1 })).toBe(false);
    expect(ok('lead', { source: { provider_name: 'P', extra: 1 } })).toBe(false);
  });
  it('uses the shared https rule for the URL', () => {
    expect(source({ url: 'https://www.cargurus.com/lead' })).toBe(true);
    expect(source({ url: 'http://www.cargurus.com/lead' })).toBe(false);
    expect(source({ url: 'https://127.0.0.1' })).toBe(false);
  });
});
