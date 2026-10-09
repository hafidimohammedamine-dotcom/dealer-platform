// @ts-check
// Small AST helpers shared by the Payload ban rules.

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {import('@typescript-eslint/utils').TSESTree.CallExpression} CallExpression
 * @typedef {import('@typescript-eslint/utils').TSESTree.MemberExpression} MemberExpression
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
