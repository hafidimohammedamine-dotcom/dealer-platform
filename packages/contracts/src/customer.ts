import { z } from 'zod';
import { email, id, phoneE164, recordBase } from './common.js';

export const CustomerSchema = z.strictObject({
  ...recordBase,
  first_name: z.string().max(100).optional(),
  last_name: z.string().max(100).optional(),
  email: email.optional(),
  phone: phoneE164.optional(),
  /** IANA time zone when known, for texting hours. */
  time_zone: z.string().max(64).optional(),
  address: z
    .strictObject({
      street: z.string().max(200).optional(),
      city: z.string().max(100).optional(),
      region: z.string().max(50).optional(),
      postal_code: z.string().max(20).optional(),
    })
    .optional(),
  /** Rep (user) who owns the customer. */
  owner_user_id: id.optional(),
});
export type Customer = z.infer<typeof CustomerSchema>;
