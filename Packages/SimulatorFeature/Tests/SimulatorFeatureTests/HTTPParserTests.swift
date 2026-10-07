import Foundation
import Testing
@testable import SimulatorFeature

struct HTTPParserTests {
	private func raw(_ text: String) -> Data {
		Data(text.utf8)
	}

	@Test
	func parsesARequestWithBody() {
		let body = #"{"jsonrpc":"2.0"}"#
		let buffer = raw("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:47615\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")

		guard case let .request(request, consumed) = HTTPParser.parse(buffer) else {
			Issue.record("expected a request")
			return
		}
		#expect(request.method == "POST")
		#expect(request.path == "/mcp")
		#expect(request.header("Content-Type") == "application/json")
		#expect(request.body == raw(body))
		#expect(consumed == buffer.count)
	}

	@Test
	func waitsForTheRestOfTheBody() {
		let buffer = raw("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\"")
		#expect(HTTPParser.parse(buffer) == .incomplete)
		#expect(HTTPParser.parse(raw("POST /mcp HTTP/1.1\r\nHost: x")) == .incomplete)
	}

	@Test
	func leavesAPipelinedRequestInTheBuffer() {
		let first = "GET /a HTTP/1.1\r\n\r\n"
		let buffer = raw(first + "GET /b HTTP/1.1\r\n\r\n")
		guard case let .request(request, consumed) = HTTPParser.parse(buffer) else {
			Issue.record("expected a request")
			return
		}
		#expect(request.path == "/a")
		#expect(consumed == first.utf8.count)
	}

	@Test
	func rejectsChunkedAndMalformedRequests() {
		guard case let .invalid(chunked) = HTTPParser.parse(raw("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")) else {
			Issue.record("expected chunked to be refused")
			return
		}
		#expect(chunked.status == 411)

		guard case let .invalid(malformed) = HTTPParser.parse(raw("NONSENSE\r\n\r\n")) else {
			Issue.record("expected a malformed request line to be refused")
			return
		}
		#expect(malformed.status == 400)
	}

	@Test
	func onlyLoopbackHostsWithoutAnOriginGetThrough() {
		func request(_ headers: [String: String]) -> HTTPRequest {
			HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: Data())
		}

		#expect(HTTPParser.rejection(for: request(["host": "127.0.0.1:47615"]), port: 47615) == nil)
		#expect(HTTPParser.rejection(for: request(["host": "localhost:47615"]), port: 47615) == nil)
		// A browser page, cross-site or from a sandboxed frame.
		#expect(HTTPParser.rejection(for: request(["host": "127.0.0.1:47615", "origin": "https://example.com"]), port: 47615)?.status == 403)
		#expect(HTTPParser.rejection(for: request(["host": "127.0.0.1:47615", "origin": "null"]), port: 47615)?.status == 403)
		// DNS rebinding: a foreign name that resolved to loopback.
		#expect(HTTPParser.rejection(for: request(["host": "attacker.example:47615"]), port: 47615)?.status == 403)
		#expect(HTTPParser.rejection(for: request([:]), port: 47615)?.status == 403)
	}
}
