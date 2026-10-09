import { describe, expect, it } from 'vitest';
import {
  localApiMethods,
  overrideAccessAllowedPaths,
  requiredLocalApiOptions,
} from '../../../eslint.payload-ban.mjs';
import { OVERRIDE, errors, inside, outside } from './test-helpers/lint.js';

const full = 'overrideAccess: false, depth: 0, versions: false';

describe('overrideAccess is only ever the literal false, everywhere', () => {
  const files = [outside, inside, 'apps/admin/src/x.ts', 'tests/e2e/x.ts'];

  it('starts with an empty system-job allow-list', () => {
    expect(overrideAccessAllowedPaths).toEqual([]);
  });

  it.each(files)('flags true, shorthand and computed values in %s', async (file) => {
    for (const value of [
      'overrideAccess: true',
      "'overrideAccess': true",
      "['overrideAccess']: true",
      '[`overrideAccess`]: true',
      'overrideAccess: flag',
      'overrideAccess',
      'overrideAccess: !user',
      'overrideAccess: 0',
    ]) {
      const code = `f({ ${value} });\n`;
      expect(await errors(code, file), code).toEqual([OVERRIDE]);
    }
  });

  it.each(files)('allows the literal false in %s', async (file) => {
    expect(await errors('f({ overrideAccess: false });\n', file)).toEqual([]);
  });

  it('ignores destructuring', async () => {
    expect(await errors('const { overrideAccess: o } = opts; void o;\n', outside)).toEqual([]);
  });
});

describe('Local API calls in packages/data spell out every access option', () => {
  it('requires overrideAccess, depth and versions', () => {
    expect(requiredLocalApiOptions).toEqual(['overrideAccess', 'depth', 'versions']);
  });

  it.each(localApiMethods)('accepts a complete literal for %s', async (method) => {
    const code = `db.${method}({ collection: 'leads', ${full} });\n`;
    expect(await errors(code, inside)).toEqual([]);
  });

  it.each(localApiMethods)('flags %s with overrideAccess omitted', async (method) => {
    const code = `db.${method}({ collection: 'leads', depth: 0, versions: false });\n`;
    expect(await errors(code, inside)).toEqual([OVERRIDE]);
  });

  it('flags each missing option', async () => {
    expect(await errors('db.find({ overrideAccess: false, versions: false });\n', inside)).toEqual([
      OVERRIDE,
    ]);
    expect(await errors('db.find({ overrideAccess: false, depth: 0 });\n', inside)).toEqual([
      OVERRIDE,
    ]);
    expect(await errors('db.find({});\n', inside)).toEqual([OVERRIDE, OVERRIDE, OVERRIDE]);
  });

  it('flags options that are not one object literal', async () => {
    for (const code of [
      'db.find(opts);\n',
      'db.find();\n',
      `db.find.call(db, opts);\n`,
      `db.find.apply(db, [{ ${full} }]);\n`,
      `db.find.bind(db)({ ${full} });\n`,
      `db[method]({ ${full} });\n`,
    ]) {
      expect(await errors(code, inside), code).toContain(OVERRIDE);
    }
  });

  it('checks the options of .call', async () => {
    expect(await errors(`db.find.call(db, { ${full} });\n`, inside)).toEqual([]);
    expect(await errors('db.find.call(db, { depth: 0, versions: false });\n', inside)).toEqual([
      OVERRIDE,
    ]);
  });

  it('flags spreads, even with every option present', async () => {
    expect(await errors(`db.find({ ...opts, ${full} });\n`, inside)).toEqual([OVERRIDE]);
    expect(await errors(`db.find({ ${full}, ...opts });\n`, inside)).toEqual([OVERRIDE]);
  });

  it('flags computed keys unless the value is the literal false', async () => {
    expect(await errors(`db.find({ ${full}, [key]: true });\n`, inside)).toEqual([OVERRIDE]);
    expect(await errors(`db.find({ ${full}, [key]: value });\n`, inside)).toEqual([OVERRIDE]);
    expect(await errors(`db.find({ ${full}, [key]: false });\n`, inside)).toEqual([]);
    expect(
      await errors(`db.find({ ['depth']: 0, overrideAccess: false, versions: false });\n`, inside),
    ).toEqual([]);
  });

  it('does not treat callbacks or other methods as Local API calls', async () => {
    const code = 'rows.find((row) => row.id === 1);\nrows.filter(Boolean);\nf.call(null, x);\n';
    expect(await errors(code, inside)).toEqual([]);
  });

  it('does not require the options outside packages/data (the call itself is banned there)', async () => {
    expect(await errors('telnyx.messages.create({ to, text });\n', outside)).toEqual([]);
  });
});
