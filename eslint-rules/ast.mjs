// @ts-check
// Small AST helpers shared by the Payload ban rules.

import { fileURLToPath } from 'node:url';
import { globalObjectName } from './payload-lists.mjs';

/** Absolute path of the repo root (with a trailing slash): the folder above eslint-rules/. */
export const repoRoot = fileURLToPath(new URL('..', import.meta.url));

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {import('@typescript-eslint/utils').TSESTree.MemberExpression} MemberExpression
 * @typedef {import('@typescript-eslint/utils').TSESTree.CallExpression} CallExpression
 */

/** Nodes that only wrap a value: `x!`, `x as T`, `<T>x`, `x satisfies T`, `await x`, `a?.b`. */
export const wrapperTypes = new Set([
  'TSNonNullExpression',
  'TSAsExpression',
  'TSSatisfiesExpression',
  'TSTypeAssertion',
  'AwaitExpression',
  'ChainExpression',
]);

/** Parents whose string child is a module name, not a value. */
export const moduleNameParents = new Set([
  'ImportDeclaration',
  'ExportAllDeclaration',
  'ExportNamedDeclaration',
  'ImportExpression',
  'TSExternalModuleReference',
  'TSImportType',
  'TSModuleDeclaration',
]);

// ---------------------------------------------------------------------------------------------
// Small helpers.
// ---------------------------------------------------------------------------------------------

/**
 * The value of a string/number literal or a template literal without `${}`. Undefined otherwise.
 * @param {Node | null | undefined} node
 * @returns {string | undefined}
 */
export function staticString(node) {
  if (
    node?.type === 'Literal' &&
    (typeof node.value === 'string' || typeof node.value === 'number')
  ) {
    return String(node.value);
  }
  if (node?.type === 'TemplateLiteral' && node.expressions.length === 0) {
    return node.quasis[0]?.value.cooked ?? undefined;
  }
  return undefined;
}

/**
 * Name of `obj.name`, `obj['name']`, `obj[`name`]`. Undefined when the key is dynamic.
 * @param {MemberExpression} member
 */
export function memberName(member) {
  if (member.computed) return staticString(member.property);
  return member.property.type === 'Identifier' ? member.property.name : undefined;
}

/**
 * Name of an object key (`name`, `'name'`, `['name']`). Undefined when the key is dynamic.
 * @param {import('@typescript-eslint/utils').TSESTree.Property} property
 */
export function propertyName(property) {
  if (!property.computed && property.key.type === 'Identifier') return property.key.name;
  return staticString(property.key);
}

/**
 * The outermost node that only wraps `node` (see wrapperTypes).
 * @param {Node} node
 * @returns {Node}
 */
export function outermostWrapper(node) {
  let outer = node;
  while (outer.parent && wrapperTypes.has(outer.parent.type)) outer = outer.parent;
  return outer;
}

/**
 * The node inside any wrappers.
 * @param {Node} node
 * @returns {Node}
 */
export function unwrap(node) {
  let inner = node;
  for (;;) {
    switch (inner.type) {
      case 'TSNonNullExpression':
      case 'TSAsExpression':
      case 'TSSatisfiesExpression':
      case 'TSTypeAssertion':
      case 'ChainExpression':
        inner = inner.expression;
        break;
      case 'AwaitExpression':
        inner = inner.argument;
        break;
      default:
        return inner;
    }
  }
}

/**
 * Is `node` the callee of a call, ignoring wrappers (`x!`, `x?.()`, `await`)?
 * @param {Node} node
 */
export function isCallee(node) {
  const outer = outermostWrapper(node);
  return outer.parent?.type === 'CallExpression' && outer.parent.callee === outer;
}

/**
 * Is this the global object (`global`, `globalThis`, `globalThis.global`)?
 * @param {Node} node
 * @returns {boolean}
 */
export function isGlobalObject(node) {
  const inner = unwrap(node);
  if (inner.type === 'Identifier') return globalObjectName.test(inner.name);
  if (inner.type !== 'MemberExpression') return false;
  const name = memberName(inner);
  return name !== undefined && globalObjectName.test(name) && isGlobalObject(inner.object);
}

/**
 * The method name and the first argument of a call as a Local API call would be written: `find(opts)`,
 * `x.find(opts)` and `x.find.call(x, opts)`. `name` is undefined when the callee is not a plain name
 * (`x[k](opts)`, `(a, b)(opts)`); `options` is undefined when the argument is missing. Whether `name` is
 * really a Local API method is for the caller to decide.
 * @param {CallExpression} node
 * @returns {{ name: string | undefined, options: Node | undefined }}
 */
export function localApiCallParts(node) {
  const callee = unwrap(node.callee);
  if (callee.type === 'Identifier') return { name: callee.name, options: node.arguments[0] };
  if (callee.type !== 'MemberExpression') return { name: undefined, options: node.arguments[0] };
  const name = memberName(callee);
  const target = unwrap(callee.object);
  const targetName = target.type === 'MemberExpression' ? memberName(target) : undefined;
  if (name === 'call' && targetName !== undefined) {
    return { name: targetName, options: node.arguments[1] };
  }
  return { name, options: node.arguments[0] };
}
