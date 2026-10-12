import { describe, expect, it } from 'vitest';
import * as api from './index.js';
import { packageName } from './index.js';

describe('@dealer/contracts', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/contracts');
  });

  // Guard: the shared shapes are security-critical. Everything `index.ts` exports must be listed here, so a new
  // export cannot slip in unseen. Each new export is added to this list with its own tests
  // (integer cents, `dealer_id`, sensitive-field marks: see shapes.test.ts).
  it('exports exactly the reviewed names', () => {
    expect(Object.keys(api).sort()).toEqual([
      'CREDIT_APP_SENSITIVE_FIELDS',
      'ConsentChannelSchema',
      'ConsentSchema',
      'ConsentStatusSchema',
      'CreditAppSchema',
      'CustomerSchema',
      'DealSchema',
      'DealStatusSchema',
      'DealerSchema',
      'LeadSchema',
      'LeadSourceSchema',
      'LeadStatusSchema',
      'LeadVehicleInterestSchema',
      'LenderDecisionSchema',
      'LenderDecisionStatusSchema',
      'SENSITIVE_META_KEY',
      'VehicleSchema',
      'VehicleStatusSchema',
      'VinSchema',
      'cents',
      'centsNonNegative',
      'dealerId',
      'email',
      'id',
      'isSensitive',
      'isoDate',
      'isoDateTime',
      'maskCreditApp',
      'packageName',
      'phoneE164',
      'recordBase',
      'sensitive',
      'sensitiveFields',
    ]);
  });

  it('exports no database client or query helper (shapes only)', () => {
    const banned = /^(payload|getPayload\w*|db|pool|client|drizzle|knex|sql|query\w*)$/i;
    expect(Object.keys(api).filter((name) => banned.test(name))).toEqual([]);
  });
});
