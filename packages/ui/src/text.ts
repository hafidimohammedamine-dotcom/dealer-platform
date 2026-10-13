// Internal helpers. Not exported from index.ts. The one rule for blank text: empty or only spaces counts as missing.

/** Throws a plain-English error when a required piece of screen text is empty. */
export function requireText(value: string, what: string): void {
  if (value.trim() === '') throw new Error(`${what} cannot be empty`);
}

/** Returns the text, or undefined when it is missing, empty or only spaces. */
export function present(value: string | undefined): string | undefined {
  return value !== undefined && value.trim() !== '' ? value : undefined;
}
