// Design tokens: the only place colors, fonts and spacing are defined. Phone width first.
export const colors = {
  brand: '#0b4f9c',
  brandHover: '#093e7a',
  onBrand: '#ffffff',
  text: '#14202e',
  textMuted: '#4a5868',
  surface: '#ffffff',
  surfaceAlt: '#f1f4f8',
  border: '#6b7a8a',
  focus: '#b45309',
  success: '#0f6b3a',
  successBg: '#dff3e7',
  warning: '#7a4a00',
  warningBg: '#fdf0cf',
  danger: '#a1141f',
  dangerHover: '#82101a',
  dangerBg: '#fde4e6',
  info: '#0b4f9c',
  infoBg: '#e1ecf9',
} as const;

export const fonts = {
  body: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif",
  mono: "ui-monospace, 'SF Mono', Menlo, Consolas, monospace",
} as const;

// Sizes in px. Body text is 16px so phones do not zoom on inputs.
export const fontSizes = { sm: 14, md: 16, lg: 20, xl: 28 } as const;

// 4px grid.
export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;

export const radii = { sm: 4, md: 8 } as const;

// Smallest tap target on a phone, in px.
export const minTapTarget = 44;

// Breakpoints in px (min-width). Design for phone first, then widen.
export const breakpoints = { phone: 375, tablet: 768, desktop: 1100 } as const;

// One visible focus ring for buttons, inputs, links and scrollable tables.
export const focusRing = {
  outline: `3px solid ${colors.focus}`,
  outlineOffset: '2px',
} as const;

const px = (n: number): string => `${n}px`;

/** CSS custom properties for every token, e.g. `--color-brand`. For the app stylesheet and the Payload admin theme. Not wired up yet (tracked in #65). */
export function cssVariables(): Record<string, string> {
  const kebab = (s: string): string => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
  const vars: Record<string, string> = {};
  for (const [k, v] of Object.entries(colors)) vars[`--color-${kebab(k)}`] = v;
  for (const [k, v] of Object.entries(fonts)) vars[`--font-${k}`] = v;
  for (const [k, v] of Object.entries(fontSizes)) vars[`--font-size-${k}`] = px(v);
  for (const [k, v] of Object.entries(spacing)) vars[`--space-${k}`] = px(v);
  for (const [k, v] of Object.entries(radii)) vars[`--radius-${k}`] = px(v);
  vars['--tap-target'] = px(minTapTarget);
  vars['--focus-ring'] = focusRing.outline;
  vars['--focus-ring-offset'] = focusRing.outlineOffset;
  for (const [k, v] of Object.entries(breakpoints)) vars[`--breakpoint-${k}`] = px(v);
  return vars;
}
