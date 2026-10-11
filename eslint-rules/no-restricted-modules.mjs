// @ts-check
import { posix } from 'node:path';
import {
  allowedPayloadValueImports,
  deskingDbDir,
  deskingDbPackage,
  isDbClientModule,
  isProcessModule,
  loaderMembers,
  payloadModule,
  processBindingMember,
} from './payload-lists.mjs';
import { memberName, outermostWrapper, propertyName, staticString, unwrap } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {{ allowPayload?: boolean, allowDbClients?: boolean, allowSpawn?: boolean }} ModuleOptions
 * @typedef {'payloadValue' | 'dbClient' | 'dynamicLoad' | 'processModule' | 'loaderMember' | 'deskingDb'} ModuleMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-restricted-modules
// ---------------------------------------------------------------------------------------------

/**
 * Is `source`, imported from `file`, inside services/desking/src/db/? `file` is repo-relative with forward slashes.
 * Relative sources are resolved against the importing file; bare ones are matched by path or package name.
 * @param {string} source
 * @param {string} file
 */
function isDeskingDbImport(source, file) {
  const resolved = source.startsWith('.') ? posix.join(posix.dirname(file), source) : source;
  const inDb = (/** @type {string} */ path) =>
    path === deskingDbDir || path.includes(`${deskingDbDir}/`) || path.endsWith(`/${deskingDbDir}`);
  return inDb(resolved) || deskingDbPackage.test(source);
}

/**
 * Which problem, if any, loading the module named by `sourceNode` has under these options.
 * @param {Node | null | undefined} sourceNode
 * @param {boolean} isValue false for a type-only import
 * @param {ModuleOptions} options
 * @param {string} file repo-relative path of the importing file
 * @returns {ModuleMessage | undefined}
 */
function loadProblem(sourceNode, isValue, options, file) {
  const source = staticString(sourceNode);
  if (source === undefined) return isFullyAllowed(options) ? undefined : 'dynamicLoad';
  if (isProcessModule(source) && !options.allowSpawn) return 'processModule';
  if (!file.startsWith('services/desking/') && isDeskingDbImport(source, file)) return 'deskingDb';
  if (isDbClientModule(source)) return options.allowDbClients ? undefined : 'dbClient';
  if (isValue && payloadModule.test(source) && !options.allowPayload) return 'payloadValue';
  return undefined;
}

/** @param {ModuleOptions} options */
const isFullyAllowed = (options) =>
  options.allowPayload === true && options.allowDbClients === true;

/**
 * `require` used other than as a direct call, or `createRequire` used at all: a module loader as a value.
 * @param {import('@typescript-eslint/utils').TSESTree.Identifier} node
 */
function isLoaderValue(node) {
  if (node.name === 'createRequire') return true;
  if (node.name !== 'require') return false;
  const outer = outermostWrapper(node);
  return !(outer.parent?.type === 'CallExpression' && outer.parent.callee === outer);
}

/** @param {Node | null | undefined} node */
function isProcess(node) {
  const inner = node ? unwrap(node) : undefined;
  return inner?.type === 'Identifier' && inner.name === 'process';
}

/**
 * A read of a hand-loading member: `Module._load`, `process.getBuiltinModule`, `process.binding`, `process[k]`.
 * @param {import('@typescript-eslint/utils').TSESTree.MemberExpression} node
 */
function isLoaderMember(node) {
  const name = memberName(node);
  const onProcess = isProcess(node.object);
  if (name === undefined) return onProcess && node.computed;
  return loaderMembers.includes(name) || (onProcess && name === processBindingMember);
}

/**
 * The value specifiers of an import, minus the reviewed named imports from `payload`.
 * @param {import('@typescript-eslint/utils').TSESTree.ImportDeclaration} node
 * @returns {Node[]}
 */
function valueSpecifiers(node) {
  if (node.importKind === 'type') return [];
  if (node.specifiers.length === 0) return [node]; // `import 'x'` runs the module
  return node.specifiers.filter((spec) => {
    if (spec.type !== 'ImportSpecifier') return true;
    if (spec.importKind === 'type') return false;
    const imported = spec.imported.type === 'Identifier' ? spec.imported.name : spec.imported.value;
    return !allowedPayloadValueImports.includes(imported);
  });
}

