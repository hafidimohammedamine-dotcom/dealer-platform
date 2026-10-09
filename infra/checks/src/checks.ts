/** `.yarnrc.yml` must keep dependency install scripts off. */
export function yarnrcKeepsScriptsOff(text: string): boolean {
  return /^enableScripts:\s*false\s*$/m.test(text);
}

/**
 * Problems found in the values of an env template. Only localhost URLs with a
 * placeholder password are allowed, plus APP_ENV=dev. Keys, tokens and secrets stay empty.
 */
export function envValueProblems(vars: ReadonlyMap<string, string>): string[] {
  const problems: string[] = [];
  for (const [key, value] of vars) {
    if (value === '') continue;
    if (/(SECRET|KEY|TOKEN)/.test(key)) {
      problems.push(`${key}: must be empty`);
    } else if (/^[a-z]+:\/\//.test(value)) {
      const url = new URL(value);
      if (url.hostname !== 'localhost') problems.push(`${key}: host must be localhost`);
      if (url.password !== '' && url.password !== 'change-me') {
        problems.push(`${key}: password must be empty or change-me`);
      }
    } else if (key !== 'APP_ENV' || value !== 'dev') {
      problems.push(`${key}: unexpected plain value`);
    }
  }
  return problems;
}
