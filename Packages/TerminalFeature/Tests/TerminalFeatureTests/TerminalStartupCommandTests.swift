import AppKit
import Foundation
import Testing

@testable import TerminalFeature

/// Polls `condition` until it holds or `timeout` passes. Sleeping yields the main actor, which is
/// where SwiftTerm delivers the shell's output.
@MainActor
private func eventually(
	within timeout: Duration = .seconds(5),
	_ condition: @MainActor () -> Bool
) async -> Bool {
	let clock = ContinuousClock()
	let deadline = clock.now + timeout
	while clock.now < deadline {
		if condition() {
			return true
		}

		try? await Task.sleep(for: .milliseconds(50))
	}
	return condition()
}

@Suite("TerminalSession startup command")
struct TerminalSessionStartupCommandTests {
	@Test("no command given means none to type")
	func defaultsToNil() {
		#expect(TerminalSession(repositoryPath: "/r").startupCommand == nil)
	}

	@Test("a blank command is dropped, so the pane has nothing to type")
	func blankIsNil() {
		#expect(TerminalSession(repositoryPath: "/r", startupCommand: "").startupCommand == nil)
		#expect(TerminalSession(repositoryPath: "/r", startupCommand: "  \n\t").startupCommand == nil)
	}

	@Test("surrounding whitespace is trimmed; inner spaces stay")
	func trims() {
		let session = TerminalSession(repositoryPath: "/r", startupCommand: "  mise install && claude \n")
		#expect(session.startupCommand == "mise install && claude")
	}
}

/// The pane types its session's command once the shell has written something, and only once.
/// The shells here are `cat`, whose terminal echoes whatever reaches it, so a typed command shows
/// up on screen; plain `cat` never writes on its own, which keeps the "before output" state stable.
@MainActor
@Suite("Terminal startup command", .serialized)
struct TerminalStartupCommandTests {
	private let processDelegate = TerminalProcessDelegate(onFailed: { _ in })

	private func startPane(
		command: String?,
		shell: String = "/bin/cat",
		arguments: [String] = []
	) -> (store: TerminalViewStore, session: TerminalSession, view: ClaudeAwareTerminalView) {
		let store = TerminalViewStore(shellExecutable: shell, shellArguments: arguments)
		let session = TerminalSession(repositoryPath: "/", startupCommand: command)
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _ in }
		)
		return (store, session, view)
	}

	private func screenText(of view: ClaudeAwareTerminalView) -> String {
		String(decoding: view.getTerminal().getBufferAsData(), as: UTF8.self)
	}

	private func occurrences(of needle: String, in view: ClaudeAwareTerminalView) -> Int {
		screenText(of: view).components(separatedBy: needle).count - 1
	}

	@Test("the store hands the session's command to the pane")
	func storeHandsCommandToPane() {
		let (store, session, view) = startPane(command: "zzcmd")
		defer { store.killSession(sessionId: session.id) }

		#expect(view.pendingStartupCommand == "zzcmd")
	}

	@Test("a session without a command leaves the pane with nothing to type")
	func noCommandNothingPending() {
		let (store, session, view) = startPane(command: nil)
		defer { store.killSession(sessionId: session.id) }

		#expect(view.pendingStartupCommand == nil)
	}

	@Test("nothing is typed before the shell writes anything")
	func waitsForFirstOutput() async throws {
		let (store, session, view) = startPane(command: "zzcmd")
		defer { store.killSession(sessionId: session.id) }

		try await Task.sleep(for: .milliseconds(500))

		#expect(view.pendingStartupCommand == "zzcmd")
		#expect(!screenText(of: view).contains("zzcmd"))
	}

	@Test("the shell's first output types the command and presses Return")
	func firstOutputTypesCommand() async {
		// Prints first, as a shell prints its prompt, then echoes whatever it is sent.
		let (store, session, view) = startPane(
			command: "zzcmd",
			shell: "/bin/sh",
			arguments: ["-c", "printf 'ready> '; exec /bin/cat"]
		)
		defer { store.killSession(sessionId: session.id) }

		// `cat` only writes a line back once Return ends it, so the command coming back from
		// `cat` itself, not just the terminal's echo, proves the Return was sent too.
		#expect(await eventually { occurrences(of: "zzcmd", in: view) == 2 })
		#expect(view.pendingStartupCommand == nil)
	}

	@Test("later output does not type the command again")
	func typesOnlyOnce() async throws {
		let (store, session, view) = startPane(command: "zzcmd")
		defer { store.killSession(sessionId: session.id) }

		view.dataReceived(slice: Array("ready> ".utf8)[...])
		#expect(await eventually { occurrences(of: "zzcmd", in: view) == 2 })

		view.dataReceived(slice: Array("more output\r\n".utf8)[...])
		view.dataReceived(slice: Array("ready> ".utf8)[...])
		try await Task.sleep(for: .milliseconds(500))

		#expect(occurrences(of: "zzcmd", in: view) == 2)
	}

	@Test("a pane with no command types nothing on output")
	func noCommandTypesNothing() async throws {
		let (store, session, view) = startPane(command: nil)
		defer { store.killSession(sessionId: session.id) }

		view.dataReceived(slice: Array("ready> ".utf8)[...])
		try await Task.sleep(for: .milliseconds(500))

		#expect(screenText(of: view).trimmingCharacters(in: .whitespacesAndNewlines) == "ready>")
	}
}
