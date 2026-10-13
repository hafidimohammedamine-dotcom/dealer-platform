import { describe, expect, it } from 'vitest';
import * as api from './index.js';
import { packageName } from './index.js';

describe('@dealer/contracts', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/contracts');
  });

  // Guard: the shared shapes are security-critical. Everything `index.ts` exports must be listed here, so a new
  // export cannot slip in unseen. Each new export is added to this list with its own tests
  // (integer cents, `dealer_id`, sensitive-field marks: see the other *.test.ts files).
  it('exports exactly the reviewed names', () => {
    expect(Object.keys(api).sort()).toEqual([
      'BasisPointsSchema',
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
      'DealTypeSchema',
      'DealerIdSchema',
      'DealerSchema',
      'EmailSchema',
      'EvidenceTextSchema',
      'Form8300Schema',
      'HttpsUrlSchema',
      'IdSchema',
      'IdentityVerificationSchema',
      'IsoDateSchema',
      'IsoDateTimeSchema',
      'JointIntentEvidenceSchema',
      'LENDER_DECISION_SENSITIVE_FIELDS',
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
      'SafeLongTextSchema',
      'SafeTextSchema',
      'TermMonthsSchema',
      'TimeZoneSchema',
      'VehicleSchema',
      'VehicleStatusSchema',
      'VinSchema',
      'isSensitive',
      'packageName',
      'sensitive',
      'sensitiveFields',
    ]);
  });

  it('keeps recordBase and contactFields internal', () => {
    expect(Object.keys(api)).not.toContain('recordBase');
    expect(Object.keys(api)).not.toContain('contactFields');
  });

  it('exports no database client or query helper (shapes only)', () => {
    const banned = /^(payload|getPayload\w*|db|pool|client|drizzle|knex|sql|query\w*)$/i;
    expect(Object.keys(api).filter((name) => banned.test(name))).toEqual([]);
  });
});
