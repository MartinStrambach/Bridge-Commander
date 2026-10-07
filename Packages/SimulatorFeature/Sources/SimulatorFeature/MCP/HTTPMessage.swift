import Foundation

/// An HTTP/1.1 request, as much of one as the MCP endpoint needs.
struct HTTPRequest: Equatable, Sendable {
	var method: String
	var path: String
	/// Header names lowercased.
	var headers: [String: String]
	var body: Data

	func header(_ name: String) -> String? {
		headers[name.lowercased()]
	}
}

struct HTTPResponse: Equatable, Sendable {
	var status: Int
	var headers: [(String, String)] = []
	var body = Data()

	static func == (lhs: HTTPResponse, rhs: HTTPResponse) -> Bool {
		lhs.status == rhs.status && lhs.body == rhs.body
			&& lhs.headers.map { "\($0.0): \($0.1)" } == rhs.headers.map { "\($0.0): \($0.1)" }
	}

	static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
		HTTPResponse(status: status, headers: [("Content-Type", "application/json")], body: data)
	}

	static func text(_ status: Int, _ message: String) -> HTTPResponse {
		HTTPResponse(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")], body: Data(message.utf8))
	}

	func serialized(keepAlive: Bool) -> Data {
		var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
		for (name, value) in headers {
			head += "\(name): \(value)\r\n"
		}
		head += "Content-Length: \(body.count)\r\n"
		head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
		return Data(head.utf8) + body
	}

	private static func reason(for status: Int) -> String {
		switch status {
		case 200: "OK"
		case 202: "Accepted"
		case 400: "Bad Request"
		case 403: "Forbidden"
		case 404: "Not Found"
		case 405: "Method Not Allowed"
		case 411: "Length Required"
		case 413: "Payload Too Large"
		case 415: "Unsupported Media Type"
		default: "Status"
		}
	}
}

enum HTTPParser {
	enum Result: Equatable {
		/// More bytes are needed.
		case incomplete
		case request(HTTPRequest, consumed: Int)
		case invalid(HTTPResponse)
	}

	static let maximumHeaderLength = 16 * 1024
	static let maximumBodyLength = 4 * 1024 * 1024

	/// Parses the first request in `buffer`. Bodies must come with a `Content-Length`: the MCP
	/// client posts JSON it has already serialized, and nothing here needs chunked uploads.
	static func parse(_ buffer: Data) -> Result {
		let separator = Data("\r\n\r\n".utf8)
		guard let headerEnd = buffer.range(of: separator) else {
			return buffer.count > maximumHeaderLength ? .invalid(.text(413, "Headers too large")) : .incomplete
		}

		let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
		let lines = String(decoding: headerData, as: UTF8.self).components(separatedBy: "\r\n")
		let requestLine = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
		guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
			return .invalid(.text(400, "Malformed request line"))
		}

		var headers: [String: String] = [:]
		for line in lines.dropFirst() where !line.isEmpty {
			guard let colon = line.firstIndex(of: ":") else {
				return .invalid(.text(400, "Malformed header"))
			}
			let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			headers[name] = value
		}

		if headers["transfer-encoding"] != nil {
			return .invalid(.text(411, "Send a Content-Length"))
		}
		let length = headers["content-length"].flatMap { Int($0) } ?? 0
		guard length >= 0, length <= maximumBodyLength else {
			return .invalid(.text(413, "Body too large"))
		}

		let bodyStart = headerEnd.upperBound
		guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else {
			return .incomplete
		}
		let bodyEnd = buffer.index(bodyStart, offsetBy: length)
		let request = HTTPRequest(
			method: String(requestLine[0]),
			path: String(requestLine[1]),
			headers: headers,
			body: Data(buffer[bodyStart..<bodyEnd])
		)
		return .request(request, consumed: buffer.distance(from: buffer.startIndex, to: bodyEnd))
	}

	/// Why a request may not reach the MCP endpoint, if it may not.
	///
	/// The listener is bound to loopback, so only local processes connect — and any of them could
	/// already drive a simulator with `xcrun simctl`. What remains is a web page in the user's
	/// browser: it can make requests to localhost (a cross-site POST, or a DNS-rebound name
	/// resolving to 127.0.0.1). A browser always sends `Origin` on those (`null` from a sandboxed
	/// frame) and the page's own name in `Host`; the MCP client sends no `Origin` and a loopback
	/// `Host`.
	static func rejection(for request: HTTPRequest, port: UInt16) -> HTTPResponse? {
		if request.header("origin") != nil {
			return .text(403, "Browser requests are not accepted")
		}
		let allowedHosts = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
		guard let host = request.header("host"), allowedHosts.contains(host.lowercased()) else {
			return .text(403, "Unexpected Host")
		}
		return nil
	}
}
