import Foundation
import XCTest
@testable import StashCore

final class MediaAndSourcesTests: XCTestCase {
    func testRecognizedTextRanksBelowWrittenText() {
        let written = Snip(kind: .tweet, body: "invoice template")
        let recognized = Snip(kind: .tweet, body: "look at this", ocrText: "Invoice total")
        let labeled = Snip(kind: .tweet, body: "nice", labels: ["invoice"])
        let hits = HybridRanker.rank([written, recognized, labeled].map(SearchCandidate.init), query: QueryParser.parse("invoice"), semantic: nil)
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits.first?.id, written.id)
        XCTAssertLessThan(hits[1].keyword, hits[0].keyword)
        XCTAssertGreaterThan(hits[1].keyword, 0)
    }

    func testDocumentUsesAllPhotosVideoFramesOCRAndLabels() {
        let snip = Snip(
            kind: .tweet,
            body: "launch video",
            media: [
                SnipMedia(kind: .image, localFile: "a.jpg"),
                SnipMedia(kind: .video, localFile: "poster.jpg", videoURL: "https://v/x.mp4", frames: ["f1.jpg", "f2.jpg"]),
            ],
            ocrText: "SALE 50%",
            labels: ["chart"]
        )
        let doc = EmbeddingDocumentBuilder.document(for: snip, style: .gemma)
        XCTAssertEqual(doc.imageFiles, ["a.jpg", "f1.jpg", "f2.jpg"])
        XCTAssertTrue(doc.text?.contains("SALE 50%") == true)
        XCTAssertTrue(doc.text?.contains("chart") == true)
        XCTAssertEqual(doc.text?.components(separatedBy: EmbeddingPrompts.imagePlaceholder).count, 4)

        let many = Snip(kind: .tweet, body: "x", media: (0..<10).map { SnipMedia(localFile: "\($0).jpg") })
        XCTAssertEqual(EmbeddingDocumentBuilder.document(for: many, style: .gemma).imageFiles.count, 6)
    }

    func testRedditJSONURL() {
        XCTAssertEqual(
            RedditParser.jsonURL(for: URL(string: "https://old.reddit.com/r/swift/comments/abc123/some_title/")!)?.absoluteString,
            "https://www.reddit.com/r/swift/comments/abc123/some_title.json?raw_json=1&limit=1"
        )
        XCTAssertNil(RedditParser.jsonURL(for: URL(string: "https://www.reddit.com/r/swift/")!))
        XCTAssertNil(RedditParser.jsonURL(for: URL(string: "https://example.com/comments/1")!))
    }

    func testRedditGalleryPost() throws {
        let json = """
        [{"data":{"children":[{"kind":"t3","data":{
          "title":"My setup","selftext":"Desk tour","author":"alice","subreddit":"battlestations",
          "permalink":"/r/battlestations/comments/x1/my_setup/","created_utc":1700000000,
          "gallery_data":{"items":[{"media_id":"b"},{"media_id":"a"}]},
          "media_metadata":{"a":{"s":{"u":"https://i.redd.it/a.jpg?x=1&amp;y=2","x":10,"y":20}},"b":{"s":{"u":"https://i.redd.it/b.jpg","x":30,"y":40}}}
        }}]}},{"data":{"children":[]}}]
        """
        let snip = try RedditParser.snip(from: Data(json.utf8), source: "test")
        XCTAssertEqual(snip.kind, .link)
        XCTAssertEqual(snip.title, "My setup")
        XCTAssertEqual(snip.body, "Desk tour")
        XCTAssertEqual(snip.author?.handle, "alice")
        XCTAssertEqual(snip.tags, ["r-battlestations"])
        XCTAssertEqual(snip.url, "https://www.reddit.com/r/battlestations/comments/x1/my_setup/")
        XCTAssertEqual(snip.media.map(\.remoteURL), ["https://i.redd.it/b.jpg", "https://i.redd.it/a.jpg?x=1&y=2"])
        XCTAssertEqual(snip.createdAt, Date(timeIntervalSince1970: 1700000000))
    }

    func testRedditVideoPost() throws {
        let json = """
        {"data":{"children":[{"data":{"title":"Clip","author":"bob","subreddit":"videos","permalink":"/r/videos/comments/v1/clip/",
          "secure_media":{"reddit_video":{"fallback_url":"https://v.redd.it/v1/DASH_720.mp4","width":1280,"height":720}},
          "preview":{"images":[{"source":{"url":"https://preview.redd.it/p.jpg","width":1280,"height":720}}]}}}]}}
        """
        let snip = try RedditParser.snip(from: Data(json.utf8), source: nil)
        XCTAssertEqual(snip.media.count, 1)
        XCTAssertEqual(snip.media[0].kind, .video)
        XCTAssertEqual(snip.media[0].videoURL, "https://v.redd.it/v1/DASH_720.mp4")
        XCTAssertEqual(snip.media[0].remoteURL, "https://preview.redd.it/p.jpg")
    }

    func testOldRowsDecodeWithoutNewFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"tweet","media":[{"kind":"video","videoURL":"https://v"}]}"#
        let snip = try SnipCoding.storageDecoder().decode(Snip.self, from: Data(json.utf8))
        XCTAssertEqual(snip.labels, [])
        XCTAssertNil(snip.analysisVersion)
        XCTAssertNil(snip.media[0].frames)
    }
}

final class ReadableTextTests: XCTestCase {
    func testArticleWinsOverChrome() {
        let body = String(repeating: "Real paragraph text. ", count: 20)
        let html = "<html><head><script>var x=1</script></head><body><nav>Home About</nav><article><h1>Title</h1><p>\(body)</p></article><footer>© 2026</footer></body></html>"
        let text = HTMLText.readableText(fromPage: html)
        XCTAssertTrue(text.hasPrefix("Title"))
        XCTAssertFalse(text.contains("Home About"))
        XCTAssertFalse(text.contains("©"))
        XCTAssertFalse(text.contains("var x"))
    }

    func testBodyFallbackDropsNavigation() {
        let html = "<body><header>Logo</header><div>Short page</div><nav>Menu</nav></body>"
        XCTAssertEqual(HTMLText.readableText(fromPage: html), "Short page")
    }
}
