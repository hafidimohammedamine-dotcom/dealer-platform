import { describe, expect, it } from 'vitest';
import { packageName } from './index.js';

describe('@dealer/platform', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/platform');
  });
});
