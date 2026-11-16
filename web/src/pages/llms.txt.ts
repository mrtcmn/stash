import { allPosts, SITE } from '../lib/posts'
import { LIVE, homePath } from '../i18n'

// llms.txt: a plain index for generative engines (llmstxt.org format).
export async function GET() {
  const posts = await allPosts()
  const body = `# Stash

> Stash saves every post, page and screenshot you keep in one library on your Mac and finds them by meaning, on-device. Free, macOS 26+, Apple Silicon.

## Product
- [Home](${SITE}/): what Stash does, pricing and FAQ
- [Privacy](${SITE}/privacy.html): what the app and the site collect
- [Source](https://github.com/mrtcmn/stash): code and releases

## Languages
The homepage exists in ${LIVE.length} languages:
${LIVE.map((l) => `- [${l.name}](${SITE}${homePath(l)})`).join('\n')}

## Blog
${posts.map((p) => `- [${p.data.title}](${SITE}/blog/${p.id}/): ${p.data.description}`).join('\n') || '- No posts yet.'}
`
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } })
}
