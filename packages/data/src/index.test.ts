import { describe, expect, it } from 'vitest';
import * as api from './index.js';
import { packageName } from './index.js';

describe('@dealer/data', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/data');
  });

  // Guard (CLAUDE.md, Payload rules 1 and 2): this package is security-critical. Everything `index.ts` exports must
  // be listed here, so a new export cannot slip in unseen. The real tests arrive with the tenant-safe helper
  // (issue #5): each new export is added to this list in that PR, with its own tests.
  it('exports exactly the reviewed names', () => {
    expect(Object.keys(api).sort()).toEqual(['packageName']);
  });

  it('does not export anything that hands out the Payload instance or a database client', () => {
    const banned = /^(payload|getPayload\w*|db|pool|client|drizzle|knex|sql|rawQuery)$/i;
    expect(Object.keys(api).filter((name) => banned.test(name))).toEqual([]);
  });
});
