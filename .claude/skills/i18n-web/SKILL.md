---
name: i18n-web
description: Translate or update the Stash website (Astro, web/) into the 20 languages in i18n/languages.json. Use when the user asks to translate, localize or add a language to the site or blog, or to sync web translations after a copy change.
---

Read `i18n/languages.json` and `i18n/glossary.md` first. English is the source.

## Setup (done; read it to know how the site works)

A language gets pages, `hreflang` links and a switcher entry only when `web/src/i18n/<web>.json` exists (`LIVE` in `web/src/i18n/index.ts`). This prevents English copies under other URLs.


1. Move every visible string out of `web/src/components/Landing.tsx`, `SearchMode.tsx`, `FooterWordmark.tsx` and the layouts into `web/src/i18n/en.json`. Use flat keys like `hero.title`. Use `{name}` for values. Add `web/src/i18n/index.ts` with `t(locale, key, vars)`; it falls back to English.
2. In `web/astro.config.mjs` set `i18n: { defaultLocale: 'en', locales: [...web codes], routing: { prefixDefaultLocale: false } }`.
3. Pages: `src/pages/[...locale]/index.astro` via `getStaticPaths`, one page per locale. `Landing` takes `locale` and `strings` as props. The island must not import all 20 files: pass only the active one.
4. In `Base.astro` set `<html lang dir>` (`dir="rtl"` for `rtl: true`), a canonical per locale, `hreflang` links for every locale plus `x-default`, and `og:locale`.
5. The language switcher is a row of plain links in the homepage footer. It works with no JS.
6. Sitemap: use the sitemap integration's `i18n` option so it emits `xhtml:link` alternates. Add each locale to `llms.txt`.
7. Blog: posts stay English. Blog pages stay at `/blog/`. Put `hreflang` only on pages that have translations. Record this choice in `i18n/glossary.md` if the user wants translated posts later.
8. Privacy and Terms (`web/public/*.html`) need a legal review before translation. Leave them English and ask the user.

## Translate or update

1. Diff `web/src/i18n/en.json` against each `<web>.json`. Translate only missing or changed keys. Never rewrite keys that did not change.
2. Write each language file with the same keys in the same order.
3. Check the glossary words for that language. Add new chosen words to the glossary.
4. Check the hero and nav in the widest language (German, Russian) for overflow. Check Arabic for layout.
5. Run `node scripts/i18n-check.mjs` and `cd web && npm run build`. Both must pass.

Do not commit. Do not translate with a script that calls a paid API unless the user asks.
