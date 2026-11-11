---
name: blog-post
description: Write or update a Stash blog post by hand from recent commits. Use when the user asks to write, draft or update a blog post, a changelog post, or release notes for the website.
---

Posts are Markdown files in `web/src/content/blog/`. The file name is the URL: `YYYY-MM-DD-slug.md` becomes `/blog/YYYY-MM-DD-slug/`. Nothing generates posts automatically.

## Steps

1. Find the last covered commit: read the `commit:` field of the newest file in `web/src/content/blog/`. If no post has it, use `HEAD~15`.
2. Read what changed: `git log --no-merges --format='%h %s%n%b' <commit>..HEAD -- . ':!web/src/content'`. Read the diff of a commit when the subject is unclear.
3. Ask the user for the angle only if the commits do not show one. Otherwise pick the changes a user would notice. Skip refactors, CI and chores.
4. Write the file. Use this frontmatter and no other fields:
   ```
   ---
   title: "Plain title, 60 characters or fewer"
   description: "One sentence, 155 characters or fewer. It becomes the meta description."
   date: YYYY-MM-DD
   updated: YYYY-MM-DD   # only when you edit an existing post
   tags: [changelog]
   commit: <short sha of HEAD>
   ---
   ```
5. Body: 80 to 250 words. Use `##` headings, never `#`. Start with what the user gains. Link to `/` or `/blog/` pages when it helps. Use only absolute paths from the site root.
6. Run `cd web && npm run build`. The schema fails the build on a bad field. Fix it and run again.
7. Tell the user the file path. Do not commit. Offer the `blog-check` and `blog-publish` skills.

## Rules

- Say only what the commits show. Never invent a feature, a number or a date.
- Write for users of the Mac app, not for developers, unless the user asks for a dev log.
- One post per topic. To change a published post, edit the same file and set `updated`.
- Images go in `web/public/blog/`. Use the alt text. Prefer WebP, 1200 px wide at most.
