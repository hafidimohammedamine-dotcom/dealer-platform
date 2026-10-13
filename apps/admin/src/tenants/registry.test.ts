import { describe, expect, it } from 'vitest';
import { notTenantScopedAllowlist, tenantScopedCollections } from './registry.js';

describe('the collection registry', () => {
  it('lists no collection yet, and every entry has a slug', () => {
    expect(Array.isArray(tenantScopedCollections)).toBe(true);
    expect(tenantScopedCollections.every((c) => c.slug !== '')).toBe(true);
  });

  it('keeps the not-dealer-scoped allowlist short and free of repeats', () => {
    expect(notTenantScopedAllowlist.length).toBeLessThanOrEqual(5);
    expect(new Set(notTenantScopedAllowlist).size).toBe(notTenantScopedAllowlist.length);
  });
});
