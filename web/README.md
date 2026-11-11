# Stash web

Astro static site: the landing page (a React island in `src/components/Landing.tsx`) and a Markdown blog.

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # static output in dist/, served by server.ts (Bun) in the Dockerfile
```

Posts live in `src/content/blog/*.md`. `scripts/blog-draft.mjs` drafts them from commits, run by `.github/workflows/blog.yml`.
