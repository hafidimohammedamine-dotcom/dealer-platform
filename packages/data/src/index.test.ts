import { describe, expect, it } from 'vitest';
import * as api from './index.js';

describe('@dealer/data exports', () => {
  // Guard (CLAUDE.md, Payload rules 1 and 2): this package is security-critical. Everything `index.ts` exports must
  // be listed here, so a new export cannot slip in unseen.
  it('exports exactly the reviewed names', () => {
    expect(Object.keys(api).sort()).toEqual([
      'DEFAULT_LIMIT',
      'MAX_DEPTH',
      'MAX_LIMIT',
      'MAX_PAGE',
      'NotFoundError',
      'TENANT_FIELD',
      'TenantAccessError',
      'forTenant',
      'packageName',
      'tenantIdsOf',
    ]);
  });

  it('does not export anything that hands out the Payload instance or a database client', () => {
    const banned = /^(payload|getPayload\w*|db|pool|client|drizzle|knex|sql|rawQuery)$/i;
    expect(Object.keys(api).filter((name) => banned.test(name))).toEqual([]);
  });
});
