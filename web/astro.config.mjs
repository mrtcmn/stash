import { defineConfig } from 'astro/config'
import react from '@astrojs/react'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  site: 'https://stash.grasco.dev',
  trailingSlash: 'always',
  integrations: [react(), sitemap({ customPages: ['https://stash.grasco.dev/privacy.html', 'https://stash.grasco.dev/terms.html'] })],
  vite: { plugins: [tailwindcss()], resolve: { alias: { '#': new URL('./src', import.meta.url).pathname } } },
})
