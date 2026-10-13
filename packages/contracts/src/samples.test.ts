import { describe, expect, it } from 'vitest';
import {
  ConsentSchema,
  CreditAppSchema,
  CustomerSchema,
  DealSchema,
  DealerSchema,
  LeadSchema,
  LenderDecisionSchema,
  VehicleSchema,
} from './index.js';

/** Fake data shared by the contract tests. A `.test.ts` file, so it is left out of the build and the coverage count. */
export const T = '2026-10-12T14:30:00Z';
const base = { id: 'r1', dealer_id: 'd1', created_at: T, updated_at: T };

export const samples = {
  dealer: {
    schema: DealerSchema,
    value: {
      id: 'd1',
      dealer_id: 'd1',
      name: 'Fake Motors',
      time_zone: 'America/Chicago',
      phone: '+15555550100',
      email: 'a@example.com',
      active: true,
      created_at: T,
      updated_at: T,
    },
  },
  consent: {
    schema: ConsentSchema,
    value: {
      ...base,
      customer_id: 'c1',
      channel: 'sms',
      status: 'granted',
      purpose: 'marketing',
      address: '+15555550101',
      source: 'web_form',
      capture_context: { method: 'web_form', ip_address: '203.0.113.7' },
      evidence_text: 'I agree to receive texts.',
      recorded_at: T,
    },
  },
  customer: {
    schema: CustomerSchema,
    value: {
      ...base,
      first_name: 'Ann',
      email: 'ann@example.com',
      phone: '+15555550101',
      address: { city: 'Austin' },
    },
  },
  vehicle: {
    schema: VehicleSchema,
    value: {
      ...base,
      vin: '1HGCM82633A004352',
      year: 2020,
      make: 'Honda',
      model: 'Accord',
      condition: 'used',
      status: 'available',
      advertised_price_cents: 1999900,
    },
  },
  lead: {
    schema: LeadSchema,
    value: {
      ...base,
      request_date: T,
      status: 'new',
      source: { provider_name: 'CarGurus', url: 'https://example.com' },
      contact: { phone: '+15555550101' },
      vehicles: [{ interest: 'buy', vin: '1HGCM82633A004352' }],
      comments: 'Is it available?',
    },
  },
  deal: {
    schema: DealSchema,
    value: {
      ...base,
      customer_id: 'c1',
      vehicle_id: 'v1',
      deal_type: 'retail_installment',
      status: 'quote',
      selling_price_cents: 1999900,
      trade_allowance_cents: 500000,
      trade_payoff_cents: 400000,
      down_payment_cents: 100000,
      doc_fee_cents: 25000,
      title_fee_cents: 1500,
      registration_fee_cents: 3500,
      taxes_cents: 120000,
      tax_rate_basis_points: 650,
      tax_jurisdiction: 'Butler County, OH',
      taxable_amount_cents: 1499900,
      amount_financed_cents: 1900000,
      term_months: 72,
      apr_basis_points: 650,
      finance_charge_cents: 400000,
      total_of_payments_cents: 2300000,
      total_sale_price_cents: 2500000,
      monthly_payment_cents: 31000,
      first_payment_date: '2026-11-12',
      cash_received_cents: 10000,
    },
  },
  creditApp: {
    schema: CreditAppSchema,
    value: {
      ...base,
      deal_id: 'x1',
      customer_id: 'c1',
      applicant_name: 'Ann Test',
      ssn: '900-12-3456',
      date_of_birth: '1980-02-29',
      monthly_income_cents: 500000,
      bank_account_number: '12345678',
      bank_routing_number: '123456789',
      credit_pull_authorization: {
        evidence_text: 'I authorize a credit check.',
        authorized_at: T,
        method: 'electronic',
      },
      has_coapplicant: false,
    },
  },
  decision: {
    schema: LenderDecisionSchema,
    value: {
      ...base,
      deal_id: 'x1',
      credit_app_id: 'a1',
      request_id: 'q1',
      provider_message_id: 'msg-1',
      lender: 'FAKEBANK',
      status: 'approved',
      approved_amount_cents: 1900000,
      apr_basis_points: 650,
      term_months: 72,
      monthly_payment_cents: 31000,
      request_date: T,
      decided_at: T,
    },
  },
} as const;

/** True when the schema accepts `{ ...samples[name].value, ...patch }`. */
export function ok(name: keyof typeof samples, patch: Record<string, unknown>): boolean {
  const { schema, value } = samples[name];
  return schema.safeParse({ ...value, ...patch }).success;
}

/** The sample with some keys removed. */
export function without(name: keyof typeof samples, ...keys: string[]): Record<string, unknown> {
  const rest: Record<string, unknown> = { ...samples[name].value };
  for (const key of keys) {
    delete rest[key];
  }
  return rest;
}

describe('samples', () => {
  it('are valid, use fake SSNs and have two different helper outcomes', () => {
    for (const [name, { schema, value }] of Object.entries(samples)) {
      expect(schema.safeParse(value).success, name).toBe(true);
    }
    expect(samples.creditApp.value.ssn.startsWith('900-')).toBe(true);
    expect(ok('vehicle', { year: 1800 })).toBe(false);
    expect(without('vehicle', 'vin')).not.toHaveProperty('vin');
  });
});
