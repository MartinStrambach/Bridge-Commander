import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import StagingFeature

// Staging or unstaging whole files used to reload the file lists outside the panel's cancellable
// load, so a refresh already in flight (the app becoming active, ⌘R, a hunk action) could answer
// last and put its older snapshot back: a just-staged file showed as unstaged again. Whichever
// snapshot landed first also took the selection meant for the one after the stage.
@Suite("Repository detail file list loading")
@MainActor
struct RepositoryDetailLoadChangesTests {

	private func file(_ path: String) -> GitCore.FileChange {
		GitCore.FileChange(path: path, status: .modified)
	}

	/// A panel whose first file-list fetch waits for `refreshGate` and returns `before`; every
	/// fetch made once `stageFiles` has finished returns `after` straight away.
	private func makeStore(
		unstaged: [GitCore.FileChange],
		before: GitFileChanges,
		after: GitFileChanges,
		refreshStarted: AsyncStream<Void>.Continuation,
		refreshGate: AsyncStream<Void>,
		stageGate: AsyncStream<Void>? = nil
	) -> TestStoreOf<RepositoryDetail> {
		let didStage = LockIsolated(false)
		var initial = RepositoryDetail.State(repositoryPath: "/repo", iosSubfolderPath: "")
		initial.unstaged.files = unstaged
		let store = TestStore(initialState: initial) {
			RepositoryDetail()
		} withDependencies: {
			$0[GitStagingClient.self].fetchFileChanges = { _ in
				if didStage.value {
					return after
				}
				refreshStarted.yield()
				for await _ in refreshGate {}
				return before
			}
			$0[GitStagingClient.self].stageFiles = { _, _ in
				if let stageGate {
					for await _ in stageGate {}
				}
				didStage.setValue(true)
			}
			$0[GitStagingClient.self].fetchFileDiff = { _, file, _ in
				GitCore.FileDiff(fileChange: file, hunks: [], isBinary: false)
			}
		}
		store.exhaustivity = .off
		return store
	}

	@Test("a refresh still in flight when staging finishes cannot put the older list back")
	func olderRefreshCannotOverwriteTheStagedList() async {
		let a = file("a.swift")
		let refreshStarted = AsyncStream.makeStream(of: Void.self)
		let refreshGate = AsyncStream.makeStream(of: Void.self)
		let store = makeStore(
			unstaged: [a],
			before: GitFileChanges(staged: [], unstaged: [a]),
			after: GitFileChanges(staged: [a], unstaged: []),
			refreshStarted: refreshStarted.continuation,
			refreshGate: refreshGate.stream
		)

		await store.send(.loadChanges)
		for await _ in refreshStarted.stream { break }

		await store.send(.unstaged(.delegate(.toggleAll([a]))))
		await store.receive(\.stageFilesCompleted)
		await store.receive(\.loadChangesResponse)

		// The older refresh answers only now.
		refreshGate.continuation.finish()
		await store.finish()
		await store.skipReceivedActions()

		#expect(store.state.staged.files == [a])
		#expect(store.state.unstaged.files.isEmpty)
		#expect(store.state.diffViewer.fileId == a.id)
		#expect(store.state.diffViewer.fileIsStaged == true)
	}

	@Test("a refresh that answers while files are being staged leaves the next selection to the list after the stage")
	func refreshDuringStagingDoesNotTakeTheNextSelection() async {
		let a = file("a.swift")
		let b = file("b.swift")
		let c = file("c.swift")
		let refreshStarted = AsyncStream.makeStream(of: Void.self)
		let refreshGate = AsyncStream.makeStream(of: Void.self)
		let stageGate = AsyncStream.makeStream(of: Void.self)
		let store = makeStore(
			unstaged: [a, b, c],
			before: GitFileChanges(staged: [], unstaged: [a, b, c]),
			after: GitFileChanges(staged: [b], unstaged: [a, c]),
			refreshStarted: refreshStarted.continuation,
			refreshGate: refreshGate.stream,
			stageGate: stageGate.stream
		)

		await store.send(.loadChanges)
		for await _ in refreshStarted.stream { break }
		await store.send(.unstaged(.delegate(.toggleAll([b]))))

		// The refresh lands while `git add` is still running.
		refreshGate.continuation.finish()
		await store.receive(\.loadChangesResponse)

		stageGate.continuation.finish()
		await store.receive(\.stageFilesCompleted)
		await store.receive(\.loadChangesResponse)
		await store.finish()
		await store.skipReceivedActions()

		// b was second in the unstaged list, so the file now second there is selected.
		#expect(store.state.unstaged.files == [a, c])
		#expect(store.state.unstaged.selectedFileIds == [c.id])
		#expect(store.state.diffViewer.fileId == c.id)
		#expect(store.state.diffViewer.fileIsStaged == false)
	}
}
