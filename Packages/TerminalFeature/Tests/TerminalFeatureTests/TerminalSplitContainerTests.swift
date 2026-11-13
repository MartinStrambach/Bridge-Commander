import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
@testable import TerminalFeature

/// What the panel shows: the sessions, and which of them are on screen side by side.
@MainActor
@Observable
private final class SplitModel {
	var sessions: IdentifiedArrayOf<TerminalSession> = []
	var shown: [UUID] = []
	/// The pane with the keyboard; the first on screen when not set.
	var active: UUID?
	/// The panes clicked, in order.
	var clicked: [UUID] = []
}

/// The terminal panel's split, without the panel: one container per pane on screen, keyed by
/// slot, in an `HStack` at equal fixed widths, as the panel lays them out.
private struct SplitHarness: View {
	let model: SplitModel
	let store: TerminalViewStore

	var body: some View {
		let count = max(model.shown.count, 1)
		return HStack(spacing: 0) {
			ForEach(0 ..< count, id: \.self) { slot in
				TerminalContainerRepresentable(
					terminalViewStore: store,
					sessions: model.sessions,
					shownSessionIds: model.shown,
					slot: slot,
					activeSessionId: model.active ?? model.shown.first,
					colors: TerminalColors(foreground: .white, background: .black),
					readsImageFiles: false,
					copyOnSelect: false,
					mouseReporting: true,
					font: .monospacedSystemFont(ofSize: 12, weight: .regular),
					events: TerminalPaneEvents(),
					onPaneClicked: { model.clicked.append($0) }
				)
				.frame(width: 900 / CGFloat(count))
				.frame(maxHeight: .infinity)
			}
		}
	}
}

// Which container a pane sits in, and at what size, as tabs with one and several panes take the
// screen in turn. Sizes matter because every change of one reaches the shell as a SIGWINCH.
@MainActor
@Suite(.serialized)
struct TerminalSplitContainerTests {
	private let store = TerminalViewStore(shellExecutable: "/bin/cat", shellArguments: [])
	private let model = SplitModel()
	private let window = NSWindow(
		contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
		styleMask: [.titled],
		backing: .buffered,
		defer: false
	)

	private func show() {
		// Owned by the test: a window made in code otherwise releases itself when closed.
		window.isReleasedWhenClosed = false
		window.contentView = NSHostingView(rootView: SplitHarness(model: model, store: store))
		window.orderBack(nil)
	}

	private func settle() async throws {
		for _ in 0 ..< 3 {
			try await Task.sleep(for: .milliseconds(50))
			window.contentView?.layoutSubtreeIfNeeded()
		}
	}

	private func pane(_ session: TerminalSession) -> TerminalPaneView {
		store.view(
			for: session,
			colors: TerminalColors(foreground: .white, background: .black),
			events: TerminalPaneEvents()
		)
	}

	@Test func panesOfTheTabOnScreenShareTheWidthAndTheRestKeepTheirSize() async throws {
		let left = TerminalSession(repositoryPath: "/")
		let right = TerminalSession(repositoryPath: "/other")
		let other = TerminalSession(repositoryPath: "/")
		model.sessions = [left, right, other]
		model.shown = [left.id, right.id]
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()

		// Side by side, each in a container of its own; the tab off screen waits in the first.
		#expect(!pane(left).isHidden)
		#expect(!pane(right).isHidden)
		#expect(pane(other).isHidden)
		#expect(pane(left).superview !== pane(right).superview)
		#expect(pane(other).superview === pane(left).superview)
		#expect(abs(pane(left).frame.width - 450) < 10)
		#expect(abs(pane(right).frame.width - 450) < 10)
		#expect(pane(left).frame.maxX <= pane(right).convert(pane(right).bounds, to: pane(left)).minX)

		// The other tab takes the screen: the split's panes go into hiding at the size they had.
		let splitWidth = pane(right).frame.width
		model.shown = [other.id]
		try await settle()

		#expect(pane(left).isHidden)
		#expect(pane(right).isHidden)
		#expect(!pane(other).isHidden)
		#expect(pane(right).superview === pane(other).superview)
		#expect(pane(right).frame.width == splitWidth)
		#expect(abs(pane(other).frame.width - 900) < 2)

		// And back: the same panes, the same sizes, no pane resized on the way.
		model.shown = [left.id, right.id]
		try await settle()

		#expect(!pane(left).isHidden)
		#expect(!pane(right).isHidden)
		#expect(pane(other).isHidden)
		#expect(pane(left).superview !== pane(right).superview)
		#expect(pane(right).frame.width == splitWidth)
		#expect(abs(pane(other).frame.width - 900) < 2)
	}

