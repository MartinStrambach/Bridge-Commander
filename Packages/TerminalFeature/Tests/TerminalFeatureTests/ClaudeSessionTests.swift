import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Polls `condition` until it holds or `timeout` passes.
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

@MainActor
@Suite(.serialized)
struct ClaudeSessionTests {
	private let sessionId = "948fa96a-ed30-4a60-ad45-46cd868d3433"

	// MARK: - The record

	@Test func readsTheSessionIdOfTheProcessNamedInTheRecord() {
		let record = Data(#"{"pid":3657,"sessionId":"\#(sessionId)","cwd":"/repos/alpha","kind":"interactive"}"#.utf8)

		#expect(ClaudeSession.id(fromRecord: record, processId: 3657) == sessionId)
	}

	@Test func refusesARecordForAnotherProcess() {
		let record = Data(#"{"pid":3657,"sessionId":"\#(sessionId)"}"#.utf8)

		#expect(ClaudeSession.id(fromRecord: record, processId: 4901) == nil)
	}

	@Test func refusesASessionIdThatIsNotAUUID() {
		let record = Data(#"{"pid":3657,"sessionId":"x; rm -rf ~"}"#.utf8)

		#expect(ClaudeSession.id(fromRecord: record, processId: 3657) == nil)
		#expect(ClaudeSession.resumeCommand(sessionId: "x; rm -rf ~") == nil)
	}

	@Test func refusesARecordInAnUnexpectedShape() {
		#expect(ClaudeSession.id(fromRecord: Data("[]".utf8), processId: 3657) == nil)
	}

	// MARK: - The session

	@Test func aResumedTabTypesTheResumeAndKeepsItsStartupCommand() {
		let session = TerminalSession(
			repositoryPath: "/repos/alpha",
			startupCommand: "claude",
			resumingClaudeSession: sessionId
		)

		#expect(session.commandToType == "claude --resume \(sessionId)")
		#expect(session.startupCommand == "claude")
		#expect(session.resumedClaudeSessionId == sessionId)
		#expect(session.awaitsStartupPrompt)
	}

	@Test func aMalformedSessionIdFallsBackToTheStartupCommand() {
		let session = TerminalSession(
			repositoryPath: "/repos/alpha",
			startupCommand: "claude",
			resumingClaudeSession: "not-a-session"
		)

		#expect(session.commandToType == "claude")
		#expect(session.resumedClaudeSessionId == nil)
	}

	// MARK: - Finding it behind a pane

	/// `cat` started under the name `claude`, holding the foreground of a real pseudo-terminal the
	/// way Claude Code does, with a record for its pid in a sessions directory of the test's own.
	@Test func findsTheConversationInThePanesForeground() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appending(component: "ClaudeSessionTests-\(UUID().uuidString)")
		let sessions = directory.appending(component: "sessions")
		try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let fakeClaude = directory.appending(component: "claude")
		try FileManager.default.createSymbolicLink(
			at: fakeClaude,
			withDestinationURL: URL(fileURLWithPath: "/bin/cat")
		)

		let store = TerminalViewStore(shellExecutable: fakeClaude.path, shellArguments: [])
		let delegate = TerminalProcessDelegate(onFailed: { _ in })
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: delegate,
			onStatusChange: { _, _ in },
			onNotification: { _, _ in }
		)
		defer { store.killSession(sessionId: session.id) }
		let pid = view.process.shellPid
		try #require(pid > 0)
		// The pid exists from the fork on, but until the exec lands it is not yet `claude`, and
		// would read as "no session" for that reason alone.
		try #require(await eventually { PtyForegroundProcess.isClaude(ptyDescriptor: view.process.childfd) == true })

		#expect(ClaudeSession.id(inForegroundOf: view.process.childfd, sessionsDirectory: sessions) == nil)

		try Data(#"{"pid":\#(pid),"sessionId":"\#(sessionId)"}"#.utf8)
			.write(to: sessions.appending(component: "\(pid).json"))

		#expect(ClaudeSession.id(inForegroundOf: view.process.childfd, sessionsDirectory: sessions) == sessionId)
	}

	@Test func listsTheProcessGroupLeaderFirst() {
		let members = PtyForegroundProcess.processes(inGroup: getpgrp())

		#expect(members.first == getpgrp())
		#expect(members.contains(getpid()))
	}
}
