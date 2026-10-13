import { describe, expect, it } from 'vitest';
import { parseEnvTemplate } from './repo.js';
import {
  dependenciesMetaProblems,
  lifecycleScriptProblems,
  lifecycleScripts,
  envPlaceholders,
  envValueProblems,
  optionalYarnrc,
  requiredYarnrc,
  trackedFileProblems,
  yarnrcProblems,
} from './checks.js';

const good = 'nodeLinker: node-modules\nenableTelemetry: false\nenableScripts: false\n';

describe('yarnrcProblems', () => {
  it('accepts exactly the allowed settings, with or without the optional ones', () => {
    expect(Object.keys(requiredYarnrc)).toEqual(['nodeLinker', 'enableScripts']);
    expect(Object.keys(optionalYarnrc)).toEqual(['enableTelemetry']);
    expect(yarnrcProblems(good)).toEqual([]);
    expect(yarnrcProblems(good.replace(/\n/g, '\r\n'))).toEqual([]);
    expect(yarnrcProblems(good.replace('enableTelemetry: false\n', ''))).toEqual([]);
  });

  it('accepts a comment-only header and the founder-approved built entries', () => {
    const header =
      '# founder-owned\n# dependenciesMeta:\n#   "<package>@<version>":\n#     built: true\n';
    expect(yarnrcProblems(`${header}${good}`)).toEqual([]);
    const built =
      'dependenciesMeta:\n  "esbuild@0.25.0":\n    built: true\n  "@scope/pkg@1.2.3":\n    built: true\n';
    expect(yarnrcProblems(`${good}${built}`)).toEqual([]);
  });

  it.each([
    [
      'a version range',
      '"esbuild@^0.25.0":\n    built: true',
      'key must be an exact package version: esbuild@^0.25.0',
    ],
    ['no version', '"esbuild":\n    built: true', 'key must be an exact package version: esbuild'],
    [
      'built false',
      '"esbuild@0.25.0":\n    built: false',
      'entry must be exactly { built: true }: esbuild@0.25.0',
    ],
    [
      'another key',
      '"esbuild@0.25.0":\n    built: true\n    optional: true',
      'entry must be exactly { built: true }: esbuild@0.25.0',
    ],
    [
      'not an object',
      '"esbuild@0.25.0": true',
      'entry must be exactly { built: true }: esbuild@0.25.0',
    ],
  ])('rejects a dependenciesMeta entry with %s', (_name, entry, message) => {
    expect(yarnrcProblems(`${good}dependenciesMeta:\n  ${entry}\n`)).toEqual([
      `.yarnrc.yml: dependenciesMeta ${message}`,
    ]);
    expect(yarnrcProblems(`${good}dependenciesMeta: []\n`)).toEqual([
      '.yarnrc.yml: dependenciesMeta must be an object',
    ]);
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

describe('lifecycleScriptProblems', () => {
  it('lists the install and pack scripts', () => {
    expect(lifecycleScripts).toEqual([
      'preinstall',
      'install',
      'postinstall',
      'prepare',
      'prepack',
      'postpack',
    ]);
  });

  it('accepts no scripts, and ordinary scripts', () => {
    expect(lifecycleScriptProblems({ name: 'x' }, 'package.json')).toEqual([]);
    const scripts = { build: 'tsc', test: 'vitest run', postinstallation: 'x' };
    expect(lifecycleScriptProblems({ scripts }, 'package.json')).toEqual([]);
  });

  it.each(lifecycleScripts)('flags %s', (name) => {
    const manifest = { scripts: { build: 'tsc', [name]: 'node evil.js' } };
    expect(lifecycleScriptProblems(manifest, 'a/package.json')).toEqual([
      `a/package.json: scripts.${name} must not exist (lifecycle scripts stay off)`,
    ]);
  });

  it('flags every lifecycle script in one file', () => {
    const scripts = { postinstall: 'a', prepare: 'b' };
    expect(lifecycleScriptProblems({ scripts }, 'p')).toHaveLength(2);
  });

  it('flags a bad shape', () => {
    expect(lifecycleScriptProblems([], 'p')).toEqual(['p: not a JSON object']);
    expect(lifecycleScriptProblems(undefined, 'p')).toEqual(['p: not a JSON object']);
    expect(lifecycleScriptProblems({ scripts: [] }, 'p')).toEqual(['p: scripts must be an object']);
  });
});

describe('envValueProblems', () => {
  // Built at run time so no secret-looking text sits in the source.
  const fake = ['not', 'a', 'real', 'value'].join('-');
  const message = (key: string): string =>
    `${key}: must be empty or exactly its placeholder in envPlaceholders`;
  const db = envPlaceholders.get('DATABASE_URL') ?? '';

  it('accepts empty values and every reviewed placeholder', () => {
    expect(envValueProblems(new Map(envPlaceholders))).toEqual([]);
    expect(
      envValueProblems(
        new Map([
          ['PAYLOAD_SECRET', ''],
          ['SENTRY_DSN', ''],
        ]),
      ),
    ).toEqual([]);
  });

  it('accepts the placeholders from a CRLF template', () => {
    const text = [...envPlaceholders].map(([key, value]) => `${key}=${value}\r\n`).join('');
    expect(envValueProblems(parseEnvTemplate(text))).toEqual([]);
  });

  it.each([
    ['a filled key', 'TELNYX_API_KEY', fake],
    ['a filled secret that looks like a URL', 'ROUTEONE_CLIENT_SECRET', db],
    ['a plain value on a variable with no placeholder', 'SENTRY_DSN', fake],
    ['another APP_ENV', 'APP_ENV', 'production'],
    ['a secret as the user name', 'REDIS_URL', `redis://${fake}@localhost:6379`],
    ['another user name', 'DATABASE_URL', db.replace('app_user', 'owner_user')],
    ['a real-looking password', 'DATABASE_URL', db.replace('change-me', fake)],
    ['another host', 'DATABASE_URL', db.replace('localhost', 'db.example.com')],
    ['another port', 'DATABASE_URL', db.replace('5432', '5433')],
    ['a secret in the path', 'DATABASE_URL', `${db}/${fake}`],
    ['a query string', 'DATABASE_URL', `${db}?a=b`],
    ['a secret in the query string', 'DATABASE_URL', `${db}?sslpassword=${fake}`],
    ['a fragment', 'DATABASE_URL', `${db}#${fake}`],
    ['an upper-case scheme', 'DATABASE_URL', db.replace('postgres', 'POSTGRES')],
    ['a value with = inside', 'PAYLOAD_PUBLIC_SERVER_URL', 'http://localhost:3000/?a=b'],
  ])('flags %s, without repeating the value', (_name, key, value) => {
    const problems = envValueProblems(new Map([[key, value]]));
    expect(problems).toEqual([message(key)]);
    expect(problems.join('\n')).not.toContain(fake);
  });

  it('flags every bad value in one template', () => {
    const text = `APP_ENV=dev\r\nDATABASE_URL=${db}?a=b\r\nSENTRY_DSN=a=b\r\n`;
    expect(envValueProblems(parseEnvTemplate(text))).toEqual([
      message('DATABASE_URL'),
      message('SENTRY_DSN'),
    ]);
  });
});

describe('trackedFileProblems', () => {
  it('accepts linted files, the root ESLint config and the founder-owned Yarn folders', () => {
    const paths = [
      'eslint.config.mjs',
      'package.json',
      'apps/admin/src/x/dist/y.ts',
      'services/intake/src/coverage/y.ts',
      'tests/e2e/src/dist/y.ts',
      'dist/notes.md',
      '.yarn/releases/yarn-4.18.1.cjs',
      '.yarn/plugins/plugin.cjs',
      'docs/eslint.config.md',
      'packages/data/src/.nx/x.ts',
      'services/ai/.yarn/x.js',
    ];
    expect(trackedFileProblems(paths)).toEqual([]);
  });

  it.each([
    'node_modules/pg/index.js',
    'services/ai/src/node_modules/helper/index.js',
    'apps/admin/dist/index.js',
    'services/intake/coverage/lcov.info',
    'tests/e2e/dist/x.js',
    'tests/e2e/coverage/lcov.info',
    'infra/checks/dist/deep/x.js',
    '.nx/cache/x.js',
    '.yarn/cache/x.zip',
    '.yarn/install-state.gz',
  ])('flags %s, committed in a folder lint skips', (path) => {
    expect(trackedFileProblems([path])).toEqual([`${path}: committed in a folder lint skips`]);
  });

  it.each([
    'apps/admin/src/dist/eslint.config.mjs',
    'services/ai/eslint.config.js',
    'packages/data/src/eslint.config.cjs',
    'eslint.config.ts',
    'apps/admin/eslint.config.mts',
    'services/ai/src/eslint.config.cts',
    '.eslintrc',
    'apps/admin/.eslintrc.json',
  ])('flags the ESLint config %s outside the repo root', (path) => {
    expect(trackedFileProblems([path])).toEqual([`${path}: ESLint config outside the repo root`]);
  });

  it('reports both problems for a config in a skipped folder', () => {
    expect(trackedFileProblems(['apps/admin/dist/eslint.config.mjs'])).toHaveLength(2);
  });
});
