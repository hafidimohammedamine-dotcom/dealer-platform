import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  CREDIT_APP_SENSITIVE_FIELDS,
  CentsNonNegativeSchema,
  ConsentSchema,
  CreditAppSchema,
  CustomerSchema,
  DealSchema,
  DealerSchema,
  IdSchema,
  IsoDateSchema,
  LeadSchema,
  LeadSourceSchema,
  LenderDecisionSchema,
  LenderDecisionStatusSchema,
  TimeZoneSchema,
  VehicleSchema,
  isSensitive,
  sensitive,
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
      purpose: 'marketing',
      address: '+15555550101',
      source: 'web_form',
      capture_context: { method: 'web_form', ip_address: '203.0.113.7' },
      evidence_text: 'I agree to receive texts.',
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
function ok(name: keyof typeof samples, patch: Record<string, unknown>): boolean {
  const { schema, value } = samples[name];
  return schema.safeParse({ ...value, ...patch }).success;
}

function without(name: keyof typeof samples, ...keys: string[]): Record<string, unknown> {
  const rest: Record<string, unknown> = { ...samples[name].value };
  for (const key of keys) {
    delete rest[key];
  }
  return rest;
}

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
      it('rejects an empty, over-long, null or numeric dealer_id', () => {
        for (const bad of ['', 'x'.repeat(65), null, 5]) {
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

describe('ids', () => {
  it('rejects ids that could climb out of a path or URL', () => {
    for (const bad of ['../x', 'a/b', '%2e%2e', 'a b', '', 'a\0b', 'x'.repeat(65)]) {
      expect(IdSchema.safeParse(bad).success, bad).toBe(false);
    }
    expect(IdSchema.safeParse('Dealer_01-a').success).toBe(true);
    expect(IdSchema.safeParse('x'.repeat(64)).success).toBe(true);
  });
});

describe('time zone', () => {
  it('accepts IANA names and rejects everything else', () => {
    for (const good of ['America/Chicago', 'America/Indiana/Indianapolis']) {
      expect(TimeZoneSchema.safeParse(good).success, good).toBe(true);
    }
    for (const bad of ['Mars/Olympus', 'CST', '', 'America/', '../etc', 'x/'.repeat(40)]) {
      expect(TimeZoneSchema.safeParse(bad).success, bad).toBe(false);
    }
    expect(ok('dealer', { time_zone: 'Mars/Olympus' })).toBe(false);
    expect(ok('customer', { time_zone: 'CST' })).toBe(false);
    expect(ok('customer', { time_zone: 'America/Chicago' })).toBe(true);
  });
});

describe('dealer', () => {
  it('has dealer_id equal to its own id', () => {
    expect(ok('dealer', { dealer_id: 'other' })).toBe(false);
  });
  it('checks name, phone and email', () => {
    expect(ok('dealer', { name: '' })).toBe(false);
    expect(ok('dealer', { name: 'Müller Автo 車'.repeat(10) })).toBe(true);
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
});

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
  it('limits vehicles to 10 and comments to 5000 characters', () => {
    const one = { interest: 'buy' };
    expect(ok('lead', { vehicles: Array.from({ length: 10 }, () => one) })).toBe(true);
    expect(ok('lead', { vehicles: Array.from({ length: 11 }, () => one) })).toBe(false);
    expect(ok('lead', { comments: 'x'.repeat(5000) })).toBe(true);
    expect(ok('lead', { comments: 'x'.repeat(5001) })).toBe(false);
  });
  it('requires a non-empty contact (decision: at least one contact field)', () => {
    expect(ok('lead', { contact: {} })).toBe(false);
    expect(ok('lead', { contact: { last_name: 'Smith' } })).toBe(true);
    expect(ok('lead', { contact: { first_name: '' } })).toBe(true);
  });
  it('checks contact phone, email and names', () => {
    expect(ok('lead', { contact: { phone: '555-0101' } })).toBe(false);
    expect(ok('lead', { contact: { email: `${'a'.repeat(250)}@example.com` } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'x'.repeat(101) } })).toBe(false);
    expect(ok('lead', { contact: { first_name: 'Zoë 李' } })).toBe(true);
  });
  it('accepts only https provider URLs on a public domain name', () => {
    const url = (u: string) => LeadSourceSchema.safeParse({ provider_name: 'P', url: u }).success;
    expect(url('https://www.cargurus.com/lead')).toBe(true);
    for (const bad of [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'http://example.com',
      'http://127.0.0.1',
      'https://127.0.0.1',
      'http://169.254.169.254/latest',
      'https://localhost',
      `https://example.com/${'a'.repeat(2048)}`,
    ]) {
      expect(url(bad), bad).toBe(false);
    }
  });
});

describe('deal', () => {
  const contracted = {
    status: 'contracted',
    identity_verification: { method: 'drivers_license', verified_at: T, verified_by_user_id: 'u1' },
    ofac_screening: { result: 'clear', screened_at: T },
  };
  it('has no lump-sum fees_cents or stored trade equity', () => {
    expect(ok('deal', { fees_cents: 50000 })).toBe(false);
    expect(ok('deal', { trade_equity_cents: 1 })).toBe(false);
  });
  it('splits fees into doc, title, registration and other', () => {
    for (const key of ['doc_fee_cents', 'title_fee_cents', 'registration_fee_cents']) {
      expect(DealSchema.safeParse(without('deal', key)).success, key).toBe(false);
    }
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: 9900 }] })).toBe(true);
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: 99.5 }] })).toBe(false);
    expect(ok('deal', { other_fees: [{ description: 'Etch', amount_cents: -1 }] })).toBe(false);
    expect(ok('deal', { other_fees: [{ description: '', amount_cents: 1 }] })).toBe(false);
  });
  it('records tax rate, jurisdiction and base (Butler County at 650)', () => {
    expect(ok('deal', { tax_rate_basis_points: 650, tax_jurisdiction: 'Butler County, OH' })).toBe(
      true,
    );
    expect(ok('deal', { tax_rate_basis_points: 650.5 })).toBe(false);
    expect(ok('deal', { tax_rate_basis_points: 10001 })).toBe(false);
    expect(ok('deal', { tax_jurisdiction: '' })).toBe(false);
  });
  it('limits term_months to 1-120 and apr to 0-10000 basis points', () => {
    for (const [term, good] of [
      [0, false],
      [1, true],
      [120, true],
      [121, false],
    ] as const) {
      expect(ok('deal', { term_months: term }), String(term)).toBe(good);
    }
    for (const [apr, good] of [
      [-1, false],
      [0, true],
      [10000, true],
      [10001, false],
    ] as const) {
      expect(ok('deal', { apr_basis_points: apr }), String(apr)).toBe(good);
    }
  });
  it('accepts a contracted deal with every disclosure, identity check and a clear OFAC result', () => {
    expect(ok('deal', contracted)).toBe(true);
    expect(ok('deal', { ...contracted, status: 'funded' })).toBe(true);
  });
  it('requires the Reg Z and tax fields once contracted', () => {
    for (const key of [
      'apr_basis_points',
      'finance_charge_cents',
      'total_of_payments_cents',
      'total_sale_price_cents',
      'monthly_payment_cents',
      'first_payment_date',
      'tax_rate_basis_points',
      'tax_jurisdiction',
      'taxable_amount_cents',
    ]) {
      const rest: Record<string, unknown> = { ...samples.deal.value, ...contracted };
      delete rest[key];
      expect(DealSchema.safeParse(rest).success, key).toBe(false);
      expect(DealSchema.safeParse({ ...rest, status: 'quote' }).success, `quote ${key}`).toBe(true);
    }
  });
  it('requires the identity check and a clear OFAC screening once contracted', () => {
    expect(ok('deal', { ...contracted, identity_verification: undefined })).toBe(false);
    expect(ok('deal', { ...contracted, ofac_screening: undefined })).toBe(false);
    for (const result of ['potential_match', 'confirmed_match']) {
      expect(
        ok('deal', { ...contracted, ofac_screening: { result, screened_at: T } }),
        result,
      ).toBe(false);
    }
    expect(ok('deal', { ofac_screening: { result: 'potential_match', screened_at: T } })).toBe(
      true,
    );
  });
  it('accepts cash over 1,000,000 cents (Form 8300) and rejects fractional cash', () => {
    expect(ok('deal', { cash_received_cents: 1500000 })).toBe(true);
    expect(ok('deal', { cash_received_cents: 1500000.5 })).toBe(false);
  });
});

