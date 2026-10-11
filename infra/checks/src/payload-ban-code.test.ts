import { describe, expect, it } from 'vitest';
import {
  codeConstructorMember,
  codeConstructorName,
} from '../../../eslint-rules/payload-lists.mjs';
import { CODE, errors, inside, outside } from './test-helpers/lint.js';

// Code can be built without `eval` or `new Function`: `x.constructor` is `Function` for any function.
const members = [
  'constructor',
  '__proto__',
  '__lookupGetter__',
  '__lookupSetter__',
  '__defineGetter__',
  '__defineSetter__',
];
// Built from parts: the ban also covers these names as exact strings, in this file too.
const functions = ['', 'Async', 'Generator', 'AsyncGenerator'].map((prefix) => `${prefix}Function`);

const memberForms = (name: string): string[] => [
  `void x.${name};`,
  `void x?.${name};`,
  `void x['${name}'];`,
  `void x[\`${name}\`];`,
  `void x.y.${name}.z;`,
  `const { ${name} } = x; void ${name};`,
  `const { ${name}: f } = x; void f;`,
  `const { '${name}': f } = x; void f;`,
  `const { [\`${name}\`]: f } = x; void f;`,
  `function g({ ${name}: f }) { return f; }`,
  `let f; ({ ${name}: f } = x); void f;`,
];

describe('constructor and prototype members', () => {
  it.each(members)(
    'bans %s as a member, computed string member and destructured key',
    async (name) => {
      for (const file of [outside, inside]) {
        for (const code of memberForms(name)) {
          expect(await errors(`${code}\n`, file), `${file} ${code}`).toEqual([CODE]);
        }
      }
    },
  );

  it('bans the two reviewed bypasses', async () => {
    for (const file of [outside, inside]) {
      const first = '({}).constructor.values(req);\n';
      const second = '(async () => {}).constructor(\'return import("payload")\')();\n';
      expect(await errors(first, file), first).toContain(CODE);
      expect(await errors(second, file), second).toContain(CODE);
    }
  });

  it('bans a constructor reached through the prototype chain', async () => {
    const code = 'void Object.getPrototypeOf(async function () {}).constructor;\n';
    expect(await errors(code, outside)).toContain(CODE);
  });

  it('does not flag a class constructor method or unrelated names', async () => {
    const code = [
      'class A {',
      '  constructor(private readonly n: number) { void n; }',
      '}',
      'class B extends A {',
      '  constructor() { super(1); }',
      '}',
      'interface I { constructor: unknown; Function: string }',
      'void x.constructors;',
      'void x.proto;',
      "void x['construct'];",
      'const { constructors } = x; void constructors;',
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
    expect(await errors(code, inside)).toEqual([]);
  });

  it('matches exactly the reviewed member names', () => {
    for (const name of members) expect(codeConstructorMember.test(name), name).toBe(true);
    for (const name of ['constructors', 'proto', '__proto', '__defineGetter', 'Constructor']) {
      expect(codeConstructorMember.test(name), name).toBe(false);
    }
  });
});

describe('function constructors', () => {
  const nameForms = (name: string): string[] => [
    `new ${name}('return 1');`,
    `${name}('return 1')();`,
    `const F = ${name}; void F;`,
    `void [${name}];`,
    `function f(a: ${name}) { return a; }`,
    `void globalThis.${name};`,
    `void global.${name};`,
    `void globalThis.globalThis.${name};`,
    `void globalThis['${name}'];`,
    `void globalThis[\`${name}\`];`,
    `const { ${name} } = globalThis; void ${name};`,
    `const { ${name}: F } = globalThis; void F;`,
    `void '${name}';`,
    `void \`${name}\`;`,
    `void Reflect.get(globalThis, '${name}');`,
  ];

  it.each(functions)('bans %s as an identifier, string or global member', async (name) => {
    for (const file of [outside, inside]) {
      for (const code of nameForms(name)) {
        const ids = await errors(`${code}\n`, file);
        expect(ids, `${file} ${code}`).toContain(CODE);
      }
    }
  });

  it('flags each of those forms once, not twice', async () => {
    for (const code of [
      'void globalThis.Function;',
      "void globalThis['Function'];",
      'const { Function } = globalThis; void 0;',
    ]) {
      const ids = (await errors(`${code}\n`, inside)).filter((id) => id === CODE);
      expect(ids, code).toHaveLength(1);
    }
  });

  it('allows a property that is merely called like one when it is not on the global object', async () => {
    const code = ['void x.Function;', 'void { Function: 1 };', 'void Types.Function;', ''].join(
      '\n',
    );
    expect(await errors(code, outside)).toEqual([]);
  });

  it('matches exactly the reviewed function names', () => {
    for (const name of functions) expect(codeConstructorName.test(name), name).toBe(true);
    for (const name of ['Functions', 'MyFunction', 'function', 'AsyncFunctions']) {
      expect(codeConstructorName.test(name), name).toBe(false);
    }
  });
});
