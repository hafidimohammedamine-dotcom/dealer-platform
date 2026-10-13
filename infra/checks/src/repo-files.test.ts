import { describe, expect, it } from 'vitest';
import { envValueProblems } from './checks.js';
import { parseEnvTemplate, readText } from './repo.js';
import { root } from './test-helpers/root.js';

// Add a name here (and to .env.example) whenever a service needs a new variable.
const expectedEnvKeys = [
  'APP_ENV',
  'DATABASE_URL',
  'MIGRATION_DATABASE_URL',
  'DESKING_DATABASE_URL',
  'REDIS_URL',
  'PAYLOAD_SECRET',
  'PAYLOAD_PUBLIC_SERVER_URL',
  'FIELD_ENCRYPTION_KEY',
  'RESEND_API_KEY',
  'EMAIL_FROM',
  'RESEND_WEBHOOK_SECRET',
  'TELNYX_API_KEY',
  'TELNYX_PUBLIC_KEY',
  'TELNYX_MESSAGING_PROFILE_ID',
  'ELEVENLABS_API_KEY',
  'ELEVENLABS_WEBHOOK_SECRET',
  'ANTHROPIC_API_KEY',
  'META_APP_SECRET',
  'META_VERIFY_TOKEN',
  'META_PAGE_ACCESS_TOKEN',
  'ROUTEONE_CLIENT_ID',
  'ROUTEONE_CLIENT_SECRET',
  'ROUTEONE_WEBHOOK_SECRET',
  'DEALERTRACK_CLIENT_ID',
  'DEALERTRACK_CLIENT_SECRET',
  'DEALERTRACK_WEBHOOK_SECRET',
  'SENTRY_DSN',
];

describe('.env.example', () => {
  const vars = parseEnvTemplate(readText(root, '.env.example'));

  it('lists every expected variable and nothing else', () => {
    expect([...vars.keys()].sort()).toEqual([...expectedEnvKeys].sort());
  });

  it('has no real-looking secret values', () => {
    expect(envValueProblems(vars)).toEqual([]);
  });

  it('has every variable documented in docs/dev/env-vars.md', () => {
    const doc = readText(root, 'docs/dev/env-vars.md');
    const undocumented = [...vars.keys()].filter((key) => !doc.includes(`\`${key}\``));
    expect(undocumented).toEqual([]);
  });

  it('documents no variable that the template does not have', () => {
    const doc = readText(root, 'docs/dev/env-vars.md');
    const rows = [...doc.matchAll(/^\| `([A-Z][A-Z0-9_]+)` /gm)].map((match) => match[1]);
    expect(rows.sort()).toEqual([...vars.keys()].sort());
  });
});

describe('.prettierignore', () => {
  const lines = readText(root, '.prettierignore').split('\n');

  // `yarn format` (prettier --write .) must never rewrite a founder-only file.
  it.each([
    '.github',
    '.claude',
    'CLAUDE.md',
    'scripts/check-*',
    '.gitleaks.toml',
    '.gitleaksignore',
    '.yarnrc.yml',
    '.mcp.json',
    'CLAUDE.local.md',
  ])('skips the founder-only file %s', (entry) => {
    expect(lines).toContain(entry);
  });
});
