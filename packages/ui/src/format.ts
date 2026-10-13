// One way to show money, dates, phones and sensitive values everywhere.

/** Money is integer cents, never floats. 123456 -> "$1,234.56". */
export function formatMoney(cents: number): string {
  if (!Number.isSafeInteger(cents)) throw new RangeError('Money must be a whole number of cents');
  const abs = Math.abs(cents);
  const dollars = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const rest = (abs % 100).toString().padStart(2, '0');
  return `${cents < 0 ? '-' : ''}$${dollars}.${rest}`;
}

/**
 * US phone numbers as (555) 234-5678. Letters and symbols are dropped first, then a leading 1 or +1
 * is accepted. A number that is not 10 digits, or whose area code or exchange starts with 0 or 1,
 * is shown as "Phone not valid" so a rep notices.
 */
export function formatPhone(input: string): string {
  let digits = input.replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('1')) digits = digits.slice(1);
  if (digits.length !== 10 || /^[01]/.test(digits) || /^[01]/.test(digits.slice(3))) {
    return 'Phone not valid';
  }
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}

function isValidZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone });
    return true;
  } catch {
    return false;
  }
}

const dateOnly = /^\d{4}-\d{2}-\d{2}$/;
/** A time must end with Z or an offset such as -05:00, so every machine reads it the same way. */
const hasZone = /T\d{2}:\d{2}.*(Z|[+-]\d{2}(:?\d{2})?)$/i;

/**
 * Dates as "Oct 12, 2026". A date with no time ("2026-10-12") is a calendar date and never shifts.
 * A moment in time is shown in the dealer's time zone. A time with no zone ("2026-10-12T02:00:00") is refused,
 * because each machine would read it differently. A bad date or time zone gives "Date not valid".
 * Display only: never use this for quiet-hours checks, which depend on the customer's local time.
 */
export function formatDate(value: Date | string, timeZone: string): string {
  if (!isValidZone(timeZone)) return 'Date not valid';
  let date: Date;
  let zone = timeZone;
  if (typeof value === 'string') {
    date = new Date(value);
    if (dateOnly.test(value)) {
      if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
        return 'Date not valid';
      }
      zone = 'UTC';
    } else if (!hasZone.test(value)) {
      return 'Date not valid';
    }
  } else {
    date = value;
  }
  if (Number.isNaN(date.getTime())) return 'Date not valid';
  return new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
}

/**
 * DISPLAY ONLY, for an SSN or account number. Pass ONLY the last 4 digits, already
 * masked by services/desking. The full number must never reach the browser.
 * Throws if it is not exactly 4 digits, so a full value can never be passed by mistake.
 */
export function maskLast4(last4: string): string {
  if (!/^\d{4}$/.test(last4)) throw new RangeError('Pass only the last 4 digits');
  return `•••• ${last4}`;
}

/** Date of birth is never shown, not even the year. Takes no value so nothing can leak. */
export function maskDob(): string {
  return '••••';
}

/** Income is never shown. Takes no value so nothing can leak. */
export function maskIncome(): string {
  return '••••';
}
