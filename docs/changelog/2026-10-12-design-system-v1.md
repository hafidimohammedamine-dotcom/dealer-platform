# 2026-10-12 - design system v1 in packages/ui

Part of issue #8 (PR #54). `packages/ui/src/` now has real code: the design tokens, the money, phone, date and masking formatters,
badge tones, and the input, state and table rules. There is no React yet. Nothing renders these rules, so the screens do
not use them yet.

- Tokens: colors (with `dangerHover`, and a darker border `#6b7a8a` for contrast on `surfaceAlt`), fonts, font sizes,
  spacing, radii, `minTapTarget` (44px) and breakpoints. `focusRing` is the one focus style.
  `cssVariables()` gives the same values as CSS custom properties, including `--focus-ring`, `--focus-ring-offset` and
  `--breakpoint-*`. Nothing applies them yet.
- Formatters:
  - `formatMoney(cents)` shows integer cents as `$1,234.56` and throws on a number that is not a safe whole number of cents (no decimals, within ±9,007,199,254,740,991).
  - `formatPhone` shows a US number as `(555) 234-5678`. Letters and other symbols are dropped first. What is left must be
    10 digits, or 11 digits starting with 1. A leading 1 or `+1` is accepted. An area code or an exchange (the 3 digits
    after the area code) that starts with 0 or 1 is rejected. Anything else shows `Phone not valid`.
  - `formatDate(value, timeZone)` shows `Oct 12, 2026`. Text must be one of two exact forms of at most 40 characters.
    A date with no time (`2026-10-12`) is a calendar date and never shifts. A moment in time
    (`2026-10-12T02:00:00Z`, with optional seconds and up to 9 fraction digits) must end with `Z` or an offset like
    `-05:00` or `-0500`, and is shown in the dealer's time zone. A time with no zone (`2026-10-12T02:00:00`) shows
    `Date not valid`, because each machine would read it differently. A day not on the calendar (`2026-02-31`), an hour
    past 23, longer text and any other text also show `Date not valid`, so a crafted value cannot slow the server.
    A bad time zone (including an empty one) shows `Date not valid` for every date, with or without a time. The zone
    is checked first. It is for display only and is never used for quiet hours.
  - `maskLast4(last4)` shows `•••• 1234`. It throws unless it gets exactly 4 digits. The value must already be masked by
    `services/desking`.
  - `maskDob()` and `maskIncome()` always show `••••`. They take no value, so nothing can leak.
- Badges: `badgeTones` and `BadgeTone` (`success`, `warning`, `danger`, `info`). `badge(tone, label, symbol)` needs a word
  and a symbol. Colour alone is never enough. `isBadgeTone(text)` checks text that comes from outside the code (for
  example a setting) before it is used as a tone.
- Components (plain rules, no React):
  - `buttonStyles`: primary, secondary and danger, each with hover, disabled and focus styles. Every button is at least 44px tall.
  - `inputStyles` and `inputAttributes`: every input needs an id and a label. An error wins over a hint. For an invalid
    input, the input gets a thicker border, and its error message starts with `⚠ `.
  - `emptyState(thing, action)` says what is missing and what to press next. `errorState(what, 'load' | 'save')` and `loadingState`. The save error says the changes were not saved.
    The load error says to check the connection. The loading state has no button.
  - `tableModel` and `tableStyles`: tables get cell padding, a line under each row, right-aligned numbers with equal-width
    digits (`columnStyle` picks it from a column's `numeric` flag) and a card look below the tablet width. Every table needs a caption. Cells are text the screen has
    already formatted (for example with `formatMoney`). A missing, empty or blank cell shows `—`. Only the row's own keys are read,
    so a column named `toString` or `constructor` still shows `—`. Duplicate column keys are rejected, and the keys
    `__proto__`, `constructor` and `prototype` are rejected too.
- Later, not in this PR:
  - the Payload admin theme (logo, colors, fonts), the payment card, the deal worksheet grid, toasts, and a stylesheet that
    applies `cssVariables()`: #65
  - lender-answer badges (approved, countered, declined, waiting), which wait for `LenderDecision` in `packages/contracts`: #68
  - React rendering of these rules: #63
