import { describe, expect, it } from 'vitest';
import { LeadSourceSchema } from './index.js';
import { ok } from './test-samples.js';

describe('lead', () => {
  const v = (interest: string) => ({ vehicles: [{ interest }] });
  it('uses ADF vehicle interest values', () => {
    expect(ok('lead', v('test-drive'))).toBe(true);
    expect(ok('lead', v('window-shop'))).toBe(false);
  });
  it('limits the vehicle year and VIN of interest', () => {
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 1899 }] })).toBe(false);
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 2101 }] })).toBe(false);
    expect(ok('lead', { vehicles: [{ interest: 'buy', year: 2020 }] })).toBe(true);
    for (const vin of ['1hgcm82633a004352', '1HGCM82633A00435O', '1HGCM82633A00435']) {
      expect(ok('lead', { vehicles: [{ interest: 'buy', vin }] }), vin).toBe(false);
    }
  });
  it('limits and cleans the vehicle of interest text', () => {
    const car = (extra: Record<string, unknown>) => ({ vehicles: [{ interest: 'buy', ...extra }] });
    expect(ok('lead', car({ make: 'Citroën', model: '東京', trim: 'Sport', stock: 'A1' }))).toBe(
      true,
    );
    expect(ok('lead', car({ make: 'x'.repeat(51) }))).toBe(false);
    expect(ok('lead', car({ model: 'x'.repeat(101) }))).toBe(false);
    expect(ok('lead', car({ trim: 'x'.repeat(101) }))).toBe(false);
    expect(ok('lead', car({ stock: 'x'.repeat(51) }))).toBe(false);
    expect(ok('lead', car({ status: 'new' }))).toBe(true);
    expect(ok('lead', car({ status: 'broken' }))).toBe(false);
    expect(ok('lead', car({ surprise: 1 }))).toBe(false);
  });
  it('limits vehicles to 10 and comments to 5000 characters', () => {
    const one = { interest: 'buy' };
    expect(ok('lead', { vehicles: Array.from({ length: 10 }, () => one) })).toBe(true);
    expect(ok('lead', { vehicles: Array.from({ length: 11 }, () => one) })).toBe(false);
    expect(ok('lead', { comments: 'x'.repeat(5000) })).toBe(true);
    expect(ok('lead', { comments: 'x'.repeat(5001) })).toBe(false);
    expect(ok('lead', { comments: 'line 1\nline 2' })).toBe(true);
    expect(ok('lead', { comments: 'a\u0000b' })).toBe(false);
  });
  it('knows the lead statuses', () => {
    for (const status of ['new', 'contacted', 'appointment', 'working', 'won', 'lost']) {
      expect(ok('lead', { status }), status).toBe(true);
    }
    expect(ok('lead', { status: 'archived' })).toBe(false);
  });
  it('requires a contact with at least one non-empty field', () => {
    expect(ok('lead', { contact: {} })).toBe(false);
    expect(ok('lead', { contact: { last_name: 'Smith' } })).toBe(true);
    expect(ok('lead', { contact: { first_name: '' } })).toBe(false);
    expect(ok('lead', { contact: { first_name: '   ' } })).toBe(false);
    expect(ok('lead', { contact: { first_name: '', last_name: 'Smith' } })).toBe(false);
  });
  it('checks contact phone, email and names', () => {
    expect(ok('lead', { contact: { phone: '555-0101' } })).toBe(false);
    expect(ok('lead', { contact: { email: `${'a'.repeat(250)}@example.com` } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'x'.repeat(101) } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'Zoë 李' } })).toBe(true);
  });
  it('rejects unknown keys in the source and contact', () => {
    expect(ok('lead', { source: { provider_name: 'CarGurus', extra: 1 } })).toBe(false);
    expect(ok('lead', { contact: { phone: '+15555550101', extra: 1 } })).toBe(false);
  });
  it('limits and cleans the provider text', () => {
    const src = (extra: Record<string, unknown>) => LeadSourceSchema.safeParse(extra).success;
    expect(src({ provider_name: 'Autotrader 車' })).toBe(true);
    expect(src({ provider_name: 'x'.repeat(200) })).toBe(true);
    expect(src({ provider_name: 'x'.repeat(201) })).toBe(false);
    expect(src({ provider_name: '' })).toBe(false);
    expect(src({ provider_name: 'P', service: 'x'.repeat(201) })).toBe(false);
    expect(src({ provider_name: 'P', service: 'Ünïcode' })).toBe(true);
  });
  it('accepts only https provider URLs', () => {
    const url = (u: string) => LeadSourceSchema.safeParse({ provider_name: 'P', url: u }).success;
    expect(url('https://www.cargurus.com/lead')).toBe(true);
    expect(url('http://example.com')).toBe(false);
    expect(url('https://127.0.0.1')).toBe(false);
    // Display-only: a name that points inside a network still passes (see HttpsUrlSchema).
    expect(url('https://metadata.google.internal')).toBe(true);
  });
});
