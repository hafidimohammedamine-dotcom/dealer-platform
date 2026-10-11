import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { MODULES, errors, errorsWith, eslintFrom, root } from './test-helpers/lint.js';

const desking = 'services/desking/src/db/credit.ts';

describe('nothing outside services/desking imports from services/desking/src/db', () => {
  const imports = [
    "import { creditApp } from '../../desking/src/db/credit.js';",
    "import { creditApp } from '../../desking/src/db';",
    "import '../../desking/src/db/credit.js';",
    "export { x } from '../../desking/src/db/credit.js';",
    "export * from '../../desking/src/db/credit.js';",
    "import type { T } from '../../desking/src/db/credit.js';",
    "import x = require('../../desking/src/db/credit.js');",
    "await import('../../desking/src/db/credit.js');",
    "require('../../desking/src/db/credit.js');",
    "import x from 'services/desking/src/db/credit';",
    "import x from '../services/desking/src/db/credit';",
    "import x from '@dealer/desking/src/db/credit';",
    "import x from '@dealer/desking/dist/db/credit.js';",
    "import x from '@dealer/desking/db';",
  ];

  it.each(imports)('flags %s from another service', async (code) => {
    expect(await errors(`${code}\n`, 'services/lenders/src/x.ts'), code).toContain(MODULES);
  });

  it('flags the import from apps and packages too', async () => {
    const code = "import x from '../../../services/desking/src/db/credit.js';\nvoid x;\n";
    expect(await errors(code, 'apps/admin/src/deep/x.ts')).toEqual([MODULES]);
    expect(await errors(code, 'packages/platform/src/x.ts')).toEqual([MODULES]);
  });

  it('allows imports inside services/desking and other desking paths', async () => {
    const code = "import { creditApp } from './db/credit.js';\nvoid creditApp;\n";
    expect(await errors(code, 'services/desking/src/deals.ts')).toEqual([]);
    expect(await errors("import x from './credit.js';\nvoid x;\n", desking)).toEqual([]);
    expect(
      await errors("import x from '@dealer/desking';\nvoid x;\n", 'services/lenders/src/x.ts'),
    ).toEqual([]);
    expect(
      await errors("import x from '../desking-db/x.js';\nvoid x;\n", 'services/lenders/src/x.ts'),
    ).toEqual([]);
  });
});

describe('the desking boundary does not depend on the folder ESLint runs from', () => {
  const lenders = 'services/lenders/src/x.ts';
  const bad = "import x from '../../desking/src/db/credit.js';\nvoid x;\n";

  // Run from `services/`, the old code saw `lenders/src/x.ts` and `../../desking/src/db` became `desking/src/db`.
  it('flags the import and allows desking itself when run from a subfolder', async () => {
    const linter = eslintFrom(join(root, 'services'));
    expect(await errorsWith(linter, bad, lenders)).toEqual([MODULES]);
    const own = "import { creditApp } from './db/credit.js';\nvoid creditApp;\n";
    expect(await errorsWith(linter, own, 'services/desking/src/deals.ts')).toEqual([]);
  });
});