describe('consent', () => {
  const revoked = {
    status: 'revoked',
    evidence_text: undefined,
    recorded_at: T,
    retain_until: '2031-10-12T14:30:00Z',
  };
  it('requires evidence_text when granted', () => {
    expect(ConsentSchema.safeParse(without('consent', 'evidence_text')).success).toBe(false);
    expect(ok('consent', { evidence_text: '' })).toBe(false);
    expect(ok('consent', revoked)).toBe(true);
  });
  it('stores the consented address and needs a customer or a lead', () => {
    expect(ConsentSchema.safeParse(without('consent', 'address')).success).toBe(false);
    expect(ok('consent', { address: '' })).toBe(false);
    expect(ConsentSchema.safeParse(without('consent', 'customer_id')).success).toBe(false);
    expect(
      ConsentSchema.safeParse({ ...without('consent', 'customer_id'), lead_id: 'l1' }).success,
    ).toBe(true);
    expect(ok('consent', { lead_id: 'l1' })).toBe(true);
  });
  it('allows a revoke-all record only when revoked', () => {
    expect(ok('consent', { ...revoked, channel: 'all' })).toBe(true);
    expect(ok('consent', { channel: 'all' })).toBe(false);
    expect(ok('consent', { channel: 'fax' })).toBe(false);
  });
  it('requires purpose and capture context, and accepts a rep id', () => {
    expect(ConsentSchema.safeParse(without('consent', 'purpose')).success).toBe(false);
    expect(ok('consent', { purpose: 'informational' })).toBe(true);
    expect(ok('consent', { purpose: 'spam' })).toBe(false);
    expect(ConsentSchema.safeParse(without('consent', 'capture_context')).success).toBe(false);
    expect(ok('consent', { capture_context: {} })).toBe(false);
    expect(ok('consent', { capture_context: { method: 'paper', ip_address: 'nope' } })).toBe(false);
    expect(
      ok('consent', { capture_context: { method: 'web_form', page_url: 'javascript:1' } }),
    ).toBe(false);
    expect(
      ok('consent', {
        capture_context: {
          method: 'web_form',
          ip_address: '2001:db8::1',
          page_url: 'https://example.com/x',
        },
        captured_by_user_id: 'u1',
      }),
    ).toBe(true);
  });
  it('keeps every record, granted or revoked, at least 5 years after recorded_at', () => {
    for (const patch of [{}, revoked]) {
      expect(ok('consent', { ...patch, retain_until: '2031-10-12T14:29:59Z' })).toBe(false);
      expect(ok('consent', { ...patch, retain_until: '2020-01-01T00:00:00Z' })).toBe(false);
      expect(ok('consent', { ...patch, retain_until: '2031-10-12T14:30:00Z' })).toBe(true);
      expect(ok('consent', { ...patch, retain_until: '2040-01-01T00:00:00Z' })).toBe(true);
    }
  });
});

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
  it('keeps the mark through optional, nullable, default and pipe wrappers', () => {
    const s = sensitive(z.string());
    expect(sensitiveFields(z.object({ a: s.optional() }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: s.nullable().optional() }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: s.default('x') }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: s.readonly() }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: s.pipe(z.string()) }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: sensitive(z.string().optional()) }))).toEqual(['a']);
    expect(sensitiveFields(z.object({ a: z.string().optional(), b: z.string() }))).toEqual([]);
  });
  it('walks nested objects and arrays of objects', () => {
    const nested = z.object({
      a: z.object({ b: sensitive(z.string()), c: z.string() }).optional(),
      list: z.array(z.object({ d: sensitive(z.string()) })),
      plain: z.array(z.string()),
    });
    expect(sensitiveFields(nested)).toEqual(['a.b', 'list[].d']);
  });
  it('reports the same set on derived credit app schemas', () => {
    const shape = CreditAppSchema.shape;
    const derived = [
      z.object(shape),
      z.object(shape).partial(),
      z.object(shape).extend({ extra: z.string() }),
      z.object(shape).pick({ ssn: true, applicant_name: true }),
      z.object({ nested: z.object(shape).optional() }),
    ];
    const expected = [
      CREDIT_APP_SENSITIVE_FIELDS,
      CREDIT_APP_SENSITIVE_FIELDS,
      CREDIT_APP_SENSITIVE_FIELDS,
    ];
    expect(sensitiveFields(derived[0]!)).toEqual(expected[0]);
    expect(sensitiveFields(derived[1]!)).toEqual(expected[1]);
    expect(sensitiveFields(derived[2]!)).toEqual(expected[2]);
    expect(sensitiveFields(derived[3]!)).toEqual(['ssn']);
    expect(sensitiveFields(derived[4]!)).toEqual(
      CREDIT_APP_SENSITIVE_FIELDS.map((n) => `nested.${n}`),
    );
  });
  it('rejects malformed SSN and uses the fake 900 range in the sample', () => {
    expect(ok('creditApp', { ssn: '123456789' })).toBe(false);
    expect(ok('creditApp', { ssn: '900-1-23456' })).toBe(false);
    expect(samples.creditApp.value.ssn.startsWith('900-')).toBe(true);
  });
});

