import Foundation
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

	private func openDescriptorCount() -> Int {
		(0..<Int32(4096)).count { fcntl($0, F_GETFD) != -1 }
	}
}
