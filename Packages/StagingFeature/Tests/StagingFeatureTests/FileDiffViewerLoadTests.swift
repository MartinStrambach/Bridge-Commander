import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import StagingFeature

// Selecting a file used to switch the viewer's file and side at once, while the old diff stayed on
// screen until the new one arrived: a staged diff could show Stage buttons in the meantime, which
// send the wrong git operation. And deselecting while a diff loaded did not cancel the load, so the
// diff showed up afterwards with nothing selected.
@Suite("File diff viewer loading")
@MainActor
struct FileDiffViewerLoadTests {

	private let file = GitCore.FileChange(path: "Sources/App.swift", status: .modified)

	private func diff(header: String) -> GitCore.FileDiff {
		let line = GitCore.DiffLine(rawLine: "+let value = 1", id: "\(header):0", oldLineNumber: nil, newLineNumber: 1)
		return GitCore.FileDiff(
			fileChange: file,
			hunks: [
				GitCore.DiffHunk(header: header, oldStart: 1, oldCount: 0, newStart: 1, newCount: 1, lines: [line]),
			],
			isBinary: false
		)
	}

	@Test("while the other side of a file loads, the diff on screen keeps its own side")
	func pendingLoadKeepsTheShownDiffsSide() async {
		let stagedDiff = diff(header: "@@ -0,0 +1,1 @@")
		let unstagedDiff = diff(header: "@@ -5,0 +6,1 @@")
		let gate = AsyncStream.makeStream(of: Void.self)
		let store = TestStore(initialState: FileDiffViewer.State(repositoryPath: "/repo")) {
			FileDiffViewer()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileDiff = { _, _, isStaged in
				if isStaged {
					return stagedDiff
				}
				for await _ in gate.stream {}
				return unstagedDiff
			}
		}
		store.exhaustivity = .off

		await store.send(.load(file, isStaged: true))
		await store.receive(\.loadResponse)

		await store.send(.load(file, isStaged: false))
		#expect(store.state.fileDiff == stagedDiff, "the staged diff stays on screen until the unstaged one arrives")
		#expect(store.state.diffIsStaged, "staged hunks must not get Stage buttons in the meantime")

		gate.continuation.finish()
		await store.receive(\.loadResponse)
		#expect(store.state.fileDiff == unstagedDiff)
		#expect(!store.state.diffIsStaged)
	}

	@Test("a response for another file or side than the one selected is dropped")
	func mismatchedResponseIsDropped() async {
		var initial = FileDiffViewer.State(repositoryPath: "/repo")
		initial.fileId = file.id
		initial.fileIsStaged = true
		let store = TestStore(initialState: initial) { FileDiffViewer() }

		// Exhaustive: any state change or delegate action would fail the test.
		await store.send(.loadResponse(fileId: file.id, isStaged: false, diff(header: "@@ -0,0 +1,1 @@")))
		await store.send(.loadResponse(fileId: "Other.swift", isStaged: true, nil))
	}

	@Test("deselecting the file while its diff loads leaves no diff on screen")
	func deselectingDuringLoadDropsTheDiff() async {
		let gate = AsyncStream.makeStream(of: Void.self)
		let loaded = diff(header: "@@ -0,0 +1,1 @@")
		var initial = RepositoryDetail.State(repositoryPath: "/repo", iosSubfolderPath: "")
		initial.unstaged.files = [file]
		let store = TestStore(initialState: initial) {
			RepositoryDetail()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileDiff = { _, _, _ in
				for await _ in gate.stream {}
				return loaded
			}
		}
		store.exhaustivity = .off

		await store.send(.unstaged(.updateSelection([file.id])))
		await store.receive(\.diffViewer.load)
		await store.send(.unstaged(.updateSelection([])))
		gate.continuation.finish()
		await store.finish()
		await store.skipReceivedActions()

		#expect(store.state.diffViewer.fileId == nil)
		#expect(store.state.diffViewer.fileDiff == nil)
		#expect(store.state.diffViewer.displayDiff == nil, "hunk buttons would act on a file nobody selected")
	}
}
