// @ts-check
import { localApiMethods, requiredLocalApiOptions } from './payload-lists.mjs';
import { memberName, propertyName, unwrap } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {import('@typescript-eslint/utils').TSESTree.CallExpression} CallExpression
 * @typedef {import('@typescript-eslint/utils').TSESTree.MemberExpression} MemberExpression
 * @typedef {{ requireOptions?: boolean }} OverrideOptions
 * @typedef {'notFalse' | 'notLiteral' | 'spread' | 'computedKey' | 'missing'} OverrideMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-override-access
// ---------------------------------------------------------------------------------------------

/**
 * For a Local API call, the argument that holds the options. `null` when the call cannot be checked
 * (`.apply`, `.bind`, a dynamic method name). Undefined when this is not a Local API call.
 * @param {CallExpression} node
 * @returns {Node | null | undefined}
 */
function localApiOptionsArgument(node) {
  const callee = unwrap(node.callee);
  if (callee.type !== 'MemberExpression') return undefined;
  const name = memberName(callee);
  if (name === undefined) return null;
  const target = unwrap(callee.object);
  const targetName = target.type === 'MemberExpression' ? memberName(target) : undefined;
  const targetIsMethod = targetName !== undefined && localApiMethods.includes(targetName);
  if (localApiMethods.includes(name)) {
    const [first] = node.arguments;
    // Array#find, Map#delete with a callback are not Local API calls.
    if (first?.type === 'ArrowFunctionExpression' || first?.type === 'FunctionExpression') {
      return undefined;
    }
    return first ?? null;
  }
  if (targetIsMethod && name === 'call') return node.arguments[1] ?? null;
  if (targetIsMethod && (name === 'apply' || name === 'bind')) return null;
  return undefined;
}

/**
 * Problems with the options object of one Local API call.
 * @param {import('@typescript-eslint/utils').TSESLint.RuleContext<OverrideMessage, [OverrideOptions?]>} context
 * @param {CallExpression} call
 * @param {Node | null} options
 */
function checkLocalApiOptions(context, call, options) {
  if (options?.type !== 'ObjectExpression') {
    context.report({ node: options ?? call, messageId: 'notLiteral' });
    return;
  }
  const keys = new Set();
  for (const property of options.properties) {
    if (property.type === 'SpreadElement') {
      context.report({ node: property, messageId: 'spread' });
      continue;
    }
    const name = propertyName(property);
    if (name !== undefined) keys.add(name);
    const isFalse = property.value.type === 'Literal' && property.value.value === false;
    if (name === undefined && !isFalse)
      context.report({ node: property, messageId: 'computedKey' });
  }
  for (const name of requiredLocalApiOptions) {
    if (!keys.has(name)) context.report({ node: options, messageId: 'missing', data: { name } });
  }
}

/** @type {import('@typescript-eslint/utils').TSESLint.RuleModule<OverrideMessage, [OverrideOptions?]>} */
export const noOverrideAccess = {
  meta: {
    type: 'problem',
    schema: [
      {
        type: 'object',
        properties: { requireOptions: { type: 'boolean' } },
        additionalProperties: false,
      },
    ],
    messages: {
      notFalse:
        '`overrideAccess` must be the literal `false`. Anything else can skip access checks (CLAUDE.md, Payload rules 1 and 4).',
      notLiteral:
        'Pass the Local API options as one object literal, so `overrideAccess`, `depth` and `versions` can be checked (CLAUDE.md, Payload rule 4).',
      spread:
        'No spreads in Local API options: a spread can carry `overrideAccess: true` (CLAUDE.md, Payload rule 1).',
      computedKey:
        'No computed keys in Local API options unless the value is the literal `false` (CLAUDE.md, Payload rule 1).',
      missing: 'Local API options must set `{{name}}` explicitly (CLAUDE.md, Payload rule 4).',
    },
  },
  defaultOptions: [{}],
  create(context) {
    const requireOptions = context.options[0]?.requireOptions === true;
    return {
      Property(node) {
        if (node.parent.type === 'ObjectPattern' || propertyName(node) !== 'overrideAccess') return;
        if (!(node.value.type === 'Literal' && node.value.value === false)) {
          context.report({ node, messageId: 'notFalse' });
        }
      },
      CallExpression(node) {
        if (!requireOptions) return;
        const options = localApiOptionsArgument(node);
        if (options !== undefined) checkLocalApiOptions(context, node, options);
      },
    };
  },
};