describe('credit app authorization and co-applicant', () => {
  const joint = {
    has_coapplicant: true,
    coapplicant_customer_id: 'c2',
    joint_intent_evidence: { evidence_text: 'We apply together.', recorded_at: T },
  };
  it('requires the credit pull authorization with wording, time and method', () => {
    const cpa = samples.creditApp.value.credit_pull_authorization;
    expect(
      CreditAppSchema.safeParse(without('creditApp', 'credit_pull_authorization')).success,
    ).toBe(false);
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, evidence_text: '' } })).toBe(
      false,
    );
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, method: 'wink' } })).toBe(false);
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, authorized_at: 'x' } })).toBe(
      false,
    );
  });
  it('requires the co-applicant customer and joint intent evidence when has_coapplicant', () => {
    expect(ok('creditApp', joint)).toBe(true);
    expect(ok('creditApp', { ...joint, coapplicant_customer_id: undefined })).toBe(false);
    expect(ok('creditApp', { ...joint, joint_intent_evidence: undefined })).toBe(false);
    expect(ok('creditApp', { has_coapplicant: true })).toBe(false);
    expect(ok('creditApp', { ...joint, coapplicant_customer_id: '../c2' })).toBe(false);
  });
  it('rejects co-applicant fields when has_coapplicant is false', () => {
    expect(ok('creditApp', { coapplicant_customer_id: 'c2' })).toBe(false);
    expect(ok('creditApp', { joint_intent_evidence: joint.joint_intent_evidence })).toBe(false);
  });
});

