// Internal helper. Not exported from index.ts.

/** Throws a plain-English error when a required piece of screen text is empty. */
export function requireText(value: string, what: string): void {
  if (value.trim() === '') throw new Error(`${what} cannot be empty`);
}
