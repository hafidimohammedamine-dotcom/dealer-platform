import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  CREDIT_APP_SENSITIVE_FIELDS,
  ConsentSchema,
  CreditAppSchema,
  CustomerSchema,
  DealSchema,
  DealerSchema,
  LeadSchema,
  LenderDecisionSchema,
  VehicleSchema,
  isSensitive,
  maskCreditApp,
  sensitiveFields,
} from './index.js';

const T = '2026-10-12T14:30:00Z';
const base = { id: 'r1', dealer_id: 'd1', created_at: T, updated_at: T };

const samples = {
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
      source: 'web_form',
      recorded_at: T,
      retain_until: '2031-10-12T14:30:00Z',
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
      price_cents: 1999900,
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
      status: 'quote',
      selling_price_cents: 1999900,
      down_payment_cents: 100000,
      fees_cents: 50000,
      taxes_cents: 120000,
      amount_financed_cents: 1900000,
      trade_equity_cents: -5000,
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
      has_coapplicant: false,
    },
  },
  decision: {
    schema: LenderDecisionSchema,
    value: {
      ...base,
      deal_id: 'x1',
      credit_app_id: 'a1',
      lender: 'FAKEBANK',
      status: 'approved',
      approved_amount_cents: 1900000,
      apr_basis_points: 650,
      term_months: 72,
      monthly_payment_cents: 31000,
      decided_at: T,
    },
  },
} as const;

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
      it('rejects unknown fields', () => {
        expect(schema.safeParse({ ...value, surprise: 1 }).success).toBe(false);
      });
      it('rejects non-UTC and non-ISO timestamps', () => {
        expect(
          schema.safeParse({ ...value, created_at: '2026-10-12T14:30:00-05:00' }).success,
        ).toBe(false);
        expect(schema.safeParse({ ...value, created_at: '10/12/2026' }).success).toBe(false);
      });
      it('keeps every money field as integer cents', () => {
        const moneyKeys = Object.keys(value).filter((k) => k.endsWith('_cents'));
        for (const key of moneyKeys) {
          expect(schema.safeParse({ ...value, [key]: 10.5 }).success, key).toBe(false);
        }
      });
    });
  }
});

describe('dealer', () => {
  it('has dealer_id equal to its own id', () => {
    expect(DealerSchema.safeParse({ ...samples.dealer.value, dealer_id: 'other' }).success).toBe(
      false,
    );
  });
});

describe('money', () => {
  it('rejects negative amounts where they make no sense but allows negative equity', () => {
    expect(VehicleSchema.safeParse({ ...samples.vehicle.value, price_cents: -1 }).success).toBe(
      false,
    );
    expect(DealSchema.safeParse({ ...samples.deal.value, trade_equity_cents: -1 }).success).toBe(
      true,
    );
  });
});

describe('vehicle and lead', () => {
  it('rejects a VIN with I, O or Q or the wrong length', () => {
    expect(
      VehicleSchema.safeParse({ ...samples.vehicle.value, vin: '1HGCM82633A00435I' }).success,
    ).toBe(false);
    expect(VehicleSchema.safeParse({ ...samples.vehicle.value, vin: 'SHORT' }).success).toBe(false);
  });
  it('uses ADF vehicle interest values', () => {
    const v = (interest: string) => ({ ...samples.lead.value, vehicles: [{ interest }] });
    expect(LeadSchema.safeParse(v('test-drive')).success).toBe(true);
    expect(LeadSchema.safeParse(v('window-shop')).success).toBe(false);
  });
  it('requires E.164 phone numbers', () => {
    expect(CustomerSchema.safeParse({ ...samples.customer.value, phone: '555-0101' }).success).toBe(
      false,
    );
  });
});

describe('credit app sensitive fields', () => {
  it('marks exactly SSN, DOB, income and bank fields', () => {
    expect(CREDIT_APP_SENSITIVE_FIELDS).toEqual([
      'bank_account_number',
      'bank_routing_number',
      'date_of_birth',
      'monthly_income_cents',
      'ssn',
    ]);
  });
  it('isSensitive is false for unmarked fields', () => {
    expect(isSensitive(z.string())).toBe(false);
    expect(isSensitive(CreditAppSchema.shape.applicant_name)).toBe(false);
    expect(sensitiveFields(CustomerSchema)).toEqual([]);
  });
  it('rejects malformed SSN and fake-range is used in samples', () => {
    expect(
      CreditAppSchema.safeParse({ ...samples.creditApp.value, ssn: '123456789' }).success,
    ).toBe(false);
    expect(samples.creditApp.value.ssn.startsWith('900-')).toBe(true);
  });
  it('masks every sensitive value, keeping only the last 4 of the SSN', () => {
    const app = CreditAppSchema.parse(samples.creditApp.value);
    const masked = maskCreditApp(app);
    const text = JSON.stringify(masked);
    expect(masked.ssn).toBe('***-**-3456');
    expect(text).not.toContain('900-12-3456');
    expect(text).not.toContain('1980-02-29');
    expect(text).not.toContain('12345678');
    expect(text).not.toContain('500000');
    expect(masked.applicant_name).toBe('Ann Test');
  });
});
