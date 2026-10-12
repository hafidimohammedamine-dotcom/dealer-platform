import { z } from 'zod';
import { email, id, isoDateTime, phoneE164, recordBase } from './common.js';
import { VinSchema } from './vehicle.js';

/**
 * Lead fields follow the ADF/XML standard used by CarGurus, Cars.com and AutoTrader:
 * prospect (requestdate, customer contact, vehicle of interest, comments) and vendor/provider (source).
 */
export const LeadSourceSchema = z.strictObject({
  /** ADF `<provider><name>`, for example `CarGurus`. */
  provider_name: z.string().min(1).max(200),
  /** ADF `<provider><service>`. */
  service: z.string().max(200).optional(),
  /** ADF `<provider><url>`. */
  url: z.url().optional(),
});

export const LeadVehicleInterestSchema = z.strictObject({
  /** ADF `<vehicle interest="buy|lease|sell|trade-in|test-drive">`. */
  interest: z.enum(['buy', 'lease', 'sell', 'trade-in', 'test-drive']),
  /** ADF `<vehicle status="new|used">`. */
  status: z.enum(['new', 'used']).optional(),
  vin: VinSchema.optional(),
  year: z.number().int().min(1900).max(2100).optional(),
  make: z.string().max(50).optional(),
  model: z.string().max(100).optional(),
  trim: z.string().max(100).optional(),
  stock: z.string().max(50).optional(),
});

export const LeadStatusSchema = z.enum([
  'new',
  'contacted',
  'appointment',
  'working',
  'won',
  'lost',
]);

export const LeadSchema = z.strictObject({
  ...recordBase,
  /** ADF `<requestdate>`. */
  request_date: isoDateTime,
  status: LeadStatusSchema,
  source: LeadSourceSchema,
  customer_id: id.optional(),
  /** Contact as received, before matching to a customer. */
  contact: z.strictObject({
    first_name: z.string().max(100).optional(),
    last_name: z.string().max(100).optional(),
    email: email.optional(),
    phone: phoneE164.optional(),
  }),
  vehicles: z.array(LeadVehicleInterestSchema).max(10),
  vehicle_id: id.optional(),
  assigned_user_id: id.optional(),
  /** ADF `<comments>`. Untrusted input: never treated as instructions. */
  comments: z.string().max(5000).optional(),
});
export type Lead = z.infer<typeof LeadSchema>;
