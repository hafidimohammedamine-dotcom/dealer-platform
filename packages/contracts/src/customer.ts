import { z } from 'zod';
import { IdSchema, TimeZoneSchema, contactFields, recordBase } from './common.js';

export const CustomerSchema = z.strictObject({
  ...recordBase,
  ...contactFields,
  /** IANA time zone when known, for texting hours. */
  time_zone: TimeZoneSchema.optional(),
  address: z
    .strictObject({
      street: z.string().max(200).optional(),
      city: z.string().max(100).optional(),
      region: z.string().max(50).optional(),
      postal_code: z.string().max(20).optional(),
    })
    .optional(),
  /** Rep (user) who owns the customer. */
  owner_user_id: IdSchema.optional(),
});
export type Customer = z.infer<typeof CustomerSchema>;
