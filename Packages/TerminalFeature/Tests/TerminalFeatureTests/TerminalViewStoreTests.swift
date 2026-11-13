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

/// Collects the titles a pane passed on, in order.
@MainActor
private final class Titles {
	var items: [String?] = []
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
	/// `cat` sits reading its terminal forever and exits on hangup, which is all a shell needs to
	/// do for these tests. The real thing is checked once, in the zsh test.
	private func makeStore(shell: String = "/bin/cat", arguments: [String] = []) -> TerminalViewStore {
		TerminalViewStore(shellExecutable: shell, shellArguments: arguments)
	}

	/// Starts a pane and hands back what the test needs to watch it, without keeping the view
	/// itself: the store must be the only owner, as it is in the app.
	private func startSession(
		in store: TerminalViewStore,
		repositoryPath: String = "/"
	) -> (session: TerminalSession, pid: pid_t, pty: Int32) {
		let session = TerminalSession(repositoryPath: repositoryPath)
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
		)
		return (session, view.process.shellPid, view.process.childfd)
	}

	/// Option composes the layout's characters (Czech ⌥4 = `$`) yet stays Meta on the keys that
	/// compose nothing, which is what makes ⌥← move a word; SwiftTerm's own tests pin the bytes.
	@Test func optionComposesTextButIsMetaOnFunctionalKeys() {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
		)
		defer { store.killSession(sessionId: session.id) }

		#expect(!view.optionAsMetaKey)
		#expect(view.optionAsMetaKeyForFunctionalKeys)
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

	@Test func killAllSessionsHangsUpEveryShell() async throws {
		let store = makeStore()
		let first = startSession(in: store)
		let second = startSession(in: store)
		try #require(first.pid > 0 && second.pid > 0)

		store.killAllSessions()

		#expect(await eventually { !isRunning(first.pid) })
		#expect(await eventually { !isRunning(second.pid) })
	}

	/// Ctrl-C reaches the foreground program as the user's keystroke would: the terminal turns it
	/// into SIGINT, which ends `cat`, and the pane reports its shell gone.
	@Test func interruptSendsTheForegroundProgramSIGINT() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onStatusChange: { _, status, _ in
					MainActor.assumeIsolated { reported.statuses.append(status) }
				}
			)
		)
		let pid = view.process.shellPid
		try #require(pid > 0)
		defer { store.killSession(sessionId: session.id) }

		store.interrupt(sessionId: session.id)

		#expect(await eventually { !isRunning(pid) })
		#expect(await eventually {
			reported.statuses.contains { if case .failed = $0 { true } else { false } }
		})
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
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onStatusChange: { _, status, _ in
					MainActor.assumeIsolated { reported.statuses.append(status) }
				}
			)
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

	/// Panes are created from `updateNSView`, and a status reported from inside it changes the
	/// state that update is drawing, so the first `.active` waits for the next turn of the main
	/// queue. It is said once: asking the store for the pane again makes no second report.
	@Test func aNewPaneReportsItselfActiveOnceAfterTheTurnThatMadeIt() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		let events = TerminalPaneEvents(
			onStatusChange: { _, status, _ in
				MainActor.assumeIsolated { reported.statuses.append(status) }
			}
		)
		let colors = TerminalColors(foreground: .white, background: .black)
		let view = store.view(for: session, colors: colors, events: events)
		defer { store.killSession(sessionId: session.id) }

		#expect(reported.statuses.isEmpty, "nothing is reported from inside the call that made the pane")
		#expect(await eventually { reported.statuses == [.active] })

		#expect(store.view(for: session, colors: colors, events: events) === view)
		try await Task.sleep(for: .milliseconds(200))
		#expect(reported.statuses == [.active])
	}

	/// A tab can be closed in the turn it was opened in. Its pane then has no session left to
	/// report a status for.
	@Test func aPaneKilledBeforeItsFirstReportSaysNothing() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		_ = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onStatusChange: { _, status, _ in
					MainActor.assumeIsolated { reported.statuses.append(status) }
				}
			)
		)

		store.killSession(sessionId: session.id)
		try await Task.sleep(for: .milliseconds(300))

		#expect(reported.statuses.isEmpty)
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
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onStatusChange: { _, status, report in
					MainActor.assumeIsolated {
						reported.statuses.append(status)
						reported.reports.append(report)
					}
				}
			)
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

	/// The pane's own report of its title and of its shell's exit, which SwiftTerm makes through a
	/// delegate it holds only weakly. The store keeps that delegate: the terminal panel, which
	/// used to, can close while the pane runs on, and a pane that lost it reported neither again.
	@Test func thePaneKeepsReportingItsTitleAndItsShellsExit() async throws {
		let store = makeStore()
		let session = TerminalSession(repositoryPath: "/")
		let reported = Reported()
		let titles = Titles()
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents(
				onStatusChange: { _, status, _ in
					MainActor.assumeIsolated { reported.statuses.append(status) }
				},
				onTitleChange: { _, title in
					MainActor.assumeIsolated { titles.items.append(title) }
				}
			)
		)
		defer { store.killSession(sessionId: session.id) }
		let pid = view.process.shellPid
		try #require(pid > 0)

		view.feed(text: "\u{1B}]0;Fix the login bug\u{07}")
		#expect(await eventually { titles.items == ["Fix the login bug"] })

		kill(pid, SIGKILL)
		#expect(await eventually {
			if case .failed = reported.statuses.last {
				return true
			}
			return false
		})
	}

	/// A pane's shell leads its own process group, so it holds the foreground exactly while no job
	/// runs, and a job holds it under a group of its own — what tells a report left behind by a
	/// crashed or suspended program from a live one.
	@Test func theShellHoldsTheForegroundOnlyAtItsPrompt() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f"])
		let session = TerminalSession(repositoryPath: "/")
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
		)
		defer { store.killSession(sessionId: session.id) }
		let shell = view.process.shellPid
		let pty = view.process.childfd
		try #require(shell > 0)
		#expect(await eventually { PtyForegroundProcess.foreground(ofShell: shell, ptyDescriptor: pty) == .shell })

		view.send(txt: "sleep 5\r")

		#expect(await eventually {
			if case let .job(group) = PtyForegroundProcess.foreground(ofShell: shell, ptyDescriptor: pty) {
				return group != shell
			}
			return false
		})
	}

	/// What a relaunch reopens a tab in: where its shell is now, which is not where it started once
	/// the user has `cd`'d.
	@Test func paneSnapshotsFollowTheShellsDirectory() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f"])
		let session = TerminalSession(repositoryPath: "/", startingDirectory: "/tmp")
		let view = store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
		)
		try #require(view.process.shellPid > 0)
		#expect(await eventually { store.paneSnapshots()[session.id]?.directory == "/private/tmp" })

		view.send(txt: "cd /usr\r")

		#expect(await eventually { store.paneSnapshots()[session.id]?.directory == "/usr" })
		store.killSession(sessionId: session.id)
		#expect(store.paneSnapshots().isEmpty)
	}

	/// What ⌘D opens the new pane in: where the one session's shell is, asked of the kernel.
	@Test func currentDirectoryIsTheNamedSessionsShells() async throws {
		let store = makeStore(shell: "/bin/zsh", arguments: ["-f"])
		let inTmp = TerminalSession(repositoryPath: "/", startingDirectory: "/tmp")
		let inUsr = TerminalSession(repositoryPath: "/", startingDirectory: "/usr")
		for session in [inTmp, inUsr] {
			_ = store.view(
				for: session,
				colors: TerminalColors(foreground: .white, background: .black),
				events: TerminalPaneEvents()
			)
		}
		defer { store.killAllSessions() }

		#expect(await eventually { store.currentDirectory(sessionId: inTmp.id) == "/private/tmp" })
		#expect(await eventually { store.currentDirectory(sessionId: inUsr.id) == "/usr" })
		#expect(store.currentDirectory(sessionId: UUID()) == nil, "a session with no pane has no directory")

		store.killSession(sessionId: inTmp.id)
		#expect(store.currentDirectory(sessionId: inTmp.id) == nil)
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
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
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
