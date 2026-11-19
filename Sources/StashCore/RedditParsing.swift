import Foundation

/// Reads a Reddit post from Reddit's public JSON (`<permalink>.json`).
public enum RedditParser {
    /// The JSON URL for a Reddit post link, or nil if `url` is not a post.
    public static func jsonURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host == "reddit.com" || host.hasSuffix(".reddit.com"),
              url.path.contains("/comments/") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.reddit.com"
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + ".json"
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1"), URLQueryItem(name: "limit", value: "1")]
        return components.url
    }

    public static func snip(from data: Data, source: String?, now: Date = Date()) throws -> Snip {
        let root = try JSONSerialization.jsonObject(with: data)
        // A post page is [post listing, comments listing]; accept a bare listing too.
        let listing = (root as? [Any])?.first ?? root
        guard let post = JSONValue.object(JSONValue.value(JSONValue.array(JSONValue.value(listing, "data.children")).first, "data")) else {
            throw PostParseError.unavailable("Reddit post")
        }
        return snip(fromPost: post, source: source, now: now)
    }

    /// Builds a link snip from one `t3` post object.
    public static func snip(fromPost post: [String: Any], source: String?, now: Date = Date()) -> Snip {
        let permalink = JSONValue.string(post["permalink"]).map { "https://www.reddit.com" + $0 }
        let url = permalink ?? JSONValue.string(post["url"]) ?? "https://www.reddit.com"
        let subreddit = JSONValue.string(post["subreddit"])
        let handle = JSONValue.string(post["author"])
        let created = (post["created_utc"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let title = JSONValue.string(post["title"]) ?? ""
        let outbound = JSONValue.string(post["url_overridden_by_dest"])
        var body = JSONValue.string(post["selftext"]) ?? ""
        if let outbound, !outbound.contains("reddit.com"), !outbound.contains("redd.it") {
            body = [body, outbound].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }

        return Snip(
            kind: .link,
            title: title,
            body: body,
            url: url,
            author: handle.map { SnipAuthor(name: $0, handle: $0) },
            media: media(post),
            tags: subreddit.map { [TagNormalizer.normalize("r-\($0)")] } ?? [],
            createdAt: created ?? now,
            savedAt: now,
            source: source,
            externalID: "url:\(URLNormalizer.normalize(url))",
            link: LinkInfo(url: url, title: title, siteName: subreddit.map { "r/\($0)" } ?? "Reddit")
        )
    }

    static func media(_ post: [String: Any]) -> [SnipMedia] {
        let source = JSONValue.value(JSONValue.array(JSONValue.value(post, "preview.images")).first, "source")
        let poster = JSONValue.string(JSONValue.value(source, "url")).map(unescape)
        if let video = JSONValue.value(post, "secure_media.reddit_video") ?? JSONValue.value(post, "media.reddit_video"),
           let mp4 = JSONValue.string(JSONValue.value(video, "fallback_url")) {
            return [SnipMedia(
                kind: .video,
                remoteURL: poster,
                videoURL: unescape(mp4),
                width: JSONValue.int(JSONValue.value(video, "width")),
                height: JSONValue.int(JSONValue.value(video, "height"))
            )]
        }
        if let metadata = post["media_metadata"] as? [String: Any] {
            var order = JSONValue.array(JSONValue.value(post, "gallery_data.items"))
                .compactMap { JSONValue.string(JSONValue.value($0, "media_id")) }
            if order.isEmpty { order = metadata.keys.sorted() }
            let items: [SnipMedia] = order.compactMap { id in
                guard let entry = metadata[id], let u = JSONValue.string(JSONValue.value(entry, "s.u") ?? JSONValue.value(entry, "s.gif")) else { return nil }
                return SnipMedia(
                    kind: .image,
                    remoteURL: unescape(u),
                    width: JSONValue.int(JSONValue.value(entry, "s.x")),
                    height: JSONValue.int(JSONValue.value(entry, "s.y"))
                )
            }
            if !items.isEmpty { return items }
        }
        guard let poster else { return [] }
        return [SnipMedia(
            kind: .image,
            remoteURL: poster,
            width: JSONValue.int(JSONValue.value(source, "width")),
            height: JSONValue.int(JSONValue.value(source, "height"))
        )]
    }

    /// Reddit escapes `&` in media URLs unless `raw_json=1` was asked for.
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
    }
}
