import { describe, expect, it } from 'vitest';
import {
  ACCESS,
  allErrors,
  errors,
  flatConfigOf,
  messageIds,
  outside,
} from './test-helpers/lint.js';

describe('flatConfigOf', () => {
  it('returns the default export when it is an array of config objects', () => {
    const config = [{ rules: {} }];
    expect(flatConfigOf({ default: config })).toBe(config);
  });

  it.each([
    ['a module that is not an object', 'nope'],
    ['a module without a default export', {}],
    ['a default export that is not an array', { default: { rules: {} } }],
    ['an array with an entry that is not an object', { default: [{}, 1] }],
  ])('throws for %s', (_name, module) => {
    expect(() => flatConfigOf(module)).toThrow('flat config array');
  });
});

describe('lint helpers', () => {
  it('report a parse error as parse-error', async () => {
    expect(await errors('const = ;\n', outside)).toEqual(['parse-error']);
    expect(await allErrors('const = ;\n', outside)).toEqual(['parse-error']);
  });

  it('list the message ids of the instance rule in order', async () => {
    expect(await messageIds('void req.payload;\n', outside)).toEqual(['named']);
    expect(await messageIds('void x;\n', outside)).toEqual([]);
    expect(ACCESS).toBe('local/no-payload-instance-access');
  });
});
