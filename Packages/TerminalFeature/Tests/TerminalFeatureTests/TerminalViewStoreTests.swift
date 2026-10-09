import AppKit
import Darwin
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Whether a child of this process is still running. Reaps it if it has exited and nobody else has
/// yet; SwiftTerm's exit monitor usually gets there first, in which case `waitpid` reports `ECHILD`
/// and the answer is the same.
private func isRunning(_ pid: pid_t) -> Bool {
	var status: Int32 = 0
	return waitpid(pid, &status, WNOHANG) == 0
}

/// Whether a process that is not our child still exists.
private func exists(_ pid: pid_t) -> Bool {
	kill(pid, 0) == 0
}

/// Identifies what a descriptor is open on. Two pseudo-terminals share an inode but differ in
/// device number, so a changed device means the original was closed and the number reused.
private struct OpenFile: Equatable {
	let device: dev_t

	init?(descriptor: Int32) {
		var info = stat()
		guard fstat(descriptor, &info) == 0 else {
			return nil
		}

		device = info.st_rdev
	}
}

/// Polls `condition` until it holds or `timeout` passes. Sleeping yields the main actor, which is
/// where SwiftTerm delivers process exits.
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

/// The first child `pgrep` reports for `pid`, waiting for it to appear.
@MainActor
private func firstChild(of pid: pid_t) async -> pid_t? {
	var child: pid_t?
	_ = await eventually {
		let pgrep = Process()
		pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
		pgrep.arguments = ["-P", String(pid)]
		let output = Pipe()
		pgrep.standardOutput = output
		try? pgrep.run()
		pgrep.waitUntilExit()
		let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		child = text.split(whereSeparator: \.isNewline).first.flatMap { pid_t($0) }
		return child != nil
	}
	return child
}

/// Collects what a pane reported, in order.
@MainActor
private final class Reported {
	var statuses: [TerminalSessionStatus] = []
	var reports: [TerminalProgramReport?] = []
}

@MainActor
@Suite(.serialized)
struct TerminalViewStoreTests {
	/// Keeps the process delegate alive for the panes, as the representable's coordinator does.
	private let processDelegate = TerminalProcessDelegate(onFailed: { _ in })

	/// `cat` sits reading its terminal forever and exits on hangup, which is all a shell needs to
	/// do for these tests. The real thing is checked once, in the zsh test.
	private func makeStore(shell: String = "/bin/cat", arguments: [String] = []) -> TerminalViewStore {
		TerminalViewStore(shellExecutable: shell, shellArguments: arguments)
	}

	/// Starts a pane and hands back what the test needs to watch it, without keeping the view
	/// itself: the store must be the only owner, as it is in the app.
	private func startSession(in store: TerminalViewStore) -> (session: TerminalSession, pid: pid_t, pty: Int32) {
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
		return (session, view.process.shellPid, view.process.childfd)
	}

	@Test func killSessionEndsTheShell() async throws {
		let store = makeStore()
		let (session, pid, _) = startSession(in: store)
		try #require(pid > 0)
		#expect(isRunning(pid))

		store.killSession(sessionId: session.id)

		#expect(await eventually { !isRunning(pid) }, "shell should be gone after its session is killed")
	}

