// Shared test scaffolding for the admin app (not built: tsconfig.build.json excludes this folder; not counted in
// coverage). Fake values only.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AppEnv } from '../tenants/env.js';
import type { SourceFile } from '../tenants/readiness.js';
import { guardUserWrite } from '../tenants/users.js';

export const devEnv: AppEnv = {
  stage: 'dev',
  production: false,
  secret: 'x'.repeat(40),
  databaseUrl: 'postgres://app_user:fake@localhost:5432/dealer',
  serverURL: 'http://localhost:3000',
};

// Hooks and access functions take big argument objects; the tests hand them only what they read, through one cast.
interface Loose {
  run(args: unknown): unknown;
}
export const call = (fn: Loose['run'] | undefined, args: unknown): unknown => fn?.(args);
export const t = () => 'x';

export const adminA = { id: 'adminA', role: 'admin', tenants: [{ tenant: 'A' }] };
export const adminB = { id: 'adminB', role: 'admin', tenants: [{ tenant: 'B' }] };
export const adminAB = {
  id: 'adminAB',
  role: 'admin',
  tenants: [{ tenant: 'A' }, { tenant: 'B' }],
};
export const repA = { id: 'repA', role: 'sales_rep', tenants: [{ tenant: 'A' }] };

/** Runs the users write guard as `user` would trigger it. */
export function write(
  user: unknown,
  operation: 'create' | 'update',
  data: Record<string, unknown> | undefined,
  originalDoc?: unknown,
) {
  return () => call(guardUserWrite, { data, originalDoc, operation, req: { user, t } });
}

export const adminDir = fileURLToPath(new URL('../../', import.meta.url));
const SKIP = ['node_modules', 'dist', 'coverage', '.next'];
const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;

/** Every file of the admin app (paths like `src/app/page.tsx`), with the text of code files; no install or build output. */
export function adminFiles(dir = adminDir, prefix = ''): SourceFile[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    if (SKIP.includes(entry.name)) return [];
    const full = join(dir, entry.name);
    const path = `${prefix}${entry.name}`;
    if (entry.isDirectory()) return adminFiles(full, `${path}/`);
    return [{ path, text: CODE.test(entry.name) ? readFileSync(full, 'utf8') : '' }];
  });
}
