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
					activeSessionId: model.shown.first,
					colors: TerminalColors(foreground: .white, background: .black),
					readsImageFiles: false,
					copyOnSelect: false,
					mouseReporting: true,
					font: .monospacedSystemFont(ofSize: 12, weight: .regular),
					events: TerminalPaneEvents()
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
}