	@Test func killSessionReleasesThePseudoTerminal() async throws {
		let store = makeStore()
		let (session, pid, pty) = startSession(in: store)
		try #require(pid > 0)
		let before = try #require(OpenFile(descriptor: pty))

		store.killSession(sessionId: session.id)

		#expect(
			await eventually { OpenFile(descriptor: pty) != before },
			"PTY master should be closed once the shell is gone"
		)
	}

	@Test func killSessionLeavesOtherSessionsAlone() async throws {
		let store = makeStore()
		let victim = startSession(in: store)
		let survivor = startSession(in: store)
		try #require(victim.pid > 0 && survivor.pid > 0)

		store.killSession(sessionId: victim.session.id)

		#expect(await eventually { !isRunning(victim.pid) })
		#expect(isRunning(survivor.pid))
		store.killSession(sessionId: survivor.session.id)
	}

	@Test func killSessionsNotInHangsUpOnlyTheSessionsThatVanished() async throws {
		let store = makeStore()
		let kept = startSession(in: store)
		let vanished = startSession(in: store)
		try #require(kept.pid > 0 && vanished.pid > 0)

		store.killSessions(notIn: [kept.session.id])

		#expect(await eventually { !isRunning(vanished.pid) })
		#expect(isRunning(kept.pid))
		store.killSession(sessionId: kept.session.id)
	}

	/// A killed pane gets one last burst of output as its shell exits, and the pane can outlive the
	/// kill for a moment. Acting on it would report a status for a session the reducer has already
	/// dropped, and would do so after the terminal panel may have closed.
	@Test func killSessionSilencesStatusReports() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, status, _ in
				MainActor.assumeIsolated { reported.statuses.append(status) }
			},
			onNotification: { _, _ in }
		)
		try #require(view.process.shellPid > 0)

		store.killSession(sessionId: session.id)
		let reportedBeforeOutput = reported.statuses
		// What Claude's last word looks like to the detector: its records cleared on exit, after a
		// report of waiting that would otherwise move the dot.
		view.feed(text: Self.statusReport("state=done:app=claude-code") + Self.statusReport("state=clear"))
		view.processOutputReceived()
		try await Task.sleep(for: .seconds(2)) // past the detector's foreground check

		#expect(reported.statuses == reportedBeforeOutput, "a killed pane has nothing more to say")
	}

	/// An OSC 7501 report as a program writes it.
	private static func statusReport(_ body: String) -> String {
		"\u{1B}]7501;\(body)\u{1B}\\"
	}

	/// A program's own report, parsed by SwiftTerm, is what moves the pane's status — whichever
	/// program it is — and it comes with what the program said, for the notification.
	@Test func aProgramsReportSetsThePanesStatus() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, status, report in
				MainActor.assumeIsolated {
					reported.statuses.append(status)
					reported.reports.append(report)
				}
			},
			onNotification: { _, _ in }
		)
		defer { store.killSession(sessionId: session.id) }
		try #require(view.process.shellPid > 0)

		// "Allow write?"
		view.feed(text: Self.statusReport("state=blocked:app=codex:kind=permission:msg=QWxsb3cgd3JpdGU/"))
		#expect(await eventually { reported.statuses.last == .waitingForInput })
		#expect(reported.reports.last == TerminalProgramReport(program: "codex", state: .blocked(.permission), message: "Allow write?"))

		view.feed(text: Self.statusReport("state=working:app=codex"))
		#expect(await eventually { reported.statuses.last == .active })
	}

	/// A pane's shell leads its own process group, so it holds the foreground exactly while no job
	/// runs — what tells a report left behind by a crashed program from a live one.
	@Test func theShellHoldsTheForegroundOnlyAtItsPrompt() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f"])
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
		defer { store.killSession(sessionId: session.id) }
		let shell = view.process.shellPid
		let pty = view.process.childfd
		try #require(shell > 0)
		#expect(await eventually { PtyForegroundProcess.isInForeground(processGroup: shell, ptyDescriptor: pty) == true })

		view.send(txt: "sleep 5\r")

		#expect(await eventually { PtyForegroundProcess.isInForeground(processGroup: shell, ptyDescriptor: pty) == false })
	}

	/// What a relaunch reopens a tab in: where its shell is now, which is not where it started once
	/// the user has `cd`'d.
	@Test func paneSnapshotsFollowTheShellsDirectory() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f"])
		let session = TerminalSession(repositoryPath: "/", startingDirectory: "/tmp")
		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
		try #require(view.process.shellPid > 0)
		#expect(await eventually { store.paneSnapshots()[session.id]?.directory == "/private/tmp" })

		view.send(txt: "cd /usr\r")

		#expect(await eventually { store.paneSnapshots()[session.id]?.directory == "/usr" })
		store.killSession(sessionId: session.id)
		#expect(store.paneSnapshots().isEmpty)
	}

	/// The store goes with the window. Whatever it still holds must hang up rather than outlive it.
	@Test func releasingTheStoreEndsEveryShell() async throws {
		var store: TerminalViewStore? = makeStore()
		let first = startSession(in: store!)
		let second = startSession(in: store!)
		try #require(first.pid > 0 && second.pid > 0)

		store = nil

		#expect(await eventually { !isRunning(first.pid) && !isRunning(second.pid) })
	}

	/// The real shell is zsh with a job in the foreground, typically Claude Code. Killing the
	/// session must take the job down too. SIGTERM would not: interactive zsh ignores it.
	@Test func killSessionEndsTheJobRunningInsideTheShell() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f", "-i"])
		let (session, shellPid, _) = startSession(in: store)
		try #require(shellPid > 0)

		let view = store.view(
			for: session,
			foregroundColor: .white,
			backgroundColor: .black,
			processDelegate: processDelegate,
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
		view.process.send(data: Array("sleep 300\n".utf8)[...])
		let job = try #require(await firstChild(of: shellPid))

		store.killSession(sessionId: session.id)

		#expect(await eventually { !isRunning(shellPid) }, "zsh should have hung up")
		#expect(await eventually { !exists(job) }, "the foreground job should have been hung up with the shell")
		if exists(job) {
			kill(job, SIGKILL)
		}
	}
}
