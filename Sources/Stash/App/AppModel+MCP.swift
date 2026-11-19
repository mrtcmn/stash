import Foundation
import StashCore

/// The library as an MCP server at `http://127.0.0.1:<port>/mcp`, so coding agents
/// (Claude Code, Codex, Cursor) can search and read what the user saved.
extension AppModel {
    var mcpURL: String { "http://127.0.0.1:\(settings.serverPort)/mcp" }
    var mcpInstallCommand: String { "claude mcp add --transport http stash \(mcpURL)" }

    func handleMCP(_ request: HTTPRequest) async -> HTTPResponse {
        guard MCP.isAllowed(request) else { return .error(403, "Forbidden") }
        guard request.method == "POST" else {
            // No server-to-client event stream: every answer comes back on the POST.
            return HTTPResponse(status: 405, headers: [("Allow", "POST")])
        }
        let reply = await MCP.handle(
            request.body,
            server: ("Stash", AppResources.version),
            instructions: """
                Stash is the user's personal library of saved posts from X, Reddit and Pinterest, \
                web pages, screenshots, images, notes and text clips. Use search_stash to find things \
                the user saved (it understands meaning, image content and text inside images), \
                get_snip for the full content and local media file paths, and save_to_stash to save.
                """,
            tools: Self.mcpTools,
            call: { [weak self] name, args in
                guard let self else { throw MCP.ToolError("Stash is shutting down") }
                return try await self.callMCPTool(name, args)
            }
        )
        guard let body = reply.body else { return HTTPResponse(status: 202) }
        return .json(body, status: reply.status)
    }

    private static let typeSchema: [String: Any] = [
        "type": "string",
        "enum": ["post", "link", "screenshot", "image", "note", "clip"],
        "description": "Only this kind of snip.",
    ]

