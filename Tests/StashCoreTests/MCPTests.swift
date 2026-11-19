import Foundation
import XCTest
@testable import StashCore

final class MCPTests: XCTestCase {
    private let tools = [MCP.Tool(name: "echo", description: "Echo", inputSchema: ["type": "object"])]

    private func send(_ json: String) async -> MCP.Reply {
        await MCP.handle(Data(json.utf8), server: ("Stash", "1"), instructions: "hi", tools: tools) { name, args in
            if args["fail"] != nil { throw MCP.ToolError("nope") }
            return "\(name):\(args["x"] ?? "")"
        }
    }

    private func result(_ reply: MCP.Reply) -> [String: Any] {
        (reply.body as? [String: Any])?["result"] as? [String: Any] ?? [:]
    }

    func testInitializeNegotiatesVersion() async {
        let reply = await send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual(result(reply)["protocolVersion"] as? String, "2025-03-26")
        let unknown = await send(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual(result(unknown)["protocolVersion"] as? String, MCP.supportedVersions[0])
    }

    func testNotificationGetsNoBody() async {
        let reply = await send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(reply.status, 202)
        XCTAssertNil(reply.body)
    }

    func testListAndCallTools() async {
        let list = result(await send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        XCTAssertEqual((list["tools"] as? [[String: Any]])?.first?["name"] as? String, "echo")

        let call = result(await send(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"x":"y"}}}"#))
        XCTAssertEqual(call["isError"] as? Bool, false)
        XCTAssertEqual((call["content"] as? [[String: Any]])?.first?["text"] as? String, "echo:y")

        let failed = result(await send(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"echo","arguments":{"fail":1}}}"#))
        XCTAssertEqual(failed["isError"] as? Bool, true)
    }

    func testErrors() async {
        let parse = await send("not json")
        XCTAssertEqual(parse.status, 400)
        let unknown = await send(#"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
        XCTAssertEqual(((unknown.body as? [String: Any])?["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testOnlyLocalCallersAreAllowed() {
        func request(_ headers: [String: String]) -> HTTPRequest {
            HTTPRequest(method: "POST", path: "/mcp", query: [:], headers: headers, body: Data())
        }
        XCTAssertTrue(MCP.isAllowed(request(["host": "127.0.0.1:47615"])))
        XCTAssertTrue(MCP.isAllowed(request(["host": "[::1]:47615"])))
        XCTAssertFalse(MCP.isAllowed(request(["host": "127.0.0.1:47615", "origin": "https://evil.example"])))
        XCTAssertFalse(MCP.isAllowed(request(["host": "rebind.evil.example:47615"])))
    }
}
