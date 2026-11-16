// Writes translations into the app's String Catalog.
// Usage: node scripts/i18n-app-merge.mjs <apple code> <file.json>   file: { "<English key>": "<translation>" }
// Unknown keys are reported and skipped. Run the xcstringstool sync afterwards to restore Xcode's formatting.
import { readFileSync, writeFileSync } from 'node:fs'

const [lang, file] = process.argv.slice(2)
if (!lang || !file) { console.error('Usage: node scripts/i18n-app-merge.mjs <apple code> <file.json>'); process.exit(2) }
const CAT = 'Sources/Stash/Resources/Localizable.xcstrings'
const cat = JSON.parse(readFileSync(CAT, 'utf8'))
const add = JSON.parse(readFileSync(file, 'utf8'))
let n = 0
for (const [key, value] of Object.entries(add)) {
  const e = cat.strings[key]
  if (!e) { console.log(`skip unknown key: ${key}`); continue }
  if (typeof value !== 'string' || !value.trim()) { console.log(`skip empty: ${key}`); continue }
  e.localizations ??= {}
  e.localizations[lang] = { stringUnit: { state: 'translated', value } }
  n++
}
writeFileSync(CAT, JSON.stringify(cat, null, 2) + '\n')
console.log(`${lang}: ${n} strings written`)
