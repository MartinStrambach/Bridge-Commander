import ComposableArchitecture
import GitCore
import Testing
@testable import StagingFeature

// ↑/↓ in the file lists are handled by the reducer rather than the native table (which stopped
// moving the selection on macOS 27). These tests pin down where each arrow press lands.
@Suite("File change list arrow-key selection")
@MainActor
struct FileChangeListSelectionTests {

	private func makeStore(selected: Set<String>) -> TestStoreOf<FileChangeList> {
		var state = FileChangeList.State(repositoryPath: "/repo", iosSubfolderPath: "", listType: .unstaged)
		state.files = ["a", "b", "c"].map { GitCore.FileChange(path: $0, status: .modified) }
		state.selectedFileIds = selected
		return TestStore(initialState: state) { FileChangeList() }
	}

	@Test
	func downMovesToNextFile() async {
		let store = makeStore(selected: ["a"])
		await store.send(.moveSelection(by: 1))
		await store.receive(\.updateSelection) { $0.selectedFileIds = ["b"] }
	}

	@Test
	func upStopsAtFirstFile() async {
		let store = makeStore(selected: ["a"])
		await store.send(.moveSelection(by: -1))
		await store.receive(\.updateSelection)
	}

	@Test
	func downStopsAtLastFile() async {
		let store = makeStore(selected: ["c"])
		await store.send(.moveSelection(by: 1))
		await store.receive(\.updateSelection)
	}

	@Test
	func emptySelectionSelectsFirstFile() async {
		let store = makeStore(selected: [])
		await store.send(.moveSelection(by: 1))
		await store.receive(\.updateSelection) { $0.selectedFileIds = ["a"] }
	}

	@Test
	func multiSelectionStepsFromTheEdgeInTheDirectionOfTravel() async {
		let store = makeStore(selected: ["a", "b"])
		await store.send(.moveSelection(by: 1))
		await store.receive(\.updateSelection) { $0.selectedFileIds = ["c"] }
	}
}
