import AppUI
import ComposableArchitecture
import DiffModelMapping
import Foundation
import GitCore
import Testing
@testable import StagingFeature

// Races between the staging panel's git calls: a hunk applied twice, a diff landing after its
// selection was cleared, a stage's refresh overtaken by an older one, and a failed push leaving the
// committed files listed as staged.
@Suite("Staging panel races")
@MainActor
struct StagingPanelRaceTests {

	// MARK: - Fixtures

	private static let hunkHeader = "@@ -1 +1 @@"

	private func modifiedFile(_ path: String = "Sources/App.swift") -> GitCore.FileChange {
		GitCore.FileChange(path: path, status: .modified)
	}

	private func diff(for file: GitCore.FileChange) -> GitCore.FileDiff {
		GitCore.FileDiff(
			fileChange: file,
			hunks: [
				GitCore.DiffHunk(
					header: Self.hunkHeader,
					oldStart: 1,
					oldCount: 1,
					newStart: 1,
					newCount: 1,
					lines: [
						GitCore.DiffLine(rawLine: "-old", id: "\(Self.hunkHeader):0", oldLineNumber: 1, newLineNumber: nil),
						GitCore.DiffLine(rawLine: "+new", id: "\(Self.hunkHeader):1", oldLineNumber: nil, newLineNumber: 1),
					]
				),
			],
			isBinary: false
		)
	}

	private struct GitFailed: Error {}

	// MARK: - Hunk actions

	@Test
	func aSecondHunkClickBeforeTheDiffReloadsIsDropped() async {
		let file = modifiedFile()
		let loaded = diff(for: file)
		let store = TestStore(initialState: FileDiffViewer.State(repositoryPath: "/repo")) {
			FileDiffViewer()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileDiff = { _, _, _ in loaded }
		}

		await store.send(.load(file, isStaged: false)) {
			$0.fileId = file.id
			$0.fileIsStaged = false
		}
		await store.receive(\.loadResponse) {
			$0.fileDiff = loaded
			$0.displayDiff = loaded.toAppUI()
		}

		await store.send(.stageHunk(hunkId: Self.hunkHeader)) { $0.isApplyingHunk = true }
		await store.receive(\.delegate.stageHunk)

		// Exhaustive: a second delegate action would fail the test.
		await store.send(.stageHunk(hunkId: Self.hunkHeader))
		await store.send(.discardHunk(hunkId: Self.hunkHeader))

		// The reload that follows the write brings the hunk actions back.
		await store.send(.load(file, isStaged: false))
		await store.receive(\.loadResponse) { $0.isApplyingHunk = false }
		await store.send(.unstageHunk(hunkId: Self.hunkHeader)) { $0.isApplyingHunk = true }
		await store.receive(\.delegate.unstageHunk)
	}

	@Test
	func aFailedWriteBringsTheHunkActionsBack() async {
		var initial = RepositoryDetail.State(repositoryPath: "/repo", iosSubfolderPath: "")
		initial.diffViewer.isApplyingHunk = true
		let store = TestStore(initialState: initial) { RepositoryDetail() }
		store.exhaustivity = .off

		await store.send(.operationCompleted(.failure(GitFailed())))

		#expect(!store.state.diffViewer.isApplyingHunk)
		#expect(store.state.alert != nil)
	}

	// MARK: - Diff loading

	@Test
	func aDiffArrivingAfterTheSelectionWasClearedIsDropped() async {
		let file = modifiedFile()
		let loaded = diff(for: file)
		let (diffReady, releaseDiff) = AsyncStream<Void>.makeStream()
		var initial = RepositoryDetail.State(repositoryPath: "/repo", iosSubfolderPath: "")
		initial.unstaged.files = [file]
		let store = TestStore(initialState: initial) {
			RepositoryDetail()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileDiff = { _, _, _ in
				for await _ in diffReady {
					break
				}
				return loaded
			}
		}
		store.exhaustivity = .off

		await store.send(.unstaged(.updateSelection([file.id])))
		await store.receive(\.diffViewer.load)
		await store.send(.unstaged(.updateSelection([])))

		releaseDiff.yield()
		await store.receive(\.diffViewer.loadResponse)

		#expect(store.state.diffViewer.fileDiff == nil)
		#expect(store.state.diffViewer.displayDiff == nil, "the hunk buttons would act on a file no longer selected")
	}

	// MARK: - Refresh after staging

	@Test
	func anOlderRefreshCannotLandAfterTheStagesRefresh() async {
		let first = modifiedFile("a.txt")
		let second = modifiedFile("b.txt")
		let isStaged = LockIsolated(false)
		let (slowRefreshStarted, signalSlowRefresh) = AsyncStream<Void>.makeStream()
		let (slowRefreshGate, releaseSlowRefresh) = AsyncStream<Void>.makeStream()
		let (slowRefreshReturned, signalSlowRefreshReturned) = AsyncStream<Void>.makeStream()

		var initial = RepositoryDetail.State(repositoryPath: "/repo", iosSubfolderPath: "")
		initial.unstaged.files = [first, second]
		let store = TestStore(initialState: initial) {
			RepositoryDetail()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileChanges = { _ in
				if isStaged.value {
					return GitFileChanges(staged: [first], unstaged: [second])
				}
				// A refresh (window focus, ⌘R) that read the index before the stage and is slow to finish.
				signalSlowRefresh.yield()
				defer { signalSlowRefreshReturned.yield() }
				for await _ in slowRefreshGate {
					break
				}
				return GitFileChanges(staged: [], unstaged: [first, second])
			}
			$0[GitStagingClient.self].stageFiles = { _, _ in isStaged.setValue(true) }
			$0[GitStagingClient.self].fetchFileDiff = { _, file, _ in
				GitCore.FileDiff(fileChange: file, hunks: [], isBinary: false)
			}
		}
		store.exhaustivity = .off

		await store.send(.loadChanges)
		for await _ in slowRefreshStarted {
			break
		}

		await store.send(.unstaged(.delegate(.toggleAll([first]))))
		await store.receive(\.stageFilesCompleted)
		await store.receive(\.loadChangesResponse)

		releaseSlowRefresh.yield()
		for await _ in slowRefreshReturned {
			break
		}
		// Lets the slow refresh deliver its snapshot, if it is still allowed to.
		await Task.megaYield()
		await store.finish()
		// Non-exhaustive: `state` only reflects received actions once they are skipped past.
		await store.skipReceivedActions()

		#expect(store.state.staged.files.map(\.path) == ["a.txt"])
		#expect(store.state.unstaged.files.map(\.path) == ["b.txt"])
		#expect(!store.state.isLoadingChanges)
	}

	// MARK: - Commit & Push

	@Test
	func aFailedPushStillReportsTheCommit() async {
		var initial = CommitReducer.State(repositoryPath: "/repo")
		initial.message = "Message"
		initial.isCommitting = true
		initial.shouldPushAfterCommit = true
		let store = TestStore(initialState: initial) { CommitReducer() }

		await store.send(.pushCompleted(.failure(GitFailed()))) {
			$0.isCommitting = false
			$0.alert = ScrollableAlertReducer.State(
				title: "Push Failed",
				message: GitFailed().localizedDescription,
				isError: true
			)
		}
		await store.receive(\.delegate)
	}
}
