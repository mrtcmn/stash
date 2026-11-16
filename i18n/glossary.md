# Translation rules (all surfaces)

- English is the source. Translate from the English text, never from another language.
- Never translate: `Stash`, `Mac`, `macOS`, `X`, `Chrome`, `GitHub`, `Pexels`, file names, URLs, code, and key shortcuts such as `⌥⇧S`.
- Keep every placeholder exactly: `%@`, `%lld`, `%1$@`, `$1`, `$NAME$`, `{name}`, and Markdown or HTML tags.
- Tone: short, friendly, plain. Use the informal "you" where the language has one (tu, du, 你). Use the polite form in Japanese and Korean.
- Keep the length close to English. Buttons and the popup have no room for long text.
- UI verbs: "Save" is the product action. Use one word for it in each language and keep it everywhere. Pick the word once and record it below.
- Search is by meaning, on-device. Never write that Stash uploads or shares data.
- Store limits (Chrome Web Store): name 75 characters, short description 132 characters.

## Chosen words (add one line per language when you pick them)

- zh-Hans: Save = 保存; snip = 摘录; library = 资料库
- zh-Hant: Save = 儲存; snip = 摘錄; library = 資料庫
- ja: Save = 保存; snip = スニップ; library = ライブラリ
- ko: Save = 저장; snip = 항목; library = 보관함
- th: Save = บันทึก; snip = รายการ; library = คลัง
- es: Save = Guardar; snip = recorte; library = biblioteca; X bookmarks = marcadores
- pt-BR: Save = Salvar; snip = recorte; library = biblioteca; bookmarks = marcadores (Favoritos is the Favorites filter)
- fr: Save = Enregistrer; snip = extrait; library = bibliothèque
- it: Save = Salva; snip = ritaglio; library = libreria
- de: Save = Sichern; snip = Snip; library = Mediathek; Terms = AGB
- ru: Save = Сохранить; snip = запись; library = библиотека
- uk: Save = Зберегти; snip = запис; library = бібліотека
- pl: Save = Zapisz; snip = zapis; library = biblioteka
- nl: Save = Bewaren; snip = snip; library = bibliotheek
- tr: Save = Kaydet; snip = kayıt; library = arşiv; suffixes after brand names take an apostrophe (Stash'e)
- ar: Save = احفظ; snip = قصاصة; library = مكتبة; counts as "label: number"
- hi: Save = सहेजें; snip = स्निप; library = लाइब्रेरी; uses the polite आप
- id: Save = Simpan; snip = snip; library = pustaka
- vi: Save = Lưu; snip = mẩu lưu; library = thư viện

## App notes

- The Services menu item "Save to Stash" comes from `App/Info.plist` and stays English until `InfoPlist.xcstrings` exists. Sentences that name it keep it in English.
- `Settings` and `Browser` in the extension `portHint` must match the app's menu words.

## Counts

Russian, Ukrainian, Polish and Arabic have more than two plural forms. Write counted text without a plural noun: "Результатов: {count}".

## What stays English

Blog posts, Privacy and Terms, and the sample posts in the website search demo.
