// Production server: static files from dist/. Astro builds directories, so /blog/ serves /blog/index.html.
const root = `${import.meta.dir}/dist`

Bun.serve({
  port: Number(process.env.PORT ?? 3000),
  async fetch(req) {
    const url = new URL(req.url)
    const path = decodeURIComponent(url.pathname)
    if (!path.includes('..')) {
      const file = Bun.file(root + (path.endsWith('/') ? path + 'index.html' : path))
      if (await file.exists()) {
        // Astro fingerprints /_astro; everything else can change between deploys.
        const cache = path.startsWith('/_astro/') ? 'public, max-age=31536000, immutable' : path.endsWith('.html') || path.endsWith('/') ? 'public, max-age=0, s-maxage=600, stale-while-revalidate=86400' : 'public, max-age=3600'
        return serveFile(req, file, cache)
      }
      // /blog -> /blog/ (trailingSlash: always)
      if (!path.split('/').pop()!.includes('.') && (await Bun.file(root + path + '/index.html').exists())) {
        return Response.redirect(url.origin + path + '/' + url.search, 301)
      }
    }
    return new Response((await Bun.file(root + '/404.html').exists()) ? Bun.file(root + '/404.html') : 'Not found', { status: 404, headers: { 'Content-Type': 'text/html; charset=utf-8' } })
  },
})

// Range support: Safari will not play a <video> from a server that ignores Range.
function serveFile(req: Request, file: ReturnType<typeof Bun.file>, cache: string) {
  const headers = { 'Content-Type': file.type, 'Cache-Control': cache, 'Accept-Ranges': 'bytes' }
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get('range') ?? '')
  if (!m) return new Response(file, { headers })
  const size = file.size
  const start = m[1] ? Number(m[1]) : Math.max(0, size - Number(m[2]))
  const end = m[1] && m[2] ? Math.min(Number(m[2]), size - 1) : size - 1
  if (start >= size || start > end) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } })
  return new Response(file.slice(start, end + 1), {
    status: 206,
    headers: { ...headers, 'Content-Range': `bytes ${start}-${end}/${size}`, 'Content-Length': String(end - start + 1) },
  })
}
