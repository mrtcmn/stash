---
name: i18n-extension
description: Translate or update the Stash Chrome extension (Extension/) with chrome.i18n into the 20 languages in i18n/languages.json. Use when the user asks to translate, localize or add a language to the extension or its store listing.
---

Read `i18n/languages.json` and `i18n/glossary.md` first. Chrome locale codes are the `chrome` field (`zh_CN`, `pt_BR`, with an underscore).

## One-time setup (skip if `Extension/_locales/en/messages.json` exists)

1. In `manifest.json` add `"default_locale": "en"`. Replace the `name`, `description` and the two command descriptions with `__MSG_extName__`, `__MSG_extDescription__`, and so on.
2. Move every user-visible string of `popup/popup.html`, `popup/popup.js`, `content/x.js` and `background.js` into `_locales/en/messages.json`. Each entry is `{ "message": "...", "description": "where it shows" }`. Use `placeholders` for values. Give a `description` for every key; translators need it.
3. In HTML put `data-i18n="key"` on elements and fill them at load with `chrome.i18n.getMessage`. In JS replace literals with `chrome.i18n.getMessage('key', [values])`. Content scripts can call it too.
4. Keep `extName` at 75 characters or fewer and `extDescription` at 132 or fewer in every language.
5. `Extension/` is also bundled in the Mac app by `scripts/build-app.sh` and `project.yml`. `_locales` goes with it. Check the rsync excludes do not drop it.
6. Keep `Extension/tests/` green: `make test-extension`.

## Translate or update

1. Diff `en/messages.json` against each language. Translate only missing or changed keys. Keep key order.
2. Keep every `$1`, `$NAME$` and `placeholders` block. Keep `⌥⇧S` style shortcuts.
3. Check the popup width in German and Russian. Short labels win over exact ones.
4. Run `node scripts/i18n-check.mjs` and `make test-extension`.
5. Store listing: translate the name, short description and long description for the Chrome Web Store dashboard into `Extension/store/<chrome code>.md`. The dashboard is manual. Tell the user which languages still need an upload.
6. Bump the extension version in `manifest.json`. Chrome rejects an upload with the same version.

Do not commit.
