---
name: i18n-app
description: Translate or update the Stash Mac and iOS app (SwiftUI) with an Xcode String Catalog into the 20 languages in i18n/languages.json. Use when the user asks to translate, localize or add a language to the desktop app, or to sync app translations after a UI text change.
---

Read `i18n/languages.json` and `i18n/glossary.md` first. App codes are the `apple` field (`zh-Hans`, `pt-BR`).

## Setup and extraction (setup is done; step 1 runs on every change)

1. The catalog is `Sources/Stash/Resources/Localizable.xcstrings`. Fill and refresh it from the code with the compiler, no Xcode needed:
   ```
   rm -rf .build/loc && mkdir -p .build/loc
   swift build --product Stash -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc $PWD/.build/loc
   xcrun xcstringstool sync Sources/Stash/Resources/Localizable.xcstrings --stringsdata .build/loc/*.stringsdata
   ```
   Run this after every UI text change. Keys that left the code become `stale`; delete them.
2. SwiftUI literals (`Text("..")`, `Button("..")`, `Label`, `Toggle`, `.help`, `navigationTitle`) localize by themselves. Strings in `String`, alerts, `NSMenu`, `NSAlert` and notifications do not. Wrap them in `String(localized: "...", comment: "...")`. About 184 literals in 12 files need a pass. Add a `comment` to each.
3. Never build UI text by joining strings. Use `String(localized:)` with `%@` or `%lld`, or plural variations in the catalog.
4. `App/Info.plist`: add `CFBundleLocalizations` with every `apple` code. Localize the display name and the permission texts with `InfoPlist.xcstrings`.
5. `project.yml`: set `knownRegions` to the list. Add `Sources/Stash/Resources/Localizable.xcstrings` to the resources of both the macOS and the iOS target. Also add it to the iOS Share Extension.
6. `scripts/build-app.sh` compiles the catalog with `xcrun xcstringstool compile` into `<lang>.lproj`. Keep that step: without it the SwiftPM build ships English only.
7. App Store and DMG text: translate the App Store description, keywords and screenshots text into `App/Store/<apple code>.md`. `App/DMG/background.svg` has English text. Make one per language or remove the text.

## Translate or update

1. Run the extraction in step 1 of the setup. Then in the catalog find entries with a missing language, or `state` other than `translated`, or `needs_review`. Translate only those. Set `state` to `translated`.
   Write the translations as `{ "<English key>": "<translation>" }` in a scratch file. Then run `node scripts/i18n-app-merge.mjs <apple code> <file>` and the `xcstringstool sync` command again. Do not edit the catalog by hand.
2. Keep `%@`, `%lld`, `%1$@` and the order of positional arguments.
3. Plurals: write every plural form the language needs (Russian, Polish, Arabic have more than two).
4. Test: `defaults write dev.grasco.stash AppleLanguages '(de)'` and run the app, or use the scheme option "App Language". Check truncation in German and Russian, and mirroring in Arabic.
5. Run `node scripts/i18n-check.mjs` and `swift test`.

Do not commit.
