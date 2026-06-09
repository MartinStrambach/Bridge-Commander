import Foundation
import Testing
@testable import RepositoryFeature

@Suite("Terminal header Tuist button")
struct TerminalTuistButtonTests {
	private func makeRow(supportsIOS: Bool, supportsTuist: Bool) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "main",
			supportsIOS: supportsIOS,
			iosSubfolderPath: "ios",
			supportsTuist: supportsTuist
		)
	}

	@Test("shown when the row supports both iOS and Tuist")
	func shownWhenIOSAndTuistSupported() {
		let row = makeRow(supportsIOS: true, supportsTuist: true)
		let button = terminalTuistButton(for: row)
		#expect(button == row.tuistButton)
		#expect(button?.repositoryPath == "/repos/app")
		#expect(button?.iosSubfolderPath == "ios")
	}

	@Test("hidden when the row supports iOS but not Tuist")
	func hiddenWithoutTuistSupport() {
		let row = makeRow(supportsIOS: true, supportsTuist: false)
		#expect(terminalTuistButton(for: row) == nil)
	}

	@Test("hidden when the row supports Tuist but not iOS")
	func hiddenWithoutIOSSupport() {
		let row = makeRow(supportsIOS: false, supportsTuist: true)
		#expect(terminalTuistButton(for: row) == nil)
	}

	@Test("hidden when there is no active row")
	func hiddenWithoutRow() {
		#expect(terminalTuistButton(for: nil) == nil)
	}
}