	@Test func closingTheFirstPaneHandsItsSlotToTheNext() async throws {
		let left = TerminalSession(repositoryPath: "/")
		let right = TerminalSession(repositoryPath: "/other")
		model.sessions = [left, right]
		model.shown = [left.id, right.id]
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()
		let firstContainer = pane(left).superview

		model.sessions = [right]
		model.shown = [right.id]
		store.killSession(sessionId: left.id)
		try await settle()

		#expect(pane(right).superview === firstContainer)
		#expect(!pane(right).isHidden)
		#expect(abs(pane(right).frame.width - 900) < 2)
	}

	@Test func threePanesEachHaveAContainerAndClosingTheMiddleOneMovesTheLastUp() async throws {
		let first = TerminalSession(repositoryPath: "/")
		let middle = TerminalSession(repositoryPath: "/other")
		let last = TerminalSession(repositoryPath: "/third")
		model.sessions = [first, middle, last]
		model.shown = [first.id, middle.id, last.id]
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()

		let containers = [first, middle, last].map { pane($0).superview }
		#expect(Set(containers.compactMap { $0.map(ObjectIdentifier.init) }).count == 3)
		for session in [first, middle, last] {
			#expect(!pane(session).isHidden)
			#expect(abs(pane(session).frame.width - 300) < 10)
		}

		model.sessions = [first, last]
		model.shown = [first.id, last.id]
		store.killSession(sessionId: middle.id)
		try await settle()

		// The last pane takes the middle one's container; the first never moved.
		#expect(pane(first).superview === containers[0])
		#expect(pane(last).superview === containers[1])
		#expect(!pane(first).isHidden)
		#expect(!pane(last).isHidden)
		#expect(abs(pane(first).frame.width - 450) < 10)
		#expect(abs(pane(last).frame.width - 450) < 10)
		#expect(store.currentDirectory(sessionId: middle.id) == nil, "the closed pane's shell stays gone")
	}

	@Test func theActivePaneHoldsTheKeyboardWhicheverSlotItIsIn() async throws {
		let left = TerminalSession(repositoryPath: "/")
		let right = TerminalSession(repositoryPath: "/other")
		model.sessions = [left, right]
		model.shown = [left.id, right.id]
		model.active = right.id
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()

		#expect(window.firstResponder === pane(right))

		model.active = left.id
		try await settle()

		#expect(window.firstResponder === pane(left))
	}

	@Test func aClickedPaneIsReportedByItsSession() async throws {
		let left = TerminalSession(repositoryPath: "/")
		let right = TerminalSession(repositoryPath: "/other")
		model.sessions = [left, right]
		model.shown = [left.id, right.id]
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()

		pane(right).mouseDown(with: mouseDownEvent(in: pane(right)))
		pane(left).mouseDown(with: mouseDownEvent(in: pane(left)))

		#expect(model.clicked == [right.id, left.id])
	}

	/// The panel closes while its panes run on, and its containers go with it.
	@Test func aSplitComesBackWhenThePanelIsClosedAndReopened() async throws {
		let left = TerminalSession(repositoryPath: "/")
		let right = TerminalSession(repositoryPath: "/other")
		model.sessions = [left, right]
		model.shown = [left.id, right.id]
		show()
		defer {
			store.killAllSessions()
			window.close()
		}
		try await settle()
		let leftPane = pane(left)
		let rightPane = pane(right)

		window.contentView = NSView()
		try await settle()

		#expect(leftPane.window == nil)
		#expect(pane(left) === leftPane, "the pane and its shell outlive the panel")
		#expect(pane(right) === rightPane)

		show()
		try await settle()

		#expect(leftPane.window === window)
		#expect(rightPane.window === window)
		#expect(!leftPane.isHidden)
		#expect(!rightPane.isHidden)
		#expect(leftPane.superview !== rightPane.superview)
		#expect(abs(leftPane.frame.width - 450) < 10)
		#expect(abs(rightPane.frame.width - 450) < 10)
	}

	/// A press in the middle of the pane. SwiftTerm reads the event for the cell under the
	/// pointer, so it has to be a real `NSEvent` rather than a stub.
	private func mouseDownEvent(in view: NSView) -> NSEvent {
		NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		)!
	}
}
