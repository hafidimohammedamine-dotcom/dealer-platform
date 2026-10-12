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
      'AprBasisPointsSchema',
      'CREDIT_APP_SENSITIVE_FIELDS',
      'CentsNonNegativeSchema',
      'CentsSchema',
      'ConsentCaptureContextSchema',
      'ConsentChannelSchema',
      'ConsentPurposeSchema',
      'ConsentSchema',
      'ConsentStatusSchema',
      'CreditAppSchema',
      'CreditPullAuthorizationSchema',
      'CustomerSchema',
      'DealSchema',
      'DealStatusSchema',
      'DealerIdSchema',
      'DealerSchema',
      'EmailSchema',
      'IdSchema',
      'IdentityVerificationSchema',
      'IsoDateSchema',
      'IsoDateTimeSchema',
      'JointIntentEvidenceSchema',
      'LeadSchema',
      'LeadSourceSchema',
      'LeadStatusSchema',
      'LeadVehicleInterestSchema',
      'LenderDecisionSchema',
      'LenderDecisionStatusSchema',
      'ModelYearSchema',
      'OfacScreeningSchema',
      'OtherFeeSchema',
      'PhoneE164Schema',
      'SENSITIVE_META_KEY',
      'TermMonthsSchema',
      'TimeZoneSchema',
      'VehicleSchema',
      'VehicleStatusSchema',
      'VinSchema',
      'contactFields',
      'isSensitive',
      'packageName',
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
