import list from '../../../i18n/languages.json'
import en from './en.json'
import type { Strings } from './t'

export type Lang = (typeof list.languages)[number] & { rtl?: boolean }
export const LANGS: Lang[] = list.languages
export const EN = LANGS[0]

const files = import.meta.glob<Strings>('./*.json', { eager: true, import: 'default' })

/** Languages with a translation file. Only these get pages, hreflang links and switcher entries. */
export const LIVE = LANGS.filter((l) => l === EN || `./${l.web}.json` in files)

/** English, overlaid with the language file. Missing keys fall back to English. */
export const stringsFor = (lang: Lang): Strings => ({ ...en, ...(files[`./${lang.web}.json`] ?? {}) })
export const homePath = (lang: Lang) => (lang.web === 'en' ? '/' : `/${lang.web}/`)
export const ogLocale = (lang: Lang) => lang.hreflang.replace('-', '_')
