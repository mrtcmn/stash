---
name: i18n-pre-update
description: Pre-update checklist for translations. Run before every release of the Stash app, extension or website, or when the user asks to check, sync or audit translations before an update.
---

Run this before the version bump, the DMG, the Chrome upload or a deploy. Report each line as pass, fail or not applicable. Fix nothing without the user's word.

## Checklist

1. **New text.** `git diff <last release tag>..HEAD` for changed UI strings in `Sources/`, `iOS/`, `Extension/` and `web/src`. Any literal not in a catalog or `en.json`? Move it first.
2. **Extract.** Run the app extraction commands from the `i18n-app` skill, so the catalog matches the code. Delete `stale` keys.
3. **Source first.** English files are final: `Extension/_locales/en/messages.json`, `web/src/i18n/en.json`, `Localizable.xcstrings`. Fix English typos before translation.
4. **Run the check.** `node scripts/i18n-check.mjs` exits 0. It covers missing keys, extra keys, empty text, placeholders, `needs_review` states and the Chrome store limits.
5. **Stale text.** A key whose English changed but whose translation did not is a silent bug. Compare `git log -p` of the English files with each language file. Re-translate those keys.
6. **Glossary.** New product terms are in `i18n/glossary.md` with the chosen word per language.
7. **Layout.** Check German and Russian for overflow, Arabic for mirroring, Japanese and Thai for line breaks. Surfaces: popup, the app's main window and menus, hero and pricing on the site.
8. **Language list.** `i18n/languages.json` matches `CFBundleLocalizations` in `App/Info.plist`, the `Extension/_locales` folders and the `web/src/i18n/*.json` files. The site and the sitemap read the list directly.
9. **Build.** `swift test`, `make test-extension`, `cd web && npm run build`, `scripts/build-app.sh`. Open the built app with `AppleLanguages` set to one non-English language and see translated text.
10. **Web SEO.** Every locale page has `lang`, `dir`, canonical, `hreflang` with `x-default`, `og:locale`, and is in the sitemap and `llms.txt`.
11. **Store text.** `Extension/store/*.md` and `App/Store/*.md` are current. Tell the user which store dashboards need a manual upload.
12. **Legal.** Privacy and Terms are English only until a legal review. The site links must still work in every language.
13. **Version.** The extension version in `manifest.json` is higher than the live one. The app build number is higher.

Finish with a short list: blockers first, then warnings.
