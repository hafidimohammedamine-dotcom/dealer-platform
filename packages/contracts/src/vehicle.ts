import { z } from 'zod';
import { CentsSchema, ModelYearSchema, SafeTextSchema, recordBase } from './common.js';

export const VinSchema = z
  .string()
  .regex(/^[A-HJ-NPR-Z0-9]{17}$/, 'VIN is 17 characters, no I, O or Q');
export const VehicleStatusSchema = z.enum(['available', 'hold', 'sold', 'wholesale']);

export const VehicleSchema = z.strictObject({
  ...recordBase,
  vin: VinSchema,
  stock_number: SafeTextSchema.max(50).optional(),
  year: ModelYearSchema,
  make: SafeTextSchema.min(1).max(50),
  model: SafeTextSchema.min(1).max(100),
  trim: SafeTextSchema.max(100).optional(),
  odometer_miles: z.number().int().nonnegative().optional(),
  condition: z.enum(['new', 'used', 'certified']),
  status: VehicleStatusSchema,
  /**
   * The only price the AI may quote, in integer cents. It must include every dealer charge (doc fee, dealer
   * add-ons and the like) except tax, title and registration (OAC 109:4-3-16). Do not store a price that leaves a
   * dealer charge out. Must be above zero: a $0 price is bait pricing and would be quoted by the AI.
   */
  advertised_price_cents: CentsSchema.positive(),
});
export type Vehicle = z.infer<typeof VehicleSchema>;
