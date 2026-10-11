// @ts-check
import { codeConstructorMember, codeConstructorName } from './payload-lists.mjs';
import { isGlobalObject, memberName, propertyName, staticString } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {'codeConstructor'} CodeMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-code-constructors
//
// Everywhere, packages/data too. Code can be built at run time without `eval` or `new Function`: any function's
// `.constructor` is `Function` (`({}).constructor.constructor('...')()`, `(async () => {}).constructor('...')`),
// and `__proto__` and the `__lookup*__` / `__define*__` accessors walk to it. Those members are banned however they
// are written: `x.constructor`, `x['constructor']`, `const { constructor } = x`. The function constructors
// (`Function`, `AsyncFunction`, `GeneratorFunction`, `AsyncGeneratorFunction`) are banned as identifiers, as exact
// strings and as `global`/`globalThis` members. A class's own `constructor() {}` method is not a read and is fine.
// ---------------------------------------------------------------------------------------------

/** Parents where an identifier is a name being declared or a fixed key, not a value read. */
const keyParents = new Set([
  'MethodDefinition',
  'PropertyDefinition',
  'AccessorProperty',
  'TSAbstractMethodDefinition',
  'TSAbstractPropertyDefinition',
  'TSPropertySignature',
  'TSMethodSignature',
]);

/**
 * Is this identifier only a property name (`x.Function`, `{ Function: 1 }`, a class member), not a variable read?
 * Member reads and destructured keys are checked by their own visitors.
 * @param {Node} node
 */
function isPropertyName(node) {
  const { parent } = node;
  if (!parent) return false;
  if (parent.type === 'MemberExpression') return parent.property === node && !parent.computed;
  if (parent.type === 'TSQualifiedName') return parent.right === node;
  if (parent.type === 'Property')
    return parent.key === node && !parent.computed && !parent.shorthand;
  if (!keyParents.has(parent.type)) return false;
  return 'key' in parent && parent.key === node && 'computed' in parent && !parent.computed;
}

/** @type {import('@typescript-eslint/utils').TSESLint.RuleModule<CodeMessage, []>} */
export const noCodeConstructors = {
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      codeConstructor:
        'No `constructor`, `__proto__`, `__lookupGetter__` or `__defineGetter__` members, and no `Function`, `AsyncFunction` or `GeneratorFunction`, however they are written: they build code at run time that the lint rules cannot see (CLAUDE.md, Payload rule 1).',
    },
  },
  defaultOptions: [],
  create(context) {
    /** @type {Set<number>} */
    const reported = new Set();
    /** @param {Node} node */
    const report = (node) => {
      if (reported.has(node.range[0])) return;
      reported.add(node.range[0]);
      context.report({ node, messageId: 'codeConstructor' });
    };
    /** @param {Node} node @param {string | undefined} name */
    const checkName = (node, name) => {
      if (name !== undefined && codeConstructorName.test(name)) report(node);
    };
    return {
      Identifier(node) {
        if (!isPropertyName(node)) checkName(node, node.name);
      },
      Literal(node) {
        if (typeof node.value === 'string') checkName(node, node.value);
      },
      TemplateLiteral: (node) => checkName(node, staticString(node)),
      MemberExpression(node) {
        const name = memberName(node);
        if (name === undefined) return;
        if (codeConstructorMember.test(name)) report(node.property);
        // `globalThis['Function']` is a string, caught above; this is the `globalThis.Function` form.
        else if (!node.computed && codeConstructorName.test(name) && isGlobalObject(node.object)) {
          report(node.property);
        }
      },
      Property(node) {
        if (node.parent.type !== 'ObjectPattern') return;
        const name = propertyName(node);
        if (name === undefined) return;
        if (codeConstructorMember.test(name)) report(node);
        else if (!node.computed) checkName(node, name);
      },
    };
  },
};
