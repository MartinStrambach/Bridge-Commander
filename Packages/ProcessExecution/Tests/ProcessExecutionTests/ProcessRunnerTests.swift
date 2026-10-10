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

	/// The result waits for the pipes' end of file, not just the exit: a child still holding the
	/// pipe writes after the process is gone.
	@Test
	func outputWrittenAfterTheExitIsKept() async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", "echo first; (sleep 0.3; echo late; echo late-err >&2) & exit 0"]
		)

		#expect(result.success)
		#expect(result.outputString == "first\nlate\n")
		#expect(result.errorString == "late-err\n")
	}

	/// A child that keeps a pipe open past `pipeDrainTimeout` does not hold the result back. The
	/// exit used to block in `readToEnd()` until that child exited too.
	@Test
	func pipeHeldOpenByAChildTimesOut() async {
		let start = ContinuousClock.now
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", "echo first; sleep 10 & exit 0"]
		)

		#expect(result.success)
		#expect(result.outputString == "first\n")
		#expect(ContinuousClock.now - start < .seconds(5))
	}

	/// `withTaskCancellationHandler` calls `onCancel` at once in a task already cancelled, when
	/// nothing is running yet, and the process used to be launched after it and run to the end.
	@Test
	func anAlreadyCancelledTaskDoesNotLaunchTheProcess() async throws {
		let marker = FileManager.default.temporaryDirectory.appending(path: "ProcessRunnerTests-\(UUID())")
		defer { try? FileManager.default.removeItem(at: marker) }

		let result = await Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return await ProcessRunner.run(executableURL: URL(filePath: "/usr/bin/touch"), arguments: [marker.path])
		}.value

		#expect(result.wasCancelled)
		#expect(!result.success)
		#expect(!FileManager.default.fileExists(atPath: marker.path))
	}

	@Test
	func cancellingTheTaskTerminatesTheProcess() async {
		let start = ContinuousClock.now
		let task = Task {
			await ProcessRunner.run(executableURL: URL(filePath: "/bin/sleep"), arguments: ["10"])
		}
		try? await Task.sleep(for: .milliseconds(200))
		task.cancel()
		let result = await task.value

		#expect(result.wasCancelled)
		#expect(result.exitCode == SIGTERM)
		#expect(ContinuousClock.now - start < .seconds(5))
	}

	/// Only a termination the cancellation asked for is reported as cancelled, not any death by SIGTERM.
	@Test
	func aProcessThatExitsByItselfIsNotCancelled() async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", "kill -TERM $$"]
		)

		#expect(result.exitCode == SIGTERM)
		#expect(!result.wasCancelled)
	}

	/// A command that changes something is not cut short by a cancellation, and still runs in a task
	/// already cancelled — cleanup such as `--abort` runs exactly then.
	@Test
	func finishRunsTheProcessToTheEndDespiteCancellation() async throws {
		let directory = FileManager.default.temporaryDirectory.appending(path: "ProcessRunnerTests-\(UUID())")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let late = directory.appending(path: "late")
		let cancelledBefore = directory.appending(path: "cancelled-before")

		let running = Task {
			await ProcessRunner.run(
				executableURL: URL(filePath: "/bin/sh"),
				arguments: ["-c", "sleep 0.5; touch \"$0\"", late.path],
				cancellation: .finish
			)
		}
		try await Task.sleep(for: .milliseconds(100))
		running.cancel()
		let runningResult = await running.value

		let alreadyCancelled = await Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/touch"),
				arguments: [cancelledBefore.path],
				cancellation: .finish
			)
		}.value

		#expect(runningResult.success)
		#expect(!runningResult.wasCancelled)
		#expect(FileManager.default.fileExists(atPath: late.path))
		#expect(alreadyCancelled.success)
		#expect(FileManager.default.fileExists(atPath: cancelledBefore.path))
	}

	/// `runGit` terminates a read-only command on cancellation and lets one that changes something
	/// finish.
	@Test
	func runGitLetsOnlyACommandThatChangesSomethingRunWhenCancelled() async throws {
		let directory = FileManager.default.temporaryDirectory.appending(path: "ProcessRunnerTests-\(UUID())")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let (version, initialize) = await Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return (
				await ProcessRunner.runGit(arguments: ["version"], at: directory.path),
				await ProcessRunner.runGit(arguments: ["init", "--quiet"], at: directory.path)
			)
		}.value

		#expect(version.wasCancelled)
		#expect(initialize.success)
		#expect(FileManager.default.fileExists(atPath: directory.appending(path: ".git").path))
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
