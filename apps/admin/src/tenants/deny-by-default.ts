import type { CollectionConfig } from 'payload';

const REQUIRED_ACCESS = ['create', 'read', 'update', 'delete'] as const;
export const LOCKED_DOCUMENTS_SLUG = 'payload-locked-documents';

export interface DenyByDefaultInput {
  /** Collections as written by us, before Payload or the plugin touch them. */
  collections: readonly CollectionConfig[];
  /** Slugs given to the multi-tenant plugin. */
  pluginSlugs: readonly string[];
  /** The dealers and users collections, which the plugin handles itself. */
  coreSlugs: readonly string[];
  /** Reviewed collections that are not dealer-scoped. */
  allowlist: readonly string[];
}

/** Returns a list of problems; the config test fails CI when the list is not empty (Payload rule 11). */
export function denyByDefaultProblems(input: DenyByDefaultInput): string[] {
  const problems: string[] = [];
  const known = new Set([...input.pluginSlugs, ...input.coreSlugs, ...input.allowlist]);
  for (const collection of input.collections) {
    const slug = collection.slug;
    if (!known.has(slug))
      problems.push(`${slug}: not in the multi-tenant plugin or the reviewed allowlist`);
    for (const key of REQUIRED_ACCESS) {
      if (typeof collection.access?.[key] !== 'function')
        problems.push(`${slug}: access.${key} is not explicit`);
    }
    if (collection.lockDocuments !== false) problems.push(`${slug}: lockDocuments must be false`);
  }
  for (const slug of input.pluginSlugs) {
    if (!input.collections.some((collection) => collection.slug === slug)) {
      problems.push(`${slug}: given to the plugin but not a collection`);
    }
  }
  return problems;
}

/** Problems in the final config: Payload's locked-documents collection (open to every logged-in user) must not exist. */
export function sanitizedConfigProblems(collectionSlugs: readonly string[]): string[] {
  return collectionSlugs.includes(LOCKED_DOCUMENTS_SLUG) ? [`${LOCKED_DOCUMENTS_SLUG} exists`] : [];
}
