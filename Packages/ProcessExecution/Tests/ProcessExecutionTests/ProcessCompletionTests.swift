import Foundation
import Testing
@testable import ProcessExecution

/// `ProcessRunner.run` used to build its result as soon as the process exited, racing a read
/// handler that had already taken the last chunk from the pipe but not appended it yet. Under load
/// one `git status` in about a thousand succeeded with no output — a row lost its changes and
/// showed "No remote" — and longer output lost a chunk from the middle. The result now waits for
/// both pipes' end of file, which a handle's handler reports only after every chunk before it.
@Suite
struct ProcessCompletionTests {
	private let output = PipeDataCollector()
	private let error = PipeDataCollector()

	@Test
	func aChunkAppendedAfterTheExitIsInTheResult() async {
		let completion = ProcessCompletion(output: output, error: error)

		let result = await withCheckedContinuation { continuation in
			completion.resume(with: continuation)
			output.append(Data("first\n".utf8))
			completion.processExited(with: 0)
			// The handler that read this chunk before the exit appends it only now.
			output.append(Data("last\n".utf8))
			completion.pipeReachedEndOfFile()
			error.append(Data("warning\n".utf8))
			completion.pipeReachedEndOfFile()
		}

		#expect(result.exitCode == 0)
		#expect(result.outputString == "first\nlast\n")
		#expect(result.errorString == "warning\n")
	}

	@Test
	func pipesClosingBeforeTheExitWaitForIt() async {
		let completion = ProcessCompletion(output: output, error: error)

		let result = await withCheckedContinuation { continuation in
			completion.resume(with: continuation)
			output.append(Data("out\n".utf8))
			completion.pipeReachedEndOfFile()
			completion.pipeReachedEndOfFile()
			// A timeout before the exit has nothing to report yet.
			completion.pipeDrainTimedOut()
			completion.processExited(with: 3)
		}

		#expect(result.exitCode == 3)
		#expect(result.outputString == "out\n")
	}

	/// Resuming a continuation twice traps, so a late timeout or end of file must do nothing.
	@Test
	func resumesOnlyOnce() async {
		let completion = ProcessCompletion(output: output, error: error)

		let result = await withCheckedContinuation { continuation in
			completion.resume(with: continuation)
			completion.processExited(with: 0)
			completion.pipeReachedEndOfFile()
			completion.pipeDrainTimedOut()
			output.append(Data("ignored\n".utf8))
			completion.pipeReachedEndOfFile()
		}
		completion.pipeDrainTimedOut()

		#expect(result.outputString == "")
	}
}
