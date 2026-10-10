// @ts-check
import { allowedPayloadValueImports, isDbClientModule, payloadModule } from './payload-lists.mjs';
import { outermostWrapper, staticString, unwrap } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {{ allowPayload?: boolean, allowDbClients?: boolean }} ModuleOptions
 * @typedef {'payloadValue' | 'dbClient' | 'dynamicLoad'} ModuleMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-restricted-modules
// ---------------------------------------------------------------------------------------------

/**
 * Which problem, if any, loading the module named by `sourceNode` has under these options.
 * @param {Node | null | undefined} sourceNode
 * @param {boolean} isValue false for a type-only import
 * @param {ModuleOptions} options
 * @returns {ModuleMessage | undefined}
 */
function loadProblem(sourceNode, isValue, options) {
  const source = staticString(sourceNode);
  if (source === undefined) return isFullyAllowed(options) ? undefined : 'dynamicLoad';
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
        properties: { allowPayload: { type: 'boolean' }, allowDbClients: { type: 'boolean' } },
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
    },
  },
  defaultOptions: [{}],
  create(context) {
    const options = context.options[0] ?? {};
    /**
     * @param {Node} node
     * @param {Node | null | undefined} sourceNode
     * @param {boolean} isValue
     */
    const check = (node, sourceNode, isValue) => {
      const messageId = loadProblem(sourceNode, isValue, options);
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
    };
  },
};
