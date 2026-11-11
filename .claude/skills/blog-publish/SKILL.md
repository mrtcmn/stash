---
name: blog-publish
description: Publish the Stash blog: build, commit the post, push and redeploy stash.grasco.dev. Use when the user asks to publish, ship or deploy a blog post or the website.
---

Publishing is outward-facing. Confirm with the user before the push and before the deploy.

## Steps

1. Run `blog-check` first. Stop if it reports a failure.
2. Show `git status` and the post. Stage only `web/` files for the post and its images.
3. Commit with a short message, for example `Blog: <title>`. Follow the commit attribution rules of the session.
4. Push the branch. If the user wants the push to deploy by itself, `.github/workflows/web-deploy.yml` does it after the secrets exist. Otherwise deploy by hand:
   ```
   curl -s -H "x-api-key: $(cat ~/.config/dokploy/api-key)" -H "content-type: application/json" \
     -X POST http://100.69.173.3:3000/api/application.deploy -d '{"applicationId":"YHkQ7TTxlQSowwj2B07-I"}'
   ```
   Never print the key. Dokploy is on the tailnet only.
5. Wait about a minute. Then check `https://stash.grasco.dev/blog/<slug>/` returns 200 and the homepage hero shows the new title.