    static let mcpTools: [MCP.Tool] = [
        MCP.Tool(
            name: "search_stash",
            description: "Search the user's Stash library by meaning and keywords. Matches post text, page text, text inside images and videos, and what images show. Supports operators in the query: from:handle, tag:name, type:post|link|screenshot|image|note|clip, is:fav, \"exact phrase\".",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "What to look for, in any language."],
                    "type": typeSchema,
                    "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 10],
                ],
                "required": ["query"],
            ]
        ),
        MCP.Tool(
            name: "get_snip",
            description: "Get one snip with its full text, recognized image text, page text, summary and absolute paths of its local images and video frames (readable as files).",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "The snip id from search_stash or list_recent."]],
                "required": ["id"],
            ]
        ),
        MCP.Tool(
            name: "list_recent",
            description: "List the most recently saved snips, optionally of one type or with one tag.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "type": typeSchema,
                    "tag": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 20],
                ],
            ]
        ),
        MCP.Tool(
            name: "list_tags",
            description: "List the user's tags with counts, and the names of their smart categories (use a category name as a search_stash query).",
            inputSchema: ["type": "object", "properties": [:] as [String: Any]]
        ),
        MCP.Tool(
            name: "save_to_stash",
            description: "Save a web page (url) or a note (text) to the user's Stash library.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "A web page or post link to save."],
                    "text": ["type": "string", "description": "Note text to save when there is no url."],
                    "title": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                ],
            ],
            readOnly: false
        ),
    ]

    private func callMCPTool(_ name: String, _ args: [String: Any]) async throws -> String {
        switch name {
        case "search_stash":
            guard var query = MCP.string(args, "query") else { throw MCP.ToolError("query is required") }
            if let type = MCP.string(args, "type") { query += " type:\(type)" }
            let limit = MCP.int(args, "limit", default: 10, range: 1...50)
            let parsed = QueryParser.parse(query)
            let semantic = parsed.hasFreeText && index.isReady ? try? await index.scores(forQuery: parsed.text) : nil
            let hits = HybridRanker.relevant(
                HybridRanker.rank(search.currentCandidates(), query: parsed, semantic: semantic),
                limit: limit
            )
            let results: [[String: Any]] = hits.compactMap { hit in
                guard let snip = library.snip(hit.id) else { return nil }
                var row = mcpJSON(snip, full: false)
                row["score"] = (hit.score * 1000).rounded() / 1000
                return row
            }
            return try encode(["semantic": semantic != nil, "count": results.count, "results": results])

        case "get_snip":
            guard let raw = MCP.string(args, "id"), let id = UUID(uuidString: raw), let snip = library.snip(id) else {
                throw MCP.ToolError("No snip with that id.")
            }
            return try encode(mcpJSON(snip, full: true))

        case "list_recent":
            var snips = library.snips.sorted { $0.savedAt > $1.savedAt }
            if let type = MCP.string(args, "type") {
                let kinds = QueryParser.parse("type:\(type)").kinds
                snips = snips.filter { kinds.contains($0.kind) }
            }
            if let tag = MCP.string(args, "tag").map(TagNormalizer.normalize) {
                snips = snips.filter { $0.tags.contains(tag) }
            }
            let limit = MCP.int(args, "limit", default: 20, range: 1...50)
            return try encode(["results": snips.prefix(limit).map { mcpJSON($0, full: false) }])

        case "list_tags":
            return try encode([
                "tags": library.tagCounts.map { ["tag": $0.tag, "count": $0.count] },
                "categories": settings.categories,
            ])

        case "save_to_stash":
            let tags = MCP.strings(args, "tags")
            if let raw = MCP.string(args, "url") {
                guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else {
                    throw MCP.ToolError("url must be an http or https link.")
                }
                await saveURL(url, title: MCP.string(args, "title"), source: "mcp")
                let normalized = "url:\(URLNormalizer.normalize(url.absoluteString))"
                let saved = library.snip(externalID: normalized)
                    ?? TweetURL.parse(url.absoluteString).flatMap { library.snip(externalID: $0.externalID) }
                if let saved, !tags.isEmpty { setTags(saved.tags + tags, for: saved.id) }
                return try encode(["saved": saved != nil, "id": saved?.id.uuidString ?? NSNull()])
            }
            guard let text = MCP.string(args, "text") else { throw MCP.ToolError("Give a url or a text.") }
            guard let note = addNote(title: MCP.string(args, "title") ?? "", body: text, tags: tags) else {
                throw MCP.ToolError("The note is empty.")
            }
            return try encode(["saved": true, "id": note.id.uuidString])

        default:
            throw MCP.ToolError("Unknown tool \(name)")
        }
    }

    private func mcpJSON(_ snip: Snip, full: Bool) -> [String: Any] {
        func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
        let iso = ISO8601DateFormatter()
        var row: [String: Any] = [
            "id": snip.id.uuidString,
            "type": QueryParser.typeName(snip.kind),
            "title": snip.displayTitle,
            "savedAt": iso.string(from: snip.savedAt),
        ]
        if let url = snip.url { row["url"] = url }
        if let author = snip.author { row["author"] = author.handle.isEmpty ? author.name : "@\(author.handle)" }
        if !snip.body.isEmpty { row["text"] = full ? snip.body : clip(snip.body, 500) }
        if let summary = snip.summary ?? snip.link?.summary { row["summary"] = summary }
        if !snip.tags.isEmpty { row["tags"] = snip.tags }
        if !snip.labels.isEmpty { row["imageLabels"] = snip.labels }
        if let ocr = snip.ocrText, !ocr.isEmpty { row["textInImages"] = full ? ocr : clip(ocr, 300) }
        if full {
            row["createdAt"] = iso.string(from: snip.createdAt)
            if let content = snip.link?.content { row["pageText"] = clip(content, 20_000) }
            if let quoted = snip.tweet?.quoted { row["quoted"] = quoted.text }
            let media: [[String: Any]] = snip.media.map { m in
                var item: [String: Any] = ["kind": m.kind.rawValue]
                if let file = m.localFile { item["file"] = library.media.url(for: file).path }
                if let remote = m.remoteURL { item["remoteURL"] = remote }
                if let video = m.videoURL { item["videoURL"] = video }
                if let frames = m.frames { item["videoFrames"] = frames.map { library.media.url(for: $0).path } }
                if let alt = m.alt { item["alt"] = alt }
                return item
            }
            if !media.isEmpty { row["media"] = media }
        }
        return row
    }

    private func encode(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
