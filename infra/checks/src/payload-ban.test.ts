import { join } from 'node:path';
import { ESLint } from 'eslint';
import { describe, expect, it } from 'vitest';
import { payloadDataMethods } from '../../../eslint.payload-ban.mjs';
import { findRepoRoot } from './repo.js';

const root = findRepoRoot();
const eslint = new ESLint({ cwd: root });

async function ruleIds(code: string, file: string): Promise<string[]> {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? []).map((message) => message.ruleId ?? 'parse-error');
}

const outside = 'services/intake/src/example.ts';
const inside = 'packages/data/src/example.ts';

describe('Payload rule 1 lint ban', () => {
  it('errors on payload.find({}) outside packages/data', async () => {
    expect(await ruleIds('payload.find({});\n', outside)).toEqual(['no-restricted-syntax']);
  });

  it('errors on req.payload.create({}) outside packages/data', async () => {
    expect(await ruleIds('req.payload.create({});\n', outside)).toEqual(['no-restricted-syntax']);
  });

  it('allows both calls inside packages/data', async () => {
    expect(await ruleIds('payload.find({});\nreq.payload.create({});\n', inside)).toEqual([]);
  });

  it('errors on nested and computed access', async () => {
    expect(await ruleIds("ctx.req.payload.delete({});\npayload['update']({});\n", outside)).toEqual(
      ['no-restricted-syntax', 'no-restricted-syntax'],
    );
    expect(await ruleIds("req['payload'].count({});\n", outside)).toEqual(['no-restricted-syntax']);
  });

  it.each(payloadDataMethods)('errors on payload.%s()', async (method) => {
    expect(await ruleIds(`payload.${method}({});\n`, outside)).toEqual(['no-restricted-syntax']);
    expect(await ruleIds(`req.payload.${method}({});\n`, outside)).toEqual([
      'no-restricted-syntax',
    ]);
  });

  it('does not flag unrelated calls', async () => {
    expect(await ruleIds('items.find(() => true);\nmap.delete(1);\n', outside)).toEqual([]);
  });
});
