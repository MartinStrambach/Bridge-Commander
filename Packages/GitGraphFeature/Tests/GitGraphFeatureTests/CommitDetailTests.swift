import AppUI
import ComposableArchitecture
import DiffModelMapping
import Foundation
import GitCore
import Testing

@testable import GitGraphFeature

@Suite("Commit detail")
@MainActor
struct CommitDetailTests {

	// MARK: - Fixtures

	private static let repositoryPath = "/tmp/repo"
	private static let commitHash = "aaa111"

	private func commit() -> GitLogCommit {
		GitLogCommit(
			hash: Self.commitHash,
			parents: ["bbb222"],
			author: "Author",
			date: Date(timeIntervalSince1970: 1_700_000_000),
			refs: [],
			subject: "A commit"
		)
	}

	private func file(_ path: String) -> GitCore.FileChange {
		GitCore.FileChange(path: path, status: .modified, addedLines: 1, removedLines: 1)
	}

	private func diff(for file: GitCore.FileChange) -> GitCore.FileDiff {
		let header = "@@ -1 +1 @@"
		return GitCore.FileDiff(
			fileChange: file,
			hunks: [
				GitCore.DiffHunk(
					header: header,
					oldStart: 1,
					oldCount: 1,
					newStart: 1,
					newCount: 1,
					lines: [
						GitCore.DiffLine(rawLine: "-old", id: "\(header):0", oldLineNumber: 1, newLineNumber: nil),
						GitCore.DiffLine(rawLine: "+new", id: "\(header):1", oldLineNumber: nil, newLineNumber: 1),
					]
				),
			],
			isBinary: false
		)
	}

	private func store(
		files: [GitCore.FileChange],
		diffs: [String: GitCore.FileDiff] = [:]
	) -> TestStoreOf<CommitDetailReducer> {
		TestStore(
			initialState: CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: commit())
		) {
			CommitDetailReducer()
		} withDependencies: {
			$0[GitCommitDiffClient.self].fetchFileChanges = { _, _ in files }
			$0[GitCommitDiffClient.self].fetchFileDiff = { _, _, file in diffs[file.path] }
		}
	}

	// MARK: - Loading

	@Test("loading a commit selects its first file and shows that file's diff")
	func loadingSelectsTheFirstFile() async {
		let first = file("A.swift")
		let second = file("B.swift")
		let store = store(files: [first, second], diffs: [first.path: diff(for: first)])

		await store.send(.task) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [first, second]
		}
		await store.receive(\.fileSelected) {
			$0.selectedFileId = first.id
			$0.isLoadingDiff = true
		}
		await store.receive(\.diffLoaded) {
			$0.isLoadingDiff = false
			$0.displayDiff = self.diff(for: first).toAppUI()
		}
	}

	@Test("a commit that changed nothing loads no diff and reports itself as empty")
	func aCommitWithoutChangesLoadsNoDiff() async {
		let store = store(files: [])

		await store.send(.task) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
		}
		await store.receive(\.fileSelected)

		#expect(store.state.hasNoChanges)
		#expect(store.state.displayDiff == nil)
	}

	// MARK: - Switching files

	@Test("selecting another file replaces the diff")
	func selectingAnotherFileReplacesTheDiff() async {
		let first = file("A.swift")
		let second = file("B.swift")
		let store = store(
			files: [first, second],
			diffs: [first.path: diff(for: first), second.path: diff(for: second)]
		)

		await store.send(.task) { $0.isLoadingFiles = true }
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [first, second]
		}
		await store.receive(\.fileSelected) {
			$0.selectedFileId = first.id
			$0.isLoadingDiff = true
		}
		await store.receive(\.diffLoaded) {
			$0.isLoadingDiff = false
			$0.displayDiff = self.diff(for: first).toAppUI()
		}

		await store.send(.fileSelected(second.id)) {
			// The previous diff is dropped straight away, so the pane never shows one file's
			// diff under another file's name.
			$0.selectedFileId = second.id
			$0.displayDiff = nil
			$0.isLoadingDiff = true
		}
		await store.receive(\.diffLoaded) {
			$0.isLoadingDiff = false
			$0.displayDiff = self.diff(for: second).toAppUI()
		}
	}

	@Test("deselecting clears the diff without loading anything")
	func deselectingClearsTheDiff() async {
		let only = file("A.swift")
		let store = store(files: [only], diffs: [only.path: diff(for: only)])

		await store.send(.task) { $0.isLoadingFiles = true }
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [only]
		}
		await store.receive(\.fileSelected) {
			$0.selectedFileId = only.id
			$0.isLoadingDiff = true
		}
		await store.receive(\.diffLoaded) {
			$0.isLoadingDiff = false
			$0.displayDiff = self.diff(for: only).toAppUI()
		}

		await store.send(.fileSelected(nil)) {
			$0.selectedFileId = nil
			$0.displayDiff = nil
			$0.isLoadingDiff = false
		}
	}

	@Test("a file git reports no diff for leaves the pane empty rather than stale")
	func aFileWithoutADiffLeavesThePaneEmpty() async {
		let only = file("A.swift")
		let store = store(files: [only]) // no diff registered for it

		await store.send(.task) { $0.isLoadingFiles = true }
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [only]
		}
		await store.receive(\.fileSelected) {
			$0.selectedFileId = only.id
			$0.isLoadingDiff = true
		}
		await store.receive(\.diffLoaded) {
			$0.isLoadingDiff = false
		}

		#expect(store.state.displayDiff == nil)
	}
}
