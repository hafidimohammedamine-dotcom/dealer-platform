// @ts-check
import {
  localApiMethods,
  rawDbMember,
  reflectionName,
  reflectiveMembers,
  requiredLocalApiOptions,
  requiredOneOfLocalApiOptions,
} from './payload-lists.mjs';
import { memberName, outermostWrapper, propertyName, staticString, unwrap } from './ast.mjs';

/**
 * @typedef {import('@typescript-eslint/utils').TSESTree.Node} Node
 * @typedef {import('@typescript-eslint/utils').TSESTree.CallExpression} CallExpression
 * @typedef {{ requireOptions?: boolean, allowDb?: boolean, allowOverrideTrue?: boolean }} OverrideOptions
 * @typedef {'notFalse' | 'notLiteral' | 'spread' | 'computedKey' | 'missing' | 'missingOneOf' | 'showHidden' | 'notCalled' | 'dynamicKey' | 'reflection' | 'rawDb'} OverrideMessage
 */

// ---------------------------------------------------------------------------------------------
// local/no-override-access
//
// Everywhere: `overrideAccess` is only the literal `false`. Only a static `overrideAccess` key is looked for
// outside packages/data. A dynamic key or a spread there (`{ [k]: true }`, `{ ...opts }`) is left alone on
// purpose: `overrideAccess` only means something to a Local API call, and outside packages/data nothing can
// get hold of the Payload instance (local/no-payload-instance-access bans its names, `Reflect`, `Object.values`
// and friends and every non-fixed key read, and local/no-restricted-modules bans the `payload` value import,
// DB clients and hand-made module loaders). A test proves each of those forms is flagged by those rules.
// With `requireOptions` (packages/data): every Local API call passes one object literal with the
// required options, and a Local API method is only ever read to call it directly (`x.find({...})`
// or `x.find.call(x, {...})`). So no destructured `find`, no `[x.find][0](...)`, no `.apply`/`.bind`,
// no dynamic or numeric key, no `Reflect`, no `.values()`/`.entries()`/property descriptors, and no
// `.db` (the raw adapter) unless `allowDb` is set (the one file in payloadDbAllowedPaths).
// `allowOverrideTrue` (the system-job files in the founder-only allow-list) skips only the `notFalse` report and
// the `missingOneOf` report (a system job has no user). Every other check stays on for those files.
// ---------------------------------------------------------------------------------------------

/**
 * For a Local API call, the argument that holds the options. `null` when the call cannot be checked
 * (a dynamic method name). Undefined when this is not a Local API call.
 * @param {CallExpression} node
 * @returns {Node | null | undefined}
 */
function localApiOptionsArgument(node) {
  const callee = unwrap(node.callee);
  if (callee.type !== 'MemberExpression') return undefined;
  const name = memberName(callee);
  if (name === undefined) return null;
  if (localApiMethods.includes(name)) {
    const [first] = node.arguments;
    // Array#find, Map#delete with a callback are not Local API calls.
    if (first?.type === 'ArrowFunctionExpression' || first?.type === 'FunctionExpression') {
      return undefined;
    }
    return first ?? null;
  }
  const target = unwrap(callee.object);
  const targetName = target.type === 'MemberExpression' ? memberName(target) : undefined;
  if (name === 'call' && targetName !== undefined && localApiMethods.includes(targetName)) {
    return node.arguments[1] ?? null;
  }
  return undefined;
}

/**
 * Is `node` the callee of a call, ignoring wrappers (`x!`, `x?.()`, `await`)?
 * @param {Node} node
 */
function isCallee(node) {
  const outer = outermostWrapper(node);
  return outer.parent?.type === 'CallExpression' && outer.parent.callee === outer;
}

/**
 * Is this read of a Local API method a direct call: `x.find(...)` or `x.find.call(...)`?
 * @param {Node} member
 */
function isDirectCall(member) {
  if (isCallee(member)) return true;
  const outer = outermostWrapper(member);
  const { parent } = outer;
  return (
    parent?.type === 'MemberExpression' &&
    parent.object === outer &&
    memberName(parent) === 'call' &&
    isCallee(parent)
  );
}

/**
 * Is a computed key anything other than a fixed string (`obj['name']`, obj[`name`])?
 * @param {Node} key
 */
function isDynamicKey(key) {
  if (key.type === 'Literal' && typeof key.value !== 'string') return true;
  return staticString(key) === undefined;
}

/**
 * `null` or `undefined`: a `user` or `req` set to that is no user at all.
 * @param {Node} value
 */
function isEmptyValue(value) {
  return (
    (value.type === 'Literal' && value.value === null) ||
    (value.type === 'Identifier' && value.name === 'undefined')
  );
}

