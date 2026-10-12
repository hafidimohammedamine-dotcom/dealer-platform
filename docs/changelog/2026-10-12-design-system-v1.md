# 2026-10-12 - design system v1 in packages/ui

Part of issue #8 (PR #54). `packages/ui/src/` now has real code: the design tokens, the money, phone, date and masking
formatters, badge tones, and the input, state and table rules. There is no React yet. Nothing renders these rules, so the
screens do not use them yet.

- Tokens: colors (with `dangerHover`, and a darker border `#6b7a8a` for contrast on `surfaceAlt`), fonts, font sizes,
  spacing, radii, `minTapTarget` (44px) and breakpoints. `focusRing` is the one focus style.
  `cssVariables()` gives the same values as CSS custom properties, including `--focus-ring`, `--focus-ring-offset` and
  `--breakpoint-*`. Nothing calls it yet.
- Formatters:
  - `formatMoney(cents)` shows integer cents as `$1,234.56` and throws on a number that is not a whole number of cents.
  - `formatPhone` shows a US number as `(555) 234-5678`. It strips everything that is not a digit, and accepts a single
    leading 1 or `+1`. The result must be exactly 10 digits, and the area code (first digit) and the exchange (fourth
    digit) must not start with 0 or 1. Anything else shows `Phone not valid`.
  - `formatDate(value, timeZone)` shows `Oct 12, 2026`. The time zone is checked first: if it is not a zone the runtime
    knows (for example `''` or `Not/AZone`), every input shows `Date not valid`, including a calendar date. A bad date
    also shows `Date not valid`. A date with no time (`2026-10-12`) is a calendar date: it shows the same day in every
    valid zone and never shifts. A moment in time (a timestamp or a `Date`) is shown in the dealer's zone. It is for
    display only and is never used for quiet-hours checks, which depend on the customer's local time.
  - `maskLast4(last4)` shows `•••• 1234`. It throws unless it gets exactly 4 digits. The value must already be masked by
    `services/desking`.
  - `maskDob()` and `maskIncome()` always show `••••`. They take no value, so nothing can leak.
- Badges: `badgeTones` and `BadgeTone` (`success`, `warning`, `danger`, `info`). `badge(tone, label, symbol)` needs a word
  and a symbol. Colour alone is never enough. Mapping a lender answer to a tone is not done yet (see the deferred list).
- Components (plain rules, no React):
  - `buttonStyles`: primary, secondary and danger, each with hover, disabled and focus styles. Every button is at least 44px tall.
  - `inputStyles` and `inputAttributes`: every input needs an id and a label. An error wins over a hint. An invalid input
    gets a thicker border and a `⚠ ` prefix.
  - `emptyState`, `errorState(what, 'load' | 'save')` and `loadingState`. The save error says the changes were not saved.
    The load error says to check the connection. The loading state has no button.
  - `tableModel` and `tableStyles`: every table needs a caption. A missing cell shows `—`. Duplicate column keys are
    rejected, and so are `__proto__`, `constructor` and `prototype`.
- Later, not in this PR, tracked in issue #65: the Payload admin theme (logo, colors, fonts), the payment card, the deal
  worksheet grid, toasts, the stylesheet that applies `cssVariables()`, and the lender-answer badges (approved, countered,
  declined, waiting). The lender-answer badges need the `LenderDecision` shape in `packages/contracts`. React rendering
  is tracked in issue #63.
