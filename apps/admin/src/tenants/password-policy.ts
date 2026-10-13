// The password rule for dealer staff (Payload rule 14; NIST SP 800-63B: length over complexity, and a block list).
// Payload 3.90.2 checks nothing about a password's strength (it only requires that one is present), so the rule lives here.

export const MIN_PASSWORD_LENGTH = 12;
export const MAX_PASSWORD_LENGTH = 128;

// The most common passwords and the keyboard walks people add digits to. A password is refused when, with its digits and
// symbols taken off both ends, it is on this list or only repeats one short piece. Short on purpose: a breached-password
// service call (k-anonymity range lookup) is a follow-up that needs a founder-approved outbound host.
const COMMON = new Set([
  'password',
  'passw0rd',
  'passwordpassword',
  'letmein',
  'letmeinplease',
  'welcome',
  'welcome1',
  'iloveyou',
  'admin',
  'administrator',
  'qwerty',
  'qwertyuiop',
  'qwertyuiopasdf',
  'asdfghjkl',
  'asdfghjklzxcv',
  'zxcvbnm',
  '1q2w3e4r5t6y',
  'abc123',
  'abcdefghijkl',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'master',
  'shadow',
  'sunshine',
  'princess',
  'trustno1',
  'changeme',
  'changemenow',
  'secret',
  'dealer',
  'dealership',
  'dealerplatform',
  'carlot',
  'autodealer',
  'cardealer',
  'test',
  'testtest',
  'default',
  'guest',
  'login',
  'whatever',
  'freedom',
  'starwars',
  'superman',
  'batman',
  'michael',
  'jennifer',
  'hello',
  'helloworld',
  'summer',
  'winter',
  'spring',
  'autumn',
  'ford',
  'chevy',
  'toyota',
]);

const NON_LETTERS_AT_ENDS = /^[^a-z]+|[^a-z]+$/g;

function repeatsOnePiece(value: string): boolean {
  for (let size = 1; size <= value.length / 2; size += 1) {
    if (value.length % size === 0 && value.slice(0, size).repeat(value.length / size) === value)
      return true;
  }
  return false;
}

/** The first problem with a password, as a sentence for the person who chose it, or null when it is acceptable. */
export function passwordProblem(password: unknown, email?: unknown): string | null {
  if (typeof password !== 'string') return 'A password is required.';
  if (password.length < MIN_PASSWORD_LENGTH)
    return `The password must be at least ${MIN_PASSWORD_LENGTH} characters long.`;
  if (password.length > MAX_PASSWORD_LENGTH)
    return `The password must be at most ${MAX_PASSWORD_LENGTH} characters long.`;
  const lower = password.toLowerCase();
  const core = lower.replace(NON_LETTERS_AT_ENDS, '');
  if (COMMON.has(lower) || COMMON.has(core) || repeatsOnePiece(lower))
    return 'That password is too common. Choose a longer, less guessable one.';
  if (typeof email === 'string') {
    const name = email.split('@')[0]?.toLowerCase() ?? '';
    if (name.length >= 4 && lower.includes(name))
      return 'The password must not contain your email name.';
  }
  return null;
}
