---
name: blog-check
description: Check a Stash blog post for SEO, GEO and page-speed problems after building the site. Use when the user asks to review, check or audit a post or the blog before publishing.
---

Build first: `cd web && npm run build`. Then check the post at `web/dist/blog/<slug>/index.html` and the files next to it. Report each failure with the fix. Fix it only when the user asks.

## Checklist

- Title: under 60 characters, one `<title>`, one `<h1>`, headings in order.
- Description: 70 to 160 characters, unique among posts.
- `<link rel="canonical">` is `https://stash.grasco.dev/blog/<slug>/` with the trailing slash.
- Open Graph: `og:type` is `article`. `article:published_time` and `article:modified_time` exist.
- JSON-LD: `BlogPosting` has headline, datePublished, dateModified, author, publisher, mainEntityOfPage. `BreadcrumbList` exists.
- The post is in `dist/sitemap-0.xml`, `dist/rss.xml` and `dist/llms.txt`.
- No `<script>` except JSON-LD on the blog pages. Blog pages must ship no JS.
- Images have `alt`, `width` and `height`, and are WebP or AVIF under 200 KB.
- No broken internal link: every `href` that starts with `/` points to a file in `dist/`.
- The homepage hero pill links to the newest post: `grep -o 'Latest</span>.*' dist/index.html`.
