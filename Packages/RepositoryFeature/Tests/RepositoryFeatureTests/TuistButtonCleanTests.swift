import AppUI
import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Tuist button clean action")
struct TuistButtonCleanTests {
	private func makeState(runningAction: TuistAction? = nil) -> TuistButtonReducer.State {
		var state = TuistButtonReducer.State(
			repositoryPath: "/repos/app",
			iosSubfolderPath: "ios"
		)
		state.runningAction = runningAction
		return state
	}

	@Test("clean is ignored while another Tuist action is running", arguments: [nil, TuistCleanCategory.binaries])
	@MainActor
	func cleanIgnoredWhileBusy(category: TuistCleanCategory?) async {
		let store = TestStore(initialState: makeState(runningAction: .generate)) {
			TuistButtonReducer()
		}

		await store.send(.cleanTapped(category))

		#expect(store.state.runningAction == .generate)
	}

	@Test("a finished clean clears the running action without an alert")
	@MainActor
	func cleanSuccessShowsNoAlert() async {
		let store = TestStore(initialState: makeState(runningAction: .clean(nil))) {
			TuistButtonReducer()
		}

		await store.send(.actionCompleted(.clean(nil), .success("Deleting cache"))) {
			$0.runningAction = nil
		}

		#expect(store.state.alert == nil)
	}

	@Test("a category clean completes independently of an everything clean")
	@MainActor
	func categoryCleanTracksItsCategory() async {
		let store = TestStore(initialState: makeState(runningAction: .clean(.binaries))) {
			TuistButtonReducer()
		}

		// A completion for a different category must not be confused with this one.
		#expect(store.state.runningAction == .clean(.binaries))
		#expect(store.state.runningAction != .clean(nil))
		#expect(store.state.runningAction != .clean(.selectiveTests))

		await store.send(.actionCompleted(.clean(.binaries), .success(""))) {
			$0.runningAction = nil
		}

		#expect(store.state.alert == nil)
	}

	@Test("a failed clean surfaces a clean-specific error alert")
	@MainActor
	func cleanFailureShowsAlert() async {
		let store = TestStore(initialState: makeState(runningAction: .clean(nil))) {
			TuistButtonReducer()
		}
		let error = NSError(
			domain: "TuistError",
			code: 1,
			userInfo: [NSLocalizedDescriptionKey: "tuist: command not found"]
		)

		await store.send(.actionCompleted(.clean(nil), .failure(error))) {
			$0.runningAction = nil
			$0.alert = ScrollableAlertReducer.State(
				title: "Tuist Clean Failed",
				message: "tuist: command not found",
				isError: true
			)
		}
	}
}
