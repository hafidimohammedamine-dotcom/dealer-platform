// Internal helpers. Not exported from index.ts.

/** True when the text is empty or only spaces. */
export function isBlank(value: string): boolean {
  return value.trim() === '';
}

/** Throws the given plain-English message when the text is empty or only spaces. */
export function requireText(value: string, message: string): void {
  if (isBlank(value)) throw new Error(message);
}
