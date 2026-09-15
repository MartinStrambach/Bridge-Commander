import ComposableArchitecture
import Settings
import Testing
@testable import RepositoryFeature

@Suite("Terminal panel: ⌘+ / ⌘− / ⌘0 font zoom")
@MainActor
struct TerminalZoomTests {
	private func makeStore() -> TestStoreOf<TerminalLayoutReducer> {
		TestStore(initialState: TerminalLayoutReducer.State()) {
			TerminalLayoutReducer()
		}
	}

	@Test("zooming in and out steps the stored font size by a point")
	func zoomStepsFontSize() async {
		let store = makeStore()

		await store.send(.zoomInRequested) {
			$0.terminalFontSize = TerminalFontSize.default + TerminalFontSize.step
		}
		await store.send(.zoomOutRequested) {
			$0.terminalFontSize = TerminalFontSize.default
		}
	}

	@Test("zooming stops at the supported bounds instead of running away")
	func zoomClampsAtBounds() async {
		let store = makeStore()

		store.state.$terminalFontSize.withLock { $0 = TerminalFontSize.maximum }
		await store.send(.zoomInRequested)

		store.state.$terminalFontSize.withLock { $0 = TerminalFontSize.minimum }
		await store.send(.zoomOutRequested)
	}

	@Test("⌘0 goes back to the default size from either direction")
	func resetReturnsToDefault() async {
		let store = makeStore()

		store.state.$terminalFontSize.withLock { $0 = TerminalFontSize.maximum }
		await store.send(.resetZoomRequested) {
			$0.terminalFontSize = TerminalFontSize.default
		}

		store.state.$terminalFontSize.withLock { $0 = TerminalFontSize.minimum }
		await store.send(.resetZoomRequested) {
			$0.terminalFontSize = TerminalFontSize.default
		}
	}
}
