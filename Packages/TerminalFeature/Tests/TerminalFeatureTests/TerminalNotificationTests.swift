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
		// Claude Code reports progress this way while it works.
		#expect(OSC9Payload(bytes("4;1;50")) == .progress(Terminal.ProgressReport(state: .set, progress: 50)))
		#expect(OSC9Payload(bytes("4;3")) == .progress(Terminal.ProgressReport(state: .indeterminate, progress: nil)))
		#expect(OSC9Payload(bytes("4;0;")) == .progress(Terminal.ProgressReport(state: .remove, progress: nil)))
	}

	@Test func osc9ProgressFollowsSwiftTermsParsing() {
		// A set without a value starts at 0, a value is clamped, and a malformed report is dropped.
		#expect(OSC9Payload(bytes("4;1")) == .progress(Terminal.ProgressReport(state: .set, progress: 0)))
		#expect(OSC9Payload(bytes("4;1;250")) == .progress(Terminal.ProgressReport(state: .set, progress: 100)))
		#expect(OSC9Payload(bytes("4;0;50")) == .progress(Terminal.ProgressReport(state: .remove, progress: nil)))
		#expect(OSC9Payload(bytes("4;9;50")) == .ignored)
		#expect(OSC9Payload(bytes("4;1;half")) == .ignored)
		#expect(OSC9Payload(bytes("4")) == .ignored)
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
	@Test func aPaneForwardsTheNotificationsItsProgramAsksFor() {
		let received = Received()
		let sessionId = UUID()
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: sessionId,
			onStatusChange: { _, _ in },
			onNotification: { id, notification in
				MainActor.assumeIsolated { received.items.append(.init(id: id, notification: notification)) }
			}
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)

		view.feed(text: "\u{1B}]9;4;1;20\u{07}")
		view.feed(text: "\u{1B}]9;first\u{07}")
		view.feed(text: "\u{1B}]777;notify;Title;second\u{1B}\\")

		#expect(received.items == [
			.init(id: sessionId, notification: TerminalNotification(title: nil, body: "first")),
			.init(id: sessionId, notification: TerminalNotification(title: "Title", body: "second")),
		])
	}
}

@MainActor
private final class Received {
	struct Item: Equatable {
		let id: UUID
		let notification: TerminalNotification
	}

	var items: [Item] = []
}
