import Foundation
import os

/// The requests being answered, shared by every connection: a client's `notifications/cancelled`
/// (Esc in Claude Code) arrives on another connection than the request it names, whose own is busy
/// until the request is answered.
///
/// A request is known by its JSON-RPC id and the calling terminal session (`X-Bridge-Commander-Session`):
/// ids are only unique per client, and the server hands out no `MCP-Session-Id`. Clients outside the
/// app share the session "none", so one of them could cancel another's request that has the same id.
final class SimulatorMCPRequests: Sendable {
	private struct Entry: Sendable {
		let session: String?
		let id: JSONValue
		let task: Task<JSONValue, Never>
	}

	private let entries = OSAllocatedUnfairLock<[UUID: Entry]>(initialState: [:])
	private let logger = Logger(subsystem: "com.bridgecommander", category: "SimulatorMCP")

	/// Answers request `id` with `body`, or returns nil when it was cancelled — the spec has no
	/// response for a cancelled request, and the client has stopped waiting for one.
	func run(id: JSONValue, session: String?, _ body: @escaping @Sendable () async -> JSONValue) async -> JSONValue? {
		let token = UUID()
		let task = entries.withLock { entries in
			let task = Task { await body() }
			entries[token] = Entry(session: session, id: id, task: task)
			return task
		}
		let reply = await task.value
		entries.withLock { $0[token] = nil }
		return task.isCancelled ? nil : reply
	}

	/// Cancels request `id` of `session`. A request already answered, or never seen, is ignored, as
	/// the spec asks.
	func cancel(id: JSONValue, session: String?, reason: String?) {
		let cancelled = entries.withLock { $0.values.filter { $0.id == id && $0.session == session } }
		for entry in cancelled {
			entry.task.cancel()
		}
		if !cancelled.isEmpty {
			logger.info("Cancelled request \(String(describing: id), privacy: .public): \(reason ?? "no reason given", privacy: .public)")
		}
	}

	/// How many requests are being answered, for tests.
	var count: Int {
		entries.withLock(\.count)
	}
}
