import { defineConfig } from 'astro/config'
import react from '@astrojs/react'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'
import languages from '../i18n/languages.json' with { type: 'json' }

// Sitemap alternates: URL segment -> hreflang. English lives at the root.
const locales = Object.fromEntries(languages.languages.map((l) => [l.web, l.hreflang]))

export default defineConfig({
  site: 'https://stash.grasco.dev',
  trailingSlash: 'always',
  integrations: [react(), sitemap({ i18n: { defaultLocale: 'en', locales }, customPages: ['https://stash.grasco.dev/privacy.html', 'https://stash.grasco.dev/terms.html'] })],
  vite: { plugins: [tailwindcss()], resolve: { alias: { '#': new URL('./src', import.meta.url).pathname } } },
})
