import AppKit
import CoreGraphics
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

struct TerminalNotificationTests {
	private func bytes(_ text: String) -> ArraySlice<UInt8> {
		Array(text.utf8)[...]
	}

	// MARK: - OSC 9

	@Test func osc9BodyIsANotification() {
		#expect(
			OSC9Payload(bytes("Claude needs your permission to use Bash"))
				== .notification(TerminalNotification(title: nil, body: "Claude needs your permission to use Bash"))
		)
	}

	@Test func osc9BodyKeepsItsSemicolons() {
		#expect(OSC9Payload(bytes("done; 3 failed")) == .notification(TerminalNotification(title: nil, body: "done; 3 failed")))
	}

	@Test func osc9ProgressIsNotANotification() {
		// SwiftTerm draws the progress bar for these itself.
		#expect(OSC9Payload(bytes("4;1;50")) == .ignored)
		#expect(OSC9Payload(bytes("4;3")) == .ignored)
		#expect(OSC9Payload(bytes("4;0;")) == .ignored)
	}

	@Test func osc9InvalidUTF8IsIgnored() {
		#expect(OSC9Payload([0xFF, 0xFE][...]) == .ignored)
	}

	@Test func otherConEmuSubcommandsAreIgnored() {
		#expect(OSC9Payload(bytes("9;/Users/me")) == .ignored) // current directory
		#expect(OSC9Payload(bytes("5")) == .ignored)
		#expect(OSC9Payload(bytes("")) == .ignored)
	}

	@Test func aNumberOutsideConEmuRangeIsABody() {
		#expect(OSC9Payload(bytes("42")) == .notification(TerminalNotification(title: nil, body: "42")))
	}

	// MARK: - OSC 777

	@Test func osc777NotifyCarriesTitleAndBody() {
		#expect(
			TerminalNotification(osc777: bytes("notify;Claude Code;Waiting; for input"))
				== TerminalNotification(title: "Claude Code", body: "Waiting; for input")
		)
	}

	@Test func osc777WithoutATitle() {
		#expect(TerminalNotification(osc777: bytes("notify;;body")) == TerminalNotification(title: nil, body: "body"))
	}

	@Test func osc777OtherCommandsAreIgnored() {
		#expect(TerminalNotification(osc777: bytes("preexec;ls")) == nil)
		#expect(TerminalNotification(osc777: bytes("notify;title")) == nil)
		#expect(TerminalNotification(osc777: bytes("notify;;")) == nil)
	}

	// MARK: - The pane

	@MainActor
	@Test func aPaneForwardsTheNotificationsItsProgramAsksFor() async {
		let received = Received()
		let sessionId = UUID()
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: sessionId,
			onStatusChange: { _, _, _ in },
			onNotification: { id, notification in
				MainActor.assumeIsolated { received.items.append(.init(id: id, notification: notification)) }
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)

		view.feed(text: "\u{1B}]9;4;1;20\u{07}")
		view.feed(text: "\u{1B}]9;first\u{07}")
		view.feed(text: "\u{1B}]777;notify;Title;second\u{1B}\\")

		// SwiftTerm delivers observed OSC sequences off the parse path, in order, and the pane hops
		// each to the main actor; polling yields it.
		let expected: [Received.Item] = [
			.init(id: sessionId, notification: TerminalNotification(title: nil, body: "first")),
			.init(id: sessionId, notification: TerminalNotification(title: "Title", body: "second")),
		]
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(5)
		while received.items != expected, clock.now < deadline {
			try? await Task.sleep(for: .milliseconds(20))
		}

		#expect(received.items == expected)
	}

	/// A notification is only a notification: the pane's status is the program's report to set, so
	/// a report of waiting after one still moves the pane, and carries what the program said.
	@MainActor
	@Test func aNotificationLeavesThePanesStatusToTheProgramsReport() async {
		let received = Received()
		let statuses = ReceivedStatuses()
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, status, report in
				MainActor.assumeIsolated { statuses.items.append(.init(status: status, report: report)) }
			},
			onNotification: { id, notification in
				MainActor.assumeIsolated { received.items.append(.init(id: id, notification: notification)) }
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)

		view.feed(text: "\u{1B}]9;build finished\u{07}")
		#expect(await eventually { received.items.count == 1 })
		#expect(statuses.items.isEmpty, "a notification does not set the pane's status")

		view.feed(text: "\u{1B}]7501;state=done:app=claude-code\u{1B}\\")
		let expected: [ReceivedStatuses.Item] = [
			.init(status: .waitingForInput, report: TerminalProgramReport(program: "claude-code", state: .done, message: nil)),
		]
		#expect(await eventually { statuses.items == expected })
	}

	/// A program that reports its status has its notifications marked, so the setting can keep the
	/// two channels from posting the same news twice. Once it clears its report, it is a plain
	/// program again.
	@MainActor
	@Test func marksNotificationsFromAProgramThatReportsItsStatus() async {
		let received = Received()
		let statuses = ReceivedStatuses()
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, status, report in
				MainActor.assumeIsolated { statuses.items.append(.init(status: status, report: report)) }
			},
			onNotification: { id, notification in
				MainActor.assumeIsolated { received.items.append(.init(id: id, notification: notification)) }
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)

		view.feed(text: "\u{1B}]9;before\u{07}")
		#expect(await eventually { received.items.count == 1 })

		view.feed(text: "\u{1B}]7501;state=idle:app=claude-code\u{1B}\\")
		#expect(await eventually { statuses.items.count == 1 })
		view.feed(text: "\u{1B}]777;notify;Claude Code;Claude needs your permission\u{1B}\\")
		#expect(await eventually { received.items.count == 2 })

		view.feed(text: "\u{1B}]7501;state=clear\u{1B}\\")
		#expect(await eventually { statuses.items.count == 2 })
		view.feed(text: "\u{1B}]9;after\u{07}")
		#expect(await eventually { received.items.count == 3 })

		#expect(received.items.map(\.notification.isFromStatusReportingProgram) == [false, true, false])
	}

	@MainActor
	@Test func aStoppedPaneForwardsNoNotifications() async throws {
		let received = Received()
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, _, _ in },
			onNotification: { id, notification in
				MainActor.assumeIsolated { received.items.append(.init(id: id, notification: notification)) }
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)

		view.stopReportingStatus()
		view.feed(text: "\u{1B}]9;late\u{07}")
		try await Task.sleep(for: .milliseconds(300))

		#expect(received.items.isEmpty, "the notification belongs to a session that is going away")
	}

	/// Polls the main actor until `condition` holds, for up to five seconds: SwiftTerm delivers
	/// observed OSC sequences and status records off the parse path.
	@MainActor
	private func eventually(_ condition: () -> Bool) async -> Bool {
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(5)
		while !condition(), clock.now < deadline {
			try? await Task.sleep(for: .milliseconds(20))
		}
		return condition()
	}
}

@MainActor
private final class ReceivedStatuses {
	struct Item: Equatable {
		let status: TerminalSessionStatus
		let report: TerminalProgramReport?
	}

	var items: [Item] = []
}

@MainActor
private final class Received {
	struct Item: Equatable {
		let id: UUID
		let notification: TerminalNotification
	}

	var items: [Item] = []
}
