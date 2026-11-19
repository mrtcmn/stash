import Foundation

/// A minimal Model Context Protocol server over Streamable HTTP: one JSON-RPC message per
/// POST, answered with plain JSON (no event stream, no sessions). That is enough for
/// Claude Code, Codex and Cursor to list and call tools.
public enum MCP {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public struct Tool: @unchecked Sendable {
        public var name: String
        public var description: String
        /// JSON Schema of the arguments.
        public var inputSchema: [String: Any]
        public var readOnly: Bool

        public init(name: String, description: String, inputSchema: [String: Any], readOnly: Bool = true) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
            self.readOnly = readOnly
        }
    }

    /// A tool failure the model should see, e.g. "No snip with that id".
    public struct ToolError: Error {
        public var message: String
        public init(_ message: String) { self.message = message }
    }

    /// The HTTP status and JSON body to send. A nil body means 202 Accepted with no content.
    public struct Reply {
        public var status: Int
        public var body: Any?
    }

    public static func handle(
        _ body: Data,
        server: (name: String, version: String),
        instructions: String,
        tools: [Tool],
        call: (String, [String: Any]) async throws -> String
    ) async -> Reply {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return Reply(status: 400, body: failure(id: nil, code: -32700, "Parse error"))
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // A response from the client to a request we never send.
            return Reply(status: 202, body: nil)
        }
        // Notifications (no id) need no answer.
        guard let id, !(id is NSNull) else { return Reply(status: 202, body: nil) }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return Reply(status: 200, body: success(id: id, [
                "protocolVersion": supportedVersions.contains(asked) ? asked : supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": server.name, "version": server.version],
                "instructions": instructions,
            ]))

        case "ping":
            return Reply(status: 200, body: success(id: id, [:]))

        case "tools/list":
            let list: [[String: Any]] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                    "annotations": ["readOnlyHint": tool.readOnly],
                ]
            }
            return Reply(status: 200, body: success(id: id, ["tools": list]))

        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0.name == name }) else {
                return Reply(status: 200, body: failure(id: id, code: -32602, "Unknown tool"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await call(name, arguments)
                return Reply(status: 200, body: success(id: id, ["content": [["type": "text", "text": text]], "isError": false]))
            } catch let error as ToolError {
                return Reply(status: 200, body: success(id: id, ["content": [["type": "text", "text": error.message]], "isError": true]))
            } catch {
                return Reply(status: 200, body: success(id: id, ["content": [["type": "text", "text": String(describing: error)]], "isError": true]))
            }

        default:
            return Reply(status: 200, body: failure(id: id, code: -32601, "Method not found: \(method)"))
        }
    }

    static func success(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func failure(id: Any?, code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    // MARK: Argument helpers

    public static func string(_ args: [String: Any], _ key: String) -> String? {
        (args[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func int(_ args: [String: Any], _ key: String, default value: Int, range: ClosedRange<Int>) -> Int {
        let raw = (args[key] as? Int) ?? (args[key] as? Double).map(Int.init) ?? (args[key] as? String).flatMap(Int.init) ?? value
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    public static func strings(_ args: [String: Any], _ key: String) -> [String] {
        (args[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// Requests from web pages carry an Origin; only local tools and our extension may call.
    /// The Host check stops DNS rebinding, where a web page's domain points at 127.0.0.1.
    public static func isAllowed(_ request: HTTPRequest) -> Bool {
        guard LocalAPIAccess.isAllowedOrigin(request.header("origin")) else { return false }
        let raw = (request.header("host") ?? "").lowercased()
        let host = raw.hasPrefix("[") ? String(raw.prefix { $0 != "]" }) + "]" : String(raw.prefix { $0 != ":" })
        return host.isEmpty || host == "127.0.0.1" || host == "localhost" || host == "[::1]"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
