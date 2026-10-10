import Foundation
import Testing

@testable import GitCore

// Two writes to one index at once end with git's "index.lock: File exists", so the staging
// client's writes go through this queue. These tests pin down that it runs them one at a time,
// in order, and that a failed write does not hold up the next.
@Suite("GitIndexWriteQueue")
struct GitIndexWriteQueueTests {

	private actor Log {
		private(set) var events: [String] = []

		func append(_ event: String) {
			events.append(event)
		}
	}

	private struct WriteFailed: Error {}

	/// Starts `write` on `queue` and returns once it is running, so the next one queues behind it.
	private func startWrite(
		on queue: GitIndexWriteQueue,
		at path: String,
		named name: String,
		log: Log,
		fails: Bool = false
	) async -> Task<Void, Error> {
		let (started, startedContinuation) = AsyncStream<Void>.makeStream()
		let task = Task {
			try await queue.run(at: path) {
				await log.append("\(name) start")
				startedContinuation.yield()
				try await Task.sleep(for: .milliseconds(100))
				await log.append("\(name) end")
				if fails {
					throw WriteFailed()
				}
			}
		}
		for await _ in started {
			break
		}
		return task
	}

	@Test
	func writesToOnePathRunOneAtATimeInOrder() async throws {
		let queue = GitIndexWriteQueue()
		let log = Log()

		let first = await startWrite(on: queue, at: "/repo", named: "first", log: log)
		let second = Task {
			try await queue.run(at: "/repo") {
				await log.append("second start")
				await log.append("second end")
			}
		}
		try await first.value
		try await second.value

		#expect(await log.events == ["first start", "first end", "second start", "second end"])
	}

	@Test
	func aFailedWriteDoesNotHoldUpTheNext() async throws {
		let queue = GitIndexWriteQueue()
		let log = Log()

		let first = await startWrite(on: queue, at: "/repo", named: "first", log: log, fails: true)
		let second = Task {
			try await queue.run(at: "/repo") {
				await log.append("second")
			}
		}

		await #expect(throws: WriteFailed.self) { try await first.value }
		try await second.value
		#expect(await log.events == ["first start", "first end", "second"])
	}

	@Test
	func writesToDifferentWorkingTreesDoNotWaitForEachOther() async throws {
		let queue = GitIndexWriteQueue()
		let log = Log()

		let first = await startWrite(on: queue, at: "/repo", named: "first", log: log)
		try await queue.run(at: "/repo-worktree") {
			await log.append("other worktree")
		}
		try await first.value

		#expect(await log.events == ["first start", "other worktree", "first end"])
	}
}
