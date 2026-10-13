export const packageName = '@dealer/contracts';

export {
  BasisPointsSchema,
  CentsNonNegativeSchema,
  CentsSchema,
  DealerIdSchema,
  EmailSchema,
  EvidenceTextSchema,
  HttpsUrlSchema,
  IdSchema,
  IsoDateSchema,
  IsoDateTimeSchema,
  ModelYearSchema,
  PhoneE164Schema,
  SENSITIVE_META_KEY,
  SafeLongTextSchema,
  SafeTextSchema,
  TermMonthsSchema,
  TimeZoneSchema,
  isSensitive,
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
  DealTypeSchema,
  Form8300Schema,
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
  LENDER_DECISION_SENSITIVE_FIELDS,
  LenderDecisionSchema,
  LenderDecisionStatusSchema,
  type LenderDecision,
} from './lender-decision.js';
