import { defineCollection } from 'astro:content'
import { glob } from 'astro/loaders'
import { z } from 'astro/zod'

const blog = defineCollection({
  loader: glob({ pattern: '*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(),
    description: z.string().max(160),
    date: z.coerce.date(),
    updated: z.coerce.date().optional(),
    tags: z.array(z.string()).default([]),
    // Images live in public/blog/<post id>/. cover: 1200x630 WebP on the page; og: the same as JPEG for social cards.
    cover: z.string().optional(),
    coverAlt: z.string().optional(),
    og: z.string().optional(),
    // Last commit this post covers; the draft script starts from here.
    commit: z.string().optional(),
  }),
})

export const collections = { blog }
