import { describe, expect, it } from 'vitest';
import {
  dependenciesMetaProblems,
  envValueProblems,
  requiredYarnrc,
  yarnrcProblems,
} from './checks.js';

const good = 'nodeLinker: node-modules\nenableTelemetry: false\nenableScripts: false\n';

describe('yarnrcProblems', () => {
  it('accepts exactly the allowed settings', () => {
    expect(Object.keys(requiredYarnrc)).toEqual(['nodeLinker', 'enableTelemetry', 'enableScripts']);
    expect(yarnrcProblems(good)).toEqual([]);
    expect(yarnrcProblems(good.replace(/\n/g, '\r\n'))).toEqual([]);
  });

  it('catches scripts turned on, missing or commented out', () => {
    const on = good.replace('enableScripts: false', 'enableScripts: true');
    expect(yarnrcProblems(on)).toEqual(['.yarnrc.yml: enableScripts must be false']);
    const off = good.replace('enableScripts: false', '# enableScripts: false');
    expect(yarnrcProblems(off)).toEqual(['.yarnrc.yml: enableScripts must be false']);
    const quoted = good.replace('enableScripts: false', "enableScripts: 'false'");
    expect(yarnrcProblems(quoted)).toEqual(['.yarnrc.yml: enableScripts must be false']);
  });

  it('catches a later duplicate that turns scripts back on', () => {
    expect(yarnrcProblems(`${good}enableScripts: true\n`)).toEqual([
      '.yarnrc.yml: not valid YAML (or a key appears twice)',
    ]);
  });

  it.each([
    'npmRegistryServer: "https://registry.example.com"',
    'npmScopes:\n  dealer:\n    npmRegistryServer: "https://registry.example.com"',
    'enableStrictSsl: false',
    'httpsCaFilePath: ./ca.pem',
    'unsafeHttpWhitelist:\n  - example.com',
    'httpProxy: "http://localhost:8080"',
    'yarnPath: .yarn/releases/other.cjs',
    'plugins:\n  - path: .yarn/plugins/x.cjs',
    'packageExtensions: {}',
  ])('rejects the extra setting %s', (extra) => {
    const key = extra.split(':')[0];
    expect(yarnrcProblems(`${good}${extra}\n`)).toEqual([
      `.yarnrc.yml: setting not allowed: ${key}`,
    ]);
  });

  it('catches changed values of the other settings', () => {
    expect(yarnrcProblems(good.replace('node-modules', 'pnp'))).toEqual([
      '.yarnrc.yml: nodeLinker must be node-modules',
    ]);
    expect(yarnrcProblems(good.replace('enableTelemetry: false', 'enableTelemetry: true'))).toEqual(
      ['.yarnrc.yml: enableTelemetry must be false'],
    );
  });

  it('rejects text that is not a settings mapping', () => {
    expect(yarnrcProblems('- a\n- b\n')).toEqual(['.yarnrc.yml: must be a mapping of settings']);
    expect(yarnrcProblems('')).toEqual(['.yarnrc.yml: must be a mapping of settings']);
    expect(yarnrcProblems('a: [1\n')).toEqual([
      '.yarnrc.yml: not valid YAML (or a key appears twice)',
    ]);
  });
});

describe('dependenciesMetaProblems', () => {
  it('accepts no dependenciesMeta, and entries that do not build', () => {
    expect(dependenciesMetaProblems({ name: 'x' }, 'package.json')).toEqual([]);
    const meta = { dependenciesMeta: { nx: { built: false }, other: { optional: true } } };
    expect(dependenciesMetaProblems(meta, 'package.json')).toEqual([]);
  });

  it('flags built: true', () => {
    const meta = { dependenciesMeta: { nx: { built: true }, 'esbuild@0.1.0': { built: true } } };
    expect(dependenciesMetaProblems(meta, 'a/package.json')).toEqual([
      'a/package.json: dependenciesMeta.nx.built must not be true',
      'a/package.json: dependenciesMeta.esbuild@0.1.0.built must not be true',
    ]);
  });

  it('flags a bad shape', () => {
    expect(dependenciesMetaProblems([], 'p')).toEqual(['p: not a JSON object']);
    expect(dependenciesMetaProblems({ dependenciesMeta: [] }, 'p')).toEqual([
      'p: dependenciesMeta must be an object',
    ]);
  });
});

describe('envValueProblems', () => {
  // Built at run time so no secret-looking text sits in the source.
  const fake = ['not', 'a', 'real', 'value'].join('-');

  it('flags a filled key, token or secret', () => {
    expect(envValueProblems(new Map([['TELNYX_API_KEY', fake]]))).toEqual([
      'TELNYX_API_KEY: must be empty',
    ]);
    expect(envValueProblems(new Map([['META_VERIFY_TOKEN', fake]]))).toHaveLength(1);
  });

  it('flags a non-local host and a real-looking password', () => {
    const url = ['postgres://u:', fake, '@db.example.com:5432/x'].join('');
    expect(envValueProblems(new Map([['DATABASE_URL', url]]))).toEqual([
      'DATABASE_URL: host must be localhost',
      'DATABASE_URL: password must be empty or change-me',
    ]);
  });

  it('reports a malformed URL by key only, without the value', () => {
    const bad = ['postgres://u:', fake, '@local host:99999/x'].join('');
    const problems = envValueProblems(new Map([['DATABASE_URL', bad]]));
    expect(problems).toEqual(['DATABASE_URL: invalid URL']);
    expect(problems.join('\n')).not.toContain(fake);
  });

  it('flags a plain value that is not APP_ENV=dev', () => {
    expect(envValueProblems(new Map([['SENTRY_DSN', fake]]))).toHaveLength(1);
    expect(envValueProblems(new Map([['APP_ENV', 'production']]))).toHaveLength(1);
  });

  it('accepts the allowed shapes', () => {
    const ok = new Map([
      ['APP_ENV', 'dev'],
      ['DATABASE_URL', 'postgres://u:change-me@localhost:5432/x'],
      ['REDIS_URL', 'redis://localhost:6379'],
      ['PAYLOAD_SECRET', ''],
    ]);
    expect(envValueProblems(ok)).toEqual([]);
  });
});
