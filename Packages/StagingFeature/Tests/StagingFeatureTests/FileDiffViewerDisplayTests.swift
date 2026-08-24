import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import StagingFeature

// The diff viewer used to convert the whole GitCore diff into AppUI models inside the view body,
// so every line was rebuilt on each render. The conversion now happens once, when the diff loads,
// and the result lives in state — these tests pin that down, plus the hunk lookup that moved out
// of the view's action closures.
@Suite("File diff viewer display model")
@MainActor
struct FileDiffViewerDisplayTests {

	// MARK: - Fixtures

	private static let hunkHeader = "@@ -1,2 +1,2 @@"

	private func modifiedFile() -> GitCore.FileChange {
		GitCore.FileChange(path: "Sources/App.swift", status: .modified)
	}

	/// A one-hunk diff whose addition carries an inline highlight, so the conversion has
	/// something non-trivial to preserve.
	private func diff(for file: GitCore.FileChange) -> GitCore.FileDiff {
		let deletion = GitCore.DiffLine(
			rawLine: "-let value = oldFunction()",
			id: "\(Self.hunkHeader):0",
			oldLineNumber: 1,
			newLineNumber: nil
		)
		var addition = GitCore.DiffLine(
			rawLine: "+let value = newFunction()",
			id: "\(Self.hunkHeader):1",
			oldLineNumber: nil,
			newLineNumber: 1
		)
		if let highlight = addition.content.range(of: "newFunction") {
			addition = addition.withInlineChanges([highlight])
		}

		return GitCore.FileDiff(
			fileChange: file,
			hunks: [
				GitCore.DiffHunk(
					header: Self.hunkHeader,
					oldStart: 1,
					oldCount: 2,
					newStart: 1,
					newCount: 2,
					lines: [deletion, addition]
				),
			],
			isBinary: false
		)
	}

	private func makeStore(
		returning diff: GitCore.FileDiff?
	) -> TestStoreOf<FileDiffViewer> {
		let store = TestStore(initialState: FileDiffViewer.State(repositoryPath: "/repos/app")) {
			FileDiffViewer()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileDiff = { _, _, _ in diff }
		}
		store.exhaustivity = .off
		return store
	}

	// MARK: - Conversion happens once, in the reducer

	@Test("loading a file publishes a display-ready diff in state")
	func loadPublishesDisplayDiff() async {
		let file = modifiedFile()
		let loaded = diff(for: file)
		let store = makeStore(returning: loaded)

		await store.send(.load(file, isStaged: false))
		await store.receive(\.loadResponse)

		let display = store.state.displayDiff
		#expect(display != nil, "the view must not have to convert the diff itself")
		#expect(display?.fileChange.path == file.path)
		#expect(display?.fileChange.status == .modified)
		#expect(display?.isBinary == false)
		#expect(display?.hunks.map(\.id) == loaded.hunks.map(\.id))
		#expect(display?.hunks.first?.lines.map(\.content) == ["let value = oldFunction()", "let value = newFunction()"])
		#expect(display?.hunks.first?.lines.map(\.type) == [.deletion, .addition])
		#expect(display?.hunks.first?.lines.map(\.newLineNumber) == [nil, 1])
	}

	@Test("inline highlight ranges survive the conversion")
	func inlineHighlightsSurviveConversion() async {
		let file = modifiedFile()
		let store = makeStore(returning: diff(for: file))

		await store.send(.load(file, isStaged: false))
		await store.receive(\.loadResponse)

		let addition = store.state.displayDiff?.hunks.first?.lines.last
		let highlighted = addition.map { line in line.inlineChanges.map { String(line.content[$0]) } }
		#expect(highlighted == ["newFunction"])
	}

	@Test("a file with no changes clears both the git and display diffs")
	func emptyResponseClearsDisplayDiff() async {
		let file = modifiedFile()
		let store = makeStore(returning: diff(for: file))

		await store.send(.load(file, isStaged: false))
		await store.receive(\.loadResponse)
		#expect(store.state.displayDiff != nil)

		await store.send(.loadResponse(nil))

		#expect(store.state.fileDiff == nil)
		#expect(store.state.displayDiff == nil)
		await store.receive(\.delegate.fileHasNoChanges)
	}

	@Test("clearSelection drops the git diff and the display diff together")
	func clearSelectionClearsBothDiffs() {
		let file = modifiedFile()
		var state = FileDiffViewer.State(repositoryPath: "/repos/app")
		state.fileId = file.id
		state.fileIsStaged = false
		state.fileDiff = diff(for: file)
		state.displayDiff = diff(for: file).toAppUI()

		state.clearSelection()

		#expect(state.fileId == nil)
		#expect(state.fileIsStaged == nil)
		#expect(state.fileDiff == nil)
		#expect(state.displayDiff == nil, "a stale display diff would keep rendering the old file")
	}

	@Test("deselecting a file in the detail view clears the rendered diff")
	func deselectingInDetailViewClearsRenderedDiff() async {
		let file = modifiedFile()
		var initial = RepositoryDetail.State(repositoryPath: "/repos/app", iosSubfolderPath: "")
		initial.unstaged.files = [file]
		initial.unstaged.selectedFileIds = [file.id]
		initial.diffViewer.fileId = file.id
		initial.diffViewer.fileIsStaged = false
		initial.diffViewer.fileDiff = diff(for: file)
		initial.diffViewer.displayDiff = diff(for: file).toAppUI()

		let store = TestStore(initialState: initial) { RepositoryDetail() }
		store.exhaustivity = .off

		await store.send(.unstaged(.updateSelection([])))

		#expect(store.state.diffViewer.displayDiff == nil)
		#expect(store.state.diffViewer.fileDiff == nil)
		await store.finish()
	}

	// MARK: - Hunk actions resolve by id

	@Test("staging a hunk by id delegates the matching git hunk")
	func stageHunkResolvesById() async {
		let file = modifiedFile()
		let loaded = diff(for: file)
		let store = makeStore(returning: loaded)

		await store.send(.load(file, isStaged: false))
		await store.receive(\.loadResponse)

		await store.send(.stageHunk(hunkId: Self.hunkHeader))

		await store.receive(\.delegate.stageHunk) { _ in }
		#expect(store.state.fileDiff?.hunks.first?.header == Self.hunkHeader)
	}

	@Test("an unknown hunk id is ignored")
	func unknownHunkIdIsIgnored() async {
		let file = modifiedFile()
		let store = makeStore(returning: diff(for: file))
		store.exhaustivity = .on

		await store.send(.load(file, isStaged: false)) {
			$0.fileId = file.id
			$0.fileIsStaged = false
		}
		await store.receive(\.loadResponse) {
			$0.fileDiff = self.diff(for: file)
			$0.displayDiff = self.diff(for: file).toAppUI()
		}

		// Exhaustive from here: an emitted delegate action would fail the test.
		await store.send(.stageHunk(hunkId: "@@ -99,0 +99,0 @@"))
		await store.send(.unstageHunk(hunkId: "@@ -99,0 +99,0 @@"))
		await store.send(.discardHunk(hunkId: "@@ -99,0 +99,0 @@"))
		await store.finish()
	}
}
