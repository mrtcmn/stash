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
   cover: /blog/<post id>/cover.webp      # optional, see step 5
   coverAlt: "What the cover shows"
   og: /blog/<post id>/og.jpg             # social card, same image as JPEG
   commit: <short sha of HEAD>
   ---
   ```
   `<post id>` is the file name without `.md`.
5. Images. Make a cover for every post:
   `scripts/blog-cover.py web/public/blog/<post id> "<short title>" "<subtitle>" [chip ...]`
   It writes `cover.webp` and `og.jpg` (1200x630) in the site style. Chips are optional short labels. Open the result and look at it.
   For real screenshots of the site, build it, run `PORT=4173 bun server.ts` in `web/`, and use headless Chrome:
   `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1280,800 --force-device-scale-factor=1 --virtual-time-budget=1600 --user-data-dir=<scratch dir> --screenshot=<file>.png <url>`
   Keep the budget under 3000 ms: the hero typewriter starts at 3 s. Crop and convert with `ffmpeg -vf "crop=1280:640:0:0,scale=1200:-1"` and `cwebp -q 80`. Chrome may not exit by itself: stop it after the file appears.
   In the body, use `<img src="/blog/<post id>/x.webp" alt="…" width="1200" height="600" loading="lazy" />`, not Markdown images, so the page has no layout shift.
6. Body: 80 to 250 words. Use `##` headings, never `#`. Start with what the user gains. Link to `/` or `/blog/` pages when it helps. Use only absolute paths from the site root.
7. Run `cd web && npm run build`. The schema fails the build on a bad field. Fix it and run again.
8. Tell the user the file path. Do not commit. Offer the `blog-check` and `blog-publish` skills.

## Rules

- Say only what the commits show. Never invent a feature, a number or a date.
- Write for users of the Mac app, not for developers, unless the user asks for a dev log.
- One post per topic. To change a published post, edit the same file and set `updated`.
- Images go in `web/public/blog/`. Use the alt text. Prefer WebP, 1200 px wide at most.
