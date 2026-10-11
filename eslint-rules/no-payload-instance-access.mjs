// @ts-check
import {
  allowedPayloadMembers,
  instanceName,
  memberOwnerName,
  objectBannedMembers,
  objectName,
  reflectionName,
} from './payload-lists.mjs';
import { memberName, moduleNameParents, outermostWrapper, staticString, unwrap } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {import('@typescript-eslint/utils').TSESTree.MemberExpression} MemberExpression
 * @typedef {{ allowNames?: boolean }} InstanceOptions
 * @typedef {'named' | 'dynamic' | 'reflective'} InstanceMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-payload-instance-access
// ---------------------------------------------------------------------------------------------

/**
 * Is this `payload` (identifier, or the key of `x.payload`) read only for an allowed member,
 * like `payload.logger` or `req.payload.logger`?
 * @param {Node} node
 */
function isAllowedMemberUse(node) {
  let target = node;
  const { parent } = node;
  if (parent?.type === 'MemberExpression' && parent.property === node) {
    if (parent.computed) return false;
    target = parent;
  }
  const outer = target.parent;
  if (outer?.type !== 'MemberExpression' || outer.object !== target || outer.computed) return false;
  return (
    outer.property.type === 'Identifier' && allowedPayloadMembers.includes(outer.property.name)
  );
}

/**
 * Is a string literal the name of a module (`from '...'`, `import('...')`, `declare module '...'`)?
 * Module names are checked by local/no-restricted-modules.
 * @param {Node} node
 */
function isModuleName(node) {
  const { parent } = node;
  if (!parent) return false;
  if (moduleNameParents.has(parent.type)) return true;
  // `typeof import('x')`: the name sits in a literal type inside the import type.
  if (parent.type === 'TSLiteralType') return parent.parent?.type === 'TSImportType';
  if (parent.type !== 'CallExpression' || parent.arguments[0] !== node) return false;
  const callee = unwrap(parent.callee);
  return callee.type === 'Identifier' && callee.name === 'require';
}

/**
 * A computed read whose key is not a fixed string (`obj[k]`), in any use: called, chained, destructured,
 * or saved to a variable (`const p = req[k]; p.find()`). A plain write (`obj[k] = 1`, `delete obj[k]`) is not a read.
 * @param {MemberExpression} node
 */
function isDynamicRead(node) {
  if (!node.computed || staticString(node.property) !== undefined) return false;
  const outer = outermostWrapper(node);
  const { parent } = outer;
  if (parent?.type === 'AssignmentExpression') {
    return !(parent.left === outer && parent.operator === '=');
  }
  return !(parent?.type === 'UnaryExpression' && parent.operator === 'delete');
}

/**
 * Is this `Object` anything other than `Object.<fixed name that is not a reflective helper>`?
 * `Object.values(req)`, `Object.assign`, `const O = Object` and `globalThis.Object` all hand out properties unnamed.
 * @param {Node} node an Identifier or literal named `Object`
 */
function isUnsafeObjectUse(node) {
  const { parent } = node;
  if (parent?.type === 'Property' && parent.key === node && !parent.computed && !parent.shorthand) {
    return false;
  }
  if (parent?.type !== 'MemberExpression' || parent.object !== node) return true;
  const name = memberName(parent);
  return name === undefined || objectBannedMembers.includes(name);
}

/** @type {import('@typescript-eslint/utils').TSESLint.RuleModule<InstanceMessage, [InstanceOptions?]>} */
export const noPayloadInstanceAccess = {
  meta: {
    type: 'problem',
    schema: [
      {
        type: 'object',
        properties: { allowNames: { type: 'boolean' } },
        additionalProperties: false,
      },
    ],
    messages: {
      named:
        '`{{name}}` is not allowed outside packages/data (only `payload.logger`). Use the tenant-safe helper in packages/data, or rename an unrelated value (for example `body`). See CLAUDE.md, Payload rule 1.',
      dynamic:
        'A dynamic key or reflection here could reach the Payload instance. Use a fixed property name, `.at()` or a Map. See CLAUDE.md, Payload rule 1.',
      reflective:
        '`Object.values`, `entries`, `assign`, `getOwnProperty*` and any other use of `Object` than `Object.<fixed name>` could reach the Payload instance. Use `Object.keys` with fixed names, or a Map. See CLAUDE.md, Payload rule 1.',
    },
  },
  defaultOptions: [{}],
  create(context) {
    const allowNames = context.options[0]?.allowNames === true;
    /** @type {Set<number>} */
    const reported = new Set();
    /**
     * @param {Node} node
     * @param {string | undefined} name
     */
    const checkName = (node, name) => {
      if (name === undefined || reported.has(node.range[0])) return;
      if (reflectionName.test(name)) {
        reported.add(node.range[0]);
        context.report({ node, messageId: 'dynamic' });
        return;
      }
      if (objectName.test(name) && isUnsafeObjectUse(node)) {
        reported.add(node.range[0]);
        context.report({ node, messageId: 'reflective' });
        return;
      }
      if (allowNames || !instanceName.test(name)) return;
      if (memberOwnerName.test(name) && isAllowedMemberUse(node)) return;
      reported.add(node.range[0]);
      context.report({ node, messageId: 'named', data: { name } });
    };
    return {
      Identifier: (node) => checkName(node, node.name),
      PrivateIdentifier: (node) => checkName(node, node.name),
      JSXIdentifier: (node) => checkName(node, node.name),
      Literal: (node) => {
        if (typeof node.value === 'string' && !isModuleName(node)) checkName(node, node.value);
      },
      TemplateLiteral: (node) => {
        if (!isModuleName(node)) checkName(node, staticString(node));
      },
      MemberExpression: (node) => {
        if (isDynamicRead(node)) context.report({ node, messageId: 'dynamic' });
      },
      Property: (node) => {
        // `const { [k]: value } = obj` is the destructuring form of `obj[k]`.
        const isDynamicKey = node.computed && staticString(node.key) === undefined;
        if (isDynamicKey && node.parent.type === 'ObjectPattern') {
          context.report({ node, messageId: 'dynamic' });
        }
      },
    };
  },
};