/**
 * Problems with the options object of one Local API call.
 * @param {import('@typescript-eslint/utils').TSESLint.RuleContext<OverrideMessage, [OverrideOptions?]>} context
 * @param {CallExpression} call
 * @param {Node | null} options
 * @param {boolean} allowOverrideTrue a system job: no user is needed
 */
function checkLocalApiOptions(context, call, options, allowOverrideTrue) {
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
    if (name === 'showHiddenFields' && !isFalse) {
      context.report({ node: property, messageId: 'showHidden' });
    }
    if (name !== undefined && requiredOneOfLocalApiOptions.includes(name)) {
      if (isEmptyValue(property.value)) keys.delete(name);
    }
  }
  for (const name of requiredLocalApiOptions) {
    if (!keys.has(name)) context.report({ node: options, messageId: 'missing', data: { name } });
  }
  if (!allowOverrideTrue && !requiredOneOfLocalApiOptions.some((name) => keys.has(name))) {
    context.report({ node: options, messageId: 'missingOneOf' });
  }
}

/**
 * The packages/data problem with reading member `name` (`obj.name` or `const { name } = obj`).
 * @param {string} name
 * @param {boolean} allowDb
 * @param {boolean} directCall
 * @returns {OverrideMessage | undefined}
 */
function readProblem(name, allowDb, directCall) {
  if (reflectiveMembers.includes(name)) return 'reflection';
  if (name === rawDbMember && !allowDb) return 'rawDb';
  if (localApiMethods.includes(name) && !directCall) return 'notCalled';
  return undefined;
}

/** @type {import('@typescript-eslint/utils').TSESLint.RuleModule<OverrideMessage, [OverrideOptions?]>} */
export const noOverrideAccess = {
  meta: {
    type: 'problem',
    schema: [
      {
        type: 'object',
        properties: {
          requireOptions: { type: 'boolean' },
          allowDb: { type: 'boolean' },
          allowOverrideTrue: { type: 'boolean' },
        },
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
      missingOneOf:
        'Local API options must pass the logged-in `user` (or the `req` that carries it), not null or undefined (CLAUDE.md, Payload rule 1).',
      showHidden:
        '`showHiddenFields` must be the literal `false` or left out: `true` returns fields access rules hide (CLAUDE.md, Payload rule 1).',
      notCalled:
        'In packages/data a Local API method is only read to call it directly (`x.find({...})` or `x.find.call(x, {...})`), so its options can be checked (CLAUDE.md, Payload rules 1 and 4).',
      dynamicKey:
        'No dynamic or numeric keys in packages/data: one could reach a Local API method unchecked. Use a fixed name, `.at()` or a Map (CLAUDE.md, Payload rule 1).',
      reflection:
        'No `Reflect`, `.values()`, `.entries()` or property descriptors in packages/data: they reach Local API methods unchecked. Use `for...of` on a Map (CLAUDE.md, Payload rule 1).',
      rawDb:
        '`.db` (the raw database adapter) skips access checks. It is only allowed in the reviewed file in payloadDbAllowedPaths (CLAUDE.md, Payload rules 1 and 2).',
    },
  },
  defaultOptions: [{}],
  create(context) {
    const requireOptions = context.options[0]?.requireOptions === true;
    const allowDb = context.options[0]?.allowDb === true;
    const allowOverrideTrue = context.options[0]?.allowOverrideTrue === true;
    /**
     * @param {Node} node
     * @param {OverrideMessage | undefined} messageId
     */
    const report = (node, messageId) => {
      if (messageId) context.report({ node, messageId });
    };
    return {
      Property(node) {
        if (node.parent.type !== 'ObjectPattern') {
          const isFalse = node.value.type === 'Literal' && node.value.value === false;
          if (propertyName(node) === 'overrideAccess' && !isFalse && !allowOverrideTrue) {
            report(node, 'notFalse');
          }
          return;
        }
        if (!requireOptions) return;
        if (node.computed && isDynamicKey(node.key)) return report(node, 'dynamicKey');
        const name = propertyName(node);
        if (name !== undefined) report(node, readProblem(name, allowDb, false));
      },
      MemberExpression(node) {
        if (!requireOptions) return;
        if (node.computed && isDynamicKey(node.property)) return report(node, 'dynamicKey');
        const name = memberName(node);
        if (name === undefined) return;
        if (node.computed && reflectionName.test(name)) return report(node, 'reflection');
        report(node, readProblem(name, allowDb, isDirectCall(node)));
      },
      Identifier(node) {
        if (requireOptions && reflectionName.test(node.name)) report(node, 'reflection');
      },
      CallExpression(node) {
        if (!requireOptions) return;
        const options = localApiOptionsArgument(node);
        if (options !== undefined) checkLocalApiOptions(context, node, options, allowOverrideTrue);
      },
    };
  },
};
