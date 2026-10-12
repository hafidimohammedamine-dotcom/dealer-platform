export const packageName = '@dealer/contracts';

export {
  AprBasisPointsSchema,
  CentsNonNegativeSchema,
  CentsSchema,
  DealerIdSchema,
  EmailSchema,
  IdSchema,
  IsoDateSchema,
  IsoDateTimeSchema,
  ModelYearSchema,
  PhoneE164Schema,
  SENSITIVE_META_KEY,
  TermMonthsSchema,
  TimeZoneSchema,
  contactFields,
  isSensitive,
  recordBase,
  sensitive,
  sensitiveFields,
} from './common.js';
export { DealerSchema, type Dealer } from './dealer.js';
export {
  ConsentCaptureContextSchema,
  ConsentChannelSchema,
  ConsentPurposeSchema,
  ConsentSchema,
  ConsentStatusSchema,
  type Consent,
} from './consent.js';
export { CustomerSchema, type Customer } from './customer.js';
export { VehicleSchema, VehicleStatusSchema, VinSchema, type Vehicle } from './vehicle.js';
export {
  LeadSchema,
  LeadSourceSchema,
  LeadStatusSchema,
  LeadVehicleInterestSchema,
  type Lead,
} from './lead.js';
export {
  DealSchema,
  DealStatusSchema,
  IdentityVerificationSchema,
  OfacScreeningSchema,
  OtherFeeSchema,
  type Deal,
} from './deal.js';
export {
  CREDIT_APP_SENSITIVE_FIELDS,
  CreditAppSchema,
  CreditPullAuthorizationSchema,
  JointIntentEvidenceSchema,
  type CreditApp,
} from './credit-app.js';
export {
  LenderDecisionSchema,
  LenderDecisionStatusSchema,
  type LenderDecision,
} from './lender-decision.js';
