import { describe, expect, it } from 'vitest';
import { allowedPayloadMembers } from '../../../eslint.payload-ban.mjs';
import { ACCESS, errors, inside, listOutside, messageIds, outside } from './test-helpers/lint.js';

// Every bypass any review round has found, plus close variants. Each must be flagged outside
// packages/data. The rule bans names and sources, so new spellings of a use are covered too.
const bypasses: [string, string][] = [
  ['payload.find', 'payload.find({});'],
  ['req.payload.create', 'req.payload.create({});'],
  ['nested ctx.req.payload.delete', 'ctx.req.payload.delete({});'],
  ['computed payload["update"]', "payload['update']({});"],
  ['computed req["payload"].count', "req['payload'].count({});"],
  ['template literal payload[`find`]', 'payload[`find`]({});'],
  ['template literal req[`payload`]', 'void req[`payload`];'],
  ['dynamic key payload[name]', 'payload[name]({});'],
  ['optional payload?.find', 'payload?.find({});'],
  ['optional req.payload?.create', 'req.payload?.create({});'],
  ['non-null payload!.find', 'payload!.find({});'],
  ['cast (payload as Payload).find', '(payload as Payload).find({});'],
  ['await getPayload() call', 'const p = await getPayload({}); void p;'],
  ['(await getPayload()).find', '(await getPayload({})).find({});'],
  ['getPayload().find', 'getPayload({}).find({});'],
  ['getPayloadHMR()', 'void getPayloadHMR({});'],
  ['payload.find.call', 'payload.find.call(payload, {});'],
  ['payload.find.apply', 'payload.find.apply(payload, [{}]);'],
  ['destructure from payload', 'const { find } = payload; void find;'],
  ['destructure from req.payload', 'const { find } = req.payload; void find;'],
  ['destructure payload from req', 'const { payload } = req; void payload;'],
  ['renamed destructure { payload: db }', 'const { payload: db } = req; db.find({});'],
  ['quoted destructure { "payload": db }', "const { 'payload': db } = req; db.find({});"],
  ['computed destructure { ["payload"]: db }', "const { ['payload']: db } = req; db.find({});"],
  ['dynamic destructure { [k]: db }', 'const { [k]: db } = req; db.find({});'],
  ['nested parameter destructure', 'function f({ req: { payload: db } }) { return db.find({}); }'],
  ['destructure getPayload', 'const { getPayload: gp } = await import(m); void gp;'],
  ['alias const p = req.payload', 'const p = req.payload; p.find({});'],
  ['alias of getPayload', 'const p = await getPayload({}); p.find({});'],
  ['typed parameter Payload', 'function f(p: Payload) { p.find({}); }'],
  ['typed BasePayload parameter', 'function f(p: BasePayload) { return p.create({}); }'],
  ['typed qualified parameter', 'function f(p: Types.Payload) { return p.create({}); }'],
  ['namespace P.getPayload', 'void P.getPayload({});'],
  ['dynamic key then call req[k].find', 'req[k].find({});'],
  ['dynamic key call req[k]()', 'req[k]();'],
  ['dynamic key chain req[a][b]', 'void req[a][b];'],
  ['dynamic key with await', '(await req[k]).find({});'],
  ['dynamic key non-null', 'req[k]!.find({});'],
  ['dynamic key destructure', 'const { find } = req[k]; void find;'],
  ['Reflect.get with a name', "Reflect.get(req, 'payload').find({});"],
  ['Reflect.get with a key', 'Reflect.get(req, k).find({});'],
  ['Reflect as a value', 'const r = Reflect; void r;'],
  ['dynamic key saved to a variable', 'const p = req[k]; p.find({});'],
  ['dynamic key saved, never called', 'const p = req[k]; void p;'],
  ['dynamic key read as an argument', 'run(req[k]);'],
  ['dynamic key read in an array', 'void [req[k]];'],
  ['dynamic key read with +=', 'x[k] += 1;'],
  ['dynamic key read with ++', 'x[k]++;'],
  ['dynamic key as a default value', 'const { a = req[k] } = x; void a;'],
  ['dynamic key read in a return', 'function f() { return req[k]; }'],
  ['dynamic key from a template', 'void req[`a${k}`];'],
  ['dynamic key from a concatenation', "void req['pay' + 'load'];"],
  ['negative index', 'void items[-1];'],
  ['Object.values', 'Object.values(req);'],
  ['Object.entries', 'Object.entries(req);'],
  ['Object.getOwnPropertyDescriptor', "Object.getOwnPropertyDescriptor(req, 'payload');"],
  ['Object.getOwnPropertyDescriptors', 'Object.getOwnPropertyDescriptors(req);'],
  ['Object.getOwnPropertyNames', 'Object.getOwnPropertyNames(req);'],
  ['Object.assign', 'Object.assign({}, req);'],
  ['Object.assign to read', 'Object.assign(target, req); void target;'],
  ['Object as a value', 'const O = Object; void O;'],
  ['globalThis.Object', 'globalThis.Object.values(req);'],
  ["globalThis['Object']", "globalThis['Object'].values(req);"],
  ['Object with a dynamic member', 'Object[name](req);'],
  ['destructured Object member', 'const { values } = Object; values(req);'],
  ['Object as a string', "void globalThis['Object'];"],
  ['Object in a type', 'declare const o: Object;'],
  ['payload passed to a function', 'helper(payload);'],
  ['payload as a class field', 'class A { #payload = 1; payload = 2; }'],
  ['payload as a JSX prop', 'export const V = () => <W payload={x} />;'],
  ['payload in a type', 'type T = { payload: unknown };'],
  ['payload as a string literal type', "type K = 'payload';"],
  ['payload.db.find (adapter)', 'payload.db.find({});'],
  ['req.payload.db.drizzle.execute', 'req.payload.db.drizzle.execute(sql);'],
  ['payload.forgotPassword', 'payload.forgotPassword({});'],
  ['payload.jobs.queue', 'payload.jobs.queue({});'],
  ['payload.sendEmail', 'payload.sendEmail({});'],
  ['payload.someBrandNewMethod', 'payload.someBrandNewMethod({});'],
  ['import getPayload', "import { getPayload } from 'payload'; void getPayload;"],
  ['renamed import of getPayload', "import { getPayload as gp } from 'payload'; void gp;"],
  ['type import of Payload', "import type { Payload } from 'payload';"],
  ['JSON.stringify with a replacer function', 'JSON.stringify(req, (k, v) => v);'],
  ['JSON.stringify with a replacer variable', 'JSON.stringify(req, replacer);'],
  ['JSON.stringify with a computed array', 'JSON.stringify(req, [a]);'],
  ['JSON.stringify with a replacer and space', 'JSON.stringify(req, fn, 2);'],
  ['JSON.parse with a reviver', 'JSON.parse(text, (k, v) => v);'],
  ['JSON.stringify with spread arguments', 'JSON.stringify(...args);'],
  ['JSON.stringify saved to a variable', 'const s = JSON.stringify; s(req, fn);'],
  ['JSON as a value', 'const J = JSON; J.stringify(req, fn);'],
  ['globalThis.JSON', 'globalThis.JSON.stringify(req, fn);'],
  ["globalThis['JSON']", "globalThis['JSON'].stringify(req, fn);"],
  ['JSON with a dynamic member', 'JSON[name](req, fn);'],
  ['JSON.stringify.call', 'JSON.stringify.call(JSON, req, fn);'],
  ['Local API call with collection', "void rows.find({ collection: 'leads' });"],
  ['Local API call with a global', "void rows.findGlobal({ global: 'settings' });"],
  ['quoted collection key', "void rows.count({ 'collection': 'leads' });"],
  ['shorthand collection key', 'void rows.create({ collection, data });'],
  ['bare destructured call with collection', "void find({ collection: 'leads' });"],
  ['.call with collection', "void rows.update.call(rows, { collection: 'leads' });"],
  ['cache read global._payload', 'void global._payload;'],
  ['cache read globalThis._payload', 'void globalThis._payload;'],
  ["cache read globalThis['_payload']", "void globalThis['_payload'];"],
  ['cache read with a template key', 'void globalThis[`_payload`];'],
  ['cache read through globalThis.global', 'void globalThis.global._cache;'],
  ['cache destructure', 'const { _payload: cache } = globalThis; void cache;'],
  ['any _ member of global', 'void global._something;'],
  ['any _ member destructured', 'const { _something } = global; void _something;'],
  ['any _ member assigned to a variable', 'let c; ({ _x: c } = globalThis); void c;'],
  ['cache Map form', "void global._payload.get('default');"],
  ['cache object form', 'void global._payload.payload.find({});'],
  ['_payload as a name', 'const _payload = 1; void _payload;'],
];

