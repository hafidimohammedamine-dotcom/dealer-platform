export const packageName = '@dealer/contracts';

export {
  SENSITIVE_META_KEY,
  cents,
  centsNonNegative,
  dealerId,
  email,
  id,
  isSensitive,
  isoDate,
  isoDateTime,
  phoneE164,
  recordBase,
  sensitive,
  sensitiveFields,
} from './common.js';
export { DealerSchema, type Dealer } from './dealer.js';
export {
  ConsentChannelSchema,
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
export { DealSchema, DealStatusSchema, type Deal } from './deal.js';
export {
  CREDIT_APP_SENSITIVE_FIELDS,
  CreditAppSchema,
  maskCreditApp,
  type CreditApp,
} from './credit-app.js';
export {
  LenderDecisionSchema,
  LenderDecisionStatusSchema,
  type LenderDecision,
} from './lender-decision.js';
