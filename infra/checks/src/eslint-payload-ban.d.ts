declare module '*/eslint.payload-ban.mjs' {
  export const allowedPayloadMembers: string[];
  export const overrideAccessAllowedPaths: string[];
  export const bannedImports: string[];
  export function payloadBanConfigs(options?: {
    overrideAccessAllowed?: string[];
  }): { files?: string[]; ignores?: string[]; rules: Record<string, unknown> }[];
}