/** @type {import('@typescript-eslint/utils').TSESLint.RuleModule<ModuleMessage, [ModuleOptions?]>} */
export const noRestrictedModules = {
  meta: {
    type: 'problem',
    schema: [
      {
        type: 'object',
        properties: {
          allowPayload: { type: 'boolean' },
          allowDbClients: { type: 'boolean' },
          allowSpawn: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    ],
    messages: {
      payloadValue:
        'Only type imports from `payload` are allowed outside packages/data. See CLAUDE.md, Payload rule 1.',
      dbClient:
        'Database clients and Payload database adapters are only allowed in packages/data (and the reviewed desking path). See CLAUDE.md, Payload rule 1.',
      dynamicLoad:
        'Load modules by a fixed name only (no computed import()/require(), no `require` or `createRequire` as a value).',
      processModule:
        'No `vm`, `worker_threads`, `child_process`, `module`, `cluster` or `repl`: they can run or load code the lint rules cannot see (CLAUDE.md, Payload rule 1).',
      loaderMember:
        'No `Module._load`, `process.getBuiltinModule`, `process.binding`, `dlopen` or `.require`: they load modules by hand and skip the import bans (CLAUDE.md, Payload rule 1).',
      deskingDb:
        'Only services/desking/ may import from services/desking/src/db/ (the encrypted credit schema). Ask the desking service for what you need (CLAUDE.md, Database).',
    },
  },
  defaultOptions: [{}],
  create(context) {
    const options = context.options[0] ?? {};
    const file = posix.normalize(
      context.filename.slice(context.cwd.length + 1).replaceAll('\\', '/'),
    );
    /**
     * @param {Node} node
     * @param {Node | null | undefined} sourceNode
     * @param {boolean} isValue
     */
    const check = (node, sourceNode, isValue) => {
      const messageId = loadProblem(sourceNode, isValue, options, file);
      if (messageId) context.report({ node, messageId });
    };
    return {
      ImportDeclaration(node) {
        const values = valueSpecifiers(node);
        if (isDbClientModule(node.source.value) || values.length === 0) {
          check(node, node.source, values.length > 0);
          return;
        }
        for (const spec of values) check(spec, node.source, true);
      },
      ExportAllDeclaration: (node) => check(node, node.source, node.exportKind !== 'type'),
      ExportNamedDeclaration(node) {
        if (!node.source) return;
        const isValue =
          node.exportKind !== 'type' && node.specifiers.some((spec) => spec.exportKind !== 'type');
        check(node, node.source, isValue);
      },
      TSImportEqualsDeclaration(node) {
        if (node.moduleReference.type !== 'TSExternalModuleReference') return;
        check(node, node.moduleReference.expression, node.importKind !== 'type');
      },
      ImportExpression: (node) => check(node, node.source, true),
      CallExpression(node) {
        const callee = unwrap(node.callee);
        if (callee.type === 'Identifier' && callee.name === 'require') {
          check(node, node.arguments[0], true);
        }
      },
      Identifier(node) {
        if (!isFullyAllowed(options) && isLoaderValue(node)) {
          context.report({ node, messageId: 'dynamicLoad' });
        }
      },
      MemberExpression(node) {
        if (!options.allowSpawn && isLoaderMember(node)) {
          context.report({ node, messageId: 'loaderMember' });
        }
      },
      Property(node) {
        if (options.allowSpawn || node.parent.type !== 'ObjectPattern') return;
        const name = propertyName(node);
        const owner = node.parent.parent;
        const onProcess = owner?.type === 'VariableDeclarator' && isProcess(owner.init);
        const bad =
          name === undefined
            ? onProcess
            : loaderMembers.includes(name) || (onProcess && name === processBindingMember);
        if (bad) context.report({ node, messageId: 'loaderMember' });
      },
    };
  },
};
