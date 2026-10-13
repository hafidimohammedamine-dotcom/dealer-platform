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

const notValidDate = 'Date not valid';

/** The longest text we accept ("2026-10-12T02:00:00.123456789+05:00" is 35). Longer text is refused unread. */
const maxDateLength = 40;

/** A calendar date with no time. */
const calendarDate = /^\d{4}-\d{2}-\d{2}$/;

/**
 * A moment in time, fully anchored: date, hours 00-23, minutes, optional seconds and fraction,
 * then Z or an offset such as -05:00 or -0500, so every machine reads it the same way.
 */
const momentInTime =
  /^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,9})?)?(Z|[+-]([01]\d|2[0-3]):?[0-5]\d)$/;

/** True when "YYYY-MM-DD" is a day on the calendar, so "2026-02-31" is refused instead of rolling into March. */
function isRealDay(day: string): boolean {
  const date = new Date(day);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === day;
}

function showDate(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
}

/**
 * Dates as "Oct 12, 2026". Text must be one of two exact forms, at most 40 characters:
 * - a calendar date with no time ("2026-10-12"), which never shifts between time zones;
 * - a moment in time with a zone ("2026-10-12T02:00:00Z" or "...-05:00"), shown in the dealer's time zone.
 * A time with no zone ("2026-10-12T02:00:00") is refused, because each machine would read it differently.
 * Any other text, a day not on the calendar, or a bad time zone gives "Date not valid".
 * Display only: never use this for quiet-hours checks, which depend on the customer's local time.
 */
export function formatDate(value: Date | string, timeZone: string): string {
  if (!isValidZone(timeZone)) return notValidDate;
  if (typeof value !== 'string') {
    return Number.isNaN(value.getTime()) ? notValidDate : showDate(value, timeZone);
  }
  if (value.length > maxDateLength) return notValidDate;
  if (calendarDate.test(value)) {
    return isRealDay(value) ? showDate(new Date(value), 'UTC') : notValidDate;
  }
  if (!momentInTime.test(value) || !isRealDay(value.slice(0, 10))) return notValidDate;
  return showDate(new Date(value), timeZone);
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
