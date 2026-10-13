import type { CollectionAfterChangeHook } from 'payload';
import { USERS_COLLECTION } from '@dealer/data';

/**
 * A deactivated user loses every login at once (Payload rule 14: session revoke). Payload checks each request's token
 * against the user's live `sessions`, and refresh needs one too, so clearing them ends every open login.
 *
 * Payload's `sessions` field cannot be updated through any API (its update access is `false`), so this hook is the one
 * reviewed place that writes it through the database adapter. The lint rule for Payload rule 1 allows the database for
 * this file only (eslint.config.mjs). It runs inside the update's transaction (`req`), so if it fails the deactivation
 * is rolled back with it.
 */
export const endSessionsOnDeactivate: CollectionAfterChangeHook = async ({
  doc,
  previousDoc,
  operation,
  req,
}) => {
  const deactivated =
    operation === 'update' && doc?.active === false && previousDoc?.active !== false;
  if (!deactivated) return doc;
  await req.payload.db.updateOne({
    collection: USERS_COLLECTION,
    id: doc.id,
    data: { sessions: [] },
    req,
    returning: false,
  });
  return doc;
};
