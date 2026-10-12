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

/** US phone numbers as (555) 123-4567. Anything else is shown as "Phone not valid" so a rep notices. */
export function formatPhone(input: string): string {
  let digits = input.replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('1')) digits = digits.slice(1);
  if (digits.length !== 10) return 'Phone not valid';
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}

/** Dates as "Oct 12, 2026". The dealer's time zone is required so a date never shifts a day. */
export function formatDate(value: Date | string, timeZone: string): string {
  const date = typeof value === 'string' ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return 'Date not valid';
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
}

/** Show only the last 4 characters of a sensitive value, e.g. SSN or account number: "•••• 6789". */
export function maskSensitive(value: string): string {
  const clean = value.replace(/[\s-]/g, '');
  if (clean.length < 4) return '••••';
  return `•••• ${clean.slice(-4)}`;
}
