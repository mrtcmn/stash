import { getCollection } from 'astro:content'

export const SITE = 'https://stash.grasco.dev'

/** Newest first. */
export async function allPosts() {
  return (await getCollection('blog')).sort((a, b) => +b.data.date - +a.data.date)
}
