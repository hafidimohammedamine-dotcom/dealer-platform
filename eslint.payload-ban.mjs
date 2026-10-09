// Payload rule 1: the Local API skips access checks by default, so every data
// call goes through packages/data. Calling these methods anywhere else is an error.
export const payloadDataMethods = [
  'find',
  'findByID',
  'findDistinct',
  'findVersions',
  'findVersionByID',
  'findGlobal',
  'findGlobalVersions',
  'findGlobalVersionByID',
  'create',
  'update',
  'updateGlobal',
  'delete',
  'count',
  'countVersions',
  'countGlobalVersions',
  'duplicate',
  'restoreVersion',
  'restoreGlobalVersion',
];

const methodPattern = `/^(${payloadDataMethods.join('|')})$/`;
const message =
  'Do not call the Payload Local API directly. Use packages/data (tenant-safe helper). See CLAUDE.md, Payload rule 1.';

// Matches payload.find(), req.payload.find(), ctx.req.payload.find(), payload['find']().
const callOn = (objectSelector) => [
  `CallExpression[callee.type='MemberExpression'][callee.property.name=${methodPattern}]${objectSelector}`,
  `CallExpression[callee.type='MemberExpression'][callee.computed=true][callee.property.value=${methodPattern}]${objectSelector}`,
];

const selectors = [
  ...callOn(`[callee.object.type='Identifier'][callee.object.name='payload']`),
  ...callOn(`[callee.object.type='MemberExpression'][callee.object.property.name='payload']`),
  ...callOn(
    `[callee.object.type='MemberExpression'][callee.object.computed=true][callee.object.property.value='payload']`,
  ),
];

export const payloadBanConfig = {
  ignores: ['packages/data/**'],
  rules: {
    'no-restricted-syntax': ['error', ...selectors.map((selector) => ({ selector, message }))],
  },
};
