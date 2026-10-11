import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  localApiMethods,
  payloadBanConfigs,
  payloadDbAllowedPaths,
  reflectiveMembers,
  requiredLocalApiOptions,
  requiredOneOfLocalApiOptions,
} from '../../../eslint.payload-ban.mjs';
import {
  ACCESS,
  MODULES,
  OVERRIDE,
  errors,
  errorsWith,
  eslint,
  eslintWith,
  inside,
  outside,
  root,
} from './test-helpers/lint.js';

/** Message ids of local/no-override-access, in order. */
const overrideMessages = async (code: string, file: string): Promise<string[]> => {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? [])
    .filter((message) => message.ruleId === OVERRIDE)
    .map((message) => message.messageId ?? '');
};

const full = 'overrideAccess: false, depth: 0, versions: false, user';

describe('overrideAccess is only ever the literal false, everywhere', () => {
  const files = [outside, inside, 'apps/admin/src/x.ts', 'tests/e2e/x.ts'];

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
  it('requires overrideAccess, depth and versions, and a user or req', () => {
    expect(requiredLocalApiOptions).toEqual(['overrideAccess', 'depth', 'versions']);
    expect(requiredOneOfLocalApiOptions).toEqual(['user', 'req']);
  });

  it.each(localApiMethods)('accepts a complete literal for %s', async (method) => {
    const code = `db.${method}({ collection: 'leads', ${full} });\n`;
    expect(await errors(code, inside)).toEqual([]);
  });

  it.each(localApiMethods)('flags %s with overrideAccess omitted', async (method) => {
    const code = `db.${method}({ collection: 'leads', depth: 0, versions: false, user });\n`;
    expect(await errors(code, inside)).toEqual([OVERRIDE]);
  });

  it('flags each missing option', async () => {
    const some = 'overrideAccess: false, depth: 0, versions: false, user';
    for (const missing of ['overrideAccess: false, ', 'depth: 0, ', 'versions: false, ', 'user']) {
      const code = `db.find({ ${some.replace(missing, '')} });\n`;
      expect(await errors(code, inside), code).toEqual([OVERRIDE]);
    }
    expect(await errors('db.find({});\n', inside)).toEqual([
      OVERRIDE,
      OVERRIDE,
      OVERRIDE,
      OVERRIDE,
    ]);
  });

  it('accepts req instead of user, and flags a user or req that is null or undefined', async () => {
    const base = 'overrideAccess: false, depth: 0, versions: false';
    expect(await errors(`db.find({ ${base}, req });\n`, inside)).toEqual([]);
    expect(await errors(`db.find({ ${base}, user, req });\n`, inside)).toEqual([]);
    for (const value of ['user: null', 'user: undefined', 'req: null', 'req: undefined']) {
      expect(await errors(`db.find({ ${base}, ${value} });\n`, inside), value).toEqual([OVERRIDE]);
    }
    expect(await errors(`db.find({ ${base}, user: null, req });\n`, inside)).toEqual([]);
    // Another option set to null is not a user.
    expect(await errors(`db.find({ ${base}, user, locale: null });\n`, inside)).toEqual([]);
  });

  it('flags showHiddenFields unless it is the literal false', async () => {
    expect(await errors(`db.find({ ${full}, showHiddenFields: false });\n`, inside)).toEqual([]);
    for (const value of ['true', 'flag', '!x', '0']) {
      const code = `db.find({ ${full}, showHiddenFields: ${value} });\n`;
      expect(await overrideMessages(code, inside), code).toEqual(['showHidden']);
    }
    const code = `db.find({ ${full}, showHiddenFields });\n`;
    expect(await overrideMessages(code, inside)).toEqual(['showHidden']);
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
    expect(
      await errors('db.find.call(db, { depth: 0, versions: false, user });\n', inside),
    ).toEqual([OVERRIDE]);
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
      await errors(
        `db.find({ ['depth']: 0, overrideAccess: false, versions: false, user });\n`,
        inside,
      ),
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

describe('packages/data reads a Local API method only to call it directly', () => {
  // Each of these reaches a Local API method without a checkable options literal.
  const bypasses: [string, [string, string[]]][] = [
    ['destructured find', ['const { find } = payload; find({});', ['notCalled']]],
    ['renamed destructured find', ['const { find: f } = payload; f({});', ['notCalled']]],
    ['parameter destructure', ['function g({ find }) { return find({}); }', ['notCalled']]],
    ['find stored in a variable', ['const f = payload.find; f({});', ['notCalled']]],
    ['find passed as a value', ['run(payload.find);', ['notCalled']]],
    ['[payload.find][0](...)', ['[payload.find][0]({});', ['notCalled', 'dynamicKey']]],
    ['payload.find.apply', [`payload.find.apply(payload, [{ ${full} }]);`, ['notCalled']]],
    ['payload.find.bind', [`payload.find.bind(payload)({ ${full} });`, ['notCalled']]],
    ['payload.find.call.bind', ['payload.find.call.bind(payload)({});', ['notCalled']]],
    ['new payload.find', [`new payload.find({ ${full} });`, ['notCalled']]],
    [
      'Reflect.apply(payload.find, ...)',
      ['Reflect.apply(payload.find, payload, [{}]);', ['reflection', 'notCalled']],
    ],
    ['Reflect.get then call', ["Reflect.get(payload, 'find')({});", ['reflection']]],
    ['globalThis.Reflect', ["globalThis.Reflect.get(payload, 'find');", ['reflection']]],
    ["globalThis['Reflect']", ["globalThis['Reflect'].get(payload, 'find');", ['reflection']]],
    ['Object.values', ['Object.values(payload);', ['reflection']]],
    ['Object.entries', ['Object.entries(payload);', ['reflection']]],
    [
      'Object.getOwnPropertyDescriptor',
      ["Object.getOwnPropertyDescriptor(proto, 'find');", ['reflection']],
    ],
    [
      'Object.getOwnPropertyDescriptors',
      ['Object.getOwnPropertyDescriptors(proto);', ['reflection']],
    ],
    ['dynamic key read', ['const f = payload[name]; f({});', ['dynamicKey']]],
    ['numeric key read', ['const f = methods[3]; f({});', ['dynamicKey']]],
    ['dynamic destructure', ['const { [name]: f } = payload; f({});', ['dynamicKey']]],
    ['payload.db.drizzle.execute', ['payload.db.drizzle.execute(sql);', ['rawDb']]],
    ['req.payload.db', ['req.payload.db.drizzle.execute(sql);', ['rawDb']]],
    ["payload['db']", ["payload['db'].drizzle.execute(sql);", ['rawDb']]],
    ['destructured db', ['const { db } = payload; void db;', ['rawDb']]],
  ];

  it.each(bypasses)('flags %s', async (_, [code, ids]) => {
    expect((await overrideMessages(code, inside)).sort()).toEqual([...ids].sort());
  });

  it('bans every reflective member name', () => {
    expect(reflectiveMembers).toEqual([
      'values',
      'entries',
      'getOwnPropertyDescriptor',
      'getOwnPropertyDescriptors',
    ]);
  });

  it('allows direct calls, .call with a full literal, fixed string keys and other members', async () => {
    const code = [
      `payload.find({ ${full} });`,
      `await payload?.find({ ${full} });`,
      `payload.find!({ ${full} });`,
      `payload.find.call(payload, { ${full} });`,
      `(await payload.find).call(payload, { ${full} });`,
      `payload['find']({ ${full} });`,
      'void payload.logger;',
      'const { collection, where } = args; void collection; void where;',
      'rows.at(0);',
      '',
    ].join('\n');
    expect(await overrideMessages(code, inside)).toEqual([]);
  });

  it('allows payload.db in no file until a reviewed one is listed', async () => {
    expect(payloadDbAllowedPaths).toEqual([]);
    const file = 'packages/data/src/tenant-transaction.ts';
    expect(await overrideMessages('payload.db.drizzle.execute(sql);\n', file)).toEqual(['rawDb']);
  });

  it('allows payload.db in a listed file, with every other check still on', async () => {
    const file = 'packages/data/src/tenant-transaction.ts';
    const listed = eslintWith(
      payloadBanConfigs({ overrideAccessAllowed: [], payloadDbAllowed: [file] }),
    );
    const messages = async (code: string, path: string): Promise<string[]> => {
      const [result] = await listed.lintText(code, { filePath: join(root, path) });
      return (result?.messages ?? [])
        .filter((message) => message.ruleId === OVERRIDE)
        .map((message) => message.messageId ?? '');
    };
    expect(await messages('payload.db.drizzle.execute(sql);\n', file)).toEqual([]);
    expect(await messages('const { db } = payload; void db;\n', file)).toEqual([]);
    expect(await messages('const { find } = payload; void find;\n', file)).toEqual(['notCalled']);
    expect(await messages('payload.find({});\n', file)).toHaveLength(4);
    expect(await messages('payload.db.find({});\n', 'packages/data/src/other.ts')).toEqual([
      'rawDb',
      'missing',
      'missing',
      'missing',
      'missingOneOf',
    ]);
  });

  it('does not apply these checks outside packages/data (the instance rule covers them there)', async () => {
    const code = 'const { find } = x; Object.values(x); void x.db; void rows[0];\n';
    expect(await overrideMessages(code, outside)).toEqual([]);
  });
});

// Outside packages/data only a static `overrideAccess` key is looked for. A dynamic key or a spread is not
// flagged by this rule on purpose: `overrideAccess` only matters to a Local API call, and these tests prove
// that outside packages/data every way to get hold of the Payload instance is already banned.
describe('dynamic keys and spreads outside packages/data', () => {
  const sneaky = ["f({ ['over' + 'rideAccess']: true });", 'f({ [k]: true });', 'f({ ...opts });'];

  it.each(sneaky)('is not flagged by this rule: %s', async (code) => {
    expect(await overrideMessages(`${code}\n`, outside)).toEqual([]);
  });

  it('cannot reach a Local API call, because the instance is banned everywhere else', async () => {
    const reaches = [
      'payload.find({ ...opts });',
      'req.payload.find({ [k]: true });',
      'const p = req[k]; p.find({ ...opts });',
      'const { payload } = req; payload.find({});',
      'Object.values(req);',
      'Object.assign({}, req);',
      'Reflect.get(req, k);',
      'const p = await getPayload({}); p.find({});',
    ];
    for (const code of reaches) expect(await errors(`${code}\n`, outside), code).toContain(ACCESS);
    for (const code of [
      "import { getPayload } from 'payload'; void getPayload;",
      "import pg from 'pg'; void pg;",
      "await import('pay' + 'load');",
      "process.getBuiltinModule('node:vm');",
      "import vm from 'node:vm'; void vm;",
    ]) {
      expect(await errors(`${code}\n`, outside), code).toContain(MODULES);
    }
  });

  it('is checked with the same config for the system-job files', async () => {
    const listed = eslintWith(payloadBanConfigs({ overrideAccessAllowed: [outside] }));
    expect(await errorsWith(listed, 'f({ overrideAccess: true });\n', outside)).toEqual([]);
    expect(
      await errorsWith(listed, 'f({ overrideAccess: true });\n', 'services/ai/src/x.ts'),
    ).toEqual([OVERRIDE]);
  });
});
