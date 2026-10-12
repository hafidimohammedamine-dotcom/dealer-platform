import { describe, expect, it } from 'vitest';
import { packageName } from './index.js';

describe('@dealer/lenders', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/lenders');
  });
});
