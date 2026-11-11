import rss from '@astrojs/rss'
import type { APIContext } from 'astro'
import { allPosts } from '../lib/posts'

export async function GET(ctx: APIContext) {
  const posts = await allPosts()
  return rss({
    title: 'Stash blog',
    description: 'What changed in Stash.',
    site: ctx.site!,
    items: posts.map((p) => ({ title: p.data.title, description: p.data.description, pubDate: p.data.date, link: `/blog/${p.id}/` })),
  })
}
