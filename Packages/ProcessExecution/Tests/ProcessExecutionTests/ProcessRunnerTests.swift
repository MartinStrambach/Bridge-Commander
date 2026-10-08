import Foundation
import Synchronization
import Testing
@testable import ProcessExecution

@Suite(.serialized)
struct ProcessRunnerTests {
	@Test
	func failedLaunchReportsFailure() async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/true"),
			arguments: [],
			currentDirectory: URL(filePath: "/nonexistent-\(UUID())")
		)

		#expect(result.exitCode == -1)
		#expect(result.errorString.hasPrefix("Failed to start process:"))
	}

	/// A failed launch used to leak both pipes; enough of them exhausted the app's descriptors and
	/// every later launch failed with "Bad file descriptor".
	@Test
	func failedLaunchesDoNotLeakFileDescriptors() async {
		let before = openDescriptorCount()
		for _ in 0..<20 {
			_ = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/true"),
				arguments: [],
				currentDirectory: URL(filePath: "/nonexistent-\(UUID())")
			)
		}

		// A read end that had a readability handler is closed asynchronously, on the handler's
		// dispatch queue, so the last few launches' read ends can still be open for a moment
		// (often under Thread Sanitizer). A leak never closes.
		let deadline = ContinuousClock.now + .seconds(2)
		while openDescriptorCount() > before, ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(openDescriptorCount() <= before)
	}

	@Test
	func capturesOutputAndExitCode() async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", "echo out; echo err >&2; exit 3"]
		)

		#expect(result.exitCode == 3)
		#expect(result.trimmedOutput == "out")
		#expect(result.trimmedError == "err")
	}

	/// An Xcode update deletes the git binary the app resolved at launch; every git call then failed
	/// to launch until the app restarted.
	@Test
	func resolvedExecutableIsResolvedAgainOnceItIsGone() async throws {
		let directory = FileManager.default.temporaryDirectory.appending(path: "ResolvedExecutable-\(UUID())")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let first = directory.appending(path: "first")
		let second = directory.appending(path: "second")
		for url in [first, second] {
			try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: url)
		}

		let resolutions = Mutex(0)
		let executable = ResolvedExecutable {
			resolutions.withLock { count in
				count += 1
				return count == 1 ? first : second
			}
		}

		#expect(await executable.url == first)
		#expect(await executable.url == first)
		#expect(resolutions.withLock { $0 } == 1)

		try FileManager.default.removeItem(at: first)

		#expect(await executable.url == second)
		#expect(await executable.url == second)
		#expect(resolutions.withLock { $0 } == 2)
	}

	private func openDescriptorCount() -> Int {
		(0..<Int32(4096)).count { fcntl($0, F_GETFD) != -1 }
	}
}
