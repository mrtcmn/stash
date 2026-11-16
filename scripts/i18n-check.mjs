// Checks every translation against English: missing or extra keys, empty text, placeholders, store limits.
// Usage: node scripts/i18n-check.mjs   (ROOT=<dir> to test elsewhere). Exit 1 on any problem.
import { existsSync, readFileSync } from 'node:fs'

const ROOT = process.env.ROOT ?? '.'
const read = (p) => JSON.parse(readFileSync(`${ROOT}/${p}`, 'utf8'))
const { languages } = read('i18n/languages.json')
const targets = languages.slice(1)
const PH = /%(\d+\$)?(lld|ld|d|@|f|s)|\{\w+\}|\$[A-Z0-9_]+\$|\$\d|<\/?\w+>|`[^`]+`/g
// %1$@ and %@ are the same placeholder; only the kinds and their count must match.
const ph = (s) => (s.match(PH) ?? []).map((m) => m.replace(/^%\d+\$/, '%')).sort().join('|')
let problems = 0
const bad = (surface, lang, msg) => { problems++; console.log(`✗ ${surface} ${lang}: ${msg}`) }

// Each surface: where the source and a language file live, and how to read key -> text.
const surfaces = {
  extension: { src: 'Extension/_locales/en/messages.json', file: (l) => `Extension/_locales/${l.chrome}/messages.json`, code: 'chrome', text: (e) => e.message },
  web: { src: 'web/src/i18n/en.json', file: (l) => `web/src/i18n/${l.web}.json`, code: 'web', text: (e) => e },
}
for (const [name, s] of Object.entries(surfaces)) {
  if (!existsSync(`${ROOT}/${s.src}`)) { console.log(`- ${name}: no source file yet (${s.src})`); continue }
  const en = read(s.src)
  for (const l of targets) {
    const f = s.file(l)
    if (!existsSync(`${ROOT}/${f}`)) { bad(name, l[s.code], `missing file ${f}`); continue }
    const t = read(f)
    for (const k of Object.keys(en)) {
      const v = t[k] && s.text(t[k])
      if (!v?.trim()) bad(name, l[s.code], `missing or empty "${k}"`)
      else if (ph(v) !== ph(s.text(en[k]))) bad(name, l[s.code], `placeholders differ in "${k}"`)
    }
    for (const k of Object.keys(t)) if (!(k in en)) bad(name, l[s.code], `extra key "${k}"`)
    if (name === 'extension') {
      if (t.extName && s.text(t.extName).length > 75) bad(name, l.chrome, 'extName over 75 characters')
      if (t.extDescription && s.text(t.extDescription).length > 132) bad(name, l.chrome, 'extDescription over 132 characters')
    }
  }
}

// App: Xcode String Catalog. The key is the English text unless an "en" entry exists.
const cat = 'Sources/Stash/Resources/Localizable.xcstrings'
if (!existsSync(`${ROOT}/${cat}`)) console.log(`- app: no catalog yet (${cat})`)
else {
  for (const [key, e] of Object.entries(read(cat).strings)) {
    if (e.shouldTranslate === false) continue
    if (!/\p{L}/u.test(key.replace(PH, ''))) continue // format-only keys such as "%lld"
    const en = e.localizations?.en?.stringUnit?.value ?? key
    for (const l of targets) {
      const loc = e.localizations?.[l.apple]
      const v = loc?.stringUnit?.value
      if (loc?.variations) continue // plurals: checked in Xcode
      if (!v?.trim()) bad('app', l.apple, `missing "${key}"`)
      else if (loc.stringUnit.state !== 'translated') bad('app', l.apple, `"${key}" state is ${loc.stringUnit.state}`)
      else if (ph(v) !== ph(en)) bad('app', l.apple, `placeholders differ in "${key}"`)
    }
  }
}
console.log(problems ? `\n${problems} problem(s).` : '\nAll translations match English.')
process.exit(problems ? 1 : 0)
