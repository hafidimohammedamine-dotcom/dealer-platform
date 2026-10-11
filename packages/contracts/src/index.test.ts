import { describe, expect, it } from 'vitest';
import * as api from './index.js';
import { packageName } from './index.js';

describe('@dealer/contracts', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/contracts');
  });

  // Guard: the shared shapes are security-critical. Everything `index.ts` exports must be listed here, so a new
  // export cannot slip in unseen. The real tests arrive with the shapes (issue #3): each new export is added to
  // this list in that PR, with its own tests (integer cents, `dealer_id`, sensitive-field marks).
  it('exports exactly the reviewed names', () => {
    expect(Object.keys(api).sort()).toEqual(['packageName']);
  });

  it('exports no database client or query helper (shapes only)', () => {
    const banned = /^(payload|getPayload\w*|db|pool|client|drizzle|knex|sql|query\w*)$/i;
    expect(Object.keys(api).filter((name) => banned.test(name))).toEqual([]);
  });
});
