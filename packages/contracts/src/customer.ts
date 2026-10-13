import { z } from 'zod';
import { IdSchema, SafeTextSchema, TimeZoneSchema, contactFields, recordBase } from './common.js';

export const CustomerSchema = z.strictObject({
  ...recordBase,
  ...contactFields,
  /** IANA time zone when known, for texting hours. */
  time_zone: TimeZoneSchema.optional(),
  address: z
    .strictObject({
      street: SafeTextSchema.max(200).optional(),
      city: SafeTextSchema.max(100).optional(),
      region: SafeTextSchema.max(50).optional(),
      postal_code: SafeTextSchema.max(20).optional(),
    })
    .optional(),
  /** Rep (user) who owns the customer. */
  owner_user_id: IdSchema.optional(),
});
export type Customer = z.infer<typeof CustomerSchema>;
