import { z } from 'zod';
import {
  EmailSchema,
  PhoneE164Schema,
  SafeTextSchema,
  TimeZoneSchema,
  recordBase,
} from './common.js';

/** A dealer is the tenant. Its own `dealer_id` is its `id`. */
export const DealerSchema = z
  .strictObject({
    ...recordBase,
    name: SafeTextSchema.min(1).max(200),
    /** IANA time zone, used for texting hours. */
    time_zone: TimeZoneSchema,
    phone: PhoneE164Schema.optional(),
    email: EmailSchema.optional(),
    active: z.boolean(),
  })
  .refine((d) => d.id === d.dealer_id, { message: 'dealer_id must equal id', path: ['dealer_id'] });
export type Dealer = z.infer<typeof DealerSchema>;
