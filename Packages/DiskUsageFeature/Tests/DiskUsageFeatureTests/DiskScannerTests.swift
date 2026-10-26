import Foundation
import Testing
@testable import DiskUsageFeature

@Suite("Disk scanner")
struct DiskScannerTests {
	/// A folder of known shape under the temporary directory, removed after the test.
	private func withFixture(_ body: (URL) async throws -> Void) async throws {
		let root = FileManager.default.temporaryDirectory.appending(path: "DiskScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(at: root.appending(path: "nested/deeper"), withIntermediateDirectories: true)
		try Data(count: 64 * 1024).write(to: root.appending(path: "nested/deeper/large.bin"))
		try Data(count: 4096).write(to: root.appending(path: "nested/medium.bin"))
		try Data("hello".utf8).write(to: root.appending(path: "top.txt"))
		try FileManager.default.createDirectory(at: root.appending(path: "many"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: root.appending(path: "nested/empty"), withIntermediateDirectories: true)
		for index in 0 ..< (DiskScanner.filesKeptPerDirectory + 5) {
			try Data(count: 512).write(to: root.appending(path: "many/file\(index).bin"))
		}
		try await body(root)
	}

	private func finishedResult(_ root: URL) async -> DiskScanResult? {
		for await event in DiskScanner.scan(root) {
			if case let .finished(result) = event {
				return result
			}
		}
		return nil
	}

	@Test("builds the tree with allocated sizes, largest first")
	func buildsTree() async throws {
		try await withFixture { root in
			let result = try #require(await finishedResult(root))
			#expect(result.root.name == root.path(percentEncoded: false))
			#expect(result.inaccessibleFolders == 0)
			// Allocated blocks are at least the bytes written.
			#expect(result.root.size >= 64 * 1024 + 4096 + 5 + 105 * 512)
			#expect(result.root.children.map(\.name).contains("nested"))
			let nested = try #require(result.root.child(named: "nested"))
			#expect(nested.children.map(\.name) == ["deeper", "medium.bin", "empty"])
			let empty = try #require(nested.child(named: "empty"))
			#expect(empty.isDirectory && empty.children.isEmpty && empty.size == 0 && empty.itemCount == 0)
			let deeper = try #require(nested.child(named: "deeper"))
			#expect(deeper.children.map(\.name) == ["large.bin"])
			#expect(deeper.size >= 64 * 1024)
			// Four folders, three files, and the 105 files of "many".
			#expect(result.root.itemCount == 4 + 3 + 105)
		}
	}

	@Test("a folder keeps its largest files and sums the rest")
	func sumsSmallerFiles() async throws {
		try await withFixture { root in
			let result = try #require(await finishedResult(root))
			let many = try #require(result.root.child(named: "many"))
			#expect(many.children.count == DiskScanner.filesKeptPerDirectory + 1)
			// Sorted by size like any child, so the sum is not necessarily last.
			let rest = try #require(many.children.first { !$0.isOnDisk })
			#expect(rest.kind == .smallerFiles(count: 5))
			#expect(rest.itemCount == 5)
			#expect(many.children.filter { $0.kind == .file }.count == DiskScanner.filesKeptPerDirectory)
			#expect(many.itemCount == DiskScanner.filesKeptPerDirectory + 5)
		}
	}

	@Test("a scan leaves no descriptor open, finished or cancelled")
	func closesDescriptors() async throws {
		try await withFixture { root in
			// A first scan starts the worker threads' infrastructure, whose descriptors stay.
			_ = await finishedResult(root)
			let openBefore = openDescriptorCount()
			_ = await finishedResult(root)
			#expect(openDescriptorCount() == openBefore)

			let scanning = Task {
				for await _ in DiskScanner.scan(root) {}
			}
			scanning.cancel()
			await scanning.value
			// The consumer returns before the scan's own task has drained its queue.
			for _ in 0 ..< 100 where openDescriptorCount() != openBefore {
				try await Task.sleep(for: .milliseconds(20))
			}
			#expect(openDescriptorCount() == openBefore)
		}
	}

	/// Descriptors the process has open (including the one listing them, each time).
	private func openDescriptorCount() -> Int {
		(try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
	}

	@Test("a root that cannot be opened fails instead of finishing")
	func missingRootFails() async {
		var events: [DiskScanEvent] = []
		for await event in DiskScanner.scan(URL(filePath: "/nonexistent/\(UUID().uuidString)")) {
			events.append(event)
		}
		guard case .failed = events.last else {
			Issue.record("expected a failure, got \(events)")
			return
		}
	}
}
