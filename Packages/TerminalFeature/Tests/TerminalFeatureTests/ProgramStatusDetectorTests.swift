import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Collects what the detector reported, in order.
@MainActor
private final class Reported {
	var statuses: [TerminalSessionStatus] = []
	var reports: [TerminalProgramReport?] = []
}

/// Stands in for whether the pane's shell holds its foreground.
@MainActor
private final class Foreground {
	var isShell: Bool? = false
}

@MainActor
struct ProgramStatusDetectorTests {
	/// A delay no test will reach, so the only foreground checks that run are the ones a test asks
	/// for.
	private static let neverFires: TimeInterval = 3600

	private static let claude = TerminalProgramReport(program: "claude-code", message: nil)

	private func makeDetector(
		reported: Reported,
		foreground: Foreground = Foreground()
	) -> ProgramStatusDetector {
		ProgramStatusDetector(
			label: "test",
			isShellInForeground: { foreground.isShell },
			foregroundCheckDelay: Self.neverFires,
			onStatusChange: { status, report in
				reported.statuses.append(status)
				reported.reports.append(report)
			}
		)
	}

	private static func report(
		_ state: TerminalProgramStatusState,
		_ report: TerminalProgramReport = claude
	) -> ProgramStatusReport {
		ProgramStatusReport(state: state, report: report)
	}

	// MARK: - Reports

	@Test(arguments: [
		(TerminalProgramStatusState.working, TerminalSessionStatus.active),
		(.blocked, .waitingForInput),
		(.done, .waitingForInput),
		(.idle, .waitingForInput),
		(.error, .waitingForInput),
	])
	func onlyWorkIsNotWaiting(state: TerminalProgramStatusState, status: TerminalSessionStatus) {
		#expect(ProgramStatusDetector.status(for: state) == status)
	}

	@Test func followsATurnThroughAPermissionDialog() {
		let reported = Reported()
		let detector = makeDetector(reported: reported)

		detector.statusReported(Self.report(.idle))
		detector.statusReported(Self.report(.working))
		detector.statusReported(Self.report(.blocked))
		detector.statusReported(Self.report(.working))
		detector.statusReported(Self.report(.done))

		#expect(reported.statuses == [.waitingForInput, .active, .waitingForInput, .active, .waitingForInput])
	}

	@Test func aChangeToWaitingCarriesTheReport() {
		let codex = TerminalProgramReport(program: "codex", message: "Allow write?")
		let reported = Reported()
		let detector = makeDetector(reported: reported)

		detector.statusReported(Self.report(.blocked, codex))
		detector.statusReported(Self.report(.working, codex))

		#expect(reported.reports == [codex, nil])
	}

	@Test func aClearedReportLeavesThePaneActive() {
		// Claude clears its records when it exits, which hands the pane back to the shell.
		let reported = Reported()
		let detector = makeDetector(reported: reported)

		detector.statusReported(Self.report(.done))
		detector.statusReported(nil)

		#expect(reported.statuses == [.waitingForInput, .active])
	}

	@Test func outputDoesNotChangeTheStatus() {
		// Every child repaints when the app resizes its pane. That output is not the program working.
		let reported = Reported()
		let detector = makeDetector(reported: reported)

		detector.statusReported(Self.report(.done))
		detector.outputReceived()

		#expect(reported.statuses == [.waitingForInput])
	}

	// MARK: - A report left behind

	@Test func aReportLeftByACrashedProgramIsSetAside() {
		let reported = Reported()
		let foreground = Foreground()
		let detector = makeDetector(reported: reported, foreground: foreground)
		detector.statusReported(Self.report(.done))

		foreground.isShell = true
		detector.checkForeground()

		#expect(reported.statuses == [.waitingForInput, .active])
	}

	@Test func aSuspendedProgramIsTakenUpAgainWhenItComesBack() {
		// A Claude brought back with `fg` reports again only when its state next changes.
		let reported = Reported()
		let foreground = Foreground()
		let detector = makeDetector(reported: reported, foreground: foreground)
		detector.statusReported(Self.report(.done))

		foreground.isShell = true
		detector.checkForeground()
		foreground.isShell = false
		detector.checkForeground()

		#expect(reported.statuses == [.waitingForInput, .active, .waitingForInput])
	}

	@Test func aForegroundThatCannotBeToldLeavesTheReportStanding() {
		let reported = Reported()
		let foreground = Foreground()
		let detector = makeDetector(reported: reported, foreground: foreground)
		detector.statusReported(Self.report(.done))

		foreground.isShell = nil
		detector.checkForeground()

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func aNewReportIsBelievedAfterOneWasSetAside() {
		let reported = Reported()
		let foreground = Foreground()
		let detector = makeDetector(reported: reported, foreground: foreground)
		detector.statusReported(Self.report(.done))
		foreground.isShell = true
		detector.checkForeground()

		detector.statusReported(Self.report(.idle))

		#expect(reported.statuses == [.waitingForInput, .active, .waitingForInput])
	}

	// MARK: - Stopping

	@Test func reportsNothingOnceStopped() {
		// A killed pane gets one last burst as its shell and Claude exit, Claude's clear among it.
		// Reporting that would set a status for a session the reducer has already dropped.
		let reported = Reported()
		let foreground = Foreground()
		let detector = makeDetector(reported: reported, foreground: foreground)
		detector.statusReported(Self.report(.done))

		detector.stop()
		detector.statusReported(nil)
		foreground.isShell = true
		detector.checkForeground()

		#expect(reported.statuses == [.waitingForInput], "a stopped detector has nothing more to say")
	}
}
