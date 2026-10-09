// Payload rule 1: the Local API skips access checks by default, so every data
// call goes through packages/data. This file holds three bans:
//   1. local/no-payload-instance-access  fail closed: any use of a Payload instance outside packages/data
//   2. local/no-override-access          overrideAccess must be literal false, everywhere
//   3. no-restricted-imports             no database drivers or Payload adapters outside packages/data
// Inline eslint comments are off (see eslint.config.mjs), so none of these can be disabled in a file.

/** Members of a Payload instance that may be used outside packages/data. Reviewed by security. */
export const allowedPayloadMembers = ['logger'];

/**
 * Paths where `overrideAccess` may be something other than literal false (system jobs).
 * Empty on purpose: add a path only after a security review.
 */
export const overrideAccessAllowedPaths = [];

export const bannedImports = [
  'pg',
  'drizzle-orm',
  '@payloadcms/db-postgres',
  '@payloadcms/drizzle',
];

const accessMessage =
  'Do not use the Payload instance outside packages/data (only: ' +
  allowedPayloadMembers.join(', ') +
  '). Use the tenant-safe helper in packages/data. See CLAUDE.md, Payload rule 1.';

const wrapperTypes = new Set([
  'TSNonNullExpression',
  'TSAsExpression',
  'TSSatisfiesExpression',
  'TSTypeAssertion',
  'AwaitExpression',
  'ChainExpression',
]);

const payloadTypeNames = new Set(['Payload', 'BasePayload']);

const staticName = (node) => {
  if (node.type === 'Literal' && typeof node.value === 'string') return node.value;
  if (node.type === 'TemplateLiteral' && node.expressions.length === 0) {
    return node.quasis[0].value.cooked;
  }
  return undefined;
};

/** Name of a member access (obj.name, obj['name'], obj[`name`]), or undefined when not static. */
const memberName = (member) =>
  member.computed ? staticName(member.property) : member.property.name;

const unwrap = (node) => {
  let current = node;
  for (;;) {
    if (current.type === 'ChainExpression' || wrapperTypes.has(current.type)) {
      const inner = current.expression;
      if (!inner) return current;
      current = inner;
    } else return current;
  }
};

const typeIsPayload = (annotation) => {
  const type = annotation?.typeAnnotation;
  if (type?.type !== 'TSTypeReference') return false;
  const name = type.typeName;
  const last = name.type === 'TSQualifiedName' ? name.right.name : name.name;
  return payloadTypeNames.has(last);
};

const bannedImportMatch = (source) =>
  typeof source === 'string' &&
  bannedImports.some((name) => source === name || source.startsWith(`${name}/`));

const noPayloadInstanceAccess = {
  meta: { type: 'problem', schema: [], messages: { banned: accessMessage } },
  create(context) {
    const { sourceCode } = context;
    const report = (node) => context.report({ node, messageId: 'banned' });

    // Is this node itself a Payload instance? (not looking through wrappers)
    const isPayloadValue = (node, resolved) => {
      if (node.type === 'MemberExpression') return memberName(node) === 'payload';
      if (node.type === 'CallExpression') {
        const callee = unwrap(node.callee);
        return callee.type === 'Identifier' && callee.name === 'getPayload';
      }
      if (node.type === 'Identifier') {
        if (node.name === 'payload') return true;
        return (resolved?.defs ?? []).some((def) => typeIsPayload(def.name.typeAnnotation));
      }
      return false;
    };

    // The use is fine only when the (wrapped) value is the object of an allowed member access.
    const checkUse = (node) => {
      let outer = node;
      while (outer.parent && wrapperTypes.has(outer.parent.type)) outer = outer.parent;
      const parent = outer.parent;
      if (parent?.type === 'MemberExpression' && parent.object === outer) {
        const name = memberName(parent);
        if (name !== undefined && allowedPayloadMembers.includes(name)) return;
      }
      report(node);
    };

    return {
      ImportDeclaration(node) {
        if (bannedImportMatch(node.source.value)) return; // no-restricted-imports reports it
        for (const spec of node.specifiers) {
          if (spec.type === 'ImportSpecifier' && spec.imported.name === 'getPayload') report(spec);
        }
      },
      ImportExpression(node) {
        if (bannedImportMatch(staticName(node.source))) report(node);
      },
      MemberExpression(node) {
        if (isPayloadValue(node)) checkUse(node);
      },
      CallExpression(node) {
        const callee = unwrap(node.callee);
        if (callee.type === 'Identifier' && callee.name === 'require') {
          const [arg] = node.arguments;
          if (arg && bannedImportMatch(staticName(arg))) report(node);
        }
        if (isPayloadValue(node)) checkUse(node);
      },
      'Program:exit'() {
        const scopes = sourceCode.scopeManager.scopes;
        for (const scope of scopes) {
          for (const ref of scope.references) {
            const id = ref.identifier;
            // A declaration or a plain assignment target is not a use.
            if (ref.isWrite() && !ref.isRead()) continue;
            if (!isPayloadValue(id, ref.resolved)) continue;
            checkUse(id);
          }
        }
      },
    };
  },
};

const noOverrideAccess = {
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      banned:
        '`overrideAccess` must be the literal `false`. `true` or a computed value skips access checks (CLAUDE.md, Payload rules 1 and 4).',
    },
  },
  create(context) {
    return {
      Property(node) {
        const name = node.computed ? staticName(node.key) : (node.key.name ?? staticName(node.key));
        if (name !== 'overrideAccess') return;
        // Destructuring patterns are not a call option.
        if (node.parent.type === 'ObjectPattern') return;
        const { value } = node;
        if (!(value.type === 'Literal' && value.value === false)) {
          context.report({ node, messageId: 'banned' });
        }
      },
    };
  },
};

export const localPlugin = {
  rules: {
    'no-payload-instance-access': noPayloadInstanceAccess,
    'no-override-access': noOverrideAccess,
  },
};

/** Flat-config blocks for the Payload bans. */
export function payloadBanConfigs({ overrideAccessAllowed = overrideAccessAllowedPaths } = {}) {
  const importPatterns = bannedImports.flatMap((name) => [name, `${name}/*`]);
  const configs = [
    {
      plugins: { local: localPlugin },
      rules: { 'local/no-override-access': 'error' },
    },
    {
      ignores: ['packages/data/**'],
      rules: {
        'local/no-payload-instance-access': 'error',
        'no-restricted-imports': [
          'error',
          {
            patterns: [
              {
                group: importPatterns,
                message:
                  'Database drivers and Payload adapters are only allowed in packages/data (CLAUDE.md, Payload rule 1).',
              },
            ],
          },
        ],
      },
    },
  ];
  if (overrideAccessAllowed.length > 0) {
    configs.push({ files: overrideAccessAllowed, rules: { 'local/no-override-access': 'off' } });
  }
  return configs;
}
