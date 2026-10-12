import { z } from 'zod';
import { email, isoDateTime, phoneE164, id } from './common.js';

/** A dealer is the tenant. Its own `dealer_id` is its `id`. */
export const DealerSchema = z
  .strictObject({
    id,
    dealer_id: id,
    name: z.string().min(1).max(200),
    /** IANA time zone, used for texting hours. */
    time_zone: z.string().min(1).max(64),
    phone: phoneE164.optional(),
    email: email.optional(),
    active: z.boolean(),
    created_at: isoDateTime,
    updated_at: isoDateTime,
  })
  .refine((d) => d.id === d.dealer_id, { message: 'dealer_id must equal id', path: ['dealer_id'] });
export type Dealer = z.infer<typeof DealerSchema>;