describe('local/no-payload-instance-access', () => {
  it.each(bypasses)('flags %s outside packages/data', async (_name, code) => {
    const file =
      code.includes('<') && code.includes('/>') ? outside.replace(/ts$/, 'tsx') : outside;
    expect(await errors(`${code}\n`, file)).toContain(ACCESS);
  });

  it.each(bypasses)('allows %s inside packages/data', async (_name, code) => {
    const file = code.includes('<') && code.includes('/>') ? inside.replace(/ts$/, 'tsx') : inside;
    expect(await errors(`${code}\n`, file)).not.toContain(ACCESS);
  });

  it('flags each use once', async () => {
    expect(await errors('const { payload } = req;\n', outside)).toEqual([ACCESS]);
    expect(await errors('payload.find({});\n', outside)).toEqual([ACCESS]);
  });

  it('keeps the member allow-list short', () => {
    expect(allowedPayloadMembers).toEqual(['logger']);
  });

  it('allows only the plain payload.logger form', async () => {
    const ok =
      "payload.logger.info('x');\nreq.payload.logger.info('x');\nreq.payload?.logger.child({});\n";
    expect(await errors(ok, outside)).toEqual([]);
    expect(await errors("payload['logger'].info('x');\n", outside)).toEqual([ACCESS]);
    expect(await errors("req['payload'].logger.info('x');\n", outside)).toEqual([ACCESS]);
    expect(await errors('const { logger } = req.payload; void logger;\n', outside)).toEqual([
      ACCESS,
    ]);
    expect(await errors("getPayload.logger.info('x');\n", outside)).toEqual([ACCESS]);
  });

  it('does not flag unrelated code', async () => {
    const code = [
      'const items = [1, 2];',
      'items.find(() => true);',
      'new Map([[1, 2]]).delete(1);',
      'const body = { data: 1, payloads: 2 };',
      'void items[0];',
      "void body['data'];",
      'void body[`data`];',
      'void items[0]?.toFixed(1);',
      'void Object.keys(body);',
      'void Object.freeze(body);',
      'void Object.fromEntries([]);',
      'void Object.create(null);',
      'const k = 0;',
      'items[k] = 3;',
      'delete items[k];',
      'const o = { Object: 1 };',
      'void o;',
      "import type { CollectionConfig } from 'payload';",
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('flags a probe in every workspace but packages/data, as .ts and .tsx', async () => {
    const workspaces = listOutside();
    expect(workspaces.length).toBeGreaterThan(10);
    for (const workspace of workspaces) {
      for (const ext of ['ts', 'tsx']) {
        const file = `${workspace}/src/probe.${ext}`;
        expect(await errors('void req.payload;\n', file), file).toEqual([ACCESS]);
      }
    }
    for (const file of [
      'apps/admin/src/views/crm/board.tsx',
      'apps/admin/payload.config.ts',
      'tests/e2e/leak.spec.ts',
      'packages/database/src/x.ts',
      'packages/data-extra/src/x.ts',
      'eslint.config.mjs',
    ]) {
      expect(await errors('void req.payload;\n', file), file).toEqual([ACCESS]);
    }
    expect(await errors('void req.payload;\n', 'packages/data/src/deep/dir/x.ts')).toEqual([]);
  });
});

describe('JSON.stringify and JSON.parse outside packages/data', () => {
  it('allow no second argument, null, or an array of fixed strings', async () => {
    const code = [
      'void JSON.stringify(body);',
      'void JSON.stringify(body, null);',
      'void JSON.stringify(body, null, 2);',
      "void JSON.stringify(body, ['id', `name`]);",
      'void JSON.stringify(body, []);',
      'void JSON.parse(text);',
      'void JSON.parse(text, null);',
      'void JSON.stringify?.(body);',
      'const o = { JSON: 1 };',
      'void o;',
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('flag an array with a name that is not fixed, or a hole', async () => {
    expect(await errors('JSON.stringify(body, [key]);\n', outside)).toEqual([ACCESS]);
    expect(await errors('JSON.stringify(body, [, "a"]);\n', outside)).toEqual([ACCESS]);
    expect(await errors('JSON.stringify(body, ...rest);\n', outside)).toEqual([ACCESS]);
  });

  it('are not restricted inside packages/data', async () => {
    expect(await errors('JSON.stringify(req, (k, v) => v);\n', inside)).toEqual([]);
  });
});

describe('global object members and Local API targets outside packages/data', () => {
  it('flag the Payload cache with the message for global members', async () => {
    expect(await messageIds('void global._payload;\n', outside)).toEqual(['globalMember', 'named']);
    expect(await messageIds("void globalThis['_cache'];\n", outside)).toEqual(['globalMember']);
    expect(await messageIds('const { _cache } = globalThis;\nvoid _cache;\n', outside)).toEqual([
      'globalMember',
    ]);
  });

  it('leave public members of global and private members of other objects alone', async () => {
    const code = [
      'void globalThis.process;',
      'void global.setTimeout;',
      'void other._private;',
      'const { process: p } = globalThis;',
      'const { _a } = other;',
      'const { _b } = nothing();',
      'let q; ({ _c: q } = other); ({ _d: q } = nothing());',
      'void p; void _a; void _b; void q;',
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('flag a Local API call that names a collection or global', async () => {
    expect(await messageIds("find({ collection: 'leads' });\n", outside)).toEqual(['localApiCall']);
  });

  it('leave other calls with those names alone', async () => {
    const code = [
      'rows.find((row) => row.id === 1);',
      "rows.find({ name: 'a' });",
      'rows.find({ ...opts });',
      'rows.find({ [k]: 1 });',
      "rows.find('collection');",
      'rows.find.call(rows, { id: 1 });',
      "other({ collection: 'a' });",
      "other.run({ collection: 'a' });",
      'rows.find();',
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('do not apply inside packages/data', async () => {
    const code = "global._payload; rows.find({ collection: 'leads' });\n";
    expect(await errors(code, inside)).not.toContain(ACCESS);
  });
});

describe('every non-fixed key read is flagged outside packages/data, writes are not', () => {
  it('flags a read saved to a variable', async () => {
    expect(await errors('const k = 0;\nconst v = items[k];\nvoid v;\n', outside)).toEqual([ACCESS]);
  });

  it('allows plain writes and delete', async () => {
    expect(await errors('items[k] = 3;\n', outside)).toEqual([]);
    expect(await errors('(items[k] as number) = 3;\n', outside)).toEqual([]);
    expect(await errors('delete items[k];\n', outside)).toEqual([]);
  });

  it('does not flag fixed keys', async () => {
    expect(await errors("void a['b']; void a[`c`]; void a[0]; void a[1];\n", outside)).toEqual([]);
  });

  it('does not apply inside packages/data', async () => {
    const code = 'const v = items[k];\nvoid Object.values(items);\nvoid v;\n';
    expect(await errors(code, inside)).not.toContain(ACCESS);
  });
});
