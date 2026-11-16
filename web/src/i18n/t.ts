// Client-safe helpers: no language files here, so the island bundles none of them.
export type Strings = Record<string, string>
export type T = (key: string, vars?: Record<string, string | number>) => string

/** `{name}` placeholders. A missing key shows the key, so brand names can pass through as keys. */
export const makeT = (s: Strings): T => (key, vars) =>
  (s[key] ?? key).replace(/\{(\w+)\}/g, (m, k) => (vars && k in vars ? String(vars[k]) : m))
