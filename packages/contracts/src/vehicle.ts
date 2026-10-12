import { z } from 'zod';
import { CentsNonNegativeSchema, ModelYearSchema, recordBase } from './common.js';

export const VinSchema = z
  .string()
  .regex(/^[A-HJ-NPR-Z0-9]{17}$/, 'VIN is 17 characters, no I, O or Q');
export const VehicleStatusSchema = z.enum(['available', 'hold', 'sold', 'wholesale']);

export const VehicleSchema = z.strictObject({
  ...recordBase,
  vin: VinSchema,
  stock_number: z.string().max(50).optional(),
  year: ModelYearSchema,
  make: z.string().min(1).max(50),
  model: z.string().min(1).max(100),
  trim: z.string().max(100).optional(),
  odometer_miles: z.number().int().nonnegative().optional(),
  condition: z.enum(['new', 'used', 'certified']),
  status: VehicleStatusSchema,
  /**
   * The only price the AI may quote, in integer cents. It must include every dealer charge (doc fee, dealer
   * add-ons and the like) except tax, title and registration (OAC 109:4-3-16). Do not store a price that leaves a
   * dealer charge out.
   */
  advertised_price_cents: CentsNonNegativeSchema,
});
export type Vehicle = z.infer<typeof VehicleSchema>;