describe('lender decision', () => {
  const declined = { status: 'declined', adverse_action_reasons: ['Insufficient income'] };
  it('pins the status names', () => {
    expect(LenderDecisionStatusSchema.options).toEqual([
      'pending',
      'approved',
      'conditional',
      'countered',
      'declined',
      'expired',
    ]);
  });
  it('requires request_id and keeps provider_message_id for idempotency', () => {
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_id')).success).toBe(false);
    expect(ok('decision', { request_id: '../q' })).toBe(false);
    expect(LenderDecisionSchema.safeParse(without('decision', 'provider_message_id')).success).toBe(
      true,
    );
    expect(ok('decision', { provider_message_id: '' })).toBe(false);
  });
  it('rejects decided_at before request_date and allows either one alone', () => {
    expect(ok('decision', { decided_at: '2026-10-12T14:29:59Z' })).toBe(false);
    expect(ok('decision', { decided_at: '2026-10-12T14:30:01Z' })).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'request_date')).success).toBe(true);
    expect(LenderDecisionSchema.safeParse(without('decision', 'decided_at')).success).toBe(true);
  });
  it('requires adverse action reasons when declined', () => {
    expect(ok('decision', { status: 'declined' })).toBe(false);
    expect(ok('decision', { status: 'declined', adverse_action_reasons: [] })).toBe(false);
    expect(ok('decision', declined)).toBe(true);
    expect(ok('decision', { status: 'countered' })).toBe(true);
  });
  it('carries credit score, bureau and notice date', () => {
    const extra = {
      ...declined,
      credit_score: 580,
      credit_bureau: 'experian',
      adverse_action_notice_sent_at: T,
    };
    expect(ok('decision', extra)).toBe(true);
    expect(ok('decision', { ...extra, credit_score: 299 })).toBe(false);
    expect(ok('decision', { ...extra, credit_score: 851 })).toBe(false);
    expect(ok('decision', { ...extra, credit_score: 580.5 })).toBe(false);
    expect(ok('decision', { ...extra, credit_bureau: 'acme' })).toBe(false);
    expect(ok('decision', { ...extra, adverse_action_notice_sent_at: 'yesterday' })).toBe(false);
  });
  it('limits conditions to 50 and term_months and apr to their ranges', () => {
    expect(ok('decision', { conditions: Array.from({ length: 50 }, () => 'x') })).toBe(true);
    expect(ok('decision', { conditions: Array.from({ length: 51 }, () => 'x') })).toBe(false);
    expect(ok('decision', { term_months: 0 })).toBe(false);
    expect(ok('decision', { term_months: 120 })).toBe(true);
    expect(ok('decision', { term_months: 121 })).toBe(false);
    expect(ok('decision', { apr_basis_points: -1 })).toBe(false);
    expect(ok('decision', { apr_basis_points: 0 })).toBe(true);
    expect(ok('decision', { apr_basis_points: 10000 })).toBe(true);
    expect(ok('decision', { apr_basis_points: 10001 })).toBe(false);
  });
});
